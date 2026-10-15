--!strict
--[[
	@module Effects.Settings
	@description Shared gating for Effects channels.

	Replaces the four identical copies of `onSettingsData` + double EventBus
	connection that lived in Camera/Haptic/Visual/World (DRY rule). A channel
	just asks `Settings.Get("Vfx")`, nothing more.
]]

local EventBus = require(script.Parent.Parent.Events.EventBus)

local Settings = {}

--- Internal flag -> key in data.Settings (DataTemplate).
local FLAGS: {[string]: string} = {
	Haptics     = "HapticsEnabled",
	ScreenShake = "ScreenShakeEnabled",
	Vfx         = "VfxEnabled",
	Sfx         = "SfxEnabled",
}

local values: {[string]: boolean} = {}
for flag in FLAGS do
	values[flag] = true
end

local function absorb(data: any): ()
	local playerSettings = data and data.Settings
	if not playerSettings then return end

	for flag, key in FLAGS do
		if playerSettings[key] ~= nil then
			values[flag] = playerSettings[key]
		end
	end
end

EventBus.Data.Initialized:Connect(absorb)
EventBus.Data.Updated:Connect(absorb)

--- An unknown flag is considered active: a channel without a dedicated
--- setting must not end up silenced by a typo.
--- @param flag string Key in FLAGS
function Settings.Get(flag: string): boolean
	return values[flag] ~= false
end

return Settings
