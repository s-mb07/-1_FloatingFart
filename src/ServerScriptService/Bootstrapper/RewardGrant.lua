--!strict
--[[
	@module RewardGrant
	@description Grants one reward entry and returns the toast text (win
	pads, daily, playtime, codes). Server-only;
	lives beside Services/ (not inside it) so the bootstrapper doesn't try to
	Init/Start it.

	Kinds:
	  - Trophies: +Amount trophies ("Wins" on the HUD).
	  - Length:   +Amount traversal XP, flat (the per-second multipliers live
	              in TraversalProgressionService.GetXPPerSecond instead).
	  - Skin:     unlocks SkinId; FallbackTrophies if already owned.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.Services.DataService)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local TraversalProgressionService = require(script.Parent.Services.TraversalProgressionService)

export type Reward = {
	Kind: "Trophies" | "Length" | "Skin",
	Amount: number?,
	SkinId: string?,
	FallbackTrophies: number?,
}

local RewardGrant = {}

local function addWins(player: Player, amount: number): string?
	return if DataService:AddTrophies(player, amount)
		then "+" .. NumberUtil.Format(amount) .. " Wins"
		else nil
end

--- Grants `reward` to `player`.
--- @param source string -- logged by the XP grant, tells grant paths apart
--- @return string? -- toast text, nil if the grant failed
function RewardGrant.Grant(player: Player, reward: Reward, source: string): string?
	if reward.Kind == "Trophies" then
		return addWins(player, reward.Amount :: number)
	elseif reward.Kind == "Length" then
		local amount = reward.Amount :: number
		local ok = TraversalProgressionService.AddXP(player, amount, source)
		return if ok then "+" .. NumberUtil.Format(amount) .. " Length" else nil
	elseif reward.Kind == "Skin" then
		local skinId = reward.SkinId :: string
		if DataService:OwnsSkin(player, skinId) then
			return addWins(player, reward.FallbackTrophies :: number)
		end
		return if DataService:UnlockSkin(player, skinId) then "New skin unlocked!" else nil
	end
	return nil
end

return RewardGrant
