--!strict
--[[
	@module Panels.LeaveReward.Config
	@description Navigation/Transition config for the LeaveReward panel.

	KeepAlive = true: the "LeaveRewardUI" ScreenGui has ResetOnSpawn = false
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
