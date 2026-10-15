--!strict
--[[
	@module TemplateController
	@description Skeleton for a StandaloneController. Copy this file,
	rename it -- nothing else to wire up, init.client.lua scans every
	direct ModuleScript under StandaloneControllers/ and automatically
	calls Init() (sync, pcall) then Start() (task.spawn, pcall).

	Init(): instance resolution, connections that must exist before any
	other controller runs. Must never yield for long.
	Start(): loops/long waits, anything that can yield -- runs in its own
	thread, doesn't affect the startup of other controllers.

	Optional: `Dependencies: {string}` (names of other Controllers) enables
	a topological sort of Init if ENABLE_EXPERIMENTAL_DEPENDENCIES = true in
	init.client.lua -- leave it absent unless something actually needs it.
]]

local TemplateController = {}

function TemplateController:Init(): ()
end

function TemplateController:Start(): ()
end

return TemplateController
