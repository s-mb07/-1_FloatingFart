--!strict
--[[
	@module TraversalState
	@description The authoritative per-player traversal state vocabulary,
	shared so the client can reason about the same names the server
	enforces (HUD gating, input pre-checks, aim UX) without duplicating
	string literals on both sides.

	Lives in ReplicatedStorage/Config (not on either side alone) for exactly
	the reason README §2 gives: both sides genuinely need it. The server
	OWNS the value -- `TraversalStateService` is the only thing that may
	change a player's state; the client only ever holds a replicated copy
	for responsiveness and never acts on it as authority.

	Why a state machine at all, rather than the booleans this replaced:
	WALL_LOCKED means "character movement locked BUT a launch is allowed",
	a combination no single `busy` flag can express. Once one state needs
	two independent answers, every consumer that reads a boolean pair is a
	place the two can disagree.
]]

--- One state per player. Mutually exclusive by construction -- a player is
--- in exactly one of these at all times.
export type State =
	"NORMAL" -- on their feet, free to move, free to launch
	| "PRE_LAUNCH" -- request accepted, character frozen, Start animation + lift playing
	| "ACTIVE" -- the character itself is flying, supervised
	| "ENDING" -- flight over: rebound (on an obstacle), End animation, controls not back yet
	| "WALL_LOCKED" -- suspended against a vertical face; movement locked, launch ALLOWED

local TraversalState = {
	NORMAL = "NORMAL" :: State,
	PRE_LAUNCH = "PRE_LAUNCH" :: State,
	ACTIVE = "ACTIVE" :: State,
	ENDING = "ENDING" :: State,
	WALL_LOCKED = "WALL_LOCKED" :: State,
}

--- States in which the character's own movement is under the mechanic's
--- control rather than the player's -- everything except NORMAL. Used by
--- the client to decide whether to keep Controls disabled, never as a
--- gameplay gate (the server re-derives all of that itself).
local MOVEMENT_LOCKED_STATES: { [State]: boolean } = {
	PRE_LAUNCH = true,
	ACTIVE = true,
	ENDING = true,
	WALL_LOCKED = true,
}

--- @param state State
--- @return boolean -- true when the mechanic, not the player, owns character movement
function TraversalState.IsMovementLocked(state: State): boolean
	return MOVEMENT_LOCKED_STATES[state] == true
end

--- States from which a launch can legally be requested. NORMAL is the
--- ordinary case; WALL_LOCKED is the wall-relaunch case (§6) -- the whole
--- reason this is a state machine and not a boolean.
--- @param state State
--- @return boolean
function TraversalState.IsLaunchable(state: State): boolean
	return state == TraversalState.NORMAL or state == TraversalState.WALL_LOCKED
end

return table.freeze(TraversalState)
