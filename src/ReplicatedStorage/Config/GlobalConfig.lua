--!strict
--[[
	@module GlobalConfig
	@description Global configuration for scaling the whole game.
	Lets you boost the game via a Scalar (multiplier) -- handy for a
	temporary "double gains" event without touching each individual Config.
]]

local GlobalConfig = {
	-- Global Scalar: 1 = Normal, 2 = Everything x2 (Speed, Gains, Spawn, etc.)
	Scalar = 1,
}

--- Computes a scaled value
--- @param baseValue number The base value
--- @param mode "Multiply" | "Divide" | "Add" The computation mode (Divide for durations/cooldowns)
--- @return number
function GlobalConfig.Apply(baseValue: number, mode: "Multiply" | "Divide" | "Add"): number
	if mode == "Multiply" then
		return baseValue * GlobalConfig.Scalar
	elseif mode == "Divide" then
		-- If we want it to go faster (e.g. Duration), divide by the scalar
		return baseValue / GlobalConfig.Scalar
	elseif mode == "Add" then
		-- Optional if we have scaled additions
		return baseValue + (GlobalConfig.Scalar - 1)
	end
	return baseValue
end

return GlobalConfig
