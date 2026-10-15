--!strict
--[[
	@class Format
	Generic, pure helpers for formatting values into display strings. No game-specific logic.
]]

local Format = {}

--- Format an integer-like number with thousands separators, e.g. `1234567` -> `"1,234,567"`.
--- @param value number -- number to format, will be floored
--- @return string
function Format.Commas(value: number): string
	local isNegative = value < 0
	local digits = string.format("%d", math.floor(math.abs(value)))

	local reversed = string.reverse(digits)
	local grouped = {}
	for i = 1, #reversed, 3 do
		table.insert(grouped, string.sub(reversed, i, i + 2))
	end
	local result = string.reverse(table.concat(grouped, ","))

	return isNegative and ("-" .. result) or result
end

return Format
