--!strict
--[[
	@module Panels.Settings.Config
	@description Navigation/Transition config for the Settings panel.

	KeepAlive = true: the "SettingsUI" ScreenGui has ResetOnSpawn = false
	(verified live in Studio via StarterGui -- every migrated panel instance
	is set that way, see the Phase 6 migration commit/notes.md), so its
	Container and its content are never recreated -- same reasoning as
	Panels.TradeList.Config. The old SettingsUIHandler's
	CharacterAdded/cacheReferences() was a defense against a
	ResetOnSpawn = true that never actually materialized here -- not ported
	(see Controller.lua).
]]

return {
	Navigation = {
		CanStack = false,
		CanGoBack = true,
		KeepAlive = true,
	},
	Transition = {
		Enabled = true,
		Type = "Scale",
	},
}
