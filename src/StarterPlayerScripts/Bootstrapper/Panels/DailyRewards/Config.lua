--!strict
--[[
	@module Panels.DailyRewards.Config
	@description Navigation/Transition config for the DailyRewards panel.

	KeepAlive = true: the "DailyRewardsUI" ScreenGui has ResetOnSpawn = false
	(checked in Studio), so its cards are resolved and wired once.
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
