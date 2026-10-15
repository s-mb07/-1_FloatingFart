--!strict
--[[
	@module DataTemplate
	@description Default player data template + associated types.
	Single source of truth for the data structure -- used by
	ProfileStore to initialize new players.

	The types (`PlayerProfile` and sub-types) live INSIDE this file rather
	than in a separate `Types/` under ReplicatedStorage: they're the values
	AND the shape of one and the same thing, edited together. The client
	that receives `profile.Data` via NetworkEvents ("DataInitialized"/"DataUpdated")
	treats it as `any` and locally re-types whatever it needs -- it can't
	`require` a ServerScriptService module anyway.

	Minimal example skeleton -- add your own fields as you go
	(Inventory, Progression, ...), types and values together.
]]

--- Game currencies
export type Currencies = {
	Gold: number,
	Trophies: number,
}

--- User settings
export type UserSettings = {
	MusicEnabled: boolean,
	SfxEnabled: boolean,
	VfxEnabled: boolean,
	HapticsEnabled: boolean,
	ScreenShakeEnabled: boolean,
	--- "Auto" | "Low" | "Medium" | "High" (see StarterPlayerScripts/Bootstrapper/
	--- Config/GraphicsQualityConfig.lua -- "Auto" = QualityController decides at
	--- boot, an explicit level always wins over detection).
	GraphicsQuality: string,
}

--- Game statistics
export type PlayerStats = {
	PlayTime: number,
	CreatedAt: number,
	LastLogin: number,
}

--- Traversal progression. Generic on purpose: this is the progression of
--- the traversal MECHANIC, not of any particular visual for it -- a tongue,
--- a hook and rope, a stretching hand, a tentacle, a chain, a vine and a
--- magic tether all read and write these same two fields.
---
--- Real length and the HUD stamina bar are derived from the level and never
--- persisted. XP is the TOTAL earned since the last rebirth (or the start);
--- the level is stored alongside it (tiers live in TraversalProgressionConfig).
--- Rebirths counts rebirths taken (ReplicatedStorage/Config/RebirthConfig);
--- each one resets Level to 1 and XP to 0.
export type TraversalProgress = {
	Level: number,
	XP: number,
	Rebirths: number,
}

--- Skins: ids (see Config/SkinConfig) unlocked and currently equipped.
export type SkinData = {
	Owned: { [string]: boolean },
	Equipped: string,
}

--- Daily login rewards (rules in ReplicatedStorage/Config/DailyRewardConfig).
export type DailyRewardData = {
	--- Days claimed in the current 7-day cycle (0..7).
	Claimed: number,
	--- UTC day index (DailyRewardConfig.GetDay) of the last claim; 0 = never.
	LastClaimDay: number,
}

--- Playtime rewards (rules in ReplicatedStorage/Config/PlaytimeRewardConfig):
--- they reset every UTC day, so the progress of the current day is stored.
export type PlaytimeRewardData = {
	--- UTC day index (DailyRewardConfig.GetDay) the numbers below belong to.
	Day: number,
	--- Seconds played that day, over all sessions.
	Seconds: number,
	--- Bitmask of the rewards claimed that day (bit i-1 = reward i).
	Claimed: number,
}

--- Character trails (ReplicatedStorage/Config/TrailConfig): ids owned and
--- the one equipped ("" = none).
export type TrailData = {
	Owned: { [string]: boolean },
	Equipped: string,
}

--- Permanent multipliers bought from the HUD (rules in
--- ReplicatedStorage/Config/BoostConfig). Plain coefficients, 1 = none:
--- LengthMultiplier 1..5 scales per-second XP, TreadmillSpeed 1 or 2
--- ("Fast Train") divides the treadmill grant interval. Rebirths never touch
--- them. (Old profiles may still carry a dead `TrophyMultiplier` key: the
--- X2Wins pass no longer multiplies wins, nothing reads it.)
export type BoostData = {
	LengthMultiplier: number,
	TreadmillSpeed: number,
}

--- A pass received as a gift: when, and through which buyer receipt.
export type GiftedPass = {
	At: number,
	ReceiptId: string,
}

--- Full player profile structure
export type PlayerProfile = {
	Boosts: BoostData,
	Trails: TrailData,
	--- One-time Starter Pack (ReplicatedStorage/Config/StarterPackConfig).
	StarterPackClaimed: boolean,
	--- One-time group reward (ReplicatedStorage/Config/GroupRewardConfig).
	GroupRewardClaimed: boolean,
	--- Daily "don't leave!" reward (ReplicatedStorage/Config/LeaveRewardConfig):
	--- UTC day index (DailyRewardConfig.GetDay) of the last claim; 0 = never.
	LeaveRewardLastClaimDay: number,
	--- The native "add to favorites" prompt was already shown (FavoritePromptService).
	FavoritePrompted: boolean,
	--- New-player tutorial (ReplicatedStorage/Config/TutorialConfig): current
	--- Stage (1..#Stages, #Stages + 1 = finished) and whether the one-time
	--- rebirth focus has already been shown.
	Tutorial: { Stage: number, RebirthFocusShown: boolean },
	--- Placeholder shop items claimed (ReplicatedStorage/Config/ShopConfig).
	ShopClaimed: { [string]: boolean },
	Currencies: Currencies,
	Settings: UserSettings,
	Stats: PlayerStats,
	Traversal: TraversalProgress,
	Skins: SkinData,
	DailyRewards: DailyRewardData,
	PlaytimeRewards: PlaytimeRewardData,
	RedeemedCodes: { [string]: boolean },
	--- Developer Product receipts already granted: PurchaseId -> os.time() of
	--- the grant (MonetizationService idempotence). Purged after RECEIPT_TTL
	--- in DataService. Never reset: purchases outlive a data reset.
	ProcessedReceipts: { [string]: number },
	--- Gamepasses received as a gift (GiftPassService). Counts as owned
	--- everywhere (GamePassService). Never reset.
	GiftedPasses: { [string]: GiftedPass },
}

local DataTemplate: PlayerProfile = {
	Currencies = {
		Gold = 0,
		Trophies = 0,
	},

	Settings = {
		MusicEnabled = true,
		SfxEnabled = true,
		VfxEnabled = true,
		HapticsEnabled = true,
		ScreenShakeEnabled = true,
		GraphicsQuality = "Auto",
	},

	Stats = {
		PlayTime = 0,
		CreatedAt = 0,
		LastLogin = 0,
	},

	Traversal = {
		Level = 1,
		XP = 0,
		Rebirths = 0,
	},

	Skins = {
		Owned = { ["1"] = true }, -- SkinConfig.Default
		Equipped = "1",
	},

	DailyRewards = {
		Claimed = 0,
		LastClaimDay = 0,
	},

	PlaytimeRewards = {
		Day = 0,
		Seconds = 0,
		Claimed = 0,
	},

	Boosts = {
		LengthMultiplier = 1,
		TreadmillSpeed = 1,
	},

	Trails = {
		Owned = {},
		Equipped = "",
	},

	StarterPackClaimed = false,
	GroupRewardClaimed = false,
	LeaveRewardLastClaimDay = 0,
	FavoritePrompted = false,

	Tutorial = {
		Stage = 1,
		RebirthFocusShown = false,
	},

	ShopClaimed = {},

	RedeemedCodes = {},

	ProcessedReceipts = {},
	GiftedPasses = {},
}

return DataTemplate
