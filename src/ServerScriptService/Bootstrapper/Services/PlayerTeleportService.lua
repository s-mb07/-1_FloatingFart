--!strict
--[[
	@module PlayerTeleportService
	@description THE one way to move a player around the world on the server
	(lobby, trophy claim, revive, ...). Distinct from TeleportService, which
	sends players to other places.

	Safeties, all applied here so no caller can forget one:
	  - refuses a malformed / absurd destination (NaN, inf, out of bounds);
	  - refuses a dead / missing character;
	  - waits (bounded) for traversal control to be NORMAL -- a probe flight,
	    walk-back or landing arc is never ripped away mid-motion;
	  - one teleport per player at a time (no overlapping moves);
	  - zeroes velocity and RESETS movement tracking in the same frame, so the
	    displacement is never read by AntiCheatService as speedhacking;
	  - opens a short protection window (IsProtected) other server rules must
	    honour: a player being moved by the server is never "cheating";
	  - streams the destination to the client first (StreamingEnabled), so a
	    low-end client never lands in an area it hasn't loaded.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local RespawnConfig = require(script.Parent.Parent.Config.RespawnConfig)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TraversalStateService = require(script.Parent.TraversalStateService)

local log = Logger.new("PlayerTeleportService")
local PlayerTeleportService = {}

--- Max seconds to wait for the destination to stream in before moving anyway.
local STREAM_TIMEOUT = 3

local busy: { [Player]: boolean } = {}
local lastTeleport: { [Player]: number } = {}

local function isSaneCFrame(cframe: CFrame): boolean
	local bound = RespawnConfig.MaxCoordinate
	for _, value in { cframe:GetComponents() } do
		if value ~= value or math.abs(value) > bound then
			return false -- NaN, inf or out of bounds
		end
	end
	return true
end

--- True while the player is being moved by the server or just was (grace
--- window). Rules that could mistake the displacement for cheating (movement
--- checks, checkpoint timing) must ask this first.
--- @param player Player
--- @return boolean
function PlayerTeleportService.IsProtected(player: Player): boolean
	if busy[player] then
		return true
	end
	local last = lastTeleport[player]
	return last ~= nil and os.clock() - last < RespawnConfig.TeleportGrace
end

--- Lobby: the workspace SpawnLocation, lifted so the character lands on it.
--- @return CFrame?
function PlayerTeleportService.GetLobbyCFrame(): CFrame?
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawn then
		return nil
	end
	return spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + RespawnConfig.LobbyLift, 0)
end

--- Teleports `player` to `destination`.
--- @param player Player
--- @param destination CFrame
--- @param reason string -- logged + passed to OnPlayerRelocated
--- @return boolean -- true when the player was moved
function PlayerTeleportService.TeleportTo(
	player: Player,
	destination: CFrame,
	reason: string
): boolean
	if busy[player] then
		return false
	end
	if not isSaneCFrame(destination) then
		log:Warn("%s: teleport (%s) refused, malformed destination.", player.Name, reason)
		return false
	end

	busy[player] = true
	local moved = false

	-- Bounded wait for the traversal state machine to hand control back.
	local deadline = os.clock() + RespawnConfig.TeleportWaitForControl
	while player.Parent and TraversalStateService.Get(player) ~= TraversalState.NORMAL do
		if os.clock() > deadline then
			break
		end
		task.wait(0.1)
	end

	-- StreamingEnabled: the client owns its character's physics, so a teleport
	-- into an area it hasn't loaded drops it through the missing floor (low-end
	-- devices keep the smallest radius). Load the destination first; a failure
	-- or timeout only means the teleport goes ahead as before.
	pcall(player.RequestStreamAroundAsync, player, destination.Position, STREAM_TIMEOUT)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if
		player.Parent
		and character
		and humanoid
		and root
		and humanoid.Health > 0
		and TraversalStateService.Get(player) == TraversalState.NORMAL
	then
		character:PivotTo(destination)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		AntiCheatService.ResetTracking(player)
		lastTeleport[player] = os.clock()
		moved = true
		log:Debug("%s teleported (%s).", player.Name, reason)
		GameEvents.OnPlayerRelocated:Fire(player, reason, destination)
	else
		log:Warn("%s: teleport (%s) skipped, character not ready.", player.Name, reason)
	end

	busy[player] = nil
	return moved
end

function PlayerTeleportService:Init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
		lastTeleport[player] = nil
	end)
	log:Info("Initialized.")
end

function PlayerTeleportService:Start(): () end

return PlayerTeleportService
