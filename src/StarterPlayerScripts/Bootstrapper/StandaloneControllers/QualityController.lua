--!strict
--[[
	@module QualityController
	@description Resolves the effective graphics level and applies it.

	Three inputs, in priority order:
	  1. `Settings.GraphicsQuality` if it holds an explicit level -> that level,
	     detection never overrides it;
	  2. otherwise, median frame time over a window at startup -- phones
	     included: a touchscreen only starts at `Low` until the measure is
	     in (a recent phone runs High fine, sending every phone to Low
	     for good was too harsh).

	The decision is made ONCE. No continuous degradation: a system that
	lowers quality as soon as FPS drops creates a loop (low quality -> FPS
	climbs -> quality climbs -> FPS drops again) and changes the visuals
	under the player's fingers without them understanding why.

	Application: `Scheduler.SetCosmeticRateScale` for the entire cadence of
	decorative work at once, then `EventBus.Settings.QualityChanged` for
	whatever doesn't reduce to a cadence (seed bob, world rotations, cull
	radii).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local GraphicsQualityConfig = require(script.Parent.Parent.Config.GraphicsQualityConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local EventBus = require(script.Parent.Parent.Events.EventBus)
local PlayerDataFetcher = require(script.Parent.Parent.Events.PlayerDataFetcher)

type QualityLevel = GraphicsQualityConfig.QualityLevel
type QualitySetting = GraphicsQualityConfig.QualitySetting
type Preset = GraphicsQualityConfig.Preset

local QualityController = {}
local log = Logger.new("QualityController")

--============================================================================--
-- STATE
--============================================================================--

--- Persisted value (may be "Auto").
local currentSetting: QualitySetting = GraphicsQualityConfig.DEFAULT_SETTING
--- Actually applied level (never "Auto").
local currentLevel: QualityLevel = "High"
local sampling = false
local hasAutodetected = false

--============================================================================--
-- APPLICATION
--============================================================================--

local function apply(level: QualityLevel, reason: string): ()
	if level == currentLevel then return end
	currentLevel = level

	local preset = GraphicsQualityConfig.PresetFor(level)
	Scheduler.SetCosmeticRateScale(preset.CosmeticRateScale)
	EventBus.Settings.QualityChanged:Fire(level, preset)

	log:Info("Graphics quality: %s (%s)", level, reason)
end

--============================================================================--
-- DETECTION
--============================================================================--

--- Touchscreen WITHOUT a keyboard: phone/tablet. A touch-enabled PC keeps
--- its keyboard, so it doesn't get misclassified as mobile.
local function isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function median(values: { number }): number
	table.sort(values)
	local count = #values
	if count == 0 then return 0 end
	if count % 2 == 1 then
		return values[(count + 1) // 2]
	end
	return (values[count // 2] + values[count // 2 + 1]) * 0.5
end

--- Samples frame time after a warmup, then applies the deduced level.
--- Does nothing if the player already chose an explicit level in the meantime.
local function startAutodetect(): ()
	if sampling or hasAutodetected then return end
	sampling = true

	task.spawn(function()
		local config = GraphicsQualityConfig.Autodetect
		task.wait(config.WarmupDuration)

		if currentSetting ~= "Auto" then
			sampling = false
			return
		end

		local samples: { number } = {}
		local connection = RunService.Heartbeat:Connect(function(dt: number)
			table.insert(samples, dt * 1000)
		end)
		task.wait(config.SampleDuration)
		connection:Disconnect()
		sampling = false

		if #samples == 0 then return end
		if currentSetting ~= "Auto" then return end

		hasAutodetected = true
		local medianMs = median(samples)
		apply(
			GraphicsQualityConfig.LevelForFrameTime(medianMs),
			string.format("auto, median %.1f ms over %d frames", medianMs, #samples)
		)
	end)
end

--- Translates the persisted value into an effective level and applies it.
local function resolve(): ()
	if currentSetting ~= "Auto" then
		hasAutodetected = false
		apply(currentSetting :: QualityLevel, "player choice")
		return
	end

	startAutodetect()
end

--============================================================================--
-- PUBLIC API
--============================================================================--

--- Actually applied level (never "Auto").
--- @return QualityLevel
function QualityController.GetLevel(): QualityLevel
	return currentLevel
end

--- Active preset -- read it at a system's startup, then subscribe to
--- `EventBus.Settings.QualityChanged` for changes.
--- @return Preset
function QualityController.GetPreset(): Preset
	return GraphicsQualityConfig.PresetFor(currentLevel)
end

--- Persisted value, including "Auto" (what the menu should display).
--- @return QualitySetting
function QualityController.GetSetting(): QualitySetting
	return currentSetting
end

--- Changes the setting and persists it. The server remains the authority on
--- the data (`DataService:SetSetting` validates the key and the type); we
--- apply it locally right away so the menu responds without a round-trip.
--- @param setting QualitySetting
function QualityController.SetSetting(setting: QualitySetting): ()
	local sanitized = GraphicsQualityConfig.SanitizeSetting(setting)
	if sanitized == currentSetting then return end
	currentSetting = sanitized

	NetworkEvents.FireServer("UpdateSetting", {
		Setting = GraphicsQualityConfig.SETTING_KEY,
		Value = sanitized,
	})

	resolve()
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function QualityController:Init(): ()
	-- Before any data arrives: a touch device starts Low without waiting for
	-- the profile (it would otherwise run at full tilt during the round-trip),
	-- until the frame-time measure decides.
	if isMobile() then
		apply("Low", "touchscreen device, before data")
	end

	PlayerDataFetcher.OnReady(function(data: any)
		local stored = data and data.Settings and data.Settings[GraphicsQualityConfig.SETTING_KEY]
		currentSetting = GraphicsQualityConfig.SanitizeSetting(stored)
		resolve()
	end)

	EventBus.Data.Updated:Connect(function(data: any)
		local stored = data and data.Settings and data.Settings[GraphicsQualityConfig.SETTING_KEY]
		if stored == nil then return end
		local sanitized = GraphicsQualityConfig.SanitizeSetting(stored)
		if sanitized == currentSetting then return end
		currentSetting = sanitized
		resolve()
	end)
end

function QualityController:Start(): ()
	log:Info("Started — setting '%s', level '%s'.", currentSetting, currentLevel)
end

return QualityController
