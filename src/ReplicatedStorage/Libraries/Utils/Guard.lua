--!strict
--[[
	@class Guard
	Typed runtime assertion / type-narrowing helpers. No game-specific logic.
]]

local Guard = {}

--- Return true if `value` is a Player instance.
--- @param value unknown -- value to test
--- @return boolean
function Guard.IsPlayer(value: unknown): boolean
	return typeof(value) == "Instance" and (value :: Instance):IsA("Player")
end

--- Return true if `value` is a non-nan, finite number.
--- @param value unknown -- value to test
--- @return boolean
function Guard.IsFiniteNumber(value: unknown): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local numberValue = value :: number
	return numberValue == numberValue and numberValue ~= math.huge and numberValue ~= -math.huge
end

return Guard
