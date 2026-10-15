--!strict
--[[
	@module UITag.Handlers.Utils
	@description Shared helpers for UITag handler sub-modules.

	Provides small utilities used across Effects / Actions / Reactive handlers:
	attribute bulk-reading, Color3 parsing, target resolution, etc.
]]

local CollectionService = game:GetService("CollectionService")

local Utils = {}

--============================================================================--
-- TYPES
--============================================================================--

--- Attribute value union as returned by Instance:GetAttribute().
--- Keep it open-ended because Roblox allows many primitive types.
export type AttributeValue =
	  string | number | boolean | nil
	| Vector2 | Vector3 | UDim | UDim2 | Color3
	| BrickColor | Rect | CFrame | NumberRange | NumberSequence | ColorSequence

export type AttributeMap = { [string]: AttributeValue }

--============================================================================--
-- ATTRIBUTES
--============================================================================--

--- Read a set of optional attributes from an instance into a plain table.
--- Only defined attributes are included (nil ones are skipped).
function Utils.GetAttributes(instance: Instance, names: {string}): AttributeMap
	local result: AttributeMap = {}
	for _, name in ipairs(names) do
		local val = instance:GetAttribute(name)
		if val ~= nil then
			result[name] = val :: AttributeValue
		end
	end
	return result
end

--- Read an attribute with a fallback default. The default type drives T.
--- NOTE: no runtime validation — caller is responsible for the attribute
--- having the expected type. Use narrow helpers (ToColor3, ToNumber) when
--- the attribute source is untrusted.
function Utils.GetAttr<T>(instance: Instance, name: string, default: T): T
	local val = instance:GetAttribute(name)
	if val == nil then
		return default
	end
	return val :: any
end

--============================================================================--
-- COLOR
--============================================================================--

--- Coerce a value into a Color3. Accepts Color3 directly or a {r,g,b} table
--- in 0..1 or 0..255. Falls back to the provided fallback (or white).
function Utils.ToColor3(value: any, fallback: Color3?): Color3
	if typeof(value) == "Color3" then
		return value :: Color3
	end
	if type(value) == "table" then
		local tbl = value :: { number }
		if #tbl >= 3 then
			local r, g, b = tbl[1], tbl[2], tbl[3]
			if type(r) == "number" and type(g) == "number" and type(b) == "number" then
				-- Heuristic: if any channel > 1.5 we assume 0..255 encoding.
				if r > 1.5 or g > 1.5 or b > 1.5 then
					return Color3.fromRGB(r, g, b)
				end
				return Color3.new(r, g, b)
			end
		end
	end
	return fallback or Color3.new(1, 1, 1)
end

--- HSV-cycle a color from a phase in [0..1]. Used for rainbow loops.
function Utils.RainbowColor(phase: number): Color3
	return Color3.fromHSV(phase % 1, 1, 1)
end

--============================================================================--
-- TARGET RESOLUTION
--============================================================================--

--- Resolve the "target(s)" of an action handler.
--- If `TargetTag` attribute is set, return all instances tagged with it.
--- Otherwise fall back to the instance itself.
function Utils.ResolveTargets(instance: Instance): {Instance}
	local targetTag = instance:GetAttribute("TargetTag")
	if type(targetTag) == "string" and targetTag ~= "" then
		return CollectionService:GetTagged(targetTag)
	end
	return { instance }
end

--============================================================================--
-- GEOMETRY
--============================================================================--

--- Return the absolute screen-space center of a GuiObject as a Vector2.
function Utils.GetCenterPosition(gui: GuiObject): Vector2
	local pos  = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return Vector2.new(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
end

--============================================================================--
-- NUMBER PARSING
--============================================================================--

--- Coerce a value to a number. Accepts number, numeric string, nil (returns fallback).
function Utils.ToNumber(value: any, fallback: number?): number?
	if type(value) == "number" then
		return value
	end
	if type(value) == "string" then
		return tonumber(value) or fallback
	end
	return fallback
end

return Utils
