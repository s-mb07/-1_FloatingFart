--!strict
--[[
	@module Panels.Settings.State
	@description State for the Settings panel -- client-side cache of the
	last known settings values (server-truth, see Controller.lua). Placed
	here rather than as plain upvalues of Controller.lua to follow
	PanelDefinition's CaptureState/RestoreState contract (see notes.md
	Phase 6 -- second pilot of the State.lua pattern, alongside
	Panels/TradeList/State.lua).
	KeepAlive = true (see Config.lua): this State never leaves memory for
	the duration of the session, so CaptureState/RestoreState are never
	actually invoked by Navigation.Controller today -- implemented anyway
	to stay correct if KeepAlive were ever switched to false.
]]

export type SettingsState = {
	knownSettings: { [string]: any },
	hasReceivedInitialData: boolean,
}

local State = {}

function State.new(): SettingsState
	return {
		knownSettings = {},
		hasReceivedInitialData = false,
	}
end

return State
