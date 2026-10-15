--!strict
--[[
	@module DailyRewardService
	@description Server authority for the 7-day login rewards
	(ReplicatedStorage/Config/DailyRewardConfig has the table and the rules).

	The client only asks "claim" (NetworkEvents "ClaimDailyReward", no
	payload). This service decides whether today's reward is available and
	which day it is, grants it, then records the claim through
	DataService:SetDailyRewards -- the panel redraws from the resulting
	"DataUpdated" snapshot, never from anything it computed itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardConfig = require(ReplicatedStorage.Config.DailyRewardConfig)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local PlayerService = require(script.Parent.PlayerService)
local RewardGrant = require(script.Parent.Parent.RewardGrant)

local log = Logger.new("DailyRewardService")
local DailyRewardService = {}

type ClaimResult = { Success: boolean, Error: string? }

--- Grants the next reward and records it. `skipWait` bypasses the once-per-day
--- limit (the paid "Skip Day" button).
local function grantNext(player: Player, skipWait: boolean): ClaimResult
	local claimed, lastClaimDay = DataService:GetDailyRewards(player)
	local today = DailyRewardConfig.GetDay(os.time())
	if today <= lastClaimDay and not skipWait then
		return { Success = false, Error = "AlreadyClaimed" }
	end

	-- A finished cycle restarts at Day 1 on the next day.
	local day = (if claimed >= #DailyRewardConfig.Rewards then 0 else claimed) + 1
	local message = RewardGrant.Grant(player, DailyRewardConfig.Rewards[day], "DailyReward")
	if not message then
		log:Warn("%s: day %d grant failed.", player.Name, day)
		return { Success = false, Error = "GrantFailed" }
	end

	DataService:SetDailyRewards(player, day, today)
	NotificationService.Send(player, message, "Success")
	log:Info("%s claimed daily reward day %d.", player.Name, day)
	return { Success = true }
end

--- Claims today's reward for `player` if one is available.
--- @return ClaimResult
function DailyRewardService.Claim(player: Player): ClaimResult
	return grantNext(player, false)
end

--- Claims the next reward even if today's was already taken ("Skip Day").
--- Only called from MonetizationService, on a paid "SkipDailyReward" receipt.
--- @return ClaimResult
function DailyRewardService.Skip(player: Player): ClaimResult
	return grantNext(player, true)
end

function DailyRewardService:Init(): ()
	NetworkEvents.OnServerInvoke("ClaimDailyReward", DailyRewardService.Claim, true)
end

--- Checked at join: a finished 7-day cycle starts over on the first day after
--- its last claim, so the panel opens on a fresh Day 1 (missing days alone
--- never reset the streak).
local function checkCycle(player: Player): ()
	local claimed, lastClaimDay = DataService:GetDailyRewards(player)
	if
		claimed >= #DailyRewardConfig.Rewards
		and DailyRewardConfig.GetDay(os.time()) > lastClaimDay
	then
		DataService:SetDailyRewards(player, 0, lastClaimDay)
	end
end

function DailyRewardService:Start(): ()
	GameEvents.OnDataLoaded:Connect(checkCycle)
	for _, player in PlayerService.GetRegisteredPlayers() do
		checkCycle(player)
	end
end

return DailyRewardService
