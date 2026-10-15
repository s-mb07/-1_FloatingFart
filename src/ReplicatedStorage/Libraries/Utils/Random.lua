--!strict
--[[
	@class Random
	Generic, pure-ish helpers for randomness built on the global `Random` type. No game-specific logic.
]]

local Random = {}

--- Return a random integer in the inclusive range `[min, max]`.
--- @param min number -- inclusive lower bound
--- @param max number -- inclusive upper bound
--- @return number
function Random.Range(min: number, max: number): number
	return math.random(min, max)
end

--- Return a uniformly random element from `array`. Errors if the array is empty.
--- @param array { T } -- array to pick from, must be non-empty
--- @return T
function Random.Choice<T>(array: { T }): T
	assert(#array > 0, "Random.Choice requires a non-empty array")
	return array[math.random(1, #array)]
end

return Random
