--!strict
--[[
	@class FlyConfig
	The character-flight mechanic (the player's own character is flown, with
	the rigged `Fly` model on the back): asset names, lift / rebound / camera
	tunables. Shared: the server enforces, the client reads the same numbers
	to predict camera and obstacle detection.
]]

local FlyConfig = table.freeze({
	--- ReplicatedStorage.Assets.Player.<RigName> is an R15 rig holding the
	--- `ModelName` model, joined to its UpperTorso by a Motor6D `JointName`
	--- (the joint the animations drive). Cloned onto every character.
	RigName = "AnimationFly",
	ModelName = "Fly",
	JointName = "Cube.001",
	--- Attachment inside the Fly model sitting at its FRONT: it is the
	--- obstacle detector.
	AttachmentName = "Front",
	--- Wing-tip Attachments in the Fly model: each carries a thin Trail, lit
	--- only while the flight is ACTIVE. Colour = Assets.Skins.<Id>.TrailColor
	--- (Color3Value), white without one.
	TrailsEnabled = false, -- false = no wing trails at all (switched off for now)
	WingAttachmentNames = { "WingR", "WingL" },
	TrailWidth = 0.15, -- studs, thin line
	TrailLifetime = 0.5, -- seconds

	--- A grounded player is lifted this much (studs) over the Start animation
	--- so the front attachment never starts inside the floor.
	LiftHeight = 3,
	--- "Grounded" = floor closer than this under the root (studs).
	GroundCheckDistance = 6,

	--- Start sequence aim: the character turns toward the player's camera
	--- look while the Start animation plays. The client streams that aim at
	--- `PrepAimHz` (only when it moved more than `PrepAimMinDegrees`); the
	--- server eases the facing toward it at `PrepTurnRate` (1/s, higher =
	--- snappier).
	PrepAimHz = 10,
	PrepAimMinDegrees = 2,
	PrepTurnRate = 10,
	--- Launch clearance (server): a launch heading must be free of parts for
	--- `ClearanceDistance` studs, both level and along the launch arc, for a
	--- sphere of `ClearanceRadius`. A blocked aim is turned by steps of
	--- `ClearanceStepDegrees` (nearest side first) to the closest free one.
	ClearanceDistance = 16,
	ClearanceRadius = 1.5,
	ClearanceStepDegrees = 10,

	--- Knock-back after an obstacle hit: speed (studs/s) along the hit
	--- normal, a share of it added upward, and how long it lasts (s).
	ReboundSpeed = 30,
	ReboundUpward = 0.35,
	ReboundDuration = 0.35,

	--- Start sequence: the Start animation plays; from `ZoomStartTime` (s into
	--- it) the camera pulls back `ZoomBackDistance` studs, widens its field of
	--- view by `ZoomFovBoost` degrees and (ShakeEnabled) shakes lightly; that
	--- lasts `ZoomSeconds`, then the camera returns to normal AND the flight
	--- starts. The Start animation finishes while flying and the Idle loop
	--- takes over at its end.
	ZoomStartTime = 1.25,
	ZoomSeconds = 0.6,
	--- The Idle loop starts this long (s) before the Start animation ends, so
	--- the two cross-fade with no frame where nothing drives the rig.
	IdleOverlapSeconds = 0.25,
	ZoomBackDistance = 6,
	ZoomWallMargin = 1, -- studs kept between the zoomed-out camera and any solid behind it
	ZoomFovBoost = 10,
	ZoomEaseSeconds = 0.5,
	ZoomRestoreSeconds = 0.4,
	ShakeEnabled = false, -- false = zoom and field of view only, no shake
	ShakeAmplitude = 0.35, -- studs of camera offset
	ShakeFrequency = 30,

	--- Banking like a plane: the body rolls into a turn, in proportion to how
	--- fast the heading turns (degrees of roll per degree/second of yaw), up to
	--- a maximum, eased by BankSmoothing (1/s, higher = snappier).
	BankDegreesPerYawRate = 0.35,
	BankMaxDegrees = 40,
	BankSmoothing = 6,

	--- CollisionGroup the character sits in while flying (self-collisions and
	--- world physics off: obstacles come from the front attachment's ray).
	CollisionGroup = "Flying",
	--- CollisionGroup of every character outside a flight: collides with the
	--- world but never with another player (anti-fling, PlayerCollisionService).
	PlayerCollisionGroup = "Players",
})

return FlyConfig
