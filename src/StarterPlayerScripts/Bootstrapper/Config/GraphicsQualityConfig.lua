--!strict
--[[
	@module GraphicsQualityConfig
	@description A SINGLE global quality level, expressed as presets -- not
	a checkbox per effect.

	Why a single level: fifteen independent booleans produce combinations
	nobody tests, contradict each other (turning off decorations but keeping
	their loop at 60 Hz), and become unreadable in the menu. Here there's a
	single persisted field (`Settings.GraphicsQuality`), and each system
	reads the value that concerns it from the preset.

	`Auto` is not a level: it means "let a QualityController decide", and
	it's the default. A player who explicitly picks a level keeps their
	choice, even if detection would disagree.

	The central lever is `CosmeticRateScale`: applied by Scheduler to every
	task marked cosmetic, it drops the cadence of all decorative work at
	once without any caller needing to know. Gameplay tasks (proximity,
	harvesting, countdown) are never touched.

	`Preset` only holds the 2 generic levers (Scheduler cadence + cull
	radius). Add your own gameplay booleans to it as you go (e.g.
	"Decorations", "SeedBob"...) rather than guessing a list up front.
]]

local GraphicsQualityConfig = {}

--============================================================================--
-- TYPES
--============================================================================--

export type QualityLevel = "Low" | "Medium" | "High"
--- What is actually stored in `Settings.GraphicsQuality`.
export type QualitySetting = "Auto" | "Low" | "Medium" | "High"

export type Preset = {
	--- Rate multiplier for cosmetic Scheduler tasks (1 = cadence requested
	--- by the caller). 0.5 = half as often.
	CosmeticRateScale: number,
	--- Multiplier for cull radii (1 = nominal radius). Lower = effects stop
	--- closer to the camera.
	CullScale: number,
}

--============================================================================--
-- PRESETS
--============================================================================--

GraphicsQualityConfig.SETTING_KEY = "GraphicsQuality"
GraphicsQualityConfig.DEFAULT_SETTING = "Auto" :: QualitySetting

--- Display order in the menu (the cycle button steps through this).
GraphicsQualityConfig.SETTING_VALUES = { "Auto", "Low", "Medium", "High" } :: { QualitySetting }

local PRESETS: { [QualityLevel]: Preset } = {
	-- Low stays playable: half the cosmetic cadence, not a third (at 0.34
	-- the tutorial guide and sparkles visibly stuttered on weak devices).
	Low = {
		CosmeticRateScale = 0.5,
		CullScale = 0.6,
	},
	Medium = {
		CosmeticRateScale = 0.75,
		CullScale = 0.8,
	},
	High = {
		CosmeticRateScale = 1,
		CullScale = 1,
	},
}

GraphicsQualityConfig.Presets = PRESETS

--============================================================================--
-- AUTOMATIC DETECTION
--============================================================================--

GraphicsQualityConfig.Autodetect = {
	--- Duration (s) of frame time sampling at startup. The decision is made
	--- ONCE: no continuous degradation during play, which would oscillate
	--- (quality drops -> FPS climbs -> quality climbs -> FPS drops again)
	--- and change the visuals under the player's fingers without
	--- explanation.
	SampleDuration = 10,
	--- The first frames of a session include asset loading: they're
	--- discarded before measuring.
	WarmupDuration = 5,
	--- Thresholds on the MEDIAN of sampled frame times (ms). Median, not
	--- average: a single loading spike must not classify a good machine as
	--- Low.
	LowAboveMs = 33, -- ~30 FPS
	MediumAboveMs = 20, -- ~50 FPS
}

--- Level inferred from a median frame time.
--- @param medianMs number
--- @return QualityLevel
function GraphicsQualityConfig.LevelForFrameTime(medianMs: number): QualityLevel
	local thresholds = GraphicsQualityConfig.Autodetect
	if medianMs > thresholds.LowAboveMs then
		return "Low"
	end
	if medianMs > thresholds.MediumAboveMs then
		return "Medium"
	end
	return "High"
end

--- Validates a value coming from player data (which may date back to a
--- version where the levels weren't the same).
--- @param value any
--- @return QualitySetting
function GraphicsQualityConfig.SanitizeSetting(value: any): QualitySetting
	for _, candidate in GraphicsQualityConfig.SETTING_VALUES do
		if value == candidate then
			return candidate
		end
	end
	return GraphicsQualityConfig.DEFAULT_SETTING
end

--- @param level QualityLevel
--- @return Preset
function GraphicsQualityConfig.PresetFor(level: QualityLevel): Preset
	return PRESETS[level] or PRESETS.High
end

return GraphicsQualityConfig
