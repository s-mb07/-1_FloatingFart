--!strict
--[[
	@module XPGainController
	@description Every XP gain, whatever its source (hook, treadmill, Length
	boosts, daily / playtime / code rewards, starter pack), shows a clone of
	MainHUD/XpGainFrame/IconTemplate (paper airplane + "+N") that pops up at
	a random spot of XpGainFrame (only its top SPAWN_BAND for now), then
	flies into the Level bar
	(MainHUD/BottomHUD/LevelBar); the bar only fills when it lands.

	How: the gain is the increase of the total XP the server pushes
	(EventBus.Traversal.XPChanged) -- one source for every grant path, no
	server change. The XP HUD (BarSpeedController, LevelUpController) is held
	for the whole session (XPHold true from Start) and each landing fires
	XPFlush, which reveals the newest value. A drop in total XP (rebirth) or
	the first value of the session is revealed at once, with no text.
	Purely cosmetic: nothing is granted or validated here.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)

local XPGainController = {}

local LocalPlayer = Players.LocalPlayer

--- Seconds: pop in, stay above the head, fly into the bar.
local POP_TIME = 0.15
local HOLD_TIME = 0.3
local FLY_TIME = 0.45
--- Fraction of XpGainFrame's height (from its top) where icons may spawn.
local SPAWN_BAND = 0.15

local fxGui: ScreenGui? = nil
local levelBar: GuiObject? = nil
--- MainHUD/XpGainFrame/IconTemplate (paper airplane + Amount label), cloned per gain.
local template: GuiObject? = nil
local lastXp: number? = nil

--- "+N": up to 2 decimals (1.25 x 2 = "+2.5"), compact when big ("+25K").
local function formatGain(amount: number): string
	if amount >= 1000 then
		return "+" .. NumberUtil.FormatCompact(amount)
	end
	local text = ("%.2f"):format(amount):gsub("%.?0+$", "")
	return "+" .. text
end

--- Random point in the top SPAWN_BAND of XpGainFrame (the template's
--- parent), in IgnoreGuiInset space (AbsolutePosition excludes the inset).
local function spawnScreenPoint(): Vector2?
	local source = template
	local frame = source and source.Parent
	if not (frame and frame:IsA("GuiObject")) then
		return nil
	end
	local position = frame.AbsolutePosition + Vector2.new(0, GuiService:GetGuiInset().Y)
	local size = frame.AbsoluteSize
	return position + Vector2.new(math.random() * size.X, math.random() * size.Y * SPAWN_BAND)
end

--- Level bar centre in the same space (AbsolutePosition excludes the top-bar inset).
local function barScreenPoint(): Vector2?
	local bar = levelBar
	if not bar then
		return nil
	end
	return bar.AbsolutePosition + bar.AbsoluteSize / 2 + Vector2.new(0, GuiService:GetGuiInset().Y)
end

local function flyGain(amount: number): ()
	local gui = fxGui
	local source = template
	local target = barScreenPoint()
	if not (gui and source and target) then
		-- No bar / template yet: reveal at once (deferred, same reason as in Init).
		task.defer(function()
			EventBus.Traversal.XPFlush:Fire()
		end)
		return
	end
	local camera = workspace.CurrentCamera
	local start = spawnScreenPoint() or camera.ViewportSize / 2

	-- The template is sized relative to XpGainFrame; freeze its pixel size
	-- since the clone lives in the full-screen FX gui.
	local icon = source:Clone()
	icon.Name = "XPGain"
	icon.Size = UDim2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(start.X, start.Y)
	icon.Visible = true
	local amountLabel = icon:FindFirstChild("Amount")
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = formatGain(amount)
	end
	local scale = icon:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = icon
	icon.Parent = gui

	TweenService:Create(
		scale,
		TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	task.delay(POP_TIME + HOLD_TIME, function()
		local flyInfo = TweenInfo.new(FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local fly =
			TweenService:Create(icon, flyInfo, { Position = UDim2.fromOffset(target.X, target.Y) })
		TweenService:Create(scale, flyInfo, { Scale = 0.45 }):Play()
		fly.Completed:Once(function()
			icon:Destroy()
			Effects.Play("XPLand")
			EventBus.Traversal.XPFlush:Fire() -- the bar fills now
		end)
		fly:Play()
	end)
end

function XPGainController:Init(): ()
	EventBus.Traversal.XPChanged:Connect(function(xp: number)
		local previous = lastXp
		lastXp = xp
		if previous and xp > previous + 1e-6 then
			flyGain(xp - previous)
		else
			-- First value / rebirth reset: show at once. Deferred one step so
			-- every XPChanged / LevelChanged listener has buffered the new values
			-- first (listener order is undefined; the level arrives right after).
			task.defer(function()
				EventBus.Traversal.XPFlush:Fire()
			end)
		end
	end)
end

function XPGainController:Start(): ()
	-- From now on the XP HUD only updates when a gain lands (every listener
	-- connected in its Init, so none misses this).
	EventBus.Traversal.XPHold:Fire(true)

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "XPGainFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = playerGui
	fxGui = gui

	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/BottomHUD/LevelBar", function(bar)
		levelBar = bar :: GuiObject
		-- The tiled brick `Background` overlays the fill (Studio ZIndex 3):
		-- lift the labels above it so the texture never covers the text.
		local background = bar:FindFirstChild("Background")
		if background and background:IsA("GuiObject") then
			for _, child in bar:GetChildren() do
				if child:IsA("TextLabel") then
					child.ZIndex = background.ZIndex + 1
				end
			end
		end
	end)
	SafeUIResolver.WaitForPathStringAsync(
		playerGui,
		"MainHUD/XpGainFrame/IconTemplate",
		function(icon)
			template = icon :: GuiObject
		end
	)
end

return XPGainController
