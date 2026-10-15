--!strict
--[[
	@module TutorialService
	@description Server authority for the new-player tutorial
	(ReplicatedStorage/Config/TutorialConfig has the stages and the rules).

	The current stage is saved (DataService:SetTutorialStage) and replicates
	through "DataUpdated" (`Tutorial`); TutorialController only displays it.
	Stages advance from REAL game events -- never from a client claim:
	  1 -> 2  GameEvents.OnTreadmillEntered
	  2 -> 3  traversal level >= TargetLevel (OnTraversalLevelChanged, or already)
	  3 -> 4  GameEvents.OnTrophyPadClaimed
	  4 -> 5  owns skin UpgradeSkinId (OnSkinUnlocked, or already)
	  5 -> done after FinalSeconds
	Stages whose condition already holds are skipped right away (a player
	who already reached level 3 never waits on stage 2).

	NetworkEvents "RebirthFocusShown" (client -> server, no payload) records
	that the one-time rebirth focus (RebirthFocusController) was shown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local TutorialConfig = require(ReplicatedStorage.Config.TutorialConfig)

local log = Logger.new("TutorialService")
local TutorialService = {}

local STAGE_TREADMILL = 1
local STAGE_LEVEL = 2
local STAGE_WIN = 3
local STAGE_UPGRADE = 4
local STAGE_FINAL = 5

--- Whether `stage`'s condition is already satisfied (event-only stages: false).
local function alreadyDone(player: Player, stage: number): boolean
	if stage == STAGE_LEVEL then
		return DataService:GetTraversalLevel(player) >= TutorialConfig.TargetLevel
	elseif stage == STAGE_UPGRADE then
		return DataService:OwnsSkin(player, TutorialConfig.UpgradeSkinId)
	end
	return false
end

local setStage: (Player, number) -> ()

local function enterStage(player: Player, stage: number): ()
	if stage == STAGE_FINAL then
		task.delay(TutorialConfig.FinalSeconds, function()
			if DataService:GetTutorialStage(player) == STAGE_FINAL then
				setStage(player, TutorialConfig.GetFinishedStage())
			end
		end)
	elseif alreadyDone(player, stage) then
		setStage(player, stage + 1)
	end
end

setStage = function(player: Player, stage: number): ()
	if DataService:SetTutorialStage(player, stage) then
		log:Info("%s: tutorial stage %d.", player.Name, stage)
		enterStage(player, stage)
	end
end

--- Completes `stage` if it is the player's current one.
local function complete(player: Player, stage: number): ()
	if DataService:GetTutorialStage(player) == stage then
		setStage(player, stage + 1)
	end
end

function TutorialService:Init(): ()
	NetworkEvents.OnServerEvent("RebirthFocusShown", function(player: Player)
		DataService:MarkRebirthFocusShown(player)
	end)
end

function TutorialService:Start(): ()
	GameEvents.OnDataLoaded:Connect(function(player: Player)
		local stage = DataService:GetTutorialStage(player)
		if stage and stage < TutorialConfig.GetFinishedStage() then
			enterStage(player, stage) -- resume: re-check / re-arm the final timer
		end
	end)
	GameEvents.OnTreadmillEntered:Connect(function(player: Player)
		complete(player, STAGE_TREADMILL)
	end)
	GameEvents.OnTraversalLevelChanged:Connect(function(player: Player, level: number)
		if level >= TutorialConfig.TargetLevel then
			complete(player, STAGE_LEVEL)
		end
	end)
	GameEvents.OnTrophyPadClaimed:Connect(function(player: Player)
		complete(player, STAGE_WIN)
	end)
	GameEvents.OnSkinUnlocked:Connect(function(player: Player, skinId: string)
		if skinId == TutorialConfig.UpgradeSkinId then
			complete(player, STAGE_UPGRADE)
		end
	end)
end

return TutorialService
