--!strict
--[[
	@class ParticleIds
	Registry of particle texture asset ids keyed by descriptive name.
	Built-in engine textures (rbxasset://) need no upload and always load.
]]

--- Map of particle name -> texture content id.
export type ParticleIdsType = { [string]: string }

local ParticleIds: ParticleIdsType = table.freeze({
	--- Autumn maple leaf, already colored (transparent background).
	AutumnLeaf = "rbxassetid://899737088",
	--- White petal, tinted per use (sakura pink).
	Petal = "rbxassetid://243344623",
	--- White 4-point star, tinted per use (stardust, gold glints).
	Star = "rbxassetid://16810185213",
	--- White snowflake.
	Snowflake = "rbxassetid://1190797289",
	--- Engine built-ins.
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}) :: ParticleIdsType

return ParticleIds
