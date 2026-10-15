--!strict
--[[
	@class TreadmillConfig
	Shared tunables for the treadmill training mechanic (server XP grant,
	client cosmetic launch) and the treadmill catalogue.

	ADDING A TREADMILL = a Hitbox Part tagged TagNames.Treadmill with an `Id`
	attribute in Studio, and one `Treadmills[Id]` entry below. The access rule
	is read by AccessGate (server): no field = free, `RequiredRebirths` = earned,
	`GamePass` = Robux (GamePassConfig key), both = either one.
	`LengthMultiplier` multiplies the XP ("Length") granted while training
	in it (TreadmillService). `BubbleMax` caps the multiplier of the boost
	bubbles spawned while training in it (TrainingBubbleService).

	`TrainingAttribute`: the server sets this player attribute to the fan Id
	while a training session runs (nil otherwise) -- the client shows the
	training look (float, fan wind) only then, so a locked fan never looks
	like it trains.
]]

export type TreadmillDef = {
	--- Rebirths needed to train here without paying.
	RequiredRebirths: number?,
	--- GamePassConfig key unlocking it for Robux.
	GamePass: string?,
	--- Robux price shown to the player (the real price is the gamepass's).
	PriceRobux: number?,
	--- XP multiplier while training here.
	LengthMultiplier: number,
	--- Highest boost bubble multiplier here (BubbleMin..TreadmillConfig.BubbleMax).
	BubbleMax: number,
}

local TreadmillConfig = {
	--- Seconds between grants (also the per-player re-enter cooldown).
	XPInterval = 1,

	--- Player attribute = Id of the fan the player is training in (see header).
	TrainingAttribute = "TrainingFan",
	--- Player attribute = comma list of the fan Ids this player may train in
	--- ("1,2,4"), kept up to date by TreadmillService (AccessGate): the fan
	--- signs show "UNLOCKED" / the requirement from it.
	AccessAttribute = "FanAccess",

	--- Boost bubbles (TrainingBubbleService): one appears every
	--- BubbleInterval seconds while training, then shrinks over
	--- BubbleLifetime seconds and is gone (unpopped) at the end -- the server
	--- owns that window, the client only shows it. Each bubble's multiplier
	--- is random between BubbleMin and the fan's own BubbleMax by BubbleStep;
	--- BubbleMax below is the highest any fan may go (x3.0) and sets the
	--- bubble size scale (TrainingBubbleController): the lower the
	--- multiplier, the bigger the bubble. Popping one grants one fan XP
	--- grant x its multiplier on the spot.
	BubbleInterval = 2,
	BubbleLifetime = 3,
	BubbleMin = 1.1,
	BubbleMax = 3,
	BubbleStep = 0.1,
	--- Bubble slots, reused in turn: enough that a slot's bubble is always
	--- gone before the slot comes back (BubbleSlots * BubbleInterval > BubbleLifetime).
	BubbleSlots = 3,
	--- Player attributes BubbleAttribute .. slot (slot 1..BubbleSlots) =
	--- "<serial>:<multiplier>" while that bubble waits to be popped (nil = none).
	--- The serial makes every bubble a new value, even with the same multiplier.
	BubbleAttribute = "TrainingBubble",

	Treadmills = {
		["1"] = { LengthMultiplier = 1, BubbleMax = 1.3 }, -- classic (grey): free
		["2"] = { RequiredRebirths = 3, LengthMultiplier = 2, BubbleMax = 1.5 }, -- autumn leaves
		["3"] = { RequiredRebirths = 5, LengthMultiplier = 3, BubbleMax = 1.8 }, -- pink (sakura)
		["4"] = {
			GamePass = "GoldenFan",
			PriceRobux = 24,
			LengthMultiplier = 5,
			BubbleMax = 2.2,
		}, -- golden
		["5"] = {
			GamePass = "DiamondFan",
			PriceRobux = 249,
			LengthMultiplier = 15,
			BubbleMax = 2.6,
		}, -- diamond (blue)
		["6"] = {
			GamePass = "AmethystFan",
			PriceRobux = 999,
			LengthMultiplier = 30,
			BubbleMax = 3,
		}, -- amethyst (violet)
	} :: { [string]: TreadmillDef },
}

return table.freeze(TreadmillConfig)
