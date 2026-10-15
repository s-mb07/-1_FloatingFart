--!strict
--[[
	@module GroupRewardService
	@description NetworkEvents "ClaimGroupReward": grants GroupRewardConfig's
	wins + length once per profile (DataService flag GroupRewardClaimed),
	only to a member of GroupRewardConfig.GroupId (checked here, never
	trusted from the client; skipped while GroupId = 0).
	Returns { Success, Error? } -- Error: "AlreadyClaimed" | "NotInGroup" | "GrantFailed".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GroupRewardConfig = require(ReplicatedStorage.Config.GroupRewardConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local RewardGrant = require(script.Parent.Parent.RewardGrant)

local GroupRewardService = {}

local function isMember(player: Player): boolean
	if GroupRewardConfig.GroupId == 0 then
		return true -- no group yet: placeholder, see GroupRewardConfig
	end
	local ok, member = pcall(player.IsInGroup, player, GroupRewardConfig.GroupId)
	return ok and member == true
end

local function claim(player: Player): { Success: boolean, Error: string? }
	if DataService:HasFlag(player, "GroupRewardClaimed") then
		return { Success = false, Error = "AlreadyClaimed" }
	end
	if not isMember(player) then
		return { Success = false, Error = "NotInGroup" }
	end
	-- Flag first: a grant failing halfway must never be claimable twice
	if not DataService:SetFlag(player, "GroupRewardClaimed") then
		return { Success = false, Error = "GrantFailed" }
	end
	local wins = RewardGrant.Grant(player, { Kind = "Trophies", Amount = GroupRewardConfig.Wins }, "GroupReward")
	local length = RewardGrant.Grant(player, { Kind = "Length", Amount = GroupRewardConfig.Length }, "GroupReward")
	NotificationService.Send(player, ("%s  %s"):format(wins or "", length or ""), "Success")
	return { Success = true }
end

function GroupRewardService:Init(): ()
	NetworkEvents.OnServerInvoke("ClaimGroupReward", claim, true)
end

function GroupRewardService:Start(): () end

return GroupRewardService
