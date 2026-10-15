--!strict
--[[
	@class Spawn
	Thin typed wrapper around `task.spawn`/`task.delay`. No game-specific logic.
]]

local Spawn = {}

--- Run `callback` asynchronously on a new thread, passing `...` through.
--- @param callback (...any) -> () -- function to run
--- @return thread
function Spawn.Now(callback: (...any) -> (), ...: any): thread
	return task.spawn(callback, ...)
end

--- Run `callback` asynchronously after `delaySeconds`, passing `...` through.
--- @param delaySeconds number -- delay before running, in seconds
--- @param callback (...any) -> () -- function to run
--- @return thread
function Spawn.After(delaySeconds: number, callback: (...any) -> (), ...: any): thread
	return task.delay(delaySeconds, callback, ...)
end

return Spawn
