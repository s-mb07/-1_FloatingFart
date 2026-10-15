--!strict
--[[
	@module PlaytimeRewardService
	@description Server authority for session playtime rewards
	(ReplicatedStorage/Config/PlaytimeRewardConfig has the table and the rules).

	Playtime rewards reset every UTC day (DailyRewardConfig.GetDay), so the
	day's progress is persisted (DataService:Get/SetPlaytimeRewards: day,
	seconds played that day over all sessions, claimed bitmask). On join the
	stored day is compared with today: a new day resets everything. The same
	check runs periodically, so a server that stays up past midnight UTC
	resets too.

	What the client sees is unchanged: two player attributes only the server
	writes (StartAttribute = a virtual start so "now - start" is the seconds
	played today, ClaimedAttribute = the mask). The client only asks "claim
	reward i" (NetworkEvents "ClaimPlaytimeReward"); this service re-checks
	the index, the elapsed time and the claimed bit before granting.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardConfig = require(ReplicatedStorage.Config.DailyRewardConfig)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local PlayerService = require(script.Parent.PlayerService)
local PlaytimeRewardConfig = require(ReplicatedStorage.Config.PlaytimeRewardConfig)
local RewardGrant = require(script.Parent.Parent.RewardGrant)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)

local log = Logger.new("PlaytimeRewardService")
local PlaytimeRewardService = {}

type ClaimResult = { Success: boolean, Error: string? }

--- Publishes today's progress as the two attributes; a stored day that is
--- not today resets the stored progress first. No-op until the profile is
--- loaded.
local function syncDay(player: Player): ()
	local day, seconds, claimed = DataService:GetPlaytimeRewards(player)
	local today = DailyRewardConfig.GetDay(os.time())
	if day ~= today then
		DataService:SetPlaytimeRewards(player, today, 0, 0)
		player:SetAttribute(PlaytimeRewardConfig.StartAttribute, workspace:GetServerTimeNow())
		player:SetAttribute(PlaytimeRewardConfig.ClaimedAttribute, 0)
		return
	end
	-- Same day: the virtual start makes "now - start" = seconds played today.
	player:SetAttribute(PlaytimeRewardConfig.StartAttribute, workspace:GetServerTimeNow() - seconds)
	player:SetAttribute(PlaytimeRewardConfig.ClaimedAttribute, claimed)
end

--- Writes the current progress to the profile (seconds so far today).
local function persist(player: Player): ()
	local start = player:GetAttribute(PlaytimeRewardConfig.StartAttribute)
	local mask = player:GetAttribute(PlaytimeRewardConfig.ClaimedAttribute)
	if type(start) ~= "number" or type(mask) ~= "number" then
		return
	end
	DataService:SetPlaytimeRewards(
		player,
		DailyRewardConfig.GetDay(os.time()),
		math.max(0, workspace:GetServerTimeNow() - start),
		mask
	)
end

--- Every tick: a day that changed under a running session resets it; else
--- the seconds are saved.
local function tick(): ()
	for _, player in PlayerService.GetRegisteredPlayers() do
		if player:GetAttribute(PlaytimeRewardConfig.StartAttribute) == nil then
			continue -- profile not loaded yet
		end
		local day = DataService:GetPlaytimeRewards(player)
		if day ~= DailyRewardConfig.GetDay(os.time()) then
			syncDay(player)
		else
			persist(player)
		end
	end
end

--- Claims playtime reward `index` for `player` if its time has come.
--- @param index any -- from the client, validated here
--- @return ClaimResult
function PlaytimeRewardService.Claim(player: Player, index: any): ClaimResult
	local reward = if type(index) == "number" then PlaytimeRewardConfig.Rewards[index] else nil
	local start = player:GetAttribute(PlaytimeRewardConfig.StartAttribute)
	local mask = player:GetAttribute(PlaytimeRewardConfig.ClaimedAttribute)
	if not reward or type(start) ~= "number" or type(mask) ~= "number" then
		return { Success = false, Error = "Invalid" }
	end
	if PlaytimeRewardConfig.IsClaimed(mask, index) then
		return { Success = false, Error = "AlreadyClaimed" }
	end
	if workspace:GetServerTimeNow() - start < reward.Minutes * 60 then
		return { Success = false, Error = "NotReady" }
	end

	local message = RewardGrant.Grant(player, reward, "PlaytimeReward")
	if not message then
		log:Warn("%s: playtime reward %d grant failed.", player.Name, index)
		return { Success = false, Error = "GrantFailed" }
	end

	player:SetAttribute(
		PlaytimeRewardConfig.ClaimedAttribute,
		bit32.bor(mask, bit32.lshift(1, index - 1))
	)
	persist(player)
	NotificationService.Send(player, message, "Success")
	log:Info("%s claimed playtime reward %d (%d min).", player.Name, index, reward.Minutes)
	return { Success = true }
end

function PlaytimeRewardService:Init(): ()
	NetworkEvents.OnServerInvoke("ClaimPlaytimeReward", PlaytimeRewardService.Claim, true)
end

function PlaytimeRewardService:Start(): ()
	-- The stored progress only exists once the profile is loaded.
	GameEvents.OnDataLoaded:Connect(syncDay)
	for _, player in PlayerService.GetRegisteredPlayers() do
		syncDay(player)
	end
	Players.PlayerRemoving:Connect(persist)
	Scheduler.Every("PlaytimeRewards_Persist", 1 / 30, tick)
end

return PlaytimeRewardService
