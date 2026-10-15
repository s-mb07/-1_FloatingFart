--!strict
--[[
	@class Vector
	Generic, pure helpers for Vector3 values. No game-specific logic.
]]

local Vector = {}

--- Return a copy of `vector` with its Y component set to 0.
--- @param vector Vector3 -- source vector
--- @return Vector3
function Vector.FlattenY(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

--- Return a copy of `vector` whose magnitude does not exceed `maxMagnitude`.
--- @param vector Vector3 -- source vector
--- @param maxMagnitude number -- maximum allowed magnitude, must be >= 0
--- @return Vector3
function Vector.ClampMagnitude(vector: Vector3, maxMagnitude: number): Vector3
	if vector.Magnitude <= maxMagnitude then
		return vector
	end
	if vector.Magnitude == 0 then
		return vector
	end
	return vector.Unit * maxMagnitude
end

return Vector
