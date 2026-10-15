--!strict
--[[
	@module RebirthConfig
	@description Rebirth ladder. Shared: RebirthService enforces it, the
	Rebirth panel displays it.

	THE RULES (server-enforced, see RebirthService)
	  - Rebirth #N needs traversal level Tiers[N].Level and sets the XP
	    bonus to Tiers[N].Multiplier (the table value, not a sum
	    of the previous ones). 0 rebirths = x1 (no bonus). The multiplier is
	    an ADDITIVE %: x1.25 = +25% of the skin's base XP/s, summed with the trail bonus.
	  - Rebirths are taken one at a time, in order: a level-40 player with 0
	    rebirths who rebirths gets rebirth #1 (x1.25), never #4.
	  - "Skip Rebirth" (developer product "SkipRebirth", MonetizationConfig)
	    grants the next rebirth ignoring the level requirement; otherwise
	    identical to a normal rebirth.
	  - Every rebirth resets traversal level to 1 and XP ("Total Length") to 0.
	  - The multiplier scales per-second XP only (hook + treadmill, i.e.
	    TraversalProgressionService.GetXPPerSecond) -- flat Length rewards
	    (daily, playtime, codes) are not multiplied.
	  - After the last tier, no more rebirths (MAX).
]]

export type Tier = {
	--- Traversal level required to take this rebirth.
	Level: number,
	--- XP multiplier once this rebirth is taken.
	Multiplier: number,
}

local RebirthConfig = {
	--- Index = rebirth number.
	Tiers = {
		{ Level = 10, Multiplier = 1.25 },
		{ Level = 20, Multiplier = 1.5 },
		{ Level = 30, Multiplier = 2 },
		{ Level = 40, Multiplier = 2.5 },
		{ Level = 50, Multiplier = 3 },
		{ Level = 60, Multiplier = 3.5 },
		{ Level = 70, Multiplier = 4 },
		{ Level = 80, Multiplier = 4.5 },
		{ Level = 90, Multiplier = 5 },
		{ Level = 100, Multiplier = 5.5 },
		{ Level = 110, Multiplier = 6 },
		{ Level = 120, Multiplier = 7 },
		{ Level = 130, Multiplier = 8 },
		{ Level = 140, Multiplier = 9 },
		{ Level = 150, Multiplier = 10 },
	} :: { Tier },
}

--- Number of rebirths available in total.
function RebirthConfig.GetMaxRebirths(): number
	return #RebirthConfig.Tiers
end

--- XP multiplier after `rebirths` rebirths (x1 with none).
function RebirthConfig.GetMultiplier(rebirths: number): number
	local tier = RebirthConfig.Tiers[rebirths]
	return if tier then tier.Multiplier else 1
end

--- Level rebirth #`rebirthNumber` requires (0 for "no rebirth yet").
function RebirthConfig.GetRequiredLevel(rebirthNumber: number): number
	local tier = RebirthConfig.Tiers[rebirthNumber]
	return if tier then tier.Level else 0
end

return RebirthConfig
