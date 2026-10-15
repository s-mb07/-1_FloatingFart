--!strict
--[[
	@module PanelDefinition
	@description Mandatory contract for a panel driven by Navigation.Controller.

	A panel registered in Navigation.PanelRegistry MUST implement Init/
	Activate/Deactivate/Destroy. CaptureState/RestoreState are optional:
	only panels with runtime state worth preserving between a pop and a
	push (search, filter, active tab...) implement them -- a server-truth
	panel (Settings, Achievements...) can skip them, a re-fetch on
	Activate() is enough and avoids any staleness risk.

	`Root` (the GuiObject animated by Navigation.PanelTransition) is not
	checked here: it often only exists after Init() (Instance resolution),
	so it's Navigation.Controller that asserts it right before using it,
	not PanelDefinition at registration time.

	Open/close animation, stack bookkeeping, and deciding *when* to call
	Activate/Deactivate/Destroy stay outside this contract -- those are
	Navigation.Controller's responsibilities, never the panel's own
	(see AUDIT_2026-08-21_ui-navigation-migration-plan.md §7).
]]

export type PanelNavigationConfig = {
	CanStack: boolean?,  -- true = doesn't dismiss the active panel underneath on open
	CanGoBack: boolean?, -- false = Pop() is refused while this panel is active
	KeepAlive: boolean?, -- true = never destroyed, Deactivate() only (snapshots the Controller, not the State)
}

export type PanelTransitionConfig = {
	Enabled: boolean?,
	Type: string?,
}

export type PanelConfig = {
	Navigation: PanelNavigationConfig?,
	Transition: PanelTransitionConfig?,
}

export type Panel = {
	Root: GuiObject?,
	Config: PanelConfig?,
	Init: (self: any, deps: any?) -> (),
	Activate: (self: any) -> (),
	Deactivate: (self: any) -> (),
	Destroy: (self: any) -> (),
	CaptureState: ((self: any) -> any)?,
	RestoreState: ((self: any, snapshot: any) -> ())?,
}

local REQUIRED_METHODS = { "Init", "Activate", "Deactivate", "Destroy" }

local PanelDefinition = {}

--- Checks that a panel implements the minimal contract. Fails explicitly
--- (rather than a cryptic nil-index on the first Push/Pop) if a required
--- method is missing.
function PanelDefinition.Validate(panelId: string, panel: any): ()
	for _, methodName in ipairs(REQUIRED_METHODS) do
		if type(panel[methodName]) ~= "function" then
			error(
				("PanelDefinition: panel '%s' does not implement the required method '%s'"):format(
					panelId,
					methodName
				),
				0
			)
		end
	end
end

return PanelDefinition
