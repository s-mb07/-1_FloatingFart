--!strict
--[[
	@module BoostService
	@description The grants behind the HUD boost buttons (all paid):
	- MainHUD/BottomHUD/BottomButtons/Boost1..4: Developer Products
	  Length25K..Length1M (MonetizationConfig, Kind "Length") -> GrantLength:
	  flat Length (traversal XP) through RewardGrant -- not multiplied, same
	  as the other Length rewards.
	- MainHUD/RightHUD/2XLengh ("x2 Length" ... "x5 Length"): one gamepass
	  per step, "LengthX2".."LengthX5" (the client prompts the NEXT step).
	  Owning "LengthXn" sets the Length multiplier to n if higher. Replaces
	  the old value, never multiplies it. Applied in
	  TraversalProgressionService.GetXPPerSecond.
	- MainHUD/FastTrain: gamepass "FastTrain" -> one-time, treadmill grants
	  twice as often (TreadmillService reads DataService:GetTreadmillSpeed).
	Pass effects are applied when the pass becomes owned (OnGamePassOwned)
	and re-checked on profile load (the attribute can land first). Rebirths
	never reset any multiplier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local DataService = require(script.Parent.DataService)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NotificationService = require(script.Parent.NotificationService)
local RewardGrant = require(script.Parent.Parent.RewardGrant)

local log = Logger.new("BoostService")
local BoostService = {}

--- Product "Length*": +amount Length. false = not granted.
function BoostService.GrantLength(player: Player, amount: number): boolean
	local message = RewardGrant.Grant(player, { Kind = "Length", Amount = amount }, "LengthBoost")
	if message then
		NotificationService.Send(player, message, "Success")
	end
	return message ~= nil
end

--- Pass "LengthX<step>": Length multiplier raised to `step` (never lowered).
local function onLengthStep(player: Player, step: number): ()
	if DataService:GetLengthMultiplier(player) >= step then
		return
	end
	if DataService:SetBoostMultiplier(player, "LengthMultiplier", step) then
		NotificationService.Send(player, ("Length multiplier x%d!"):format(step), "Success")
		log:Debug("%s: Length multiplier -> x%d.", player.Name, step)
	end
end

--- "Fast Train": one-time, treadmill grants TreadmillSpeed times as often.
local function onFastTrain(player: Player): ()
	if DataService:GetTreadmillSpeed(player) >= BoostConfig.TreadmillSpeed then
		return -- already bought
	end
	if DataService:SetBoostMultiplier(player, "TreadmillSpeed", BoostConfig.TreadmillSpeed) then
		NotificationService.Send(player, "Fast Train! Treadmill x2 speed", "Success")
		log:Debug("%s: Fast Train bought.", player.Name)
	end
end

--- Pass key -> its one-time effect.
local PASS_EFFECTS: { [string]: (Player) -> () } = {
	FastTrain = onFastTrain,
}
for step = 2, BoostConfig.MaxLengthMultiplier do
	PASS_EFFECTS["LengthX" .. step] = function(player: Player)
		onLengthStep(player, step)
	end
end

function BoostService:Init(): ()
	GamePassService.WhenOwned(function(player: Player, key: string)
		local effect = PASS_EFFECTS[key]
		if effect then
			effect(player)
		end
	end)
end

function BoostService:Start(): () end

return BoostService
