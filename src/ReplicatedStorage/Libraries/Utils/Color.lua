--!strict
--[[
	@class Color
	Generic, pure helpers for Color3 values. No game-specific logic.
]]

local Color = {}

--- Linearly interpolate between two colors by `alpha` (clamped to [0, 1]).
--- @param from Color3 -- start color
--- @param to Color3 -- end color
--- @param alpha number -- interpolation factor, clamped to [0, 1]
--- @return Color3
function Color.Lerp(from: Color3, to: Color3, alpha: number): Color3
	local clampedAlpha = math.clamp(alpha, 0, 1)
	return from:Lerp(to, clampedAlpha)
end

--- Convert a Color3 to a `#RRGGBB` hex string.
--- @param color Color3 -- color to convert
--- @return string
function Color.ToHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

return Color
