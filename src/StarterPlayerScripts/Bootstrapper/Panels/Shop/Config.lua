--!strict
--[[
	@module Panels.Shop.Config
	@description Navigation/Transition config for the Shop panel.

	KeepAlive = true: the "ShopUI" ScreenGui has ResetOnSpawn = false
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
