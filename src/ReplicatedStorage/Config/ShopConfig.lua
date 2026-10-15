--!strict
--[[
	@module ShopConfig
	@description Shop panel (StarterGui/ShopUI, opened by MainHUD/LeftHUD/Shop,
	the red cart button). Shared: ShopService grants / prompts, the Shop
	panel displays everything.

	Items that already have their own system just call it (no duplicate logic):
	  - StarterPackBtn -> pass "StarterPack" ("PromptGamePassPurchase")
	  - X2LenghBtn     -> pass "LengthX<next step>" ("PromptGamePassPurchase")
	  - X2WinsBtn      -> pass "X2Wins", unlocks the blue x2 win pads ("PromptGamePassPurchase")
	Placeholder items (no gameplay effect yet, only saved as claimed): none
	right now (TrainerPackBtn became a pass).
	Robux items (Exclusive): real purchases through ShopService ("PromptShopPurchase").
]]

export type ExclusiveItem = {
	Kind: "GamePass" | "Product",
	--- Kind "GamePass": GamePassConfig key (its id lives there only).
	PassKey: string?,
	--- Kind "Product": MonetizationConfig.Products key (server-side id).
	ProductKey: string?,
}

local ShopConfig = {
	--- Placeholder item id -> its button name under ShopUI's list.
	Placeholders = {} :: { [string]: string },

	--- Button path, relative to ShopUI's list (ScrollingFrame), dot-separated
	--- -> what it sells. Adding a Robux button = one line here, no code.
	--- Renaming the button in Studio breaks its key.
	Exclusive = {
		-- VIP: Golden Plane skin, VIP trail, chat tag, overhead crown (GamePassConfig).
		["PassesFrame.VipBtn"] = { Kind = "GamePass", PassKey = "VIP" },
		["TrainerPackBtn"] = { Kind = "GamePass", PassKey = "TrainerPack" },
	} :: { [string]: ExclusiveItem },
}

return ShopConfig
