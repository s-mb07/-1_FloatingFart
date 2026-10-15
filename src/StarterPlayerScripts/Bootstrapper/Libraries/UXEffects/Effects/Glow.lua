--!strict
--[[
	@module UXEffects.Effects.Glow
	@description Dynamic glow effect on UI elements.

	Adds an animated luminous halo around an element.
	Perfect for highlighting rare, active, or important elements.
]]

local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)

local Glow = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_COLOR = Color3.fromRGB(255, 215, 0)
local DEFAULT_INTENSITY = 0.3
local DEFAULT_PULSE_SPEED = 1.5

--============================================================================--
-- STATE
--============================================================================--

local activeGlows: {[GuiObject]: {
	glowFrame: Frame,
	tween: Tween?,
}} = {}

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Creates the glow frame.
local function createGlowFrame(target: GuiObject, color: Color3): Frame
	local glow = Instance.new("Frame")
	glow.Name = "UXGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 8, 1, 8)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.7
	glow.ZIndex = target.ZIndex - 1
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = glow
	
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = glow
	
	glow.Parent = target
	
	return glow
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Activates a glow effect on an element.
--- @param target GuiObject The target element
--- @param config any Optional configuration
function Glow.apply(target: GuiObject, config: Types.GlowConfig?): ()
	local settings: Types.GlowConfig = config or {}
	local color = settings.color or DEFAULT_COLOR
	local intensity = settings.intensity or DEFAULT_INTENSITY
	local pulses = settings.pulses ~= false
	local pulseSpeed = settings.pulseSpeed or DEFAULT_PULSE_SPEED

	-- Removes an existing glow
	Glow.remove(target)

	-- Creates the glow
	local glowFrame = createGlowFrame(target, color)
	local baseTransparency = 0.7 - (intensity * 0.2)
	glowFrame.BackgroundTransparency = baseTransparency
	
	local tween: Tween? = nil

	-- Pulse animation
	if pulses then
		local tweenInfo = TweenInfo.new(
			pulseSpeed / 2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		)

		local pulseTween = TweenService:Create(glowFrame, tweenInfo, {
			Size = UDim2.new(1, 14, 1, 14),
			BackgroundTransparency = baseTransparency + 0.08,
		})

		pulseTween:Play()
		tween = pulseTween
	end
	
	activeGlows[target] = {
		glowFrame = glowFrame,
		tween = tween,
	}
end

--- Removes the glow from an element.
--- @param target GuiObject The target element
function Glow.remove(target: GuiObject): ()
	local glowData = activeGlows[target]
	
	if glowData then
		if glowData.tween then
			glowData.tween:Cancel()
		end
		glowData.glowFrame:Destroy()
		activeGlows[target] = nil
	end
end

--- Checks whether an element has an active glow.
--- @param target GuiObject The element to check
--- @return boolean
function Glow.isActive(target: GuiObject): boolean
	return activeGlows[target] ~= nil
end

--- Changes the color of an existing glow.
--- @param target GuiObject The target element
--- @param color Color3 New color
--- @param duration number? Transition duration
function Glow.setColor(target: GuiObject, color: Color3, duration: number?): ()
	local glowData = activeGlows[target]
	
	if glowData then
		local transitionDuration = duration or 0.25
		
		local tweenInfo = TweenInfo.new(
			transitionDuration,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
		
		local colorTween = TweenService:Create(glowData.glowFrame, tweenInfo, {
			BackgroundColor3 = color
		})
		
		colorTween:Play()
	end
end

--- Golden glow (common rarity for items).
--- @param target GuiObject The target element
function Glow.gold(target: GuiObject): ()
	Glow.apply(target, {
		color = Color3.fromRGB(255, 215, 0),
		intensity = 1,
		pulses = true,
	})
end

--- Legendary glow (purple).
--- @param target GuiObject The target element
function Glow.legendary(target: GuiObject): ()
	Glow.apply(target, {
		color = Color3.fromRGB(170, 0, 255),
		intensity = 1.5,
		pulses = true,
		pulseSpeed = 1.2,
	})
end

--- Rare glow (blue).
--- @param target GuiObject The target element
function Glow.rare(target: GuiObject): ()
	Glow.apply(target, {
		color = Color3.fromRGB(0, 150, 255),
		intensity = 0.8,
		pulses = true,
	})
end

--- Cleans up all glows.
function Glow.cleanup(): ()
	for _target, glowData in activeGlows do
		if glowData.tween then
			glowData.tween:Cancel()
		end
		glowData.glowFrame:Destroy()
	end
	
	table.clear(activeGlows)
end

return Glow
