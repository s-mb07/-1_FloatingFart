--!strict
--[[
	@module PurchaseRevealConfig
	@description What PurchaseRevealController shows once a purchase is
	granted, by the key the server sends ("PurchaseGranted"): a
	MonetizationConfig.Products key or a GamePassConfig.Passes key. Also fired
	client-side for a free gift worth the same fanfare (Panels/LeaveReward).

	  - Icon:     the image that jumps at the player (same art as its button).
	  - Title:    big rainbow text. "%d" is replaced by the server's detail
	              number when it sends one.
	  - Benefits: lines that slide in one by one under the title.
	  - Tint:     optional gradient over the icon (a trail shows the plane in
	              its own colors, like its card).
	  - Quick:    short reveal for Developer Products ONLY (+Length boosts, Skip Rebirth...): no
	              screen dim, clicks go through, gone in about a second, so
	              the buy button is right there again.

	Cosmetic only: an unknown key falls back to `Default`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local LeaveRewardConfig = require(ReplicatedStorage.Config.LeaveRewardConfig)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local StarterPackConfig = require(ReplicatedStorage.Config.StarterPackConfig)
local TrailConfig = require(ReplicatedStorage.Config.TrailConfig)

export type Reveal = {
	Icon: string,
	Title: string,
	Benefits: { string }?,
	Tint: ColorSequence?,
	Quick: boolean?,
}

-- Same art as the HUD / Shop buttons.
local PLANE = "rbxassetid://82109037700647" -- Boost1..4, Shop X2LenghBtn, trail cards (Item)
local LENGTH_MULTIPLIER = "rbxassetid://101986319724450" -- HUD 2XLengh
local TROPHY = "rbxassetid://130249865181549" -- Wins counter, 2XWins
local STARTER_PACK = "rbxassetid://72015146208183"
local DUMBBELL = "rbxassetid://101070225192962" -- Shop TrainerPackBtn
local VIP = "rbxassetid://131794524729844"
local FAST_TRAIN = "rbxassetid://97996203730596"
local GIFT = "rbxassetid://72619050115795" -- LeaveRewardUI TopFrame Icon

local function lengthBoost(title: string): Reveal
	return { Icon = PLANE, Title = title, Benefits = { "Added to your Length!" }, Quick = true }
end

local function fan(name: string): Reveal
	return { Icon = FAST_TRAIN, Title = name, Benefits = { "Treadmill unlocked forever!" } }
end

local PurchaseRevealConfig = {
	Default = { Icon = PLANE, Title = "Thank you!", Benefits = { "Purchase complete!" } } :: Reveal,

	Items = {
		-- Developer Products (MonetizationConfig.Products)
		Length25K = lengthBoost("+25K Length"),
		Length100K = lengthBoost("+100K Length"),
		Length500K = lengthBoost("+500K Length"),
		Length1M = lengthBoost("+1M Length"),
		Wins100 = { Icon = TROPHY, Title = "+100 Wins", Quick = true },
		Wins1K = { Icon = TROPHY, Title = "+1,000 Wins", Quick = true },
		Donation = {
			Icon = TROPHY,
			Title = "Thank you!",
			Benefits = { "Wins added!" },
			Quick = true,
		},
		SkipRebirth = { Icon = PLANE, Title = "Rebirth Skipped!", Quick = true },
		SkipDailyReward = { Icon = PLANE, Title = "Day Skipped!", Quick = true },
		Revive = { Icon = PLANE, Title = "Revived!", Quick = true },

		-- Gamepasses (GamePassConfig.Passes): normal-speed reveal
		StarterPack = {
			Icon = STARTER_PACK,
			Title = "Starter Pack",
			Benefits = {
				"+" .. NumberUtil.Format(StarterPackConfig.Length) .. " Length",
				"+" .. NumberUtil.Format(StarterPackConfig.Wins) .. " Wins",
			},
		},
		TrainerPack = {
			Icon = DUMBBELL,
			Title = "Trainer Pack",
			Benefits = { "ALL TRAINERS FOREVER", "LIMITED", "50%" }, -- same lines as Shop TrainerPackBtn
		},
		VIP = {
			Icon = VIP,
			Title = "VIP",
			Benefits = { "Golden Plane unlocked!", "VIP Trail unlocked!", "VIP chat tag + crown!" },
		},
		X2Wins = {
			Icon = TROPHY,
			Title = "x2 Wins",
			Benefits = { "Blue x2 win pads unlocked!", "Forever!" },
		},
		FastTrain = {
			Icon = FAST_TRAIN,
			Title = "Fast Train",
			Benefits = { "x2 treadmill speed!", "Forever!" },
		},
		GoldenFan = fan("Golden Fan"),
		DiamondFan = fan("Diamond Fan"),
		AmethystFan = fan("Amethyst Fan"),
		RobuxSkin = { Icon = PLANE, Title = "Robux Plane", Benefits = { "New skin unlocked!" } },

		-- Free gifts (fired client-side once the server granted them)
		LeaveReward = {
			Icon = GIFT,
			Title = "THANK YOU FOR STAYING!",
			Benefits = {
				"+" .. NumberUtil.Format(LeaveRewardConfig.Reward.Amount) .. " Length",
				"Enjoy your gift!",
			},
		},
	} :: { [string]: Reveal },
}

-- One reveal per Length multiplier step gamepass (LengthX2..LengthX5).
for step = 2, BoostConfig.MaxLengthMultiplier do
	PurchaseRevealConfig.Items["LengthX" .. step] = {
		Icon = LENGTH_MULTIPLIER,
		Title = ("x%d Length"):format(step),
		Benefits = { "Every Length gain multiplied!", "Forever!" },
	}
end

-- One reveal per trail gamepass (TrailConfig GamePass key). A pass that
-- already has its own reveal (VIP, which also grants the VIP trail) keeps it.
for _, def in TrailConfig.Trails do
	if PurchaseRevealConfig.Items[def.GamePass] then
		continue
	end
	PurchaseRevealConfig.Items[def.GamePass] = {
		Icon = PLANE,
		Tint = TrailConfig.ColorSequenceOf(def),
		Title = def.DisplayName,
		Benefits = {
			"You bought the " .. def.DisplayName .. "!",
			("x%s Points"):format(tostring(def.XPMultiplier)),
			"Equipped!",
		},
	}
end

return PurchaseRevealConfig
