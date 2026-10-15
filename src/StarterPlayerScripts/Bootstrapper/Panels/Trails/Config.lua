--!strict
--[[
	@module Panels.Trails.Config
	@description Navigation/Transition config for the Trails panel.

	KeepAlive = true: the "TrailsUI" ScreenGui has ResetOnSpawn = false
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
