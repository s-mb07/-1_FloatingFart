--!strict
--[[
	@class Dict
	Generic, pure helpers for dictionary-like (`{ [K]: V }`) tables. No game-specific logic.
]]

local Dict = {}

--- Return an array of all keys in `dict`.
--- @param dict { [K]: V } -- dictionary to read
--- @return { K }
function Dict.Keys<K, V>(dict: { [K]: V }): { K }
	local keys: { K } = {}
	for key in dict do
		table.insert(keys, key)
	end
	return keys
end

--- Return an array of all values in `dict`.
--- @param dict { [K]: V } -- dictionary to read
--- @return { V }
function Dict.Values<K, V>(dict: { [K]: V }): { V }
	local values: { V } = {}
	for _, value in dict do
		table.insert(values, value)
	end
	return values
end

return Dict
