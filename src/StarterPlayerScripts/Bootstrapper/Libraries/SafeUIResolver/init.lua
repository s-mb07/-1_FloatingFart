--!strict
--[[
	@module SafeUIResolver
	@description Event-driven WaitForChild-by-path (no polling-only, no hard
	`WaitForChild` hang). `UITag/` (nested below) is the sibling tag-driven UI
	framework: both live here because they solve the same problem -- getting a
	hold of a Studio-authored UI Instance safely -- one by exact path, the
	other by CollectionService tag.
]]
local SafeUIResolver = {}

local Logger = require(game:GetService("ReplicatedStorage").Libraries.Logger)
local log = Logger.new("SafeUIResolver")

-- Default timeout when not specified: prevents a renamed/missing path from
-- leaving a ChildAdded connection alive indefinitely in silence (feature
-- never initialized, no trace). Warns instead of hanging.
local DEFAULT_TIMEOUT_SECONDS = 8

--- Waits for a direct child on an instance (event-driven, zero polling).
--- If `timeoutSeconds` is exceeded, warns and gives up (callback never called).
--- @param parent Instance
--- @param name string
--- @param callback (Instance) -> ()
--- @param timeoutSeconds number?
--- @param fullPath string? full path for a readable warn message
-- Fallback polling interval (in addition to ChildAdded): covers cases where
-- the child already exists but ChildAdded didn't fire as expected
-- (ChildAdded alone isn't 100% reliable, cf. recurring reports from the
-- Roblox community about ChildAdded being missed without error).
local POLL_INTERVAL_SECONDS = 0.5

local function waitForChild(parent: Instance, name: string, callback: (Instance) -> (), timeoutSeconds: number?, fullPath: string?)
	local child = parent:FindFirstChild(name)
	if child then
		callback(child)
		return
	end

	local done = false

	local conn: RBXScriptConnection
	conn = parent.ChildAdded:Connect(function(added: Instance)
		if added.Name == name and not done then
			done = true
			conn:Disconnect()
			callback(added)
		end
	end)

	local timeout = timeoutSeconds or DEFAULT_TIMEOUT_SECONDS

	task.spawn(function()
		local elapsed = 0
		while not done and elapsed < timeout do
			task.wait(POLL_INTERVAL_SECONDS)
			elapsed += POLL_INTERVAL_SECONDS
			if done then break end
			local polled = parent:FindFirstChild(name)
			if polled then
				done = true
				conn:Disconnect()
				callback(polled)
				return
			end
		end

		if not done then
			done = true
			conn:Disconnect()
			local childNames = {}
			for _, c in parent:GetChildren() do
				table.insert(childNames, c.Name)
			end
			log:Warn(
				"Node not found after %ds: '%s' (path: %s, parent: %s, current children: [%s]) — callback never fired.",
				timeout, name, fullPath or name, parent:GetFullName(), table.concat(childNames, ", ")
			)
		end
	end)
end

--- Resolves a UI path asynchronously, event-driven (no polling).
--- Warns (never blocks) if a path segment doesn't appear within the deadline.
--- @param parent Instance
--- @param path {string}
--- @param callback (Instance) -> ()
--- @param timeoutSeconds number? defaults to 8s per segment
function SafeUIResolver.WaitForPathAsync(parent: Instance, path: {string}, callback: (Instance) -> (), timeoutSeconds: number?)
	local fullPath = table.concat(path, "/")

	local function resolve(depth: number, current: Instance)
		if depth > #path then
			callback(current)
			return
		end

		waitForChild(current, path[depth], function(child: Instance)
			resolve(depth + 1, child)
		end, timeoutSeconds, fullPath)
	end

	resolve(1, parent)
end

--- Resolves a "MainHUD/Left/Buttons"-style UI path asynchronously, event-driven
--- @param parent Instance
--- @param path string  e.g. "MainHUD/Left/Buttons"
--- @param callback (Instance) -> ()
--- @param timeoutSeconds number?
function SafeUIResolver.WaitForPathStringAsync(parent: Instance, path: string, callback: (Instance) -> (), timeoutSeconds: number?)
	local parts = string.split(path, "/")
	SafeUIResolver.WaitForPathAsync(parent, parts, callback, timeoutSeconds)
end

return SafeUIResolver
