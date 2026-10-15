--!strict
--[[
	@class RespawnConfig
	Checkpoints, lost-run handling (kill parts), the revive window and the
	server-side teleport safeties. Shared so the client reads the window
	length; the server enforces everything.
]]

local RespawnConfig = {
	--- Seconds the "Revive" offer stays available after a run is lost. When
	--- it lapses the saved checkpoint is gone (next run starts from zero).
	ReviveWindow = 5,

	--- Minimum seconds between two checkpoints = distance / (probe speed /
	--- this). 2 = the probe at half speed is already faster than any
	--- legitimate run, so anything quicker is flagged.
	SpeedDivisor = 2,
	--- Per-axis reach (studs) for a kill part: over its footprint, and within
	--- this much above/below it (HRP stands ~3.5 studs above the surface).
	KillPartReach = Vector3.new(0, 4.5, 0),

	--- Teleport safeties (PlayerTeleportService).
	--- Seconds to wait for the traversal state to be NORMAL (a probe/landing
	--- finishing) before a teleport is given up.
	TeleportWaitForControl = 5,
	--- Seconds after a teleport during which movement/checkpoint checks treat
	--- the player as "being moved by the server", never as a cheater.
	TeleportGrace = 1,
	--- Lift (studs) above the lobby SpawnLocation.
	LobbyLift = 3,
	--- Destination sanity bound (|coordinate|).
	MaxCoordinate = 100000,
}

return RespawnConfig
