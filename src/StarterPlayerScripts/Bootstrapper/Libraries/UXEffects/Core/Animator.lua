--!strict
--[[
	@module UXEffects.Core.Animator
	@description Unified animation engine for UX effects.

	Provides utilities for creating smooth animations with:
	- Classic tweens with multiple easing styles
	- Spring animations for a more natural feel
	- Chained animation sequences
	- Parallel animations
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

local Animator = {}

--============================================================================--
-- EASING CONVERSION
--============================================================================--

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
-- TWEEN HELPERS
--============================================================================--

--- Creates a TweenInfo from a configuration.
--- @param config any
--- @return TweenInfo
function Animator.createTweenInfo(config: Types.AnimationConfig): TweenInfo
	local easingStyle: Types.EasingStyle = config.easingStyle or "Quad"
	local easingDirection: Types.EasingDirection = config.easingDirection or "Out"
	local style = EASING_STYLES[easingStyle]
	local direction = EASING_DIRECTIONS[easingDirection]

	return TweenInfo.new(
		config.duration,
		style,
		direction,
		config.repeatCount or 0,
		config.reverses or false,
		config.delay or 0
	)
end

--- Animates an object towards target properties.
--- @param target Instance The object to animate
--- @param properties any The properties to animate
--- @param config any Animation configuration
--- @return Tween
function Animator.tween(
	target: Instance,
	properties: {[string]: any},
	config: Types.AnimationConfig
): Tween
	local tweenInfo = Animator.createTweenInfo(config)
	local tween = TweenService:Create(target, tweenInfo, properties)
	tween:Play()
	return tween
end

--- Animates an object and returns a Promise-like (via callback).
--- @param target Instance The object to animate
--- @param properties any The properties to animate
--- @param config any Animation configuration
--- @param onComplete any Callback called on completion
function Animator.tweenAsync(
	target: Instance,
	properties: {[string]: any},
	config: Types.AnimationConfig,
	onComplete: (() -> ())?
): ()
	local tween = Animator.tween(target, properties, config)

	if onComplete then
		tween.Completed:Once(function()
			onComplete()
		end)
	end
end

--============================================================================--
-- SPRING ANIMATION
--============================================================================--

--- Animates a value with spring behavior.
--- @param current number Current value
--- @param target number Target value
--- @param velocity number Current velocity
--- @param config any Spring configuration
--- @param deltaTime number Time elapsed since the last frame
--- @return number, number New value and new velocity
function Animator.springStep(
	current: number,
	target: number,
	velocity: number,
	config: Types.SpringConfig,
	deltaTime: number
): (number, number)
	local mass = config.mass or 1
	local damping = config.damping
	local frequency = config.frequency

	local displacement = current - target
	local springForce = -frequency * frequency * displacement
	local dampingForce = -2 * damping * frequency * velocity

	local acceleration = (springForce + dampingForce) / mass
	local newVelocity = velocity + acceleration * deltaTime
	local newValue = current + newVelocity * deltaTime

	return newValue, newVelocity
end

--- Animates a GuiObject with a spring towards a position.
--- @param target GuiObject The object to animate
--- @param targetPosition UDim2 Target position
--- @param config any Spring configuration
--- @param onComplete any Callback called on completion
function Animator.springToPosition(
	target: GuiObject,
	targetPosition: UDim2,
	config: Types.SpringConfig,
	onComplete: (() -> ())?
): ()
	local currentX = target.Position.X.Offset
	local currentY = target.Position.Y.Offset
	local targetX = targetPosition.X.Offset
	local targetY = targetPosition.Y.Offset

	local velocityX = 0
	local velocityY = 0

	local connection: RBXScriptConnection?
	local threshold = 0.5
	local velocityThreshold = 0.1

	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		currentX, velocityX = Animator.springStep(currentX, targetX, velocityX, config, deltaTime)
		currentY, velocityY = Animator.springStep(currentY, targetY, velocityY, config, deltaTime)

		target.Position = UDim2.new(
			targetPosition.X.Scale, currentX,
			targetPosition.Y.Scale, currentY
		)

		-- Checks whether the target has been reached
		local distX = math.abs(currentX - targetX)
		local distY = math.abs(currentY - targetY)
		local speedX = math.abs(velocityX)
		local speedY = math.abs(velocityY)

		if distX < threshold and distY < threshold and speedX < velocityThreshold and speedY < velocityThreshold then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			target.Position = targetPosition
			if onComplete then
				onComplete()
			end
		end
	end)
end

--- Animates a GuiObject with a spring towards a size.
--- @param target GuiObject The object to animate
--- @param targetSize UDim2 Target size
--- @param config any Spring configuration
--- @param onComplete any Callback called on completion
function Animator.springToSize(
	target: GuiObject,
	targetSize: UDim2,
	config: Types.SpringConfig,
	onComplete: (() -> ())?
): ()
	local currentX = target.Size.X.Offset
	local currentY = target.Size.Y.Offset
	local targetX = targetSize.X.Offset
	local targetY = targetSize.Y.Offset

	local velocityX = 0
	local velocityY = 0

	local connection: RBXScriptConnection?
	local threshold = 0.5
	local velocityThreshold = 0.1

	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		currentX, velocityX = Animator.springStep(currentX, targetX, velocityX, config, deltaTime)
		currentY, velocityY = Animator.springStep(currentY, targetY, velocityY, config, deltaTime)

		target.Size = UDim2.new(
			targetSize.X.Scale, currentX,
			targetSize.Y.Scale, currentY
		)

		local distX = math.abs(currentX - targetX)
		local distY = math.abs(currentY - targetY)
		local speedX = math.abs(velocityX)
		local speedY = math.abs(velocityY)

		if distX < threshold and distY < threshold and speedX < velocityThreshold and speedY < velocityThreshold then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			target.Size = targetSize
			if onComplete then
				onComplete()
			end
		end
	end)
end

--============================================================================--
-- SEQUENCE & PARALLEL
--============================================================================--

--- Runs a sequence of animations one after another.
--- @param animations any List of animation functions
--- @param onComplete any Callback called on completion
function Animator.sequence(animations: {() -> ()}, onComplete: (() -> ())?): ()
	task.spawn(function()
		for _, animation in animations do
			animation()
			-- Note: each animation must handle its own waiting
			-- Use coroutines or signals for synchronization
		end
		if onComplete then
			onComplete()
		end
	end)
end

--- Runs several animations in parallel.
--- @param animations any List of animation functions
--- @param onComplete any Callback called once all are finished
function Animator.parallel(animations: {() -> ()}, onComplete: (() -> ())?): ()
	local remaining = #animations

	if remaining == 0 then
		if onComplete then
			onComplete()
		end
		return
	end

	for _, animation in animations do
		task.spawn(function()
			animation()
			remaining -= 1
			if remaining == 0 and onComplete then
				onComplete()
			end
		end)
	end
end

--============================================================================--
-- UTILITY FUNCTIONS
--============================================================================--

--- Linearly interpolates between two values.
--- @param a number Start value
--- @param b number End value
--- @param t number Interpolation factor (0-1)
--- @return number
function Animator.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Linearly interpolates between two Color3.
--- @param a Color3 Start color
--- @param b Color3 End color
--- @param t number Interpolation factor (0-1)
--- @return Color3
function Animator.lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		Animator.lerp(a.R, b.R, t),
		Animator.lerp(a.G, b.G, t),
		Animator.lerp(a.B, b.B, t)
	)
end

--- Linearly interpolates between two UDim2.
--- @param a UDim2 Start position
--- @param b UDim2 End position
--- @param t number Interpolation factor (0-1)
--- @return UDim2
function Animator.lerpUDim2(a: UDim2, b: UDim2, t: number): UDim2
	return UDim2.new(
		Animator.lerp(a.X.Scale, b.X.Scale, t),
		Animator.lerp(a.X.Offset, b.X.Offset, t),
		Animator.lerp(a.Y.Scale, b.Y.Scale, t),
		Animator.lerp(a.Y.Offset, b.Y.Offset, t)
	)
end

return Animator
