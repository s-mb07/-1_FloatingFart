--!strict
--[[
	@class Table
	Generic, pure helpers for plain Lua tables (mixed array/dict). No game-specific logic.
]]

local Table = {}

--- Shallow-merge `overrides` on top of `base`, returning a new table. Neither input is mutated.
--- @param base { [any]: any } -- base table
--- @param overrides { [any]: any } -- values that take precedence over `base`
--- @return { [any]: any }
function Table.Merge(base: { [any]: any }, overrides: { [any]: any }): { [any]: any }
	local result: { [any]: any } = table.clone(base)
	for key, value in overrides do
		result[key] = value
	end
	return result
end

--- Recursively deep-copy a table, including nested tables. Non-table values are returned as-is.
--- @param source { [any]: any } -- table to copy
--- @return { [any]: any }
function Table.DeepCopy(source: { [any]: any }): { [any]: any }
	local result: { [any]: any } = {}
	for key, value in source do
		if type(value) == "table" then
			result[key] = Table.DeepCopy(value :: { [any]: any })
		else
			result[key] = value
		end
	end
	return result
end

return Table
