--!strict
--[[
	@module UXEffects.Effects.Scale
	@description Scale-based entrance/exit effects.

	Pop-in, pop-out animations for UI elements.
	Ideal for elements appearing/disappearing.

	Implemented via a tweened UIScale (not via target.Size): Size is a
	layout property -- modifying it forces Roblox to recompute the geometry
	of EVERY descendant on every frame of the tween, which can visually
	desync children whose size depends on a nested ScrollingFrame/
	UIListLayout (cf. incident "Achievements ScrollingFrame not
	stuck to the panel during popIn/popOut"). UIScale is a pure rendering
	factor applied to the parent AND all its descendants in the same pass:
	always exactly in sync, no separate layout recompute.
]]

local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)

local Scale = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_DURATION = 0.21
local UISCALE_NAME = "UXEffectsPopScale"

-- Name (string) -> Enum conversion: avoids dynamic access `Enum.X[name]`
-- (not safe for the typechecker, cf. UXEffects.Core.Animator).
local EASING_STYLES: {[Types.EasingStyle]: Enum.EasingStyle} = {
	Linear = Enum.EasingStyle.Linear,
	Quad = Enum.EasingStyle.Quad,
	Cubic = Enum.EasingStyle.Cubic,
	Quart = Enum.EasingStyle.Quart,
	Quint = Enum.EasingStyle.Quint,
	Sine = Enum.EasingStyle.Sine,
	Exponential = Enum.EasingStyle.Exponential,
	Circular = Enum.EasingStyle.Circular,
	Back = Enum.EasingStyle.Back,
	Elastic = Enum.EasingStyle.Elastic,
	Bounce = Enum.EasingStyle.Bounce,
}

local EASING_DIRECTIONS: {[Types.EasingDirection]: Enum.EasingDirection} = {
	In = Enum.EasingDirection.In,
	Out = Enum.EasingDirection.Out,
	InOut = Enum.EasingDirection.InOut,
}

--============================================================================--
-- STATE
--============================================================================--

local activeTweens: {[GuiObject]: Tween} = {}
-- Weak key: no leak if `target` is destroyed without going through popOut/reset.
local uiScales: {[GuiObject]: UIScale} = setmetatable({}, { __mode = "k" }) :: any

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Retrieves (or creates) the UIScale dedicated to `target`'s pop in/out.
local function getUIScale(target: GuiObject): UIScale
	local existing = uiScales[target]
	if existing and existing.Parent then
		return existing
	end

	local uiScale = target:FindFirstChild(UISCALE_NAME) :: UIScale?
	if not uiScale then
		local newScale = Instance.new("UIScale")
		newScale.Name = UISCALE_NAME
		newScale.Parent = target
		uiScale = newScale
	end

	assert(uiScale, "UIScale should have been found or created")
	uiScales[target] = uiScale
	return uiScale
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Entrance animation (pop in).
--- @param target GuiObject The element to animate
--- @param config any Optional configuration
--- @param onComplete any Callback called at the end
function Scale.popIn(target: GuiObject, config: Types.ScaleConfig?, onComplete: (() -> ())?): ()
	local settings: Types.ScaleConfig = config or {}
	local fromScale = settings.fromScale or 0
	local toScale = settings.toScale or 1
	local duration = settings.duration or DEFAULT_DURATION
	local easingStyle: Types.EasingStyle = settings.easingStyle or "Back"
	local easingDirection: Types.EasingDirection = settings.easingDirection or "Out"

	-- Stops an animation in progress
	if activeTweens[target] then
		activeTweens[target]:Cancel()
	end

	local uiScale = getUIScale(target)
	uiScale.Scale = fromScale
	target.Visible = true

	local tweenInfo = TweenInfo.new(
		duration,
		EASING_STYLES[easingStyle],
		EASING_DIRECTIONS[easingDirection]
	)

	local tween = TweenService:Create(uiScale, tweenInfo, {
		Scale = toScale,
	})

	activeTweens[target] = tween
	tween:Play()

	tween.Completed:Once(function(state: Enum.PlaybackState)
		-- Completed ALSO fires on Cancel() (cancellation by a following popIn/popOut
		-- that interrupts this one) -- ignore this case, otherwise this callback
		-- (which belongs to an animation already replaced) would overwrite
		-- activeTweens[target] AFTER the new tween has set it, or fire onComplete twice.
		if state == Enum.PlaybackState.Cancelled then return end
		activeTweens[target] = nil
		if onComplete then
			onComplete()
		end
	end)
end

--- Exit animation (pop out).
--- @param target GuiObject The element to animate
--- @param config any Optional configuration
--- @param onComplete any Callback called at the end
function Scale.popOut(target: GuiObject, config: Types.ScaleConfig?, onComplete: (() -> ())?): ()
	local settings: Types.ScaleConfig = config or {}
	local toScale = settings.toScale or 0
	local duration = settings.duration or DEFAULT_DURATION
	local easingStyle: Types.EasingStyle = settings.easingStyle or "Back"
	local easingDirection: Types.EasingDirection = settings.easingDirection or "In"

	-- Stops an animation in progress
	if activeTweens[target] then
		activeTweens[target]:Cancel()
	end

	local uiScale = getUIScale(target)

	local tweenInfo = TweenInfo.new(
		duration,
		EASING_STYLES[easingStyle],
		EASING_DIRECTIONS[easingDirection]
	)

	local tween = TweenService:Create(uiScale, tweenInfo, {
		Scale = toScale,
	})

	activeTweens[target] = tween
	tween:Play()

	tween.Completed:Once(function(state: Enum.PlaybackState)
		-- Completed ALSO fires on Cancel() (e.g. a popIn reopening the
		-- panel while this popOut is still in flight -- fast re-click/re-keybind).
		-- Without this guard, this callback would set Visible=false AFTER the
		-- popIn has already restored Visible=true: the panel reopens then disappears
		-- immediately, and Backdrop/HudMenuController (driven by the Visible signal)
		-- stay stuck on the "closed" state even though the panel is supposed to remain
		-- open -- blur/background zoom that never restarts correctly.
		if state == Enum.PlaybackState.Cancelled then return end
		activeTweens[target] = nil
		target.Visible = false

		-- Resets the UIScale to 1 (invisible) so the next popIn starts clean.
		uiScale.Scale = 1

		if onComplete then
			onComplete()
		end
	end)
end

--- Bounce animation (springy appearance).
--- @param target GuiObject The element to animate
--- @param config any Optional configuration
function Scale.bounce(target: GuiObject, config: Types.ScaleConfig?): ()
	Scale.popIn(target, {
		fromScale = (config and config.fromScale) or 0,
		toScale = (config and config.toScale) or 1,
		duration = (config and config.duration) or 0.3,
		easingStyle = "Elastic",
		easingDirection = "Out",
	})
end

--- Subtle appearance animation.
--- @param target GuiObject The element to animate
function Scale.fadeIn(target: GuiObject): ()
	Scale.popIn(target, {
		fromScale = 0.85,
		toScale = 1,
		duration = 0.17,
		easingStyle = "Quad",
		easingDirection = "Out",
	})
end

--- Subtle disappearance animation.
--- @param target GuiObject The element to animate
function Scale.fadeOut(target: GuiObject): ()
	Scale.popOut(target, {
		toScale = 0.85,
		duration = 0.13,
		easingStyle = "Quad",
		easingDirection = "In",
	})
end

--- Resets an element to its original size.
--- @param target GuiObject The element to reset
function Scale.reset(target: GuiObject): ()
	if activeTweens[target] then
		activeTweens[target]:Cancel()
		activeTweens[target] = nil
	end

	local uiScale = uiScales[target]
	if uiScale then
		uiScale.Scale = 1
	end
end

--- Cleans up states.
function Scale.cleanup(): ()
	for _, tween in activeTweens do
		tween:Cancel()
	end

	table.clear(activeTweens)
end

return Scale
