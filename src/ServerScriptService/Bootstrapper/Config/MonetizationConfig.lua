--!strict
--[[
	@class MonetizationConfig
	Server-only monetization data (no logic):
	  - FreeMode: switch for every Robux-gated element (blue x2 win pads, paid
	    treadmills, paid skins -- their rules carry a `GamePass` key, see
	    ReplicatedStorage/Config/GamePassConfig).
	  - Products: Developer Products by logical key (MonetizationService
	    grants them from ProcessReceipt). Id 0 = not created yet, never prompted.
	  - GiftCompensationWinsPerRobux: what a gift buyer gets back when the gift
	    can't be delivered (GiftPassService).

	Product Kinds (adding one = a new branch in MonetizationService.grantProduct):
	  - "Wins":         +Amount trophies, fixed (the price paid is ignored).
	  - "WinsPerRobux": +Amount trophies per Robux spent (reads CurrencySpent;
	                    the only Kind that depends on the price, on purpose).
	  - "Length":       +Amount Length (HUD Boost1..4).
	  - "SkipRebirth":  the next rebirth, level requirement ignored (RebirthService, Amount unused).
	  - "SkipDailyReward": the next daily reward now, once-per-day limit ignored
	                    (DailyRewardService, Amount unused).
	  - "Revive":       back to the lost run's checkpoint (LifeService, Amount
	                    unused). Offer gone by the time the receipt lands =
	                    refunded as GiftCompensationWinsPerRobux Wins per Robux.
	                    Id 0 = revive is free.

	Clients prompt a product by KEY (NetworkEvents "PromptProductPurchase"),
	never by id.
]]

export type ProductDef = {
	Id: number,
	Kind: "Wins" | "WinsPerRobux" | "Length" | "SkipRebirth" | "SkipDailyReward" | "Revive",
	Amount: number,
}

local MonetizationConfig = {
	--- true: every Robux path counts as owned, so paid elements work for
	--- everyone (testing / before the ids exist). Set to false once the
	--- ids in GamePassConfig are filled in.
	FreeMode = false,

	Products = {
		Wins100 = { Id = 0, Kind = "Wins", Amount = 100 },
		Wins1K = { Id = 0, Kind = "Wins", Amount = 1000 },
		Donation = { Id = 0, Kind = "WinsPerRobux", Amount = 1 },
		Length25K = { Id = 3717770313, Kind = "Length", Amount = 25000 }, -- HUD Boost1
		Length100K = { Id = 3717770428, Kind = "Length", Amount = 100000 }, -- HUD Boost2
		Length500K = { Id = 3717770583, Kind = "Length", Amount = 500000 }, -- HUD Boost3
		Length1M = { Id = 3717770751, Kind = "Length", Amount = 1000000 }, -- HUD Boost4
		SkipRebirth = { Id = 3717770109, Kind = "SkipRebirth", Amount = 1 }, -- RebirthUI SkipRebirthBtn
		SkipDailyReward = { Id = 3717770217, Kind = "SkipDailyReward", Amount = 1 }, -- DailyRewardsUI SkipDay
		Revive = { Id = 3717994603, Kind = "Revive", Amount = 1 }, -- TopHUD Revive (LifeService); 0 = free revive
	} :: { [string]: ProductDef },

	GiftCompensationWinsPerRobux = 10,
}

return MonetizationConfig
