--!strict
--[[
	@module UIAnimationConfig
	@description Tunable constants for opening/closing UI panels:
	panel zoom (Scale), background blur (Backdrop) and camera
	zoom (e.g. a controller that zooms the camera while a menu is open).

	A single file to edit to retune these 3 effects on ALL panels at
	once -- consumed by UXEffects.Effects.Backdrop and UXEffects.Effects.
	PanelTransition. Don't duplicate these values elsewhere.
]]

export type PanelScaleConfig = {
	fromScale: number?,
	toScale: number?,
	duration: number,
	easingStyle: string,
	easingDirection: string,
}

export type UIAnimationConfig = {
	PanelOpen: PanelScaleConfig,
	PanelClose: PanelScaleConfig,
	Blur: { max: number, tweenIn: number, tweenOut: number },
	CameraZoom: { fov: number, fovDefault: number, duration: number },
}

local Config: UIAnimationConfig = {
	-- Panel opening zoom (UXEffects.Scale.popIn).
	PanelOpen = {
		fromScale = 0,
		toScale = 1,
		duration = 0.21,
		easingStyle = "Back",
		easingDirection = "Out",
	},
	-- Panel closing zoom (UXEffects.Scale.popOut).
	PanelClose = {
		toScale = 0,
		duration = 0.17,
		easingStyle = "Back",
		easingDirection = "In",
	},
	-- 3D background blur while a panel is open (UXEffects.Effects.Backdrop).
	Blur = {
		max = 26,
		tweenIn = 0.21,
		tweenOut = 0.17,
	},
	-- Camera zoom (FOV) while a menu is open.
	CameraZoom = {
		fov = 50,
		fovDefault = 70,
		duration = 0.3,
	},
}

return Config
