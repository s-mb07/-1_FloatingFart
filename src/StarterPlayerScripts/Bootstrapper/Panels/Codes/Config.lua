--!strict
--[[
	@module Panels.Codes.Config
	@description Navigation/Transition config for the Codes panel.

	KeepAlive = true: the "CodesUI" ScreenGui has ResetOnSpawn = false
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
