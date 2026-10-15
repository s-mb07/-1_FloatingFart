--!strict
--[[
	@module PlayerService
	@description Owns the player join/leave lifecycle and the live registry of
	currently-registered players. Other services should read this registry
	(`GetRegisteredPlayers`/`IsRegistered`) or react to `GameEvents.OnPlayerRegistered`/
	`OnPlayerUnregistered` instead of each independently hooking
	`Players.PlayerAdded`/`PlayerRemoving` -- one source of truth for "is this
	player fully in the game" instead of N slightly-different copies.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local GameEvents = require(script.Parent.Parent.GameEvents)

local PlayerService = {}
local log = Logger.new("PlayerService")

local registeredPlayers: { [Player]: boolean } = {}

--- Get a snapshot array of currently registered players.
--- @return { Player }
function PlayerService.GetRegisteredPlayers(): { Player }
	local players: { Player } = {}
	for player in registeredPlayers do
		table.insert(players, player)
	end
	return players
end

--- @param player Player
--- @return boolean
function PlayerService.IsRegistered(player: Player): boolean
	return registeredPlayers[player] == true
end

local function registerPlayer(player: Player): ()
	registeredPlayers[player] = true
	log:Info("%s registered.", player.Name)
	GameEvents.OnPlayerRegistered:Fire(player)
end

local function unregisterPlayer(player: Player): ()
	registeredPlayers[player] = nil
	GameEvents.OnPlayerUnregistered:Fire(player)
end

function PlayerService:Init(): ()
	Players.PlayerAdded:Connect(registerPlayer)
	Players.PlayerRemoving:Connect(unregisterPlayer)

	-- Catch players already in-game if this service is hot-reloaded/late-required
	-- (shouldn't happen via the normal bootstrap scan, cheap safety net regardless).
	for _, player in Players:GetPlayers() do
		registerPlayer(player)
	end
end

function PlayerService:Start(): () end

return PlayerService
