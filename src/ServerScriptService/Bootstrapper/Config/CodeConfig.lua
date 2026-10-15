--!strict
--[[
	@module CodeConfig
	@description Redeemable codes. SERVER-ONLY on purpose: anything under
	ReplicatedStorage is readable by every client, which would leak the
	unreleased codes. The client only ever sends what the player typed.

	Keys are lowercase: CodeService lowercases and trims the input, so codes
	are case-insensitive. Adding a code = one entry below. Rewards are paid
	out by Bootstrapper/RewardGrant (Trophies / Length / Skin).
]]

local RewardGrant = require(script.Parent.Parent.RewardGrant)

export type CodeDef = {
	Reward: RewardGrant.Reward,
}

local CodeConfig = {
	Codes = {
		-- Release codes, starter-sized: WELCOME buys the first two skins (1 + 5 Wins),
		-- MONKEYSGC matches the Day 2 daily reward.
		welcome = { Reward = { Kind = "Trophies", Amount = 10 } },
		monkeysgc = { Reward = { Kind = "Length", Amount = 10000 } },
	} :: { [string]: CodeDef },
}

return CodeConfig
