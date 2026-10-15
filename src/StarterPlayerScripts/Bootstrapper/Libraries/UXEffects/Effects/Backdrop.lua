--!strict
--[[
	@module UXEffects.Effects.Backdrop
	@description Animated background blur while a UI is opening.

	Manages a single shared BlurEffect in Lighting, animated with a fade. The blur is
	driven by the ACTUAL visibility of tracked panels (Visible signal), which
	makes it idempotent and self-correcting: regardless of the closing path
	(animation, direct close, destruction), as soon as no tracked panel is
	visible, the blur is removed.

	The BlurEffect (in Lighting) only blurs the 3D world — ScreenGuis
	remain sharp in the foreground.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Bootstrapper = script.Parent.Parent.Parent.Parent
local UIAnimationConfig = require(Bootstrapper.Config.UIAnimationConfig)

local Backdrop = {}

local BLUR_NAME = "UXEffects_UIBlur"
local MAX_BLUR = UIAnimationConfig.Blur.max
local TWEEN_IN = UIAnimationConfig.Blur.tweenIn
local TWEEN_OUT = UIAnimationConfig.Blur.tweenOut

-- Currently visible panels requesting the blur.
local openPanels: { [Instance]: boolean? } = {}
-- Panels already under observation (to avoid reconnecting the signals).
local watched: { [Instance]: boolean } = {}

local blur: BlurEffect? = nil
local activeTween: Tween? = nil

--============================================================================--
-- PRIVATE
--============================================================================--

local function getBlur(): BlurEffect
	if blur and blur.Parent then
		return blur
	end
	local existing = Lighting:FindFirstChild(BLUR_NAME)
	if existing and existing:IsA("BlurEffect") then
		blur = existing
		return existing
	end
	local created = Instance.new("BlurEffect")
	created.Name = BLUR_NAME
	created.Size = 0
	created.Enabled = true
	created.Parent = Lighting
	blur = created
	return created
end

local function tweenTo(size: number, duration: number): ()
	local target = getBlur()
	if activeTween then
		activeTween:Cancel()
	end
	local tween = TweenService:Create(
		target,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = size }
	)
	activeTween = tween
	tween:Play()
end

local function isAnyOpen(): boolean
	return next(openPanels) ~= nil
end

local function refresh(): ()
	if isAnyOpen() then
		tweenTo(MAX_BLUR, TWEEN_IN)
	else
		tweenTo(0, TWEEN_OUT)
	end
end

--============================================================================--
-- PUBLIC
--============================================================================--

--- Tracks a panel: its blur activates/deactivates based on its actual visibility.
--- Idempotent — callable on every open/close.
function Backdrop.track(panel: GuiObject): ()
	if not watched[panel] then
		watched[panel] = true

		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			openPanels[panel] = panel.Visible or nil
			refresh()
		end)

		panel.AncestryChanged:Connect(function()
			if not panel.Parent then
				openPanels[panel] = nil
				watched[panel] = nil
				refresh()
			end
		end)
	end

	openPanels[panel] = panel.Visible or nil
	refresh()
end

--- Fully resets the blur (e.g. context change).
function Backdrop.cleanup(): ()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	table.clear(openPanels)
	table.clear(watched)
	if blur then
		blur:Destroy()
		blur = nil
	end
end

return Backdrop
