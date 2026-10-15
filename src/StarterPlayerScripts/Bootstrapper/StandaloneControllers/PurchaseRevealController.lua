--!strict
--[[
	@module PurchaseRevealController
	@description Shows what was just bought, once the server granted it
	(EventBus.Purchase.Granted, bridged from "PurchaseGranted"):

	  - a rainbow sunburst spins behind the center of the screen;
	  - the item's icon jumps at the player (pops past full size, settles),
	    then keeps bobbing and wiggling;
	  - the title pops in under it, its rainbow gradient turning;
	  - rainbow confetti and the gamepass fanfare (Effects.PlayPassFanfare):
	    a coin shower while the icon lands, then one rising level-up per
	    "level" -- each one slides a benefit line in (own color), punches
	    the icon, title and sunburst.

	Item art and texts: PurchaseRevealConfig. Reveals queue (one at a time);
	a click/tap anywhere or HOLD_SECONDS ends one. A `Quick` item (repeat-buy
	products) skips the dim, lets clicks through and leaves after
	QUICK_HOLD_SECONDS, so the player can buy it again right away: its icon
	pops in the middle of the sunburst flash and clears out with it (the
	sound is PurchasePromptController's). Display only: the grant
	itself already happened server-side. Draws above PurchasePromptController's
	backdrop (DisplayOrder 60 > 50).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local PurchaseRevealConfig = require(Bootstrapper.Config.PurchaseRevealConfig)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local Children = Fusion.Children

local PurchaseRevealController = {}

local LocalPlayer = Players.LocalPlayer

--- Sunburst already used by the HUD (StarterPack / boost buttons).
local SUNBURST_IMAGE = "rbxassetid://81154417476312"
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 160, 40)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 235, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 100)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(60, 190, 255)),
	ColorSequenceKeypoint.new(0.83, Color3.fromRGB(150, 100, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 200)),
})
--- One color per benefit line (cycled).
local BENEFIT_COLORS = {
	Color3.fromRGB(255, 225, 70),
	Color3.fromRGB(110, 240, 120),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 130, 220),
}
local ICON_SIZE = 0.34 -- screen height scale
local ICON_POSITION = UDim2.fromScale(0.5, 0.35)
local SUNBURST_SIZE = 1.05 -- screen height scale
local TITLE_Y = 0.56
local BENEFIT_TOP_Y = 0.645
local BENEFIT_STEP_Y = 0.06
local BENEFIT_STAGGER = 0.18 -- quick: seconds between two benefit lines
--- Gamepass: seconds between two level-ups (one benefit line each), and
--- the fewest level-ups played even with fewer lines.
local LEVEL_INTERVAL = 0.42
local MIN_LEVELS = 3
--- Seconds a reveal stays (plus LEVEL_INTERVAL per level) before leaving.
local HOLD_SECONDS = 3.2
local QUICK_HOLD_SECONDS = 0.9
--- Quick: seconds the sunburst flash (and the icon in it) stays at full
--- before both clear out together.
local QUICK_FLASH_HOLD = 0.3
local QUICK_FLASH_FADE = 0.3
--- Seconds the exit fade takes (click or timeout).
local FADE_SECONDS = 0.2

local queue: { { key: string, detail: number? } } = {}
local busy = false
local gui: ScreenGui? = nil

local function play(target: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(target, info, goal)
	tween:Play()
	return tween
end

local function stroke(scope: any, thickness: number): UIStroke
	return scope:New("UIStroke")({
		Thickness = thickness,
		Color = Color3.fromRGB(25, 15, 45),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

--- Plays one reveal; yields until it is gone.
local function reveal(key: string, detail: number?): ()
	local parent = gui
	if not parent then
		return
	end
	local item = PurchaseRevealConfig.Items[key] or PurchaseRevealConfig.Default
	local title = if detail and item.Title:find("%%d")
		then item.Title:format(detail)
		else item.Title
	local benefits = item.Benefits or {}
	local quick = item.Quick == true

	local scope = Fusion.scoped(Fusion)
	local raysGradient = scope:New("UIGradient")({ Color = RAINBOW })
	-- Punch scales (level-ups), separate from the entrance Size tweens.
	local raysScale = scope:New("UIScale")({ Scale = 1 })
	local iconScale = scope:New("UIScale")({ Scale = 1 })
	local rays = scope:New("ImageLabel")({
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = ICON_POSITION,
		Size = UDim2.fromScale(0, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Image = SUNBURST_IMAGE,
		ImageTransparency = 0.2,
		[Children] = { raysGradient, raysScale },
	}) :: ImageLabel
	local icon = scope:New("ImageLabel")({
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = ICON_POSITION,
		Size = UDim2.fromScale(0, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Rotation = -30,
		BackgroundTransparency = 1,
		Image = item.Icon,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
		[Children] = {
			iconScale,
			if item.Tint then scope:New("UIGradient")({ Color = item.Tint }) else nil,
		} :: { any },
	}) :: ImageLabel
	local titleScale = scope:New("UIScale")({ Scale = 0 })
	local titleGradient = scope:New("UIGradient")({ Color = RAINBOW })
	-- Scrolled by UISpinController, same as the HUD RainbowGradients
	titleGradient:SetAttribute("Spin", true)
	local titleLabel = scope:New("TextLabel")({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, TITLE_Y),
		Size = UDim2.fromScale(0.7, 0.11),
		BackgroundTransparency = 1,
		FontFace = FONT,
		Text = title,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 4,
		[Children] = { titleScale, titleGradient, stroke(scope, 4) },
	}) :: TextLabel

	local lines: { TextLabel } = {}
	for index, text in benefits do
		table.insert(
			lines,
			scope:New("TextLabel")({
				Name = "Benefit" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(
					0.5,
					BENEFIT_TOP_Y + (index - 1) * BENEFIT_STEP_Y + 0.04
				),
				Size = UDim2.fromScale(0.6, 0.055),
				BackgroundTransparency = 1,
				FontFace = FONT,
				Text = text,
				TextColor3 = BENEFIT_COLORS[(index - 1) % #BENEFIT_COLORS + 1],
				TextTransparency = 1,
				TextScaled = true,
				ZIndex = 4,
				[Children] = stroke(scope, 3),
			}) :: TextLabel
		)
	end

	local dismiss = scope:New("TextButton")({
		Name = "Dismiss",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Interactable = not quick, -- quick: clicks reach the buy button behind
		[Children] = { rays, icon, titleLabel, lines :: any },
	}) :: TextButton
	-- No ButtonHoverController grow/squash: it would scale the whole reveal
	-- toward the top-left corner on hover/press instead of letting it fade.
	dismiss:SetAttribute("NoHoverFX", true)
	dismiss.Parent = parent
	local done = false -- set by leave()

	-- Entrance: dim, rays open, the icon jumps at the player, title pops
	if not quick then
		play(dismiss, TweenInfo.new(0.3), { BackgroundTransparency = 0.3 })
	end
	local levels = math.max(#lines, MIN_LEVELS)
	if quick then
		-- One blinding flash with the icon popped in its middle; both clear
		-- out together (the title carries on).
		local flashIn = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		play(rays, flashIn, {
			Size = UDim2.fromScale(SUNBURST_SIZE * 1.3, SUNBURST_SIZE * 1.3),
			ImageTransparency = 0,
		})
		play(icon, flashIn, { Size = UDim2.fromScale(ICON_SIZE, ICON_SIZE), Rotation = 0 })
		task.delay(0.12 + QUICK_FLASH_HOLD, function()
			local fadeOut =
				TweenInfo.new(QUICK_FLASH_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			play(rays, fadeOut, { ImageTransparency = 1 })
			play(icon, fadeOut, { ImageTransparency = 1 })
			play(iconScale, fadeOut, { Scale = 1.3 })
		end)
	else
		play(rays, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
			Size = UDim2.fromScale(SUNBURST_SIZE, SUNBURST_SIZE),
		})
		local big = ICON_SIZE * 1.45
		play(icon, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(big, big),
			Rotation = 8,
		}).Completed:Once(function()
			play(icon, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), {
				Size = UDim2.fromScale(ICON_SIZE, ICON_SIZE),
				Rotation = 0,
			})
		end)
		Effects.PlayPassFanfare(levels, LEVEL_INTERVAL)
	end
	task.delay(0.2, function()
		play(titleScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 })
	end)
	local function slideIn(line: TextLabel): ()
		play(line, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
			Position = line.Position - UDim2.fromScale(0, 0.04),
			TextTransparency = 0,
		})
	end
	local function punch(target: UIScale, peak: number): ()
		play(target, TweenInfo.new(0.08, Enum.EasingStyle.Quad), { Scale = peak }).Completed:Once(
			function()
				play(target, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 })
			end
		)
	end
	if quick then
		for index, line in lines do
			task.delay(0.15 + (index - 1) * BENEFIT_STAGGER, function()
				if not done then -- left before this line slid in: keep it hidden
					slideIn(line)
				end
			end)
		end
	else
		-- One beat per level-up jingle, after the coin shower.
		for level = 1, levels do
			task.delay(Effects.PassCoinSeconds + (level - 1) * LEVEL_INTERVAL, function()
				if done then
					return
				end
				local line = lines[level]
				if line then
					slideIn(line)
				end
				punch(iconScale, 1.18)
				punch(raysScale, 1.12)
				punch(titleScale, 1.12)
			end)
		end
	end
	UXEffects.Confetti.rainbow()

	-- Idle: rays and rainbows turn, the icon bobs and wiggles (after its jump)
	local started = os.clock()
	local idle = RunService.RenderStepped:Connect(function(deltaTime: number)
		local t = os.clock() - started
		rays.Rotation = (rays.Rotation + 25 * deltaTime) % 360
		raysGradient.Rotation = (raysGradient.Rotation + 90 * deltaTime) % 360
		if t > 0.7 then
			icon.Position = ICON_POSITION + UDim2.fromScale(0, math.sin(t * 3) * 0.012)
			icon.Rotation = math.sin(t * 2.2) * 6
		end
	end)

	local finished = Instance.new("BindableEvent")
	-- Exit: everything fades out together, in place (no shrink), whether the
	-- reveal timed out or the player clicked it away mid-entrance.
	local function leave()
		if done then
			return
		end
		done = true
		local fade = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		play(dismiss, fade, { BackgroundTransparency = 1 })
		play(rays, fade, { ImageTransparency = 1 })
		-- A dark stroke still reads at half transparency once the text has
		-- faded into the backdrop: the strokes go out in half the time.
		local strokeFade =
			TweenInfo.new(FADE_SECONDS / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, label in { titleLabel, table.unpack(lines) } do
			play(label, fade, { TextTransparency = 1 })
			local labelStroke = label:FindFirstChildOfClass("UIStroke")
			if labelStroke then
				play(labelStroke, strokeFade, { Transparency = 1 })
			end
		end
		play(icon, fade, { ImageTransparency = 1 }).Completed:Once(function()
			finished:Fire()
		end)
	end
	-- Ignore the click that may still be in flight from closing Roblox's prompt
	if not quick then
		task.delay(0.6, function()
			if not done then
				dismiss.Activated:Once(function()
					Effects.Play("UIClick") -- NoHoverFX also skips the shared click sound
					leave()
				end)
			end
		end)
	end
	task.delay(if quick then QUICK_HOLD_SECONDS else HOLD_SECONDS + levels * LEVEL_INTERVAL, leave)

	finished.Event:Wait()
	finished:Destroy()
	idle:Disconnect()
	scope:doCleanup()
end

local function pump(): ()
	if busy then
		return
	end
	busy = true
	while #queue > 0 do
		local entry = table.remove(queue, 1) :: { key: string, detail: number? }
		reveal(entry.key, entry.detail)
	end
	busy = false
end

function PurchaseRevealController:Init(): () end

function PurchaseRevealController:Start(): ()
	gui = Fusion.scoped(Fusion):New("ScreenGui")({
		Name = "PurchaseReveal",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 60, -- above PurchasePromptFX (50)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	EventBus.Purchase.Granted:Connect(function(key: string, detail: number?)
		if type(key) ~= "string" then
			return
		end
		table.insert(
			queue,
			{ key = key, detail = if type(detail) == "number" then detail else nil }
		)
		task.spawn(pump)
	end)
end

return PurchaseRevealController
