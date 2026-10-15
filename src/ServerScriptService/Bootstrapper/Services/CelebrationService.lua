--!strict
--[[
	@module CelebrationService
	@description Tells every OTHER client that a player levelled up or
	rebirthed, so they see the VFX on that character and hear the sound at its
	position (CelebrationController). The owner is skipped on purpose: their own
	client already plays it from its HUD (banner, data snapshot), timed to the
	XP landing. Display only -- nothing here changes any data.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameEvents = require(script.Parent.Parent.GameEvents)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local CelebrationService = {}

local function broadcast(owner: Player, kind: string): ()
	for _, other in Players:GetPlayers() do
		if other ~= owner then
			NetworkEvents.FireClient("PlayerCelebration", other, owner, kind)
		end
	end
end

function CelebrationService:Init(): ()
	GameEvents.OnTraversalLevelChanged:Connect(function(player: Player, newLevel: number, previousLevel: number)
		if newLevel > previousLevel then -- a rebirth resets the level to 1: not a level-up
			broadcast(player, "LevelUp")
		end
	end)
	GameEvents.OnRebirthed:Connect(function(player: Player)
		broadcast(player, "Rebirth")
	end)
end

function CelebrationService:Start(): () end

return CelebrationService
