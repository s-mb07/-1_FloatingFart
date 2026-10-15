--!strict
--[[
	@class Throttle
	Typed throttle factory: wraps a function so it runs at most once per `seconds` window,
	always allowing the first call through immediately. No game-specific logic.
]]

local Throttle = {}

--- Wrap `callback` so it runs at most once every `seconds`; calls made inside the
--- cooldown window are dropped.
--- @param callback (...any) -> () -- function to throttle
--- @param seconds number -- minimum seconds between runs
--- @return (...any) -> ()
function Throttle.Wrap(callback: (...any) -> (), seconds: number): (...any) -> ()
	local nextAllowedClock: number = -math.huge

	return function(...: any): ()
		local now = os.clock()
		if now < nextAllowedClock then
			return
		end
		nextAllowedClock = now + seconds
		callback(...)
	end
end

return Throttle
