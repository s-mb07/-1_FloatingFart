--!strict
--[[
	@module InactivityService
	@description Anti-kick for idle players. Roblox kicks a client idle ~20min
	(not configurable), so one `task.delay(IdleTimeout)` per player teleports
	them to another server of this place first; they rejoin with a fresh timer.
	No polling: each client activity ping (InactivityController, throttled and
	rate-limited) cancels and re-arms that player's single thread.

	Teleport fails in Studio / unpublished places (pcall absorbs it), and when
	the player is in a private or reserved server (a place teleport would send
	them to a public one) -- in those cases the fallback is a clean Kick("AFK").
	Player data is saved by DataService on PlayerRemoving, which a teleport fires.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxTeleportService = game:GetService("TeleportService")

local InactivityConfig = require(ReplicatedStorage.Config.InactivityConfig)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local GameEvents = require(script.Parent.Parent.GameEvents)

local InactivityService = {}
local log = Logger.new("InactivityService")

local idleTimers: { [Player]: thread } = {}
local isPrivateServer = game.PrivateServerId ~= ""

local function evict(player: Player): ()
	if isPrivateServer or not pcall(RobloxTeleportService.Teleport, RobloxTeleportService, game.PlaceId, player) then
		player:Kick("Kicked for inactivity.")
	end
	log:Info("%s idle, moved out.", player.Name)
end

--- (Re)arm the idle timer of a player. Called on join and on every activity ping.
--- @param player Player
function InactivityService.Arm(player: Player): ()
	local pending = idleTimers[player]
	if pending then
		task.cancel(pending)
	end
	idleTimers[player] = task.delay(InactivityConfig.IdleTimeout, function()
		idleTimers[player] = nil
		evict(player)
	end)
end

local function disarm(player: Player): ()
	local pending = idleTimers[player]
	if pending then
		task.cancel(pending)
		idleTimers[player] = nil
	end
end

function InactivityService:Init(): ()
	NetworkEvents.OnServerEvent("PlayerActivityPing", InactivityService.Arm)
	GameEvents.OnPlayerRegistered:Connect(InactivityService.Arm)
	GameEvents.OnPlayerUnregistered:Connect(disarm)

	-- Players registered before this service connected.
	for _, player in Players:GetPlayers() do
		if not idleTimers[player] then
			InactivityService.Arm(player)
		end
	end
end

function InactivityService:Start(): () end

return InactivityService
