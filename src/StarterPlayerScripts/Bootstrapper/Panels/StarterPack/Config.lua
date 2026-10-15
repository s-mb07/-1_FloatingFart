--!strict
--[[
	@module Panels.StarterPack.Config
	@description Navigation/Transition config for the StarterPack panel.

	KeepAlive = true: the "StarterPackUI" ScreenGui has ResetOnSpawn = false
	(checked in Studio), and the panel keeps driving the HUD button's
	visibility while closed, so it must never be destroyed.
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
