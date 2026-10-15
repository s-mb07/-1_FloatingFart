--!strict
--[[
	@module ModerationService
	@description Text filtering + moderation actions (kick/ban), kept in one
	place so every player-text -> text-shown-to-other-players path goes
	through ONE single function (FilterForBroadcast), never a
	`:FilterStringAsync` scattered across every service that needs to filter
	an exchanged username/message/object name.

	Bans: persisted in a dedicated DataStore ("Bans", NEVER in the player's
	ProfileStore: a ban must apply BEFORE their profile session even opens,
	see DataService:Init -> Players.PlayerAdded). Checked on every join; a
	DataStore failure (Studio without API access) never blocks a join.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local AdminConfig = require(script.Parent.Parent.Config.AdminConfig)
local Logger = require(game:GetService("ReplicatedStorage").Libraries.Logger)

local ModerationService = {}
local log = Logger.new("ModerationService")

-- UserId -> reason: cache of the DataStore "Bans" (key = UserId), filled on join / ban.
local bannedUsers: { [number]: string } = {}
local banStore = DataStoreService:GetDataStore("Bans")

--- Filters player text for broadcast to ALL other players (custom chat,
--- displayed username, name of an object created by a player...). NEVER
--- use a player's raw text for another player without going through here.
--- @param fromPlayer Player -- author of the text
--- @param text string
--- @return string -- filtered text, safe to display to ANY player
function ModerationService.FilterForBroadcast(fromPlayer: Player, text: string): string
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, fromPlayer.UserId)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	log:Warn("Filtering failed for %s: %s", fromPlayer.Name, tostring(result))
	return "" -- filtering failure = silence, never the raw unfiltered text
end

--- @return boolean
function ModerationService.IsBanned(userId: number): boolean
	return bannedUsers[userId] ~= nil
end

--- In-memory ban + immediate kick if the player is connected. `staffUserId`
--- must be a known admin from AdminConfig -- the caller (AdminService, a
--- /ban command...) is responsible for checking that BEFORE calling Ban.
function ModerationService.Ban(userId: number, reason: string, staffUserId: number): ()
	if not AdminConfig.Admins[staffUserId] then
		log:Warn("Ban refused: %d is not an admin.", staffUserId)
		return
	end

	bannedUsers[userId] = reason
	log:Info("%d banned by %d: %s", userId, staffUserId, reason)

	-- Persisted so the ban outlives this server (other servers read it on join).
	task.spawn(function()
		local saved, err = pcall(function()
			banStore:SetAsync(tostring(userId), reason)
		end)
		if not saved then
			log:Warn("Ban of %d could not be saved: %s", userId, tostring(err))
		end
	end)

	local target = Players:GetPlayerByUserId(userId)
	if target then
		target:Kick(("Banned: %s"):format(reason))
	end
end

local function checkBan(player: Player): ()
	local reason = bannedUsers[player.UserId]
	if not reason then
		local read, stored = pcall(function()
			return banStore:GetAsync(tostring(player.UserId))
		end)
		if read and type(stored) == "string" then
			reason = stored
			bannedUsers[player.UserId] = stored
		end
	end
	if reason then
		player:Kick(("Banned: %s"):format(reason))
	end
end

function ModerationService:Init(): ()
	Players.PlayerAdded:Connect(checkBan)
	for _, player in Players:GetPlayers() do
		task.spawn(checkBan, player)
	end
end

return ModerationService
