--!strict
--[[
	@module Panels.PlaytimeRewards.Config
	@description Navigation/Transition config for the PlaytimeRewards panel.

	KeepAlive = true: the "PlaytimerewardsUI" ScreenGui has ResetOnSpawn =
	false (checked in Studio), and the panel keeps ticking the HUD gift
	button countdown while closed, so it must never be destroyed.
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
