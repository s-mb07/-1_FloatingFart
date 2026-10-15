--!strict
--[[
	@module UXEffects.Effects.Pulse
	@description Pulsing effect on UI elements.

	Creates a pulsing animation (scale up/down) with options
	for color, duration, and repeat count.
	Ideal for drawing attention to important elements.
]]

local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)

local Pulse = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_SCALE = 1.15
local DEFAULT_DURATION = 0.25
local DEFAULT_REPEAT_COUNT = 1

--============================================================================--
-- STATE
--============================================================================--

local activePulses: {[GuiObject]: Tween?} = {}
local originalSizes: {[GuiObject]: UDim2} = {}
local originalColors: {[GuiObject]: Color3} = {}

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the pulsing effect on an element.
--- @param target GuiObject The element to animate
--- @param config any Optional configuration
function Pulse.play(target: GuiObject, config: Types.PulseConfig?): ()
	local settings: Types.PulseConfig = config or {}
	local scale = settings.scale or DEFAULT_SCALE
	local duration = settings.duration or DEFAULT_DURATION
	local repeatCount = settings.repeatCount or DEFAULT_REPEAT_COUNT

	-- Stops an existing pulse
	local existingTween = activePulses[target]
	if existingTween then
		existingTween:Cancel()
		activePulses[target] = nil
	end

	-- Saves the original size
	if not originalSizes[target] then
		originalSizes[target] = target.Size
	end

	local baseSize = originalSizes[target]
	local targetSize = UDim2.new(
		baseSize.X.Scale * scale,
		baseSize.X.Offset * scale,
		baseSize.Y.Scale * scale,
		baseSize.Y.Offset * scale
	)

	-- Resets to the original size
	target.Size = baseSize

	-- Pulse animation
	local tweenInfo = TweenInfo.new(
		duration / 2,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		repeatCount - 1,
		true
	)

	local pulseTween = TweenService:Create(target, tweenInfo, {
		Size = targetSize
	})

	-- Handles color if specified
	if settings.color and target:IsA("ImageLabel") then
		local imageTarget = target :: ImageLabel

		if not originalColors[target] then
			originalColors[target] = imageTarget.ImageColor3
		end

		local colorTween = TweenService:Create(imageTarget, tweenInfo, {
			ImageColor3 = settings.color
		})
		colorTween:Play()
	end

	activePulses[target] = pulseTween
	pulseTween:Play()

	pulseTween.Completed:Once(function()
		target.Size = baseSize

		if settings.color and originalColors[target] and target:IsA("ImageLabel") then
			(target :: ImageLabel).ImageColor3 = originalColors[target]
		end

		activePulses[target] = nil
	end)
end

--- Plays a continuous pulse until manually stopped.
--- @param target GuiObject The element to animate
--- @param config any Optional configuration
function Pulse.playLoop(target: GuiObject, config: Types.PulseConfig?): ()
	local settings: Types.PulseConfig = config or {}
	local scale = settings.scale or DEFAULT_SCALE
	local duration = settings.duration or DEFAULT_DURATION

	-- Stops an existing pulse
	Pulse.stop(target)

	-- Saves the original size
	if not originalSizes[target] then
		originalSizes[target] = target.Size
	end

	local baseSize = originalSizes[target]
	local targetSize = UDim2.new(
		baseSize.X.Scale * scale,
		baseSize.X.Offset * scale,
		baseSize.Y.Scale * scale,
		baseSize.Y.Offset * scale
	)

	-- Infinite pulse animation
	local tweenInfo = TweenInfo.new(
		duration / 2,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	)

	local pulseTween = TweenService:Create(target, tweenInfo, {
		Size = targetSize
	})

	activePulses[target] = pulseTween
	pulseTween:Play()
end

--- Stops the pulse on an element.
--- @param target GuiObject The element to stop
--- @param immediate boolean? If true, immediately resets to the original size
function Pulse.stop(target: GuiObject, immediate: boolean?): ()
	local tween = activePulses[target]

	if tween then
		tween:Cancel()
		activePulses[target] = nil
	end

	if immediate ~= false and originalSizes[target] then
		target.Size = originalSizes[target]

		if originalColors[target] and target:IsA("ImageLabel") then
			(target :: ImageLabel).ImageColor3 = originalColors[target]
		end
	end
end

--- Checks whether an element is currently pulsing.
--- @param target GuiObject The element to check
--- @return boolean
function Pulse.isPlaying(target: GuiObject): boolean
	return activePulses[target] ~= nil
end

--- Cleans up every active pulse.
function Pulse.cleanup(): ()
	for target, tween in activePulses do
		if tween then
			tween:Cancel()
		end

		if originalSizes[target] then
			target.Size = originalSizes[target]
		end
	end

	table.clear(activePulses)
	table.clear(originalSizes)
	table.clear(originalColors)
end

return Pulse
