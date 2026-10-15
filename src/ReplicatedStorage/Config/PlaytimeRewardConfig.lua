--!strict
--[[
	@module PlaytimeRewardConfig
	@description Rewards for time spent in the current server session.
	Shared: PlaytimeRewardService grants from it, the PlaytimeRewards panel
	and the HUD gift button display from it.

	THE RULES (server-enforced, see PlaytimeRewardService)
	  - Time played counts over all the sessions of one UTC day, and the whole
	    thing (time + claimed rewards) resets at 00:00 UTC; it is saved, and
	    checked when the player joins.
	  - Each reward is claimable once per day, in any order, as soon as its
	    `Minutes` have passed.

	Reward kinds are paid out by ServerScriptService/Bootstrapper/RewardGrant
	(Trophies = "Wins", Length = traversal XP).
]]

export type Reward = {
	Minutes: number,
	Kind: "Trophies" | "Length",
	Amount: number,
	--- Name of the card Frame under PlaytimerewardsUI/MainFrame/Content.
	Card: string,
	--- Card title shown in the panel.
	Label: string,
}

local PlaytimeRewardConfig = {
	--- Player attributes the server writes and every client reads.
	StartAttribute = "PlaytimeStart", -- server time (GetServerTimeNow) the session started
	ClaimedAttribute = "PlaytimeClaimed", -- bitmask: bit (i - 1) set = reward i claimed

	Rewards = {
		{
			Minutes = 3,
			Kind = "Length",
			Amount = 120,
			Card = "3min",
			Label = "(3 Min) +120 Length",
		},
		{ Minutes = 8, Kind = "Trophies", Amount = 20, Card = "8min", Label = "(8 Min) +20 Wins" },
		{
			Minutes = 12,
			Kind = "Length",
			Amount = 500,
			Card = "12min",
			Label = "(12 Min) +500 Length",
		},
		{
			Minutes = 20,
			Kind = "Trophies",
			Amount = 50,
			Card = "20min",
			Label = "(20 Min) +50 Wins",
		},
		{
			Minutes = 30,
			Kind = "Length",
			Amount = 2500,
			Card = "30min",
			Label = "(30 Min) +2,500 Length",
		},
		{
			Minutes = 40,
			Kind = "Trophies",
			Amount = 200,
			Card = "40min",
			Label = "(40 Min) +200 Wins",
		},
	} :: { Reward },
}

--- Whether reward `index` is marked claimed in `mask`.
function PlaytimeRewardConfig.IsClaimed(mask: number, index: number): boolean
	return bit32.btest(mask, bit32.lshift(1, index - 1))
end

return PlaytimeRewardConfig
