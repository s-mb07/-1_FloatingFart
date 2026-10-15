--!strict
--[[
	@class RateLimiter
	Small typed fixed-window rate limiter. Allows up to `limit` consumptions per
	`windowSeconds` window, then rejects until the window rolls over. No game-specific logic.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		limit: number,
		windowSeconds: number,
		windowStartClock: number,
		usedInWindow: number,
	},
	RateLimiter
))

--- Create a new rate limiter allowing `limit` calls per `windowSeconds`.
--- @param limit number -- max consumptions allowed per window, must be >= 1
--- @param windowSeconds number -- window length in seconds, must be > 0
--- @return RateLimiter
function RateLimiter.new(limit: number, windowSeconds: number): RateLimiter
	local self = setmetatable({
		limit = limit,
		windowSeconds = windowSeconds,
		windowStartClock = os.clock(),
		usedInWindow = 0,
	}, RateLimiter)
	return self
end

--- Attempt to consume one unit of the budget. Returns true and consumes if allowed,
--- false otherwise. Rolls the window over automatically when it has elapsed.
--- @return boolean
function RateLimiter.TryConsume(self: RateLimiter): boolean
	local now = os.clock()
	if now - self.windowStartClock >= self.windowSeconds then
		self.windowStartClock = now
		self.usedInWindow = 0
	end

	if self.usedInWindow >= self.limit then
		return false
	end

	self.usedInWindow += 1
	return true
end

return RateLimiter
