--!strict
--[[
	@module Effects.Channels.Haptic
	@description Effects' haptic channel, based on HapticEffect.

	HapticEffect (rather than HapticService) covers console, VR AND mobile,
	handles spatial motor selection via Position/Radius, and provides
	vibration patterns natively via SetWaveformKeys -- so there's no
	sequence for us to orchestrate ourselves.

	Not supported at the engine level, nothing to work around here: Android
	11 and earlier, gamepads plugged into mobile, gamepads on macOS 15+, VR
	controllers on PC.
]]

local Workspace = game:GetService("Workspace")

local EffectsConfig = require(script.Parent.Parent.Parent.Config.EffectsConfig)
local Settings = require(script.Parent.Parent.Settings)

local Haptic = {}

local DEFAULT_TYPE = "GameplayCollision"
-- Below this threshold, some devices trigger no feedback at all.
local MIN_INTENSITY = 0.1
-- Roblox recommends staying under 100 simultaneous effects; we keep a wide
-- margin under that limit, no feedback has any reason to stack more than that.
local MAX_LIVE = 32

local live = 0

local function buildKeys(waveform: {{number}}): {FloatCurveKey}
	local keys = table.create(#waveform)
	for index, point in waveform do
		keys[index] = FloatCurveKey.new(point[1], math.max(point[2], MIN_INTENSITY))
	end
	return keys
end

function Haptic.Play(spec: EffectsConfig.HapticSpec, _context: any): ()
	if not Settings.Get("Haptics") then return end
	if live >= MAX_LIVE then return end

	local effectType = (Enum.HapticEffectType :: any)[spec.Type or DEFAULT_TYPE]
	if not effectType then
		warn("[Effects] Unknown haptic type: " .. tostring(spec.Type))
		return
	end

	local effect = Instance.new("HapticEffect")
	effect.Type = effectType
	effect.Position = spec.Position or Vector3.zero
	effect.Radius = spec.Radius or 1

	if spec.Waveform then
		effect:SetWaveformKeys(buildKeys(spec.Waveform))
	end

	live += 1
	effect.Ended:Once(function()
		live -= 1
		effect:Destroy()
	end)

	effect.Parent = Workspace
	effect:Play()
end

return Haptic
