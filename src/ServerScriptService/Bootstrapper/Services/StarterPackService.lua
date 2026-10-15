--!strict
--[[
	@module StarterPackService
	@description Server authority for the one-time Starter Pack
	(ReplicatedStorage/Config/StarterPackConfig has the contents and rules).

	Sold as gamepass "StarterPack" (GamePassConfig): owning it calls Claim
	(GamePassService.WhenOwned), which grants +Length and +Wins through RewardGrant, once per
	player (saved via DataService:MarkStarterPackClaimed). The claim is
	recorded BEFORE the grant and nothing in between yields, so a repeated
	ownership signal can never pay twice. The client hides the pack from the
	resulting "DataUpdated".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NotificationService = require(script.Parent.NotificationService)
local RewardGrant = require(script.Parent.Parent.RewardGrant)
local StarterPackConfig = require(ReplicatedStorage.Config.StarterPackConfig)

local log = Logger.new("StarterPackService")
local StarterPackService = {}

type Result = { Success: boolean, Error: string? }

--- Grants the Starter Pack to `player` if never claimed.
function StarterPackService.Claim(player: Player): Result
	if DataService:HasClaimedStarterPack(player) then
		return { Success = false, Error = "AlreadyClaimed" }
	end
	local ok, reason = DataService:MarkStarterPackClaimed(player)
	if not ok then
		return { Success = false, Error = reason }
	end

	local length = RewardGrant.Grant(
		player,
		{ Kind = "Length", Amount = StarterPackConfig.Length },
		"StarterPack"
	)
	local wins = RewardGrant.Grant(
		player,
		{ Kind = "Trophies", Amount = StarterPackConfig.Wins },
		"StarterPack"
	)
	NotificationService.Send(
		player,
		("Starter Pack! %s %s"):format(length or "", wins or ""),
		"Success"
	)
	log:Info("%s claimed the Starter Pack (%s, %s).", player.Name, tostring(length), tostring(wins))
	return { Success = true }
end

function StarterPackService:Init(): ()
	GamePassService.WhenOwned(function(player: Player, key: string)
		if key == "StarterPack" then
			StarterPackService.Claim(player)
		end
	end)
end

function StarterPackService:Start(): () end

return StarterPackService
