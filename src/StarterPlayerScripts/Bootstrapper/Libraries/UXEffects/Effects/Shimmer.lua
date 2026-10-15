--!strict
--[[
	@module UXEffects.Effects.Shimmer
	@description Shimmer effect for UI gradients.

	Animates UI gradients to create shine and motion effects
	(special rarity, enchanted item, any gradient that needs to "live").

	Animation modes:
	- "Rotate": Pure gradient rotation (premium AAA effect)
	- "Scroll": Offset scrolling (discouraged, cheap-looking effect)
	- "Rainbow": Slow scroll for rainbow effects
]]

local RunService = game:GetService("RunService")

local Shimmer = {}

--============================================================================--
-- TYPES
--============================================================================--

type AnimationType = "Rotate" | "Scroll" | "Rainbow"

type ShimmerData = {
	connection: RBXScriptConnection?,
	animationSpeed: number,
	rotationSpeed: number,
	animationType: AnimationType,
	currentRotation: number,
	currentOffset: Vector2,
}

type ShimmerConfig = {
	animationSpeed: number?,
	rotationSpeed: number?,
	animationType: string?,
}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_ROTATION_SPEED = 30

--============================================================================--
-- STATE
--============================================================================--

local activeShimmers: {[UIGradient]: ShimmerData} = {}

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Stops an existing shimmer animation.
local function stopShimmer(gradient: UIGradient): ()
	local shimmerData = activeShimmers[gradient]
	if shimmerData then
		if shimmerData.connection and shimmerData.connection.Connected then
			shimmerData.connection:Disconnect()
		end
		activeShimmers[gradient] = nil
	end
end

--- Updates the gradient animation.
local function updateGradient(gradient: UIGradient, shimmerData: ShimmerData, deltaTime: number): ()
	-- Scrolling animation (Rainbow mode only)
	if shimmerData.animationType == "Rainbow" and shimmerData.animationSpeed > 0 then
		local offsetDelta = deltaTime * shimmerData.animationSpeed
		local newOffsetX = (shimmerData.currentOffset.X + offsetDelta) % 1

		gradient.Offset = Vector2.new(newOffsetX, 0)
		shimmerData.currentOffset = Vector2.new(newOffsetX, 0)
	end

	-- Continuous rotation (main AAA mode)
	if shimmerData.rotationSpeed > 0 then
		local rotationDelta = deltaTime * shimmerData.rotationSpeed
		local newRotation = (shimmerData.currentRotation + rotationDelta) % 360
		
		gradient.Rotation = newRotation
		shimmerData.currentRotation = newRotation
	end
end

--- Creates the animation loop for a gradient.
local function createAnimationLoop(gradient: UIGradient, shimmerData: ShimmerData): RBXScriptConnection
	return RunService.RenderStepped:Connect(function(deltaTime: number)
		if not gradient then
			return
		end

		if not gradient.Parent then
			stopShimmer(gradient)
			return
		end
		
		local currentActiveData = activeShimmers[gradient]
		if not currentActiveData or currentActiveData ~= shimmerData then
			return
		end
		
		-- Clamps deltaTime to avoid jumps in case of lag
		local clampedDelta = math.min(deltaTime, 0.033)
		
		updateGradient(gradient, shimmerData, clampedDelta)
	end)
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays a shimmer effect on a gradient.
--- @param gradient UIGradient The gradient to animate
--- @param config table? Configuration with rotationSpeed, animationType
function Shimmer.play(gradient: UIGradient, config: ShimmerConfig?): ()
	if not gradient or not gradient.Parent then
		return
	end

	local settings: ShimmerConfig = config or {}
	local animationSpeed = settings.animationSpeed or 0
	local rotationSpeed = settings.rotationSpeed or DEFAULT_ROTATION_SPEED
	local animationType: AnimationType = (settings.animationType or "Rotate") :: AnimationType
	
	-- Checks whether an identical animation is already active
	local existingData = activeShimmers[gradient]
	if existingData then
		if existingData.animationSpeed == animationSpeed 
			and existingData.rotationSpeed == rotationSpeed 
			and existingData.animationType == animationType then
			return
		else
			if existingData.connection and existingData.connection.Connected then
				existingData.connection:Disconnect()
			end
			activeShimmers[gradient] = nil
		end
	end
	
	-- Initializes from the gradient's current state (continuity)
	local currentRotation = gradient.Rotation or 0
	local currentOffset = gradient.Offset or Vector2.new(0, 0)
	
	local shimmerData: ShimmerData = {
		connection = nil,
		animationSpeed = animationSpeed,
		rotationSpeed = rotationSpeed,
		animationType = animationType,
		currentRotation = currentRotation,
		currentOffset = currentOffset,
	}
	
	local connection = createAnimationLoop(gradient, shimmerData)
	shimmerData.connection = connection
	
	activeShimmers[gradient] = shimmerData
end

--- Stops the shimmer animation of a gradient.
--- @param gradient UIGradient The gradient to stop
function Shimmer.stop(gradient: UIGradient): ()
	stopShimmer(gradient)
end

--- Checks whether a gradient has an active shimmer animation.
--- @param gradient UIGradient The gradient to check
--- @return boolean
function Shimmer.isActive(gradient: UIGradient): boolean
	return activeShimmers[gradient] ~= nil
end

--- Cleans up all shimmer animations.
function Shimmer.cleanup(): ()
	for _, shimmerData in activeShimmers do
		if shimmerData.connection and shimmerData.connection.Connected then
			shimmerData.connection:Disconnect()
		end
	end
	
	table.clear(activeShimmers)
end

return Shimmer
