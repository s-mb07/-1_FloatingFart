--!strict
--[[
	@module DailyRewardConfig
	@description 7-day login reward cycle. Shared: DailyRewardService grants
	from it, the DailyRewards panel labels its cards from it.

	THE RULES (server-enforced, see DailyRewardService)
	  - One claim per UTC calendar day (`GetDay`). The next reward unlocks at
	    00:00 UTC, which is what the panel's countdown counts down to.
	  - Missing days never resets the streak: the next day you play unlocks
	    the next reward.
	  - After Day 7 is claimed, the next day starts a new cycle at Day 1.

	Reward kinds (paid out by ServerScriptService/Bootstrapper/RewardGrant):
	  - Trophies: +Amount trophies ("Wins" on the HUD).
	  - Length:   +Amount traversal XP (the progress that levels up reach).
	  - Skin:     unlocks SkinId; FallbackTrophies instead if already owned.
]]

export type Reward = {
	Kind: "Trophies" | "Length" | "Skin",
	Amount: number?,
	SkinId: string?,
	FallbackTrophies: number?,
	--- Card title shown in the panel.
	Label: string,
}

local SECONDS_PER_DAY = 86400

local DailyRewardConfig = {
	Rewards = {
		{ Kind = "Trophies", Amount = 1, Label = "(Day1) +1 Win" },
		{ Kind = "Length", Amount = 10000, Label = "(Day2) +10,000 Length" },
		{ Kind = "Trophies", Amount = 100, Label = "(Day3) +100 Wins" },
		{ Kind = "Length", Amount = 100000, Label = "(Day4) +100,000 Length" },
		{ Kind = "Trophies", Amount = 250, Label = "(Day5) +250 Wins" },
		{ Kind = "Length", Amount = 250000, Label = "(Day6) +250,000 Length" },
		{ Kind = "Skin", SkinId = "2", FallbackTrophies = 500, Label = "(Day7) ???" },
	} :: { Reward },
}

--- UTC calendar day index of a unix timestamp.
function DailyRewardConfig.GetDay(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

--- Seconds left until the next UTC day starts.
function DailyRewardConfig.SecondsUntilNextDay(unixTime: number): number
	return SECONDS_PER_DAY - unixTime % SECONDS_PER_DAY
end

return DailyRewardConfig
