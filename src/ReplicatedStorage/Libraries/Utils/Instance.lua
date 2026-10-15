--!strict
--[[
	@class Instance
	Type-safe helpers for waiting on and reading Roblox Instance hierarchies. No game-specific logic.
]]

local InstanceUtil = {}

--- Wait for a single named child of `parent`, timing out (returning nil) instead of yielding
--- forever. Safe against `WaitForChild` erroring due to destroyed instances.
--- @param parent Instance -- instance to search under
--- @param childName string -- name of the child to wait for
--- @param timeoutSeconds number? -- max seconds to wait, defaults to 5
--- @return Instance?
function InstanceUtil.WaitForChild(parent: Instance, childName: string, timeoutSeconds: number?): Instance?
	local ok, result = pcall(function()
		return parent:WaitForChild(childName, timeoutSeconds or 5)
	end)
	if ok then
		return result :: Instance?
	end
	return nil
end

--- Wait for multiple named children of `parent`, in order. Returns nil for any name that
--- times out rather than aborting the whole batch.
--- @param parent Instance -- instance to search under
--- @param childNames { string } -- names of the children to wait for
--- @param timeoutSeconds number? -- max seconds to wait per child, defaults to 5
--- @return { [string]: Instance? }
function InstanceUtil.WaitForChildren(
	parent: Instance,
	childNames: { string },
	timeoutSeconds: number?
): { [string]: Instance? }
	local results: { [string]: Instance? } = {}
	for _, childName in childNames do
		results[childName] = InstanceUtil.WaitForChild(parent, childName, timeoutSeconds)
	end
	return results
end

--- Resolve a world-space anchor CFrame from either a BasePart or a Model, so callers can
--- treat Studio-authored anchors (a plain Part or a grouped Model) interchangeably.
--- @param instance Instance -- a BasePart or Model to read a pivot from
--- @return CFrame? -- nil if `instance` is neither
function InstanceUtil.GetPivotCFrame(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	return nil
end

--- Calls `callback` once, the first time a descendant named `name` is added
--- under `parent` (StreamingEnabled: a part's children may land after it).
--- Disconnects itself on that call or when `parent` leaves the DataModel
--- (destroyed or streamed out), so a parent that streams in and out
--- repeatedly leaks nothing.
--- @param parent Instance -- instance to watch
--- @param name string -- descendant name to wait for
--- @param callback (Instance) -> () -- receives the descendant
function InstanceUtil.OnDescendantNamed(
	parent: Instance,
	name: string,
	callback: (Instance) -> ()
): ()
	local added: RBXScriptConnection
	local removed: RBXScriptConnection
	added = parent.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == name then
			added:Disconnect()
			removed:Disconnect()
			callback(descendant)
		end
	end)
	removed = parent.AncestryChanged:Connect(function()
		if not parent:IsDescendantOf(game) then
			added:Disconnect()
			removed:Disconnect()
		end
	end)
end

return InstanceUtil
