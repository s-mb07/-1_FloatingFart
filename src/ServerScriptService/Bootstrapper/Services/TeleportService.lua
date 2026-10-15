--!strict
--[[
	@module TeleportService
	@description Thin wrapper around Roblox's engine `TeleportService` (name
	collision is intentional, same reasoning as AnalyticsService -- it's the
	platform's own name). Destination place ids must always come from trusted
	server logic, never from client input -- a client asking to be sent
	somewhere should send an intent ("I want to leave"), which the server
	then maps to a place id itself.
]]

local RobloxTeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local GameEvents = require(script.Parent.Parent.GameEvents)

local TeleportService = {}
local log = Logger.new("TeleportService")

--- Teleport a player to another place. `placeId` must originate from trusted
--- server logic -- never forward a client-supplied place id directly.
--- @param player Player -- the player to teleport
--- @param placeId number -- the destination place id
function TeleportService.TeleportPlayer(player: Player, placeId: number): ()
	local ok, err = pcall(function()
		RobloxTeleportService:Teleport(placeId, player)
	end)

	if not ok then
		log:Warn("Failed to teleport %s to place %d: %s", player.Name, placeId, tostring(err))
		return
	end

	GameEvents.OnPlayerTeleported:Fire(player, placeId)
end

function TeleportService:Init(): () end

function TeleportService:Start(): () end

return TeleportService
