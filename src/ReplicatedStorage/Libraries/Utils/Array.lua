--!strict
--[[
	@class Array
	Generic, pure helpers for array-like (`{ T }`) tables. No game-specific logic.
]]

local Array = {}

--- Return the first element for which `predicate` returns true, or nil.
--- @param array { T } -- array to search
--- @param predicate (value: T, index: number) -> boolean -- test function
--- @return T?
function Array.Find<T>(array: { T }, predicate: (value: T, index: number) -> boolean): T?
	for index, value in array do
		if predicate(value, index) then
			return value
		end
	end
	return nil
end

--- Return a new array containing only elements for which `predicate` returns true.
--- @param array { T } -- array to filter
--- @param predicate (value: T, index: number) -> boolean -- test function
--- @return { T }
function Array.Filter<T>(array: { T }, predicate: (value: T, index: number) -> boolean): { T }
	local result: { T } = {}
	for index, value in array do
		if predicate(value, index) then
			table.insert(result, value)
		end
	end
	return result
end

return Array
