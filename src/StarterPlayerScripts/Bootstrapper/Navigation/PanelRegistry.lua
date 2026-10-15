--!strict
--[[
	@module Navigation.PanelRegistry
	@description panelId -> factory registry for Navigation.Controller.

	Deliberately "dumb": a flat map, no string-eval, no
	reflection (see AUDIT_2026-08-21_ui-navigation-migration-plan.md §14,
	"Registry too magic").

	Only caches a created instance if its Config.Navigation.KeepAlive is
	true -- otherwise Resolve() calls the factory again every time, which IS
	the intended behavior: a non-KeepAlive panel must be recreated on every
	reappearance (see the Create/Init/Activate/.../Destroy/Recreate cycle
	described in the migration plan §8).
]]

local PanelDefinition = require(script.Parent.Parent.PanelDefinition)

local PanelRegistry = {}

local factories: { [string]: () -> any } = {}
local keepAliveInstances: { [string]: any } = {}

--- Registers a panel. `factory` must return a new Panel table on
--- every call (Resolve() alone decides whether it should be called again).
function PanelRegistry.Register(panelId: string, factory: () -> any): ()
	assert(factories[panelId] == nil, ("PanelRegistry: '%s' is already registered"):format(panelId))
	factories[panelId] = factory
end

--- Resolves a panel: returns the existing KeepAlive instance if it exists,
--- otherwise calls the factory and validates the PanelDefinition contract.
function PanelRegistry.Resolve(panelId: string): any
	local cached = keepAliveInstances[panelId]
	if cached then
		return cached
	end

	local factory = factories[panelId]
	assert(factory ~= nil, ("PanelRegistry: no panel registered under '%s'"):format(panelId))

	local panel = factory()
	PanelDefinition.Validate(panelId, panel)

	local navConfig = panel.Config and panel.Config.Navigation
	if navConfig ~= nil and navConfig.KeepAlive == true then
		keepAliveInstances[panelId] = panel
	end

	return panel
end

--- True if `panelId` already has a cached KeepAlive instance (useful to
--- avoid calling Init() again on a panel that's already alive).
function PanelRegistry.HasKeepAliveInstance(panelId: string): boolean
	return keepAliveInstances[panelId] ~= nil
end

return PanelRegistry
