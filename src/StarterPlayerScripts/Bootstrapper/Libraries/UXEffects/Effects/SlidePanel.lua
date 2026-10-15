--!strict
--[[
	@module UXEffects.Effects.SlidePanel
	@description Slides a UI panel from/to offscreen (top).

	Animates a GuiObject from offscreen (top) to its rest position,
	or in the reverse direction when closing.

	@usage
	```lua
	local UXEffects = require(Bootstrapper.Libraries.UXEffects)

	-- Opening from offscreen (top) toward the rest position
	UXEffects.SlidePanel.slideIn(myFrame, {
		targetPosition = UDim2.new(0.5, 0, 0.45, 0),
	})

	-- Closing toward offscreen (top), with callback
	UXEffects.SlidePanel.slideOut(myFrame, {
		targetPosition = UDim2.new(0.5, 0, 0.45, 0),
	}, function()
		myGui.Enabled = false
	end)
	```
]]

local TweenService = game:GetService("TweenService")

local SlidePanel = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_DURATION_IN  = 0.24
local DEFAULT_DURATION_OUT = 0.19

-- Offscreen offset multiplier
local OFFSCREEN_OFFSET = 1.5

--============================================================================--
-- TYPES
--============================================================================--

export type SlideDirection = "Top" | "Bottom" | "Left" | "Right"

export type SlideEasingStyle =
	"Linear"
	| "Quad"
	| "Cubic"
	| "Quart"
	| "Quint"
	| "Sine"
	| "Exponential"
	| "Circular"
	| "Back"
	| "Elastic"
	| "Bounce"

export type SlideEasingDirection = "In" | "Out" | "InOut"

export type SlidePanelConfig = {
	--- Target rest position (default: UDim2.new(0.5, 0, 0.45, 0))
	targetPosition: UDim2?,
	--- Slide direction (default: "Top")
	direction: SlideDirection?,
	--- Animation duration in seconds
	duration: number?,
	--- Easing style (Enum.EasingStyle name, default "Quint")
	easingStyle: SlideEasingStyle?,
	--- Easing direction (Enum.EasingDirection name, default "Out" for in, "In" for out)
	easingDirection: SlideEasingDirection?,
}

-- Name (string) -> Enum conversion: avoids dynamic access `Enum.X[name]`
-- (not safe for the typechecker, cf. UXEffects.Core.Animator).
local EASING_STYLES: {[SlideEasingStyle]: Enum.EasingStyle} = {
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

local EASING_DIRECTIONS: {[SlideEasingDirection]: Enum.EasingDirection} = {
	In = Enum.EasingDirection.In,
	Out = Enum.EasingDirection.Out,
	InOut = Enum.EasingDirection.InOut,
}

--============================================================================--
-- STATE
--============================================================================--

-- Active tweens per target, for clean cancellation before restarting
local activeTweens: {[GuiObject]: Tween} = {}

--============================================================================--
-- PRIVATE
--============================================================================--

local function getOffscreenPosition(restPos: UDim2, direction: SlideDirection): UDim2
	if direction == "Top" then
		return UDim2.new(restPos.X.Scale, restPos.X.Offset, -OFFSCREEN_OFFSET, 0)
	elseif direction == "Bottom" then
		return UDim2.new(restPos.X.Scale, restPos.X.Offset, OFFSCREEN_OFFSET, 0)
	elseif direction == "Left" then
		return UDim2.new(-OFFSCREEN_OFFSET, 0, restPos.Y.Scale, restPos.Y.Offset)
	elseif direction == "Right" then
		return UDim2.new(OFFSCREEN_OFFSET, 0, restPos.Y.Scale, restPos.Y.Offset)
	end
	return UDim2.new(restPos.X.Scale, restPos.X.Offset, -OFFSCREEN_OFFSET, 0)
end

local function cancelActive(target: GuiObject): ()
	if activeTweens[target] then
		activeTweens[target]:Cancel()
		activeTweens[target] = nil
	end
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Slides a panel from offscreen to its rest position.
--- The panel is made visible before the animation.
--- @param target  GuiObject       Panel to animate
--- @param config  SlidePanelConfig?
--- @param onDone  (() -> ())?     Callback called at the end of the animation
function SlidePanel.slideIn(target: GuiObject, config: SlidePanelConfig?, onDone: (() -> ())?): ()
	local cfg: SlidePanelConfig = config or {}
	local restPos  = cfg.targetPosition  or target.Position
	local direction: SlideDirection = cfg.direction      or "Top"
	local duration = cfg.duration        or DEFAULT_DURATION_IN
	local eStyle: SlideEasingStyle = cfg.easingStyle     or "Quint"
	local eDir: SlideEasingDirection = cfg.easingDirection or "Out"

	cancelActive(target)

	-- Places the panel offscreen before making it visible
	target.Position = getOffscreenPosition(restPos, direction)
	target.Visible  = true

	local tweenInfo = TweenInfo.new(duration, EASING_STYLES[eStyle], EASING_DIRECTIONS[eDir])
	local tween = TweenService:Create(target, tweenInfo, { Position = restPos })

	activeTweens[target] = tween
	tween:Play()

	tween.Completed:Once(function(state: Enum.PlaybackState)
		-- Completed ALSO fires on Cancel() (e.g. a slideOut interrupting
		-- this slideIn) -- ignore this case, otherwise this callback would overwrite
		-- activeTweens[target] AFTER the new tween has set it (cf. incident documented in Scale.lua).
		if state == Enum.PlaybackState.Cancelled then return end
		activeTweens[target] = nil
		if onDone then
			task.spawn(onDone)
		end
	end)
end

--- Slides a panel from its position toward offscreen, then calls the callback.
--- The panel is hidden (Visible = false) after exiting.
--- @param target  GuiObject       Panel to animate
--- @param config  SlidePanelConfig?
--- @param onDone  (() -> ())?     Callback called after exiting
function SlidePanel.slideOut(target: GuiObject, config: SlidePanelConfig?, onDone: (() -> ())?): ()
	local cfg: SlidePanelConfig = config or {}
	local restPos  = cfg.targetPosition  or target.Position
	local direction: SlideDirection = cfg.direction      or "Top"
	local duration = cfg.duration        or DEFAULT_DURATION_OUT
	local eStyle: SlideEasingStyle = cfg.easingStyle     or "Quint"
	local eDir: SlideEasingDirection = cfg.easingDirection or "In"

	cancelActive(target)

	local offPos = getOffscreenPosition(restPos, direction)

	local tweenInfo = TweenInfo.new(duration, EASING_STYLES[eStyle], EASING_DIRECTIONS[eDir])
	local tween = TweenService:Create(target, tweenInfo, { Position = offPos })

	activeTweens[target] = tween
	tween:Play()

	tween.Completed:Once(function(state: Enum.PlaybackState)
		-- Cf. slideIn above: ignore Cancelled so as not to set Visible=false
		-- AFTER a following slideIn has already reopened the panel.
		if state == Enum.PlaybackState.Cancelled then return end
		activeTweens[target] = nil
		target.Visible = false
		if onDone then
			task.spawn(onDone)
		end
	end)
end

--- Cancels any animation currently running on the given target.
--- @param target GuiObject
function SlidePanel.cancel(target: GuiObject): ()
	cancelActive(target)
end

--- Global cleanup of all animations in progress.
function SlidePanel.cleanup(): ()
	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

return SlidePanel
