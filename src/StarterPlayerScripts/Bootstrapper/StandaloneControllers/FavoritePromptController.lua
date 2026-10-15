--!strict
--[[
	@module FavoritePromptController
	@description Shows Roblox's native "add this experience to your favorites?"
	prompt when the server asks (EventBus.Gameplay.FavoritePromptRequested,
	from FavoritePromptService: once per profile, after a STAGE 3+ win pad sends them to the lobby).
]]

local AvatarEditorService = game:GetService("AvatarEditorService")

local EventBus = require(script.Parent.Parent.Events.EventBus)

local FavoritePromptController = {}

function FavoritePromptController:Init(): () end

function FavoritePromptController:Start(): ()
	EventBus.Gameplay.FavoritePromptRequested:Connect(function()
		-- Errors where prompts are unavailable (e.g. Studio): nothing to recover
		pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
end

return FavoritePromptController
