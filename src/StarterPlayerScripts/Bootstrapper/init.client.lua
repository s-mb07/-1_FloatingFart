--!strict
--!derogation: pcall bootstrapper isolates require/Init/Start failures per module (4 sites: require, Panels require, Init, Start), by design (see README.md §9.3)
--- Bootstrapper Client
-- Responsible for initializing every client-side controller.
-- @script BootstrapperClient

-- Disables the native Roblox hotbar (useful if you have your own system).
local StarterGui = game:GetService("StarterGui")
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- Landscape only on phones/tablets: the game is never playable held upright.
-- LandscapeSensor still lets the device flip between both landscape sides.
-- Set first thing so the loading screen already shows in landscape.
local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
PlayerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

local UIRegistry = require(script:WaitForChild("UIRegistry"))

-- PROTOTYPE, INACTIVE BY DEFAULT: topological sort by Dependencies + UIRegistry.MarkReady.
-- Leave at `false` unless there's a proven real need (Init order between two
-- specific Controllers) -- pairs() order is enough as long as nothing
-- explicitly depends on anything else. Setting back to true enables
-- sortByDependencies below.
local ENABLE_EXPERIMENTAL_DEPENDENCIES = false

local StandaloneControllersFolder = script:WaitForChild("StandaloneControllers")
local Controllers: { [string]: any } = {}
local failedModules: { string } = {}

-- Loading modules: StandaloneControllers/ (everything that's neither a
-- panel nor a component). A direct ModuleScript in this folder = one
-- Controller, with Init/Start called automatically.
local function loadFrom(folder: Instance): ()
	for _, module in ipairs(folder:GetChildren()) do
		if module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				Controllers[module.Name] = result
			else
				warn(
					string.format(
						"[CLIENT] ❌ Require failed for '%s': %s",
						module.Name,
						tostring(result)
					)
				)
				table.insert(failedModules, module.Name)
			end
		end
	end
end

loadFrom(StandaloneControllersFolder)

-- Panels migrated to Navigation.Controller: PanelRegistry registration +
-- wiring of HUD opening buttons, kept separate from the StandaloneControllers
-- scan above since these aren't Init/Start modules but a side-effect of
-- require (cf. Panels/init.lua).
local panelsOk, panelsErr = pcall(require, script:WaitForChild("Panels"))
if not panelsOk then
	warn(string.format("[CLIENT] ❌ Failed to load Panels: %s", tostring(panelsErr)))
end

-- Topological sort by Dependencies (optional `Dependencies: {string}` field on a
-- Controller, absent = no dependency = same behavior as before). Guarantees
-- that a Controller only has its Init() called after those of its declared
-- dependencies. Cycle detected -> warning only, not a blocking error: the
-- modules involved fall back to the end of the order, with no guaranteed
-- order between them (as before).
local function sortByDependencies(controllers: { [string]: any }): { string }
	local names: { string } = {}
	for name in pairs(controllers) do
		table.insert(names, name)
	end

	local inDegree: { [string]: number } = {}
	local dependents: { [string]: { string } } = {}
	for _, name in names do
		inDegree[name] = 0
	end

	for _, name in names do
		local controller = controllers[name]
		local deps = type(controller) == "table" and controller.Dependencies
		if type(deps) == "table" then
			for _, depName in deps do
				if controllers[depName] then
					inDegree[name] += 1
					dependents[depName] = dependents[depName] or {}
					table.insert(dependents[depName], name)
				end
			end
		end
	end

	local queue: { string } = {}
	for _, name in names do
		if inDegree[name] == 0 then
			table.insert(queue, name)
		end
	end

	local order: { string } = {}
	while #queue > 0 do
		local name = table.remove(queue, 1) :: string
		table.insert(order, name)
		for _, dependent in ipairs(dependents[name] or {}) do
			inDegree[dependent] -= 1
			if inDegree[dependent] == 0 then
				table.insert(queue, dependent)
			end
		end
	end

	if #order < #names then
		local stuck: { string } = {}
		for _, name in names do
			if inDegree[name] > 0 then
				table.insert(stuck, name)
			end
		end
		warn(
			string.format(
				"[CLIENT] ⚠️ Dependency cycle detected between: %s. Order not guaranteed for these modules.",
				table.concat(stuck, ", ")
			)
		)
		for _, name in stuck do
			table.insert(order, name)
		end
	end

	return order
end

local initOrder: { string }
if ENABLE_EXPERIMENTAL_DEPENDENCIES then
	initOrder = sortByDependencies(Controllers)
else
	-- Original behavior: pairs() order, not guaranteed (as before).
	initOrder = {}
	for name in pairs(Controllers) do
		table.insert(initOrder, name)
	end
end

-- Initializing Controllers (Init phase), in topological order if the
-- prototype is active, otherwise in the original order.
for _, name in initOrder do
	local controller = Controllers[name]
	if type(controller) == "table" and type(controller.Init) == "function" then
		local ok, err = pcall(function()
			controller:Init()
		end)
		if not ok then
			warn(string.format("[CLIENT] ❌ Init failed for '%s': %s", name, tostring(err)))
			table.insert(failedModules, name .. ":Init")
		elseif ENABLE_EXPERIMENTAL_DEPENDENCIES then
			UIRegistry.MarkReady(name)
		end
	elseif ENABLE_EXPERIMENTAL_DEPENDENCIES then
		UIRegistry.MarkReady(name)
	end
end

-- Starting Controllers (Start phase) -- stays async/fire-and-forget, the
-- topological order here only influences the order task.spawn is launched
-- in, not its completion (Start doesn't wait on its dependencies, only Init does).
for _, name in initOrder do
	local controller = Controllers[name]
	if type(controller) == "table" and type(controller.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(function()
				controller:Start()
			end)
			if not ok then
				warn(string.format("[CLIENT] ❌ Start failed for '%s': %s", name, tostring(err)))
				table.insert(failedModules, name .. ":Start")
			end
		end)
	end
end

if #failedModules > 0 then
	warn(
		string.format(
			"[CLIENT] ⚠️ %d module(s) failed: %s",
			#failedModules,
			table.concat(failedModules, ", ")
		)
	)
else
	print("[CLIENT] ✅ All controllers loaded successfully.")
end

-- Asset preload (README §3: LoadingController.RunPreload is the one method that
-- is called explicitly rather than by the Init/Start scan). Spawned, not
-- awaited: it yields for as long as PreloadAsync takes (up to its phase
-- timeouts), and holding the bootstrapper here would leave every controller
-- above unstarted behind a loading bar. The full-screen bar covers the screen
-- either way, and a preload failure only costs a late first asset, never a
-- controller.
local loadingController = Controllers.LoadingController
if type(loadingController) == "table" and type(loadingController.RunPreload) == "function" then
	task.spawn(function()
		loadingController.RunPreload()
	end)
end
