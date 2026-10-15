--!strict
--[[
	@module RebirthService
	@description Server authority for rebirths (ReplicatedStorage/Config/
	RebirthConfig has the ladder and the rules).

	NetworkEvents "RequestRebirth" (RemoteFunction, 1/s): a normal rebirth,
	level requirement enforced. A skip (requirement ignored) is only granted
	by the "SkipRebirth" developer product (MonetizationService). This service picks the NEXT rebirth (current count
	+ 1, never more), checks the level requirement unless skipping, then
	writes Rebirths/Level/XP in one DataService:ApplyRebirth call and
	re-publishes progression so the HUD resets.

	The XP multiplier itself is applied in
	TraversalProgressionService.GetXPPerSecond, read fresh on every grant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)
local TraversalProgressionService = require(script.Parent.TraversalProgressionService)

local log = Logger.new("RebirthService")
local RebirthService = {}

type RebirthResult = { Success: boolean, Error: string? }

--- Takes the next rebirth for `player`.
--- @param skip boolean -- true = ignore the level requirement (paid skip only, never from the client)
--- @return RebirthResult -- Error: "MaxRebirths" | "LevelTooLow" | DataService error code
function RebirthService.Rebirth(player: Player, skip: boolean): RebirthResult
	local current = DataService:GetRebirths(player)
	local nextRebirth = current + 1
	if nextRebirth > RebirthConfig.GetMaxRebirths() then
		return { Success = false, Error = "MaxRebirths" }
	end

	local previousLevel = TraversalProgressionService.GetLevel(player)
	if skip ~= true and previousLevel < RebirthConfig.GetRequiredLevel(nextRebirth) then
		return { Success = false, Error = "LevelTooLow" }
	end

	local ok, reason = DataService:ApplyRebirth(player, nextRebirth)
	if not ok then
		log:Warn("%s: rebirth %d write refused (%s).", player.Name, nextRebirth, tostring(reason))
		return { Success = false, Error = reason }
	end

	GameEvents.OnTraversalLevelChanged:Fire(player, 1, previousLevel)
	GameEvents.OnRebirthed:Fire(player)
	GameEvents.OnTraversalXPChanged:Fire(player, 0)
	TraversalProgressionService.Publish(player)
	NotificationService.Send(
		player,
		("Rebirth %d! XP x%.2f"):format(nextRebirth, RebirthConfig.GetMultiplier(nextRebirth)),
		"Success"
	)
	log:Info(
		"%s: rebirth %d -> %d (%s, was level %d).",
		player.Name,
		current,
		nextRebirth,
		if skip == true then "skip" else "normal",
		previousLevel
	)
	return { Success = true }
end

function RebirthService:Init(): ()
	NetworkEvents.OnServerInvoke("RequestRebirth", function(player: Player): RebirthResult
		return RebirthService.Rebirth(player, false)
	end, true)
end

function RebirthService:Start(): () end

return RebirthService
