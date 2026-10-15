--!strict
--[[
	@class SurfConfig
	Client-only tunables for the surf look while training on a fan
	(SurfController). Every training player rides the "waves"; the better
	the fan, the better the tricks thrown between waves.

	`Fans[Id]` (same Ids as TreadmillConfig.Treadmills): `Tricks` is the pool
	a trick is picked from every `TrickEvery` seconds (empty = plain surfing).
	Trick names are the keys of SurfController's trick table.
]]

export type TrickName = "Ollie" | "Spin" | "Kickflip" | "Backflip" | "Cork" | "Spin720"

export type FanSurf = {
	Tricks: { TrickName },
	--- Seconds between two tricks.
	TrickEvery: number,
	--- Seconds one trick lasts.
	TrickSeconds: number,
}

local SurfConfig = {
	--- The wave ride every fan has: one swell every `Period` seconds, the body
	--- rising `Bob` studs, rolling `Roll` and carving `Carve` degrees.
	Wave = {
		Period = 1.6,
		Bob = 0.5,
		Roll = 10,
		Carve = 14,
		Pitch = 5,
	},
	--- Height (studs) of the jump under a trick.
	TrickHeight = 2.5,

	Fans = {
		["1"] = { Tricks = {}, TrickEvery = math.huge, TrickSeconds = 0 }, -- classic: just surfing
		["2"] = { Tricks = { "Ollie" }, TrickEvery = 3, TrickSeconds = 0.6 }, -- autumn
		["3"] = { Tricks = { "Ollie", "Spin" }, TrickEvery = 2.6, TrickSeconds = 0.75 }, -- sakura
		["4"] = { Tricks = { "Spin", "Kickflip" }, TrickEvery = 2.3, TrickSeconds = 0.8 }, -- golden
		["5"] = { Tricks = { "Kickflip", "Backflip", "Spin" }, TrickEvery = 2, TrickSeconds = 0.85 }, -- diamond
		["6"] = { Tricks = { "Backflip", "Cork", "Spin720" }, TrickEvery = 1.8, TrickSeconds = 0.9 }, -- amethyst
	} :: { [string]: FanSurf },
}

return SurfConfig
