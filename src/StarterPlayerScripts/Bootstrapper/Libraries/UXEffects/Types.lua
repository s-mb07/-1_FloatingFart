--!strict
--[[
	@module UXEffects.Types
	@description Strict types for the UX effects library.

	This module centralizes all type definitions used by the effects,
	ensuring consistency and strong typing across the library.
]]

export type EasingStyle = 
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

export type EasingDirection = 
	"In"
	| "Out"
	| "InOut"

--============================================================================--
-- ANIMATOR TYPES
--============================================================================--

export type AnimationConfig = {
	duration: number,
	easingStyle: EasingStyle?,
	easingDirection: EasingDirection?,
	delay: number?,
	repeatCount: number?,
	reverses: boolean?,
}

export type SpringConfig = {
	damping: number,
	frequency: number,
	mass: number?,
}

--============================================================================--
-- EFFECT TYPES
--============================================================================--

--- Configuration for the FlyToUI effect
export type FlyToUIConfig = {
	iconId: string,
	count: number?,
	iconSize: number?,
	duration: number?,
	spread: number?,
	onComplete: (() -> ())?,
}

--- Configuration for the Burst effect
export type BurstConfig = {
	particleCount: number?,
	colors: {Color3}?,
	size: NumberRange?,
	speed: NumberRange?,
	lifetime: number?,
	spread: number?,
	gravity: number?,
}

--- Configuration for the Shake effect
export type ShakeConfig = {
	intensity: number?,
	duration: number?,
	frequency: number?,
	decay: boolean?,
	axis: ("X" | "Y" | "XY")?,
}

--- Configuration for the Pulse effect
export type PulseConfig = {
	scale: number?,
	duration: number?,
	repeatCount: number?,
	color: Color3?,
}

--- Configuration for the Counter effect
export type CounterConfig = {
	value: number,
	prefix: string?,
	suffix: string?,
	duration: number?,
	color: Color3?,
	floatUp: boolean?,
	floatDistance: number?,
}

--- Configuration for the Confetti effect
export type ConfettiConfig = {
	particleCount: number?,
	colors: {Color3}?,
	spread: number?,
	velocity: number?,
	duration: number?,
	gravity: number?,
	--- Burst mode: spawn points in screen SCALE (0-1). Absent = rain from the top.
	origins: {Vector2}?,
	--- Burst mode: launch angle per origin (degrees, 0 = right, -90 = up).
	angles: {number}?,
	--- Burst mode: random +/- spread around each angle (degrees).
	angleSpread: number?,
}

--- Configuration for the Glow effect
export type GlowConfig = {
	color: Color3?,
	intensity: number?,
	duration: number?,
	pulses: boolean?,
	pulseSpeed: number?,
}

--- Configuration for the Ripple effect
export type RippleConfig = {
	color: Color3?,
	size: number?,
	duration: number?,
	thickness: number?,
	fadeOut: boolean?,
}

--- Configuration for the Toast effect
export type ToastConfig = {
	message: string,
	icon: string?,
	duration: number?,
	position: ("Top" | "Bottom" | "Center")?,
	type: ("Info" | "Success" | "Warning" | "Error")?,
}

--- Configuration for the Scale effect (entrance/exit)
export type ScaleConfig = {
	fromScale: number?,
	toScale: number?,
	duration: number?,
	easingStyle: EasingStyle?,
	easingDirection: EasingDirection?,
}

--- Configuration for the Slide effect
export type SlideConfig = {
	direction: ("Left" | "Right" | "Up" | "Down")?,
	distance: number?,
	duration: number?,
	easingStyle: EasingStyle?,
}

--- Configuration for the Fade effect
export type FadeConfig = {
	fromAlpha: number?,
	toAlpha: number?,
	duration: number?,
	affectChildren: boolean?,
}

--============================================================================--
-- POOL TYPES
--============================================================================--

export type PooledObject<T> = {
	instance: T,
	inUse: boolean,
	lastUsed: number,
}

export type PoolConfig = {
	initialSize: number?,
	maxSize: number?,
	expandSize: number?,
	shrinkThreshold: number?,
}

--============================================================================--
-- CALLBACK TYPES
--============================================================================--

export type EffectCallback = () -> ()
export type ProgressCallback = (progress: number) -> ()

return nil
