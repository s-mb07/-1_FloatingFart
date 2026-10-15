--!strict
--[[
	@module ProbeConfig
	@description Shared tunables for the flight (the player's own character
	is flown: ProbeService.lua server-side, ProbeController.lua client-side).
	Lives here, not on either side alone, because both need the exact same
	numbers: the client uses Speed and the steering values to drive the
	character it owns, the server uses the same numbers (plus a tolerance) to
	judge whether that motion is plausible. Lift / rebound / camera tunables
	of the new mechanic are in FlyConfig.
]]

local ProbeConfig = {
	Speed = 65, -- studs/second, constant forward flight speed
	MaxDuration = 20, -- seconds, hard cap on one flight
	SupervisorHz = 30, -- server validation tick rate
	SpeedTolerance = 2, -- allowed multiplier over Speed before it's flagged a violation -- generous on purpose:
	-- the position of an owned character reaches the server in bursts, so a raw distance/dt
	-- sample can spike well above the nominal speed between two ticks even with a fully
	-- legitimate client. This is a coarse sanity check against a genuine speedhack/teleport.
	SpeedWindowSeconds = 1.5, -- the speed is averaged over this sliding window of time (not a few
	-- ticks): a server lag spike or a burst of position updates then averages out instead of
	-- ending a perfectly legitimate flight.
	RelaunchCooldown = 0, -- seconds after a flight fully finishes (End animation over) before that player may launch again.
	LaunchGroundTolerance = 2, -- studs below the feet within which a NORMAL-state player counts as on the ground:
	-- a launch from NORMAL needs ground under the character (no chaining flights mid-fall).
	RaycastPadding = 1.5, -- stud gap kept between a stop point and the obstacle surface; also how far
	-- ahead of the front attachment the obstacle ray reaches beyond one frame of travel.

	-- Steering (client): first LaunchRiseDuration seconds go up AND forward (the pitch decays
	-- to level like the start of a parabola), then the heading follows the camera look.
	LaunchRiseDuration = 0.15,
	LaunchPitchDegrees = 45,
	LargeTurnEasing = 2, -- extra easing on wide turns: rate is divided by (1 + this * angle/180deg), so a full flip turns 3x slower than a small correction
	DirectionSmoothing = 12, -- heading easing rate (1/s): higher = snappier turns. Direction only, speed is never reduced
	NormalCameraMinZoom = 12, -- floor on the default character camera so it can never zoom into first-person
}

return ProbeConfig
