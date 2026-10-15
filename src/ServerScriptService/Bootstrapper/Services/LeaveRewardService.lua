--!strict
--[[
	@module LeaveRewardService
	@description Grants the "don't leave!" reward (LeaveRewardConfig) through
	NetworkEvents "ClaimLeaveReward": once per UTC day (DataService
	LeaveRewardLastClaimDay, same day boundary as DailyRewardConfig.GetDay --
	the client only shows the leave warning while today's reward is still
	unclaimed). Returns { Success, Error? }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardConfig = require(ReplicatedStorage.Config.DailyRewardConfig)
local DataService = require(script.Parent.DataService)
local LeaveRewardConfig = require(ReplicatedStorage.Config.LeaveRewardConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local RewardGrant = require(script.Parent.Parent.RewardGrant)

local LeaveRewardService = {}

local function claim(player: Player): { Success: boolean, Error: string? }
	local today = DailyRewardConfig.GetDay(os.time())
	if DataService:GetLeaveRewardLastClaimDay(player) >= today then
		return { Success = false, Error = "AlreadyClaimed" }
	end
	-- Day first: a grant failing halfway must never be claimable twice
	if not DataService:SetLeaveRewardLastClaimDay(player, today) then
		return { Success = false, Error = "GrantFailed" }
	end
	local message = RewardGrant.Grant(player, LeaveRewardConfig.Reward, "LeaveReward")
	if message then
		NotificationService.Send(player, message, "Success")
	end
	return { Success = true }
end

function LeaveRewardService:Init(): ()
	NetworkEvents.OnServerInvoke("ClaimLeaveReward", claim, true)
end

function LeaveRewardService:Start(): () end

return LeaveRewardService
