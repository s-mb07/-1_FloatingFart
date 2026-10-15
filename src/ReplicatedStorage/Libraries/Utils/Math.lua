--!strict
--[[
	@class Math
	Generic, pure numeric math helpers. No game-specific logic.
]]

local Math = {}

--- Linearly interpolate between `from` and `to` by `alpha` (not clamped).
--- @param from number -- start value
--- @param to number -- end value
--- @param alpha number -- interpolation factor, 0 = from, 1 = to
--- @return number
function Math.Lerp(from: number, to: number, alpha: number): number
	return from + (to - from) * alpha
end

--- Round `value` to the nearest multiple of `step` (default 1).
--- @param value number -- value to round
--- @param step number? -- rounding step, defaults to 1
--- @return number
function Math.Round(value: number, step: number?): number
	local resolvedStep = step or 1
	return math.floor(value / resolvedStep + 0.5) * resolvedStep
end

return Math
