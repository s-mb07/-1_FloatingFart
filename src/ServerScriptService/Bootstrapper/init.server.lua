--!strict
--- Server Bootstrapper
-- Responsible for initializing every service on the server side.
-- Scans Services/ (each child ModuleScript = a service), requires it, then
-- calls :Init() (synchronous, pcall) then :Start() (task.spawn, pcall) on
-- any module that exposes those methods. Nothing else is called
-- automatically -- a service is just a ModuleScript dropped here.
-- @script ServerBootstrapper

local ServicesFolder = script:WaitForChild("Services")
local Services: { [string]: any } = {}
local failedModules: {string} = {}

-- Loading modules
for _, module in ipairs(ServicesFolder:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			Services[module.Name] = result
		else
			warn(string.format("[SERVER] \u{274C} Failed require '%s': %s", module.Name, tostring(result)))
			table.insert(failedModules, module.Name)
		end
	end
end

-- Initializing Services (Init phase)
for name, service in pairs(Services) do
	if type(service) == "table" and type(service.Init) == "function" then
		local ok, err = pcall(function()
			service:Init()
		end)
		if not ok then
			warn(string.format("[SERVER] \u{274C} Failed Init '%s': %s", name, tostring(err)))
			table.insert(failedModules, name .. ":Init")
		end
	end
end

-- Starting Services (Start phase)
for name, service in pairs(Services) do
	if type(service) == "table" and type(service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(function()
				service:Start()
			end)
			if not ok then
				warn(string.format("[SERVER] \u{274C} Failed Start '%s': %s", name, tostring(err)))
				table.insert(failedModules, name .. ":Start")
			end
		end)
	end
end

if #failedModules > 0 then
	warn(string.format("[SERVER] \u{26A0}\u{FE0F} %d module(s) failed: %s", #failedModules, table.concat(failedModules, ", ")))
else
	print("[SERVER] \u{2705} All services loaded successfully.")
end
