--!strict
--[[
	@module Traps
	@description Registry of the world traps (README 9.9). Each sibling
	ModuleScript is one trap TYPE: `{ Tag, Server?, Client? }`. `Start()` (called
	once by TrapService server side and TrapController client side) runs the
	side's function on every instance carrying `Tag`, present and future
	(streamed in, placed later). Adding a trap = one new file here + its tag on
	the Studio folder (Config/AssetIds/TagNames), never an edit to this file.

	Both sides read the same file so a trap's timing lives in one place: the
	server owns what matters (the kill hitbox), the client only draws.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

export type Trap = {
	--- CollectionService tag of the Studio folder/model the trap runs on.
	Tag: string,
	--- Called once per tagged instance; may yield. `env` is what the side's
	--- starter passes (client: Env). Returns what undoes it (connections,
	--- clones), run when the instance loses its tag or leaves (streaming).
	Server: ((instance: Instance, env: Env) -> Cleanup?)?,
	Client: ((instance: Instance, env: Env) -> Cleanup?)?,
}

export type Cleanup = () -> ()

--- Side-specific hooks a trap may need (the client's settings, ...).
export type Env = {
	--- Client only: true while the player has sound effects on.
	SoundEnabled: (() -> boolean)?,
}

local Traps = {}

--- Starts every registered trap for this side (server or client).
--- @param env Env? -- hooks handed to every trap
function Traps.Start(env: Env?): ()
	local hooks: Env = env or {}
	local isServer = RunService:IsServer()
	for _, module in script:GetChildren() do
		if not module:IsA("ModuleScript") then
			continue
		end
		local trap = require(module) :: Trap
		local run = if isServer then trap.Server else trap.Client
		if not run then
			continue
		end
		-- One run per instance at a time: `true` while starting, then its cleanup.
		local running: { [Instance]: Cleanup | boolean } = {}
		local function start(instance: Instance): ()
			if running[instance] then
				return
			end
			running[instance] = true
			task.spawn(function()
				local cleanup = run(instance, hooks)
				if running[instance] == nil then
					if cleanup then
						cleanup() -- removed while it was starting
					end
				else
					running[instance] = cleanup or true
				end
			end)
		end
		for _, instance in CollectionService:GetTagged(trap.Tag) do
			start(instance)
		end
		CollectionService:GetInstanceAddedSignal(trap.Tag):Connect(start)
		CollectionService:GetInstanceRemovedSignal(trap.Tag):Connect(function(instance: Instance)
			local cleanup = running[instance]
			running[instance] = nil
			if type(cleanup) == "function" then
				cleanup()
			end
		end)
	end
end

return Traps
