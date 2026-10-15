--!strict
--[[
	@module TraversalConfig
	@description Shared tunables for the traversal LAYER built on top of the
	probe flight itself: stamina, vertical-wall classification, wall lock,
	and the outward launch hemisphere.

	Split from ProbeConfig on purpose. ProbeConfig owns "how the probe
	flies" (speed, supervision rate, trail sampling, landing arc);
	everything here answers "is this player allowed to launch, for how
	long, and from where" -- a different domain, edited by a different
	question, and the one ProbeService must NOT accumulate inline
	(§16: keep balancing constants out of the service).

	Both sides require this file: the server enforces every number here,
	the client reads the same numbers to predict (stamina bar, aim clamp,
	launch pre-check) without a round trip. Prediction only -- every value
	that matters is re-derived server-side.

	THEME-AGNOSTIC: nothing here names a visual. The same numbers drive a
	tongue, a hook and rope, a stretching hand, a tentacle, a chain, a vine
	or a magic tether -- whatever ends up rendering the probe and its path
	never appears in this file or in anything that reads it.
]]

local TraversalConfig = {
	--========================================================================--
	-- ANIMATION
	--========================================================================--
	Animation = {
		--- Fade used when the rig is cleared at the start of the mechanic.
		--- Short but non-zero: an instant Stop(0) snaps a mid-stride pose to
		--- neutral in one frame, which reads as a glitch; this blends out.
		SuppressFadeOut = 0.15,

		--- Cross-fade used when a looping pose (FlyIdle, WallIdle) starts or
		--- stops -- see Traversal/CharacterAnimations.
		PoseFade = 0.2,

		--- Priority forced on those poses instead of trusting whatever the
		--- asset was published with. Both are Idle-style loops, and Idle is the
		--- LOWEST priority: left at Idle they would lose to any Movement/Core
		--- track still fading out. Action outranks all three yet leaves
		--- Action2-4 free for a future one-shot (a hop, a grab) to layer on top.
		PosePriority = Enum.AnimationPriority.Action,
	},

	--========================================================================--
	-- SURFACE CLASSIFICATION (server-side, from RaycastResult.Normal only --
	-- never from a part's name, and never assuming world-axis alignment, so
	-- an arbitrarily rotated part classifies correctly)
	--========================================================================--
	Surface = {
		--- A face counts as a wall-lockable vertical side when its normal is
		--- approximately horizontal: abs(normal.Y) <= this. 0.25 is about
		--- 14 degrees off vertical, which accepts the four side faces of a
		--- part (Front/Back/Left/Right) at any yaw and any mild tilt, while
		--- rejecting floors (normal.Y ~ +1) and ceilings (normal.Y ~ -1).
		VerticalNormalTolerance = 0.25,

		--- A face counts as a restable horizontal platform when its normal
		--- points up at least this much. Deliberately NOT the complement of
		--- the tolerance above: a steep ramp is neither a lockable wall nor
		--- a platform you can rest on, and should behave as neither.
		PlatformNormalMinY = 0.7,
	},

	--========================================================================--
	-- WALL LOCK
	--========================================================================--
	WallLock = {
		--- Studs kept between the wall surface and the HumanoidRootPart's
		--- center while locked. Must exceed half the root part's depth or
		--- the rig visibly intersects the wall -- 2 clears a default R15/R6
		--- root (2x1x1) with room to spare.
		Clearance = 2,

		--- How far the character may drift from the recorded anchor point
		--- before the lock is treated as stale and a relaunch from it is
		--- refused. Guards the case where something else moved the
		--- character (a moving wall, an external teleport) without going
		--- through this system.
		MaxAnchorDrift = 12,

		--- Extra reach given to the confirmation raycast that re-finds the
		--- wall surface at lock time, measured from the walk-back's final
		--- position back along -normal. Has to cover ProbeConfig.RaycastPadding
		--- plus the clearance above, with margin for the surface being
		--- slightly further than the padded stop suggested.
		SurfaceSearchDistance = 12,

		--- Face the wall (true) or face away from it (false) while locked.
		--- Cosmetic ONLY: every gameplay decision uses the stored server
		--- normal, never the avatar's orientation, so flipping this can
		--- never change what a launch is allowed to do.
		FaceIntoWall = true,
	},

	--========================================================================--
	-- OUTWARD LAUNCH HEMISPHERE (§7)
	--========================================================================--
	Launch = {
		--- A wall launch is legal only when the flattened launch direction
		--- and the flattened wall normal satisfy
		---   launchDir:Dot(wallDir) >= this
		--- 0 is the exact 180-degree hemisphere: straight out, out-left and
		--- out-right all pass, straight into the wall fails. The small
		--- negative value widens it just enough that a launch aimed
		--- perfectly parallel to the wall still passes despite float error
		--- and one frame of camera drift, without opening up any direction
		--- that actually points inward to a player's eye.
		WallDotTolerance = -0.05,

		--- Below this magnitude a flattened vector carries no usable
		--- direction (straight up/down aim, or a zero/degenerate vector) --
		--- shared by every normalize site on both sides so "too small to
		--- mean anything" is one number, not several.
		MinDirectionMagnitude = 1e-3,
	},
}

return table.freeze(TraversalConfig)
