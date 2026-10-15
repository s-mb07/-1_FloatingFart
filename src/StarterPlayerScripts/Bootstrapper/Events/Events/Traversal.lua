--!strict
--[[
	@module EventBus.Traversal
	@description Client-side traversal signals -- the generic surface every
	future VISUAL layer subscribes to.

	THEME SEPARATION (§12) is the whole point of this file. A tongue, a hook
	and rope, a stretching hand, a tentacle, a chain, a vine or a magic
	tether are all built by listening to these signals and rendering
	something; none of them may be referenced by, or reachable from, the
	systems that fire them. Nothing in stamina, progression, collision, wall
	lock, the state machine, launch validation or anti-cheat knows a visual
	exists -- swapping one is purely additive.

	`StateChanged` and `WallLocked`/`WallUnlocked` are fired for EVERY
	player (the server broadcasts them), so a visual can render other
	players' traversals too. `StaminaChanged`/`XPChanged`/`LevelChanged`
	are local-player only -- the server sends those to the owner alone.

	Fired by NetworkBridgeController (from the network) per EventBus's own
	convention, except Started/Stopped which ProbeController fires locally
	off the probe events it already handles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

return {
	--- (player: Player) -- a traversal launch became active
	Started = Signal.new(),
	--- (player: Player, reason: string) -- the probe stopped, for any reason
	Stopped = Signal.new(),
	--- (reason: string) -- local player only. The server refused a launch;
	--- see Traversal/LaunchValidator's Reasons for the vocabulary.
	LaunchRejected = Signal.new(),
	--- (player: Player, newState: string, previousState: string) -- see Config/TraversalState
	StateChanged = Signal.new(),
	--- (player: Player, wallNormal: Vector3, anchorPosition: Vector3)
	WallLocked = Signal.new(),
	--- (player: Player, reason: string)
	WallUnlocked = Signal.new(),
	--- (remaining: number, max: number) -- local player only. Studs of real
	--- length left while a probe is active; HUD bar only, not a resource.
	StaminaChanged = Signal.new(),
	--- (amount: number) -- local player only: XP the server just granted for
	--- an active probe second.
	XPGranted = Signal.new(),
	--- (seconds: number, stage: number) -- local player only: a lost run offers
	--- a revive back to checkpoint `stage` for this long (LifeService).
	ReviveOffered = Signal.new(),
	--- () -- the revive offer is over (used, lapsed or cancelled).
	ReviveClosed = Signal.new(),
	--- (xp: number, nextThreshold: number?) -- local player only.
	--- nextThreshold is nil while the real XP curve is unconfigured; the HUD
	--- shows no denominator rather than a fabricated one.
	XPChanged = Signal.new(),
	--- (level: number) -- local player only
	LevelChanged = Signal.new(),
	--- (blocked: boolean) -- local, client-only UX: true while the local
	--- player is wall-locked AND aiming into the wall, so the HUD can say
	--- so. Purely informational; the server rejects such a launch whether or
	--- not anything listened to this.
	AimBlocked = Signal.new(),
	--- (active: boolean) -- local, client-only: the local player started (true)
	--- or stopped (false) running on a treadmill (TreadmillController). The
	--- Fast Train HUD button only shows while true.
	TreadmillActive = Signal.new(),
	--- (hold: boolean) -- local, client-only: while true the HUD keeps the
	--- XP/level it shows and buffers server updates. XPGainController holds
	--- for the whole session: each flying XP icon reveals the gain when it lands
	--- in the Level bar. false flushes the buffer.
	XPHold = Signal.new(),
	--- (player: Player, kind: string) -- ANOTHER player levelled up ("LevelUp") or
	--- rebirthed ("Rebirth"): the server never sends the owner their own, who
	--- already plays it from their HUD. CelebrationController renders it.
	Celebration = Signal.new(),
	--- () -- reveal the buffered XP now (a flying XP icon reached the Level bar).
	XPFlush = Signal.new(),
}
