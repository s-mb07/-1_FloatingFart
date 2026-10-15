--!strict
--[[
	@module StarterPackConfig
	@description The one-time Starter Pack. Shared: StarterPackService grants
	it, the StarterPack panel and the HUD button display it.

	THE RULES (server-enforced, see StarterPackService)
	  - Once per player, ever (saved as StarterPackClaimed).
	  - Grants +Length (flat traversal XP) and +Wins (trophies).
	  - Sold as gamepass "StarterPack" (GamePassConfig). PriceRobux is only displayed.
	  - Once claimed, the HUD button and the panel go away.
]]

local StarterPackConfig = {
	Length = 25000,
	Wins = 50,
	--- Shown on the HUD button and in the panel (display only).
	PriceRobux = 39,
}

return StarterPackConfig
