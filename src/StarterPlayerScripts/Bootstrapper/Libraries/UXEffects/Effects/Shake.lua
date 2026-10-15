--!strict
--[[
	@module UXEffects.Effects.Shake
	@description Tremble effect for UI or screen.

	Creates a shake/vibration effect on UI elements or the camera.
	Ideal for feedback on impacts, errors, or important actions.

	Characteristics:
	- Support for X, Y, or XY axis
	- Optional progressive decay
	- Adjustable frequency
]]

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local Shake = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_INTENSITY = 10
local DEFAULT_DURATION = 0.3
local DEFAULT_FREQUENCY = 30
local DEFAULT_AXIS = "XY"

--============================================================================--
-- STATE
--============================================================================--

local activeShakes: {[GuiObject]: {
	connection: RBXScriptConnection,
	originalPosition: UDim2,
}} = {}

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Generates a random shake offset.
local function getShakeOffset(intensity: number, axis: string): (number, number)
	local offsetX = 0
	local offsetY = 0
	
	if axis == "X" or axis == "XY" then
		offsetX = (math.random() - 0.5) * 2 * intensity
	end
	
	if axis == "Y" or axis == "XY" then
		offsetY = (math.random() - 0.5) * 2 * intensity
	end
	
	return offsetX, offsetY
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the shake effect on a UI element.
--- @param target GuiObject The element to shake
--- @param config any Optional configuration
function Shake.play(target: GuiObject, config: Types.ShakeConfig?): ()
	local settings: Types.ShakeConfig = config or {}
	local intensity = settings.intensity or DEFAULT_INTENSITY
	local duration = settings.duration or DEFAULT_DURATION
	local frequency = settings.frequency or DEFAULT_FREQUENCY
	local decay = settings.decay ~= false
	local axis = settings.axis or DEFAULT_AXIS

	-- Stops an existing shake
	Shake.stop(target)

	-- Saves the original position
	local originalPosition = target.Position
	
	local startTime = tick()
	local lastShakeTime = startTime
	local shakeInterval = 1 / frequency
	
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		
		if elapsed >= duration then
			connection:Disconnect()
			target.Position = originalPosition
			activeShakes[target] = nil
			return
		end
		
		local currentTime = tick()
		if currentTime - lastShakeTime < shakeInterval then
			return
		end
		lastShakeTime = currentTime
		
		-- Computes intensity with decay
		local currentIntensity = intensity
		if decay then
			local progress = elapsed / duration
			currentIntensity = intensity * (1 - progress)
		end

		-- Applies the shake
		local offsetX, offsetY = getShakeOffset(currentIntensity, axis :: string)
		
		target.Position = UDim2.new(
			originalPosition.X.Scale,
			originalPosition.X.Offset + offsetX,
			originalPosition.Y.Scale,
			originalPosition.Y.Offset + offsetY
		)
	end)
	
	activeShakes[target] = {
		connection = connection,
		originalPosition = originalPosition,
	}
end

--- Plays a quick shake (error feedback).
--- @param target GuiObject The element to shake
function Shake.error(target: GuiObject): ()
	Shake.play(target, {
		intensity = 8,
		duration = 0.25,
		frequency = 40,
		axis = "X",
		decay = true,
	})
end

--- Plays an impact shake (collision feedback).
--- @param target GuiObject The element to shake
--- @param intensity number? Impact intensity (default: 15)
function Shake.impact(target: GuiObject, intensity: number?): ()
	Shake.play(target, {
		intensity = intensity or 15,
		duration = 0.2,
		frequency = 50,
		axis = "XY",
		decay = true,
	})
end

--- Plays a continuous shake (vibration).
--- @param target GuiObject The element to shake
--- @param intensity number? Vibration intensity (default: 3)
function Shake.vibrate(target: GuiObject, intensity: number?): ()
	Shake.play(target, {
		intensity = intensity or 3,
		duration = 999999,
		frequency = 60,
		axis = "XY",
		decay = false,
	})
end

--- Stops the shake on an element.
--- @param target GuiObject The element to stop
function Shake.stop(target: GuiObject): ()
	local shakeData = activeShakes[target]
	
	if shakeData then
		shakeData.connection:Disconnect()
		target.Position = shakeData.originalPosition
		activeShakes[target] = nil
	end
end

--- Checks whether an element is currently shaking.
--- @param target GuiObject The element to check
--- @return boolean
function Shake.isPlaying(target: GuiObject): boolean
	return activeShakes[target] ~= nil
end

--- Cleans up all active shakes.
function Shake.cleanup(): ()
	for target, shakeData in activeShakes do
		shakeData.connection:Disconnect()
		target.Position = shakeData.originalPosition
	end
	
	table.clear(activeShakes)
end

return Shake
