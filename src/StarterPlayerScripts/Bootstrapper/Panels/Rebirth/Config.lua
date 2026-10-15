--!strict
--[[
	@module Panels.Rebirth.Config
	@description Navigation/Transition config for the Rebirth panel.

	KeepAlive = true: the "RebirthUI" ScreenGui has ResetOnSpawn = false
	(checked in Studio), so it is resolved and wired once.
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
