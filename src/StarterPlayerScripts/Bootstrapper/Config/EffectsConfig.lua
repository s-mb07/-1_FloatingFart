--!strict
--[[
	@module EffectsConfig
	@description Multi-channel feedback recipes. One id = one sound/visual/camera/haptic bundle.

	Each recipe key corresponds to a channel in Effects/Channels/.
	A missing channel is simply ignored.

	Lives under StarterPlayerScripts: purely cosmetic, no server
	consumer. Nothing here should gate a gameplay value.

	A recipe reads like a timeline: channels start together, and each
	one orders its own steps (sequential steps for Camera, offset by
	`Delay` for Visual).
]]

--- A sound is an authored Sound instance in ReplicatedStorage/Assets/sfx
--- (any subfolder), picked by name: its id, volume, pitch live THERE.
export type SoundSpec = {
	Name: string,            -- name of the Sound under ReplicatedStorage/Assets/sfx
	Group: string?,          -- playing a sound stops the others of its group (see Channels/Sound)
	Stops: {string}?,        -- other groups this sound silences when it starts
}

--- Additive shake, layered on top of the base camera (timeline or default camera).
export type ShakeSpec = {
	Intensity: number,      -- amplitude in studs (math.noise gives +/-0.5, so actual range ~ Intensity/2)
	Duration: number,
	Frequency: number?,     -- oscillations/sec, default 25
}

--- Reference point for a camera move. No absolute CFrame lives in
--- this file: an anchor is always a space + an offset.
---   Subject   -- the model presented by Stage (`Subject` context)
---   Character -- the local player's HumanoidRootPart
---   World     -- raw world coordinates
---   Camera    -- relative to the camera at the moment the recipe starts
export type AnchorSpec = {
	Space: string,
	Offset: Vector3,
}

export type TravelSpec = {
	From: AnchorSpec?,      -- default: camera position at step entry
	To: AnchorSpec,
	LookAt: AnchorSpec?,    -- default: the subject if it exists, otherwise the entry direction is kept
	SpinDegrees: number?,   -- rotation applied to the subject during the step
}

--- A camera step. Steps chain sequentially; a step with neither
--- Travel nor FieldOfView is a `Duration`-second pause.
export type CameraStep = {
	Duration: number,
	Travel: TravelSpec?,
	FieldOfView: number?,
	Shake: ShakeSpec?,
	Easing: string?,        -- Enum.EasingStyle key, default "Quad"
}

export type CameraSpec = {
	Steps: {CameraStep},
	Skippable: boolean?,    -- default true; ignored if no step takes over the camera
	MaxDuration: number?,   -- hard safety net, default = sum of steps + 1
}

--- Haptics via HapticEffect (console, VR and mobile). `Waveform` is the
--- native vibration pattern mechanism: {time_ms, intensity 0-1}, required if Type == "Custom".
--- `Position`/`Radius` are expressed in device space (X=1 -> right side).
export type HapticSpec = {
	Type: string?,          -- "UIHover"|"UIClick"|"UINotification"|"GameplayExplosion"|"GameplayCollision"|"Custom"
	Position: Vector3?,
	Radius: number?,
	Waveform: {{number}}?,
}

--- A UXEffects effect, addressed by name. `Variant` is the module's
--- sub-function (Toast.success, Glow.legendary...), default documented in Visual.lua.
export type VisualStep = {
	Effect: string,
	Variant: string?,
	Delay: number?,
}

export type WorldSpec = {
	Effect: string,          -- name of an asset (Model/ParticleEmitter) under Assets/VFX
	Lifetime: number?,
}

export type Recipe = {
	Sound: SoundSpec?,
	Camera: CameraSpec?,
	Haptic: HapticSpec?,
	Visual: {VisualStep}?,
	World: WorldSpec?,
	Cooldown: number?,      -- seconds, default 0
}

-- Recipe ids are what callers pass to Effects.Play. Sounds are the Sound
-- instances of ReplicatedStorage/Assets/sfx (by name: swap / tune them in
-- Studio); SoundController maps game events here.
local EffectsConfig: {[string]: Recipe} = {
	RewardClaimed = {
		Sound = { Name = "NotifySuccess" },
		Haptic = { Type = "UINotification" },
		Visual = {
			{ Effect = "Burst" },
			{ Effect = "Toast", Variant = "success" },
		},
		Cooldown = 0.25,
	},

	RewardDenied = {
		Haptic = { Type = "UIClick" },
		Visual = { { Effect = "Toast", Variant = "error" } },
		Cooldown = 0.25,
	},

	--== UI ==================================================================--
	-- No cooldowns: every sound plays on its event, a replay restarts it.
	UIClick = {
		Sound = { Name = "UIClick" },
	},
	UIHover = {
		Sound = { Name = "UIHover" },
	},
	-- "Panel" group: a close cuts the open still ringing, and the reverse
	PanelOpen = {
		Sound = { Name = "PanelOpen", Group = "Panel" },
	},
	PanelClose = {
		Sound = { Name = "PanelClose", Group = "Panel" },
	},
	NotifySuccess = {
		Sound = { Name = "NotifySuccess", Group = "Chime" },
	},
	NotifyError = {
		Sound = { Name = "NotifyError", Group = "Chime" },
		Haptic = { Type = "UIClick" },
	},
	NotifyInfo = {
		Sound = { Name = "NotifyInfo", Group = "Chime" },
	},
	TutorialStep = {
		Sound = { Name = "TutorialStep" },
	},

	-- Roblox purchase prompt (PurchasePromptController draws the backdrop itself)
	PurchasePromptOpened = {
		Sound = { Name = "PurchasePromptOpen" },
		Haptic = { Type = "UIClick" },
	},
	-- Rewards claimed (detected from the data snapshot by SoundController);
	-- they silence the generic notification chime of the same claim
	DailyClaim = {
		Sound = { Name = "RewardCollect", Stops = { "Chime" } },
		Haptic = { Type = "UINotification" },
	},
	PlaytimeClaim = {
		Sound = { Name = "RewardCollect", Stops = { "Chime" } },
		Haptic = { Type = "UINotification" },
	},
	-- The Starter Pack is a purchase now: its sound is the purchase one
	-- (PurchasePromptController coin + XP cascade), only the haptic stays here.
	StarterPackClaimed = {
		Haptic = { Type = "UINotification" },
	},

	-- "Don't leave!" (Panels/LeaveReward): a soft alarm beep when the Roblox
	-- menu opens, then the purchase sound when the gift is claimed (played by
	-- the panel itself, Effects.PlayPurchaseFanfare, like a real purchase).
	LeaveWarning = {
		Sound = { Name = "LeaveWarning" },
		Haptic = { Type = "UINotification" },
	},
	LeaveRewardClaimed = {
		Haptic = { Type = "UINotification" },
	},

	-- Sound played by PurchasePromptController itself (coin + XP cascade).
	PurchaseSucceeded = {
		Haptic = { Type = "UINotification" },
	},

	--== Flight ==============================================================--
	-- "Flight" group: the stop / impact / wall cuts the take-off whoosh
	FlyLaunch = {
		Sound = { Name = "FlyLaunch", Group = "Flight" },
		Haptic = { Type = "UIClick" },
	},
	FlyImpact = {
		Sound = { Name = "FlyImpact", Group = "Flight" },
		Haptic = { Type = "GameplayCollision" },
	},
	FlyStop = {
		Sound = { Name = "FlyStop", Group = "Flight" },
	},
	WallLock = {
		Sound = { Name = "WallLock", Group = "Flight" },
		Haptic = { Type = "GameplayCollision" },
	},
	RunLost = {
		Sound = { Name = "RunLost", Group = "Jingle", Stops = { "Chime" } },
	},

	--== Loading screen ======================================================--
	-- Paper plane loading animation cues (LoadingController <- PaperPlaneLoadingScreen).
	-- "Loading" group: each cue cuts the previous whoosh still ringing. The
	-- wind loop is driven by LoadingController itself (Effects.GetSound).
	LoadingSwoop = {
		Sound = { Name = "LoadingSwoop", Group = "Loading" },
	},
	LoadingDive = {
		Sound = { Name = "LoadingDive", Group = "Loading" },
	},
	LoadingThrough = {
		Sound = { Name = "LoadingThrough", Group = "Loading" },
		Haptic = { Type = "GameplayCollision" },
	},

	--== Progression =========================================================--
	XPLand = {
		Sound = { Name = "XPLand" },
	},
	-- Fan boost bubble popped (TrainingBubbleController).
	BubblePop = {
		Sound = { Name = "BubblePop" },
		Haptic = { Type = "UIClick" },
	},
	-- "Jingle" group: one celebration at a time. It silences a notification
	-- chime ("Chime" group) that arrived just before it for the same event,
	-- and SoundController skips chimes while a jingle plays.
	LevelUp = {
		Sound = { Name = "LevelUp", Group = "Jingle", Stops = { "Chime" } },
		Haptic = { Type = "UINotification" },
	},
	Rebirth = {
		Sound = { Name = "Rebirth", Group = "Jingle", Stops = { "Chime" } },
		Haptic = { Type = "UINotification" },
	},
	Win = {
		Sound = { Name = "Win", Group = "Jingle", Stops = { "Chime" } },
		Haptic = { Type = "UINotification" },
	},
}

return EffectsConfig
