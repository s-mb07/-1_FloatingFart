--!strict
--[[
	@module PurchasePromptController
	@description Backdrop + sound around Roblox's own purchase prompt.

	  - Opening (EventBus.Purchase.PromptShown, bridged from
	    MonetizationService): the 3D world blurs (UXEffects.Backdrop), the
	    screen dims behind a soft vignette, a golden sunburst fades in and
	    slowly turns behind the prompt, and the "PurchasePromptOpened"
	    Effects recipe plays (sound + haptic).
	  - Closing (MarketplaceService "...PurchaseFinished" -- readable by game
	    scripts, unlike "...Requested"): bought = the sunburst flares,
	    golden confetti cannons + "PurchaseSucceeded" (haptic), then the
	    backdrop hands over to PurchaseRevealController (which plays the
	    gamepass fanfare: coins then level-ups) and fades out; cancelled = it
	    just fades out. A Developer Product (repeat buy) gets a FLASH instead,
	    with the purchase sound (Effects.PlayPurchaseFanfare: a coin shower
	    then XP ticks): the sunburst blinds for an instant and is gone, no
	    hold -- back to the buy button at once. What was bought is shown by
	    PurchaseRevealController once the server grants it.

	Display only: `wasPurchased` here only picks the celebration. Granting
	stays server-side (ProcessReceipt / UserOwnsGamePassAsync). Roblox's
	prompt is CoreGui, so it always draws above this overlay.
	A SAFETY_TIMEOUT closes the backdrop if no Finished event ever arrives.

	While the prompt is up, PlayerGui/BackgroundEffet/ImageEffet shows with
	only its RainbowGradient on, and any open Navigation panel is closed:
	gamepass bought = it stays closed, cancelled or Developer Product bought
	(Skip Rebirth, boosts...) = it is pushed back.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local NavigationController = require(Bootstrapper.Navigation.Controller)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local Children = Fusion.Children

local PurchasePromptController = {}

local LocalPlayer = Players.LocalPlayer

--- Sunburst already used by the HUD (StarterPack / boost buttons).
local SUNBURST_IMAGE = "rbxassetid://81154417476312"
local SUNBURST_COLOR = Color3.fromRGB(255, 215, 90)
local DIM_TRANSPARENCY = 0.45 -- darkest the dim layer gets (center of the vignette is lighter)
local SUNBURST_TRANSPARENCY = 0.45
local SPIN_DEGREES_PER_SECOND = 18
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLARE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
--- Seconds the celebration stays before the backdrop fades out (the
--- reveal, granted meanwhile, takes over above it).
local SUCCESS_HOLD = 0.7
--- Developer Product flash: blinding flare in, then straight out.
local FLASH_IN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
--- Seconds after which an unanswered prompt closes the backdrop anyway.
local SAFETY_TIMEOUT = 90
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 215, 70),
	Color3.fromRGB(255, 240, 160),
	Color3.fromRGB(255, 180, 40),
	Color3.fromRGB(255, 255, 255),
}

local root: Frame? = nil
local dim: Frame? = nil
local sunburst: ImageLabel? = nil
local spin: RBXScriptConnection? = nil
local token = 0
local open = false
--- Studio-authored PlayerGui/BackgroundEffet/ImageEffet (shared with LeaveReward's red alarm).
local effectImage: ImageLabel? = nil
--- Gradient Enabled states before the rainbow took over, restored on close.
local savedGradients: { [UIGradient]: boolean } = {}
--- Panel closed when the prompt opened, reopened if the player cancels.
local closedPanelId: string? = nil

local function setRainbow(on: boolean): ()
	local image = effectImage
	if not image then
		return
	end
	for _, child in image:GetChildren() do
		if child:IsA("UIGradient") then
			if on then
				savedGradients[child] = child.Enabled
				child.Enabled = child.Name == "RainbowGradient"
			elseif savedGradients[child] ~= nil then
				child.Enabled = savedGradients[child]
			end
		end
	end
	if not on then
		table.clear(savedGradients)
	end
	(image.Parent :: ScreenGui).Enabled = on
end

local function play(tweenTarget: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(tweenTarget, info, goal)
	tween:Play()
	return tween
end

local function startSpin(): ()
	if spin then
		return
	end
	spin = RunService.RenderStepped:Connect(function(deltaTime: number)
		local image = sunburst
		if image then
			image.Rotation = (image.Rotation + SPIN_DEGREES_PER_SECOND * deltaTime) % 360
		end
	end)
end

local function stopSpin(): ()
	if spin then
		spin:Disconnect()
		spin = nil
	end
end

local function show(): ()
	local frame, layer, image = root, dim, sunburst
	if not (frame and layer and image) then
		return
	end
	token += 1
	local mine = token
	if not open then
		closedPanelId = NavigationController.GetActivePanelId()
		NavigationController.CloseAll()
		if NavigationController.GetActivePanelId() then
			closedPanelId = nil -- CanGoBack = false refused the close: nothing to reopen
		end
		setRainbow(true)
	end
	open = true

	if not frame.Visible then
		layer.BackgroundTransparency = 1
		image.ImageTransparency = 1
		image.Size = UDim2.fromScale(0.6, 0.6)
		frame.Visible = true -- Backdrop blurs the world while this is visible
	end
	play(layer, FADE_IN, { BackgroundTransparency = DIM_TRANSPARENCY })
	play(
		image,
		FADE_IN,
		{ ImageTransparency = SUNBURST_TRANSPARENCY, Size = UDim2.fromScale(0.9, 0.9) }
	)
	startSpin()
	Effects.Play("PurchasePromptOpened")

	task.delay(SAFETY_TIMEOUT, function()
		if token == mine and open then
			PurchasePromptController.Close(false)
		end
	end)
end

--- Ends the backdrop. `purchased` plays the celebration first; `flash`
--- (Developer Products) makes it a one-instant blinding flare.
--- @param purchased boolean
function PurchasePromptController.Close(purchased: boolean, flash: boolean?): ()
	local frame, layer, image = root, dim, sunburst
	if not (open and frame and layer and image) then
		return
	end
	open = false
	token += 1
	local mine = token

	setRainbow(false)
	local panelId = closedPanelId
	closedPanelId = nil
	-- A Developer Product (flash) is a repeat buy: back to its panel either way.
	if (not purchased or flash) and panelId then
		NavigationController.Push(panelId)
	end

	local function fadeOut(info: TweenInfo?)
		if token ~= mine then
			return -- a new prompt reopened the backdrop meanwhile
		end
		play(layer, info or FADE_OUT, { BackgroundTransparency = 1 })
		play(image, info or FADE_OUT, { ImageTransparency = 1 }).Completed:Once(function()
			if token == mine then
				stopSpin()
				frame.Visible = false
			end
		end)
	end

	if purchased and flash then
		play(image, FLASH_IN, { Size = UDim2.fromScale(1.6, 1.6), ImageTransparency = 0 }).Completed:Once(
			function()
				fadeOut(FLASH_OUT)
			end
		)
		UXEffects.Confetti.cannons(CONFETTI_COLORS)
		Effects.Play("PurchaseSucceeded") -- haptic
		Effects.PlayPurchaseFanfare()
	elseif purchased then
		play(image, FLARE, { Size = UDim2.fromScale(1.25, 1.25), ImageTransparency = 0.15 })
		UXEffects.Confetti.cannons(CONFETTI_COLORS)
		Effects.Play("PurchaseSucceeded") -- haptic; the reveal plays the sound
		task.delay(SUCCESS_HOLD, fadeOut)
	else
		fadeOut()
	end
end

local function build(): ()
	local scope = Fusion.scoped(Fusion) -- lives as long as the client
	local layer = scope:New("Frame")({
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		[Children] = scope:New("UIGradient")({
			-- Soft vignette: lighter in the middle, where the prompt sits
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	}) :: Frame
	local image = scope:New("ImageLabel")({
		Name = "Sunburst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Image = SUNBURST_IMAGE,
		ImageColor3 = SUNBURST_COLOR,
		ImageTransparency = 1,
		ZIndex = 2,
	}) :: ImageLabel
	local frame = scope:New("Frame")({
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		[Children] = { layer, image },
	}) :: Frame

	scope:New("ScreenGui")({
		Name = "PurchasePromptFX",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 50, -- above the HUD and panels; Roblox's prompt (CoreGui) stays above
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = frame,
	})

	root, dim, sunburst = frame, layer, image
	UXEffects.Backdrop.track(frame)
end

function PurchasePromptController:Init(): () end

function PurchasePromptController:Start(): ()
	build()
	SafeUIResolver.WaitForPathAsync(
		LocalPlayer:WaitForChild("PlayerGui"),
		{ "BackgroundEffet", "ImageEffet" },
		function(image)
			effectImage = image :: ImageLabel
		end
	)

	EventBus.Purchase.PromptShown:Connect(show)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, _gamePassId: number, wasPurchased: boolean)
			if player == LocalPlayer then
				PurchasePromptController.Close(wasPurchased)
			end
		end
	)
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, _productId: number, isPurchased: boolean)
			if userId == LocalPlayer.UserId then
				PurchasePromptController.Close(isPurchased, true)
			end
		end
	)
	MarketplaceService.PromptPurchaseFinished:Connect(
		function(player: Player, _assetId: number, isPurchased: boolean)
			if player == LocalPlayer then
				PurchasePromptController.Close(isPurchased)
			end
		end
	)
end

return PurchasePromptController
