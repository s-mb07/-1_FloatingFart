--!strict
--[[
	@module Panels._Template.Config
	@description Navigation/Transition config for the `_Template` scaffold panel.
	KeepAlive = false here (unlike Settings) on purpose -- this template shows
	the non-KeepAlive path, where Init() reruns (and the Fusion scope gets
	rebuilt from scratch) every time the panel is pushed. Flip to `true` if
	your copy should behave like Settings instead.
]]

return {
	Navigation = {
		CanStack = false,
		CanGoBack = true,
		KeepAlive = false,
	},
	Transition = {
		Enabled = true,
		Type = "Scale",
	},
}
