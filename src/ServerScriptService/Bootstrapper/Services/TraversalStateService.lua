--!strict
--[[
	@module TraversalStateService
	@description THE authoritative traversal state per player, plus the two
	pieces of state that hang off it: the wall-lock record and the relaunch
	cooldown. One value, one owner, one set of legal transitions.

	This replaces ProbeService's `busyPlayers` boolean. A boolean could not
	express WALL_LOCKED, which is simultaneously:
	    character movement LOCKED    (like ACTIVE/RETURNING/LANDING)
	    launching ALLOWED            (like NORMAL)
	Any encoding of that as two booleans has a fourth, meaningless
	combination that some code path eventually produces.

	LEGAL TRANSITIONS (everything else is refused and logged):

	    NORMAL       -> PRE_LAUNCH
	    PRE_LAUNCH   -> ACTIVE
	    ACTIVE       -> RETURNING
	    RETURNING    -> LANDING
	    RETURNING    -> WALL_LOCKED        (valid vertical endpoint)
	    LANDING      -> NORMAL
	    WALL_LOCKED  -> PRE_LAUNCH         (wall relaunch)

	Plus the one escape hatch, `ForceReset`, which is the "ANY -> cleanup ->
	NORMAL" rule: death, reset, respawn, character replacement, the player
	leaving, the wall being destroyed, an aborted PRE_LAUNCH (no room to
	spawn), or any stop reason nobody will ever walk back. It is a distinct
	entry point rather than a permissive transition so that a legitimate
	cleanup can never be confused with a state machine bug.

	Theme-agnostic: nothing here knows what the probe looks like.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CharacterLock = require(script.Parent.Parent.Traversal.CharacterLock)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local ProbeConfig = require(ReplicatedStorage.Config.ProbeConfig)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local WallLock = require(script.Parent.Parent.Traversal.WallLock)

local log = Logger.new("TraversalStateService")
local TraversalStateService = {}

type State = TraversalState.State
type WallRecord = WallLock.WallRecord

local LEGAL: { [State]: { [State]: boolean } } = {
	NORMAL = { PRE_LAUNCH = true },
	PRE_LAUNCH = { ACTIVE = true },
	ACTIVE = { ENDING = true, WALL_LOCKED = true },
	ENDING = { NORMAL = true },
	WALL_LOCKED = { PRE_LAUNCH = true },
}

local states: { [Player]: State } = {}
local wallRecords: { [Player]: WallRecord } = {}
-- Connection watching the wall a player is locked to, so a wall destroyed
-- underneath them drops the lock instead of leaving them hanging in the air
-- forever (§13).
local wallWatchers: { [Player]: RBXScriptConnection } = {}
-- os.clock() before which a new launch is refused. Lives here rather than in
-- ProbeService so the launch validator can read it without requiring the
-- service that calls the validator (which would be circular).
local cooldownUntil: { [Player]: number } = {}

--============================================================================--
-- STATE
--============================================================================--

--- Current state -- NORMAL for any player this service has never seen, which
--- is the correct default for a freshly joined or freshly respawned player.
--- @param player Player
--- @return State
function TraversalStateService.Get(player: Player): State
	return states[player] or TraversalState.NORMAL
end

local function announce(player: Player, newState: State, previousState: State): ()
	GameEvents.OnTraversalStateChanged:Fire(player, newState, previousState)
	-- Broadcast, not FireClient: a spectator's own visual layer (whatever
	-- ends up rendering the mechanic) reacts to the same state the owner
	-- does, and the state of a player's traversal is not private.
	NetworkEvents.FireAllClients("TraversalStateChanged", player, newState, previousState)
end

--- Attempts a transition. Returns false, changing nothing, when the
--- transition is not in the table above -- so a caller that races (two stop
--- paths, a relaunch arriving mid-flight) is refused rather than corrupting
--- the machine.
--- @param player Player
--- @param newState State
--- @return boolean -- true when the transition happened
function TraversalStateService.Transition(player: Player, newState: State): boolean
	local current = TraversalStateService.Get(player)
	if current == newState then
		return false
	end

	local allowed = LEGAL[current]
	if not allowed or not allowed[newState] then
		log:Warn(
			"%s: illegal traversal transition %s -> %s refused.",
			player.Name,
			current,
			newState
		)
		return false
	end

	states[player] = newState
	announce(player, newState, current)
	return true
end

--- The sanctioned "ANY -> cleanup -> NORMAL" path. Drops the wall lock,
--- releases the character, and lands on NORMAL from wherever the player was.
--- Idempotent, and safe for a player who was never in the machine at all.
--- @param player Player
--- @param reason string -- logged, and forwarded on the state signal
function TraversalStateService.ForceReset(player: Player, reason: string): ()
	local current = TraversalStateService.Get(player)

	TraversalStateService.ClearWallLock(player, reason)
	CharacterLock.Release(player)

	if current ~= TraversalState.NORMAL then
		states[player] = TraversalState.NORMAL
		log:Debug("%s: traversal force-reset from %s (%s).", player.Name, current, reason)
		announce(player, TraversalState.NORMAL, current)
	else
		states[player] = TraversalState.NORMAL
	end
end

--============================================================================--
-- WALL LOCK RECORD
--============================================================================--

--- Stores the wall record and moves the player into WALL_LOCKED. The
--- character must already be suspended by the caller (ProbeService owns the
--- movement, this owns the bookkeeping).
--- @param player Player
--- @param record WallRecord
--- @return boolean -- false if the transition was refused
function TraversalStateService.SetWallLock(player: Player, record: WallRecord): boolean
	if not TraversalStateService.Transition(player, TraversalState.WALL_LOCKED) then
		return false
	end

	wallRecords[player] = record

	local watcher = wallWatchers[player]
	if watcher then
		watcher:Disconnect()
	end
	-- AncestryChanged rather than Destroying: a wall moved out of Workspace
	-- (streamed out, parented into a bin) leaves the player just as
	-- unsupported as a destroyed one.
	wallWatchers[player] = record.Part.AncestryChanged:Connect(function()
		if not record.Part:IsDescendantOf(Workspace) then
			TraversalStateService.ForceReset(player, "WallDestroyed")
		end
	end)

	GameEvents.OnTraversalWallLocked:Fire(player, record.Normal, record.AnchorPosition)
	NetworkEvents.FireAllClients(
		"TraversalWallLocked",
		player,
		record.Normal,
		record.AnchorPosition
	)
	return true
end

--- @param player Player
--- @return WallRecord? -- nil unless the player is actually WALL_LOCKED
function TraversalStateService.GetWallLock(player: Player): WallRecord?
	if TraversalStateService.Get(player) ~= TraversalState.WALL_LOCKED then
		return nil
	end
	return wallRecords[player]
end

--- Drops the wall record and undoes the suspension's character-side changes.
--- Does NOT decide the next state -- a relaunch and a death both call this
--- and then go different ways. No-op when there is no lock.
--- @param player Player
--- @param reason string
function TraversalStateService.ClearWallLock(player: Player, reason: string): ()
	local record = wallRecords[player]
	local watcher = wallWatchers[player]
	if watcher then
		watcher:Disconnect()
		wallWatchers[player] = nil
	end
	if not record then
		return
	end

	wallRecords[player] = nil
	WallLock.ReleaseSuspension(player.Character)

	GameEvents.OnTraversalWallUnlocked:Fire(player, reason)
	NetworkEvents.FireAllClients("TraversalWallUnlocked", player, reason)
end

--============================================================================--
-- COOLDOWN
--============================================================================--

--- Starts the relaunch cooldown. Called once per completed lifecycle, from
--- the same single exit point that hands control back.
--- @param player Player
function TraversalStateService.StartCooldown(player: Player): ()
	cooldownUntil[player] = os.clock() + ProbeConfig.RelaunchCooldown
end

--- @param player Player
--- @return number -- seconds still to wait, 0 when ready
function TraversalStateService.GetCooldownRemaining(player: Player): number
	local endsAt = cooldownUntil[player]
	if not endsAt then
		return 0
	end
	return math.max(0, endsAt - os.clock())
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

--- Full teardown for a player who is leaving -- no character left to
--- restore, so the records are simply dropped.
local function forgetPlayer(player: Player): ()
	local watcher = wallWatchers[player]
	if watcher then
		watcher:Disconnect()
	end
	states[player] = nil
	wallRecords[player] = nil
	wallWatchers[player] = nil
	cooldownUntil[player] = nil
	CharacterLock.Forget(player)
end

function TraversalStateService:Init(): ()
	Players.PlayerRemoving:Connect(forgetPlayer)
	log:Info("Initialized.")
end

function TraversalStateService:Start(): ()
	local function watchCharacter(player: Player): ()
		player.CharacterRemoving:Connect(function()
			-- Covers death, Reset Character and any other replacement: the
			-- character this player's traversal state refers to is gone, so
			-- whatever it was doing is over.
			if TraversalStateService.Get(player) ~= TraversalState.NORMAL then
				TraversalStateService.ForceReset(player, "CharacterRemoving")
			end
			CharacterLock.Forget(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerAdded:Connect(watchCharacter)

	log:Info("Started.")
end

return TraversalStateService
