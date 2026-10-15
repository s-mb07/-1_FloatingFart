--!strict
--[[
	@module GamePassConfig
	@description Every gamepass of the game, by logical key (shared: the
	server grants, the client only reads the ownership attribute).

	  - Id:            Roblox gamepass id (0 = not created yet: never prompted,
	                   never queried, counts as not owned).
	  - GiftProductId: Developer Product sold to GIFT this pass to another
	                   player (GiftPassService). nil/0 = not giftable.

	VIP grants: the Golden Plane skin (SkinConfig "11"), the VIP trail
	(TrailConfig "Vip", VIP-only), the [VIP] chat tag (VipChatTagController)
	and the "👑 VIP" tag above the player's head (VipService).
	X2Wins grants: access to the blue x2 win pads (TrophyPadConfig), nothing else.

	Ownership (real pass OR gifted pass) is cached server-side in the player
	attribute `GamePassConfig.Attribute(key)` ("HasVIPPass"), so both sides
	read it for free. Gameplay never calls UserOwnsGamePassAsync: server code
	uses GamePassService.HasPass, client code GamePassConfig.PlayerHasPass.

	Gameplay rules reference a pass by KEY (AccessGate rule `GamePass = "VIP"`),
	never by Roblox id: the id lives here only.
]]

export type PassDef = {
	Id: number,
	GiftProductId: number?,
}

local GamePassConfig = {
	Passes = {
		VIP = { Id = 2027000617, GiftProductId = 0 }, -- Golden Plane skin, VIP trail, chat + overhead tag; Shop VipBtn
		GoldenFan = { Id = 2025476666, GiftProductId = 0 }, -- x5 treadmill 4 (TreadmillConfig)
		DiamondFan = { Id = 2026598638, GiftProductId = 0 }, -- x15 treadmill 5
		AmethystFan = { Id = 2025158640, GiftProductId = 0 }, -- x30 treadmill 6
		RobuxSkin = { Id = 2026412640, GiftProductId = 0 }, -- skin "Robux" (SkinConfig), big skin pad
		TrailOrange = { Id = 2025164623, GiftProductId = 0 }, -- trails (TrailConfig GamePass)
		TrailBlue = { Id = 2025956614, GiftProductId = 0 },
		TrailGreen = { Id = 2026748617, GiftProductId = 0 },
		TrailPurple = { Id = 2026604617, GiftProductId = 0 },
		TrailRainbow = { Id = 2025812609, GiftProductId = 0 },
		X2Wins = { Id = 2027156637, GiftProductId = 0 }, -- blue x2 win pads (TrophyPadConfig): HUD 2XWins / Wins "+", Shop X2WinsBtn
		FastTrain = { Id = 2026442643, GiftProductId = 0 }, -- treadmill x2 pace (BoostService): HUD FastTrain
		TrainerPack = { Id = 2025182656, GiftProductId = 0 }, -- Shop TrainerPackBtn (no gameplay effect yet)
		StarterPack = { Id = 2025308630, GiftProductId = 0 }, -- one-time Starter Pack (StarterPackService): HUD StarterPack, Shop StarterPackBtn
		-- Length multiplier steps (BoostService): HUD 2XLengh, Shop X2LenghBtn
		-- prompt the NEXT step's pass.
		LengthX2 = { Id = 2026988641, GiftProductId = 0 },
		LengthX3 = { Id = 2025692620, GiftProductId = 0 },
		LengthX4 = { Id = 2025896704, GiftProductId = 0 },
		LengthX5 = { Id = 2026706614, GiftProductId = 0 },
	} :: { [string]: PassDef },
}

--- Player attribute caching the ownership of pass `key`.
function GamePassConfig.Attribute(key: string): string
	return "Has" .. key .. "Pass"
end

--- Client/server: true when the cached ownership attribute says `player` owns
--- `key`. Display/gameplay read only -- never use it to authorize a purchase.
function GamePassConfig.PlayerHasPass(player: Player, key: string): boolean
	return GamePassConfig.Passes[key] ~= nil
		and player:GetAttribute(GamePassConfig.Attribute(key)) == true
end

return GamePassConfig
