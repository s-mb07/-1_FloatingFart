--!strict
--[[
	@class String
	Generic, pure helpers for strings. No game-specific logic.
]]

local String = {}

--- Split `text` on every occurrence of `separator` (plain text, not a pattern).
--- @param text string -- string to split
--- @param separator string -- literal separator to split on
--- @return { string }
function String.Split(text: string, separator: string): { string }
	local parts: { string } = {}
	if separator == "" then
		table.insert(parts, text)
		return parts
	end

	local searchStart = 1
	while true do
		local matchStart, matchEnd = string.find(text, separator, searchStart, true)
		if not matchStart then
			table.insert(parts, string.sub(text, searchStart))
			break
		end
		table.insert(parts, string.sub(text, searchStart, matchStart - 1))
		searchStart = (matchEnd :: number) + 1
	end
	return parts
end

--- Trim leading and trailing whitespace from `text`.
--- @param text string -- string to trim
--- @return string
function String.Trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

return String
