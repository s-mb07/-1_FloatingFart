--!strict
--[[
	@module BoostConfig
	@description Permanent HUD multipliers. Shared: BoostService enforces
	them, BoostController labels the buttons and shows them claimed.

	THE RULES (server-enforced, see BoostService)
	  - Length multiplier (MainHUD/RightHUD/X2Arm): starts at x1. Each click
	    takes the NEXT step and REPLACES the current value -- x2, then x3,
	    then x4, then x5 (never 2 x 3). The button shows the next step and
	    stays claimed once MaxLengthMultiplier is reached. Scales per-second XP
	    (TraversalProgressionService.GetXPPerSecond).
	  - x2 Wins (MainHUD/RightHUD/2XWins, the "+" beside the trophy count):
	    the X2Wins gamepass. It only unlocks the blue x2 win pads
	    (TrophyPadConfig); no other win gain is multiplied. 2XWins stays
	    claimed once the pass is owned; the "+" badge goes.
	  - Fast Train (MainHUD/FastTrain, shown only while on a treadmill): one-time,
	    treadmill grants come TreadmillSpeed times as often (XPInterval 1 s ->
	    0.5 s), forever. The button disappears once bought.
	  - The Length multiplier and Fast Train are saved in the profile's
	    `Boosts`; rebirths never touch them.
]]

local BoostConfig = {
	MaxLengthMultiplier = 5,
	--- Treadmill pace once Fast Train is bought (grant interval / this).
	TreadmillSpeed = 2,

	--- Robux prices SHOWN on the buttons (display only, prefixed with the
	--- Robux glyph). The real price is whatever the gamepass/product costs.
	Prices = {
		--- MainHUD/BottomHUD/BottomButtons/Boost1..4 (+25k, +100k, +500k, +1M).
		LengthBoosts = { 29, 89, 499, 999 },
		--- Length multiplier, by the NEXT step it buys (x2..x5).
		LengthMultiplier = { [2] = 3, [3] = 24, [4] = 79, [5] = 99 } :: { [number]: number },
		--- X2Wins gamepass (HUD 2XWins, Shop X2WinsBtn).
		X2Wins = 99,
		FastTrain = 49,
	},
	--- Robux glyph (renders as the Robux icon in Roblox fonts).
	Robux = utf8.char(0xE002),
}

--- "<Robux glyph><amount>" for a price label.
function BoostConfig.PriceText(amount: number): string
	return ("%s%d"):format(BoostConfig.Robux, amount)
end

return BoostConfig
