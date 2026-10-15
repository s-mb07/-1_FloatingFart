--!strict
--[[
	@module Panels.GroupReward.Config
	@description Navigation/Transition config for the GroupReward panel.

	KeepAlive = true: the "GroupRewardUI" ScreenGui has ResetOnSpawn = false
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
