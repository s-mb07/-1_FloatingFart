--!strict
--[[
	@module FavoritePromptService
	@description Claiming a win pad of stage FAVORITE_STAGE or later (STAGE 3+),
	i.e. once the player is back in the lobby, asks the client to show Roblox's native "add to favorites" prompt
	(NetworkEvents "PromptFavorite" -> FavoritePromptController), once per
	profile (DataService flag FavoritePrompted).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local FAVORITE_STAGE = 3

local FavoritePromptService = {}

function FavoritePromptService:Init(): ()
	-- Fired by TrophyPadService only after the lobby teleport succeeded.
	GameEvents.OnTrophyPadClaimed:Connect(function(player: Player, stage: number)
		if stage >= FAVORITE_STAGE and not DataService:HasFlag(player, "FavoritePrompted") then
			DataService:SetFlag(player, "FavoritePrompted")
			NetworkEvents.FireClient("PromptFavorite", player)
		end
	end)
end

function FavoritePromptService:Start(): () end

return FavoritePromptService
