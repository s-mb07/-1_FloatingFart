--!strict
--[[
	@module ProbeService
	@description Server-authoritative supervisor of the flight: the player's
	OWN character flies. The owning client steers it (zero input latency,
	see ProbeController); the server validates every step.

	Sequence of one flight:
	  1. PRE_LAUNCH  LaunchValidator accepts, CharacterLock freezes the
	     character (Anchored, native animations off). A grounded player is
	     lifted a little (so the front attachment of the Fly model never
	     starts inside the floor) while the Start animation plays once.
	     Meanwhile the character turns toward the camera aim the client
	     streams (ProbeAimUpdate), never toward a part right in front of it
	     (Traversal/LaunchClearance).
	  2. ACTIVE      When the Start animation ends the character is handed to
	     its client (CharacterLock.BeginFlight: unanchored, PlatformStand,
	     non-colliding group) and the Idle animation loops. The supervisor
	     (SupervisorHz) checks the speed, sweeps a ray between the last and
	     the current position of the FRONT attachment (obstacles), and
	     enforces the real length (stamina) and MaxDuration. XP is granted
	     every second.
	  3. ENDING      The flight stops (obstacle, stamina, cancel...). What
	     the front attachment hit decides the outcome:
	       - Kill_Part   -> the run is lost (LifeService);
	       - Pad_Win     -> the pad is claimed (TrophyPadService);
	       - Vertical    -> the character sticks to the wall (WALL_LOCKED);
	       - any other part -> rebound (played by the client) then free fall;
	       - nothing (stamina, cancel...) -> straight free fall, no rebound.
	     Collisions come back, the End animation plays once, controls return
	     (NORMAL) and the relaunch cooldown starts.

	Trust: a client only says "I hit something" (ProbeStopRequest + normal);
	the server re-casts the ray itself to find what was hit. A client that
	ignores obstacles is caught by the sweep, a client that is too fast by
	the windowed speed check.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AdminService = require(script.Parent.AdminService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local CharacterAnimations = require(script.Parent.Parent.Traversal.CharacterAnimations)
local CharacterLock = require(script.Parent.Parent.Traversal.CharacterLock)
local FlyConfig = require(ReplicatedStorage.Config.FlyConfig)
local GameEvents = require(script.Parent.Parent.GameEvents)
local LaunchClearance = require(script.Parent.Parent.Traversal.LaunchClearance)
local LaunchValidator = require(script.Parent.Parent.Traversal.LaunchValidator)
local LifeService = require(script.Parent.LifeService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local ProbeConfig = require(ReplicatedStorage.Config.ProbeConfig)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TraversalGeometry = require(ReplicatedStorage.Libraries.TraversalGeometry)
local TraversalProgressionConfig = require(ReplicatedStorage.Config.TraversalProgressionConfig)
local TraversalProgressionService = require(script.Parent.TraversalProgressionService)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TraversalStateService = require(script.Parent.TraversalStateService)
local TreadmillService = require(script.Parent.TreadmillService)
local TrophyPadService = require(script.Parent.TrophyPadService)
local WallLock = require(script.Parent.Parent.Traversal.WallLock)

local log = Logger.new("ProbeService")
local ProbeService = {}

type SpeedSample = { Distance: number, Dt: number }

type Flight = {
	Character: Model,
	Root: BasePart,
	--- Front attachment of the Fly model (obstacle detector); nil = the root.
	Front: Attachment?,
	--- Overlap query of the whole body (kill parts touched by any part of it).
	BodyOverlap: OverlapParams,
	StartClock: number,
	LastPoint: Vector3,
	LastClock: number,
	--- Unit direction of the last movement, for the stop-request recast.
	Direction: Vector3,
	--- Real length flown so far (studs) and its limit (from the level).
	Flown: number,
	MaxDistance: number,
	SupervisorHandle: Scheduler.Handle?,
	RaycastParams: RaycastParams,
	SpeedWindow: { SpeedSample },
}

--- The launch sequence in progress (PRE_LAUNCH). Its identity is the token a
--- stale sequence checks to notice it was superseded or reset.
type Launch = {
	--- Latest validated aim of the player (unit, Y = 0), from the start
	--- request then from ProbeAimUpdate.
	Aim: Vector3,
	--- Set when launching off a wall: aim must stay outward.
	WallNormal: Vector3?,
}

local flights: { [Player]: Flight } = {}
local launches: { [Player]: Launch } = {}

--============================================================================--
-- HELPERS
--============================================================================--

local function buildRaycastParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	-- Cast as a "Players" body: other characters are not obstacles.
	params.CollisionGroup = FlyConfig.PlayerCollisionGroup
	return params
end

local function bodyOverlapParams(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

local function getFront(character: Model): Attachment?
	local fly = character:FindFirstChild(FlyConfig.ModelName)
	local attachment = fly and fly:FindFirstChild(FlyConfig.AttachmentName, true)
	return if attachment and attachment:IsA("Attachment") then attachment else nil
end

local function sensePoint(flight: Flight): Vector3
	local front = flight.Front
	return if front and front.Parent then front.WorldPosition else flight.Root.Position
end

--- Nearest ancestor of `instance` (itself included) carrying `tag`.
local function taggedAncestor(instance: Instance, tag: string): Instance?
	local current: Instance? = instance
	while current and current ~= Workspace do
		if CollectionService:HasTag(current, tag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

--- HUD-only "stamina": the share of the real length still available.
local function publishReach(player: Player, remaining: number, max: number): ()
	NetworkEvents.FireClient("TraversalStaminaChanged", player, remaining, max)
end

--- The single "this player's flight is fully over" exit point: NORMAL, the
--- character is given back, the relaunch cooldown starts.
local function finishLifecycle(player: Player, reason: string): ()
	if TraversalStateService.Transition(player, TraversalState.NORMAL) then
		CharacterLock.Release(player)
	else
		TraversalStateService.ForceReset(player, reason)
	end
	TraversalStateService.StartCooldown(player)
end

--- A launch that never got off the ground (character died during the Start
--- animation, state reset). No cooldown: nothing happened.
local function abortLaunch(player: Player, reason: string): ()
	log:Debug("%s: launch aborted (%s).", player.Name, reason)
	launches[player] = nil
	TraversalStateService.ForceReset(player, reason)
end

local function characterAlive(player: Player, character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return player.Character == character
		and humanoid ~= nil
		and humanoid.Health > 0
		and character:FindFirstChild("HumanoidRootPart") ~= nil
end

--- Waits for `seconds` in small steps, giving up (false) as soon as `alive`
--- stops holding.
local function waitWhile(seconds: number, alive: () -> boolean): boolean
	local elapsed = 0
	while elapsed < seconds do
		elapsed += task.wait(1 / 30)
		if not alive() then
			return false
		end
	end
	return alive()
end

--============================================================================--
-- ENDING
--============================================================================--

--- ACTIVE -> ENDING -> NORMAL for every stop that is not a kill, a claim or a
--- wall: optional rebound (played by the client), collisions back, End
--- animation, controls back.
local function endSequence(
	player: Player,
	character: Model,
	reboundSeconds: number,
	reason: string
): ()
	local function stillEnding(): boolean
		return characterAlive(player, character)
			and TraversalStateService.Get(player) == TraversalState.ENDING
	end

	-- The End animation starts the instant the flight stops, over the rebound
	-- (never after it: that read as a late reaction).
	local track, length = CharacterAnimations.PlayOnce(player, character, "FlyEnd")
	local startedAt = os.clock()

	if reboundSeconds > 0 and not waitWhile(reboundSeconds, stillEnding) then
		return
	end
	if not stillEnding() then
		return
	end

	CharacterLock.EndFlight(character)
	AntiCheatService.ResetTracking(player)

	local remaining = length - (os.clock() - startedAt)
	if track and remaining > 0 and not waitWhile(remaining, stillEnding) then
		return
	end
	if not stillEnding() then
		return
	end
	CharacterAnimations.Stop(player)
	finishLifecycle(player, reason)
end

--- Suspends the character against the wall it stuck to. False when the
--- wall cannot be locked after all (surface gone, state refused).
local function enterWallLock(
	player: Player,
	character: Model,
	from: Vector3,
	normal: Vector3
): boolean
	local record = WallLock.BuildRecord(from, normal, { character })
	if not record then
		return false
	end
	if not TraversalStateService.Transition(player, TraversalState.WALL_LOCKED) then
		return false
	end

	CharacterLock.EndFlight(character)
	CharacterLock.Lock(player, character) -- anchors again, native animations stay off
	WallLock.Suspend(character, record)
	if not TraversalStateService.SetWallLock(player, record) then
		WallLock.ReleaseSuspension(character)
		TraversalStateService.ForceReset(player, "WallLockRefused")
		return true
	end
	TraversalStateService.StartCooldown(player)
	CharacterAnimations.Play(player, character, "WallIdle")
	AntiCheatService.ResetTracking(player)
	return true
end

--- Ends the active flight and applies what the front attachment hit.
local function stopFlight(
	player: Player,
	reason: string,
	hit: RaycastResult?,
	touched: Instance? -- a part the BODY overlaps (kill part), when there is no ray hit
): ()
	local flight = flights[player]
	if not flight then
		return
	end
	flights[player] = nil
	if flight.SupervisorHandle then
		flight.SupervisorHandle:Disconnect()
	end
	publishReach(player, flight.MaxDistance, flight.MaxDistance) -- bar refills

	local character = flight.Character
	local instance = if hit then hit.Instance else touched
	local normal = if hit then hit.Normal else nil
	local from = sensePoint(flight)

	-- Kill part / claimable win pad: the run ends right here, no rebound.
	local killPart = instance and taggedAncestor(instance, TagNames.KillPart)
	local winPad = instance and taggedAncestor(instance, TagNames.WinPad)
	if killPart or (winPad and TrophyPadService.CanClaim(player, winPad)) then
		if killPart then
			-- Lets a kill part react to the hit itself (drones explode on it).
			killPart:SetAttribute("TouchedAt", Workspace:GetServerTimeNow())
		end
		local outcome = if killPart then "KillPart" else "WinPad"
		NetworkEvents.FireAllClients("ProbeStopped", player, outcome, normal)
		TraversalStateService.Transition(player, TraversalState.ENDING)
		CharacterLock.EndFlight(character)
		finishLifecycle(player, outcome)
		task.spawn(function()
			if killPart then
				LifeService.Lose(player, "FlyKillPart")
			else
				TrophyPadService.Claim(player, winPad :: BasePart)
			end
		end)
		return
	end

	-- Honey: stick to the wall.
	if
		instance
		and normal
		and CollectionService:HasTag(instance, TagNames.Vertical)
		and TraversalGeometry.IsVerticalFace(normal)
	then
		if enterWallLock(player, character, from, normal) then
			NetworkEvents.FireAllClients("ProbeStopped", player, "WallLock", normal)
			return
		end
		-- not lockable after all: fall through to the plain obstacle ending
	end

	local obstacle = instance ~= nil
	NetworkEvents.FireAllClients(
		"ProbeStopped",
		player,
		if obstacle then "Obstacle" else reason,
		normal
	)
	if not TraversalStateService.Transition(player, TraversalState.ENDING) then
		-- Already reset out from under us (death, reset character).
		return
	end
	-- Unclaimable win pad (x2 without the pass, checkpoint not reached): the
	-- client lands on it without a rebound, so collisions must come back now
	-- or the body falls through the pad. Claim offers the X2Wins pass.
	if winPad then
		task.spawn(TrophyPadService.Claim, player, winPad :: BasePart)
	end
	-- Only an obstacle hit rebounds on the client; a mid-air stop (stamina,
	-- cancel...) drops straight into the End sequence.
	task.spawn(
		endSequence,
		player,
		character,
		if obstacle and not winPad then FlyConfig.ReboundDuration else 0,
		reason
	)
end

--============================================================================--
-- SUPERVISION
--============================================================================--

local function superviseFlight(player: Player): ()
	local flight = flights[player]
	if not flight then
		return
	end

	local character = flight.Character
	if not characterAlive(player, character) then
		stopFlight(player, "Interrupted")
		return
	end

	local now = os.clock()
	local dt = now - flight.LastClock
	if dt <= 0 then
		return
	end

	-- Touching a kill part with ANY part of the body (wings included) kills,
	-- not only with the front attachment's ray.
	local boxCFrame, boxSize = character:GetBoundingBox()
	for _, part in Workspace:GetPartBoundsInBox(boxCFrame, boxSize, flight.BodyOverlap) do
		if taggedAncestor(part, TagNames.KillPart) then
			stopFlight(player, "KillPart", nil, part)
			return
		end
	end

	local point = sensePoint(flight)
	local delta = point - flight.LastPoint
	local distance = delta.Magnitude
	-- Speed is judged without the downward component: letting go in mid-air
	-- (cancel, stamina, rebound) is a fall, and falling faster than the
	-- flight cannot be exploited.
	local judged = Vector3.new(delta.X, math.max(delta.Y, 0), delta.Z).Magnitude

	-- Sliding window over the last SpeedWindowSeconds: a lag spike of the
	-- server (stall, then catch-up) averages out, so only a speed that is
	-- really sustained is flagged. Never judged before half a window of data.
	table.insert(flight.SpeedWindow, { Distance = judged, Dt = dt })
	local windowDistance, windowDt = 0, 0
	for _, sample in flight.SpeedWindow do
		windowDistance += sample.Distance
		windowDt += sample.Dt
	end
	while windowDt > ProbeConfig.SpeedWindowSeconds and #flight.SpeedWindow > 1 do
		local oldest = table.remove(flight.SpeedWindow, 1) :: SpeedSample
		windowDistance -= oldest.Distance
		windowDt -= oldest.Dt
	end
	if windowDt >= ProbeConfig.SpeedWindowSeconds * 0.5 then
		local averagedSpeed = windowDistance / windowDt
		if averagedSpeed > ProbeConfig.Speed * ProbeConfig.SpeedTolerance then
			log:Warn(
				"%s: flight speed %.0f studs/s (over %.1fs) exceeds tolerance (base %.0f).",
				player.Name,
				averagedSpeed,
				windowDt,
				ProbeConfig.Speed
			)
			stopFlight(player, "SpeedViolation")
			return
		end
	end

	if distance > 1e-3 then
		flight.Direction = delta.Unit
		-- Sweep, not a point check: a fast body must not tunnel through thin
		-- geometry between two ticks.
		local hit = Workspace:Raycast(flight.LastPoint, delta, flight.RaycastParams)
		if hit then
			stopFlight(player, "Obstacle", hit)
			return
		end
	end

	if
		now - flight.StartClock > ProbeConfig.MaxDuration
		and not AdminService.HasInfiniteStamina(player)
	then
		stopFlight(player, "MaxRangeReached")
		return
	end

	flight.Flown += distance
	flight.LastPoint = point
	flight.LastClock = now
	if flight.Flown > flight.MaxDistance then
		stopFlight(player, "MaxRangeReached")
		return
	end
	publishReach(player, flight.MaxDistance - flight.Flown, flight.MaxDistance)
end

--============================================================================--
-- START
--============================================================================--

--- How far (studs) a launch from `root` can be lifted off the floor: 0 from a
--- wall or when already airborne, limited by a ceiling above.
local function liftHeightFor(character: Model, root: BasePart, fromWall: boolean): number
	if fromWall then
		return 0 -- on a wall the floor is not what the front attachment fears
	end
	local params = buildRaycastParams({ character })
	local down =
		Workspace:Raycast(root.Position, Vector3.new(0, -FlyConfig.GroundCheckDistance, 0), params)
	if not down then
		return 0 -- already in the air
	end
	local reach = FlyConfig.LiftHeight + 2
	local up = Workspace:Raycast(root.Position, Vector3.new(0, reach, 0), params)
	local room = if up then up.Distance - 2 else FlyConfig.LiftHeight
	return math.clamp(room, 0, FlyConfig.LiftHeight)
end

--- `idleDelay`: seconds of the Start animation still to play; the Idle loop
--- takes over when it is over (0 = right away).
local function startFlight(player: Player, character: Model, root: BasePart, idleDelay: number): ()
	launches[player] = nil
	if not TraversalStateService.Transition(player, TraversalState.ACTIVE) then
		abortLaunch(player, "StateLostDuringStart")
		return
	end
	CharacterLock.BeginFlight(player, character)
	AntiCheatService.ResetTracking(player)

	local front = getFront(character)
	local flight: Flight = {
		Character = character,
		Root = root,
		Front = front,
		StartClock = os.clock(),
		LastPoint = if front then front.WorldPosition else root.Position,
		LastClock = os.clock(),
		Direction = root.CFrame.LookVector,
		Flown = 0,
		-- Admin "infinite stamina": a huge (finite: the HUD divides by it) reach.
		MaxDistance = if AdminService.HasInfiniteStamina(player)
			then AdminService.GetInfiniteReach()
			else math.max(
				1,
				TraversalProgressionConfig.GetMaxLength(TraversalProgressionService.GetLevel(player))
			),
		SupervisorHandle = nil,
		RaycastParams = buildRaycastParams({ character }),
		BodyOverlap = bodyOverlapParams(character),
		SpeedWindow = {},
	}
	flights[player] = flight

	-- The Start animation is left to finish while the flight is already
	-- running; Idle takes over at its end -- unless the flight ended meanwhile.
	local function playIdle(): ()
		if flights[player] == flight then
			CharacterAnimations.Play(player, character, "FlyIdle")
		end
	end
	-- Idle starts BEFORE the Start animation is over (they cross-fade): if
	-- the Start track ended first, no track would drive the rig for a moment
	-- and the Fly model would drop to its rest pose, then catch up.
	local overlapped = idleDelay - FlyConfig.IdleOverlapSeconds
	if overlapped > 0.02 then
		task.delay(overlapped, playIdle)
	else
		playIdle()
	end
	flight.SupervisorHandle = Scheduler.Every(
		"ProbeService_" .. tostring(player.UserId),
		ProbeConfig.SupervisorHz,
		function()
			superviseFlight(player)
		end
	)

	-- XP while flying: first grant 1 s later, then every second until the
	-- flight is detached (any stop reason). The client shows it on arrival.
	task.spawn(function()
		while true do
			task.wait(1)
			if flights[player] ~= flight then
				return
			end
			local amount = TraversalProgressionService.GetXPPerSecond(player)
			TraversalProgressionService.AddXP(player, amount, "Probe")
			NetworkEvents.FireClient("ProbeXPGranted", player, amount)
		end
	end)
end

--- The ONE launch entry point. Every gate lives in LaunchValidator (§8).
--- `requestedDirection` is the only client-supplied value, a claim about
--- INTENT: the validator type-checks and sanitizes it (and hemisphere-checks
--- it from a wall). The start position is the replicated character.
local function onProbeStartRequest(player: Player, requestedDirection: Vector3?): ()
	local verdict = LaunchValidator.Validate(player, requestedDirection)
	if not verdict.Allowed then
		log:Debug("%s: launch refused (%s).", player.Name, tostring(verdict.Reason))
		-- Tell the requester, always: the client locks its controls the moment
		-- the player presses, before this round trip.
		NetworkEvents.FireClient("TraversalLaunchRejected", player, tostring(verdict.Reason))
		return
	end

	local character = player.Character :: Model
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local fromWall = verdict.WallRecord ~= nil

	-- NORMAL -> PRE_LAUNCH, or WALL_LOCKED -> PRE_LAUNCH for a wall relaunch.
	-- Transition first, THEN drop the wall record.
	if not TraversalStateService.Transition(player, TraversalState.PRE_LAUNCH) then
		return
	end
	if fromWall then
		TraversalStateService.ClearWallLock(player, "Relaunch")
	end

	local launch: Launch = {
		Aim = verdict.Direction :: Vector3,
		WallNormal = if verdict.WallRecord then verdict.WallRecord.Normal else nil,
	}
	launches[player] = launch
	local function launchAlive(): boolean
		return launches[player] == launch
			and characterAlive(player, character)
			and TraversalStateService.Get(player) == TraversalState.PRE_LAUNCH
	end

	-- Freeze immediately: stops mid-stride movement, anchors the root.
	CharacterLock.Lock(player, character)

	local lift = liftHeightFor(character, root, fromWall)
	-- Facing: eased toward the player's aim (camera) over the Start
	-- animation, turned away from any part right in front of it.
	local function clearHeading(): Vector3
		return LaunchClearance.FindClearDirection(
			character,
			root.Position,
			launch.Aim,
			launch.WallNormal
		)
	end
	local function yawOf(direction: Vector3): number
		return math.atan2(-direction.X, -direction.Z)
	end
	local yaw = yawOf(root.CFrame.LookVector)
	local aimSeen = launch.Aim
	local targetYaw = yawOf(clearHeading())
	local track, startLength = CharacterAnimations.PlayOnce(player, character, "FlyStart")
	if not track then
		startLength = 0
	end
	-- The flight starts when the camera zoom of the Start animation is over
	-- (never later than the animation itself); the animation keeps playing.
	local flightStartAt = if startLength > 0
		then math.min(startLength, FlyConfig.ZoomStartTime + FlyConfig.ZoomSeconds)
		else 0
	NetworkEvents.FireAllClients("ProbeStarted", player, flightStartAt)

	-- Lift (eased) and turn over the Start animation.
	local startPosition = character:GetPivot().Position
	local duration = math.max(flightStartAt, 0.05)
	local elapsed = 0
	local function place(height: number): ()
		character:PivotTo(
			CFrame.new(startPosition + Vector3.new(0, height, 0)) * CFrame.Angles(0, yaw, 0)
		)
	end
	while elapsed < duration do
		local dt = task.wait(1 / 60)
		elapsed += dt
		if not launchAlive() then
			abortLaunch(player, "CharacterLostDuringStart")
			return
		end
		if launch.Aim ~= aimSeen then
			aimSeen = launch.Aim
			targetYaw = yawOf(clearHeading())
		end
		-- Shortest way round, eased.
		local delta = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
		yaw += delta * (1 - math.exp(-FlyConfig.PrepTurnRate * dt))
		local alpha = math.clamp(elapsed / duration, 0, 1)
		place(lift * alpha * alpha * (3 - 2 * alpha))
		if lift > 0 then
			AntiCheatService.ResetTracking(player)
		end
	end
	if not launchAlive() then
		abortLaunch(player, "CharacterLostDuringStart")
		return
	end
	-- Final check from the lifted position; snaps the leftover of the turn.
	yaw = yawOf(clearHeading())
	place(lift)

	startFlight(player, character, root, startLength - flightStartAt)
end

--- The player's camera aim while the Start animation plays. Untrusted: only
--- a usable direction is kept, and from a wall only an outward one.
local function onProbeAimUpdate(player: Player, aim: Vector3?): ()
	local launch = launches[player]
	if not launch or typeof(aim) ~= "Vector3" then
		return
	end
	local flat = TraversalGeometry.FlattenDirection(aim :: Vector3)
	if not flat then
		return
	end
	if launch.WallNormal and not TraversalGeometry.IsOutward(flat, launch.WallNormal) then
		return
	end
	launch.Aim = flat
end

local function onProbeStopRequest(player: Player, hitNormal: Vector3?): ()
	local flight = flights[player]
	if not flight then
		return
	end
	-- The client claims it hit something: find out what, ourselves, from the
	-- last known position along the current heading. Generous reach: the
	-- replicated position lags the client's by about a round trip.
	if typeof(hitNormal) == "Vector3" then
		local reach = ProbeConfig.RaycastPadding + ProbeConfig.Speed * 0.3
		local hit =
			Workspace:Raycast(sensePoint(flight), flight.Direction * reach, flight.RaycastParams)
		if hit then
			stopFlight(player, "Obstacle", hit)
			return
		end
	end
	stopFlight(player, "PlayerCanceled")
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function ProbeService:Init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		local flight = flights[player]
		flights[player] = nil
		launches[player] = nil
		if flight and flight.SupervisorHandle then
			flight.SupervisorHandle:Disconnect()
		end
	end)

	task.spawn(CharacterAnimations.Preload)

	log:Info("Initialized.")
end

function ProbeService:Start(): ()
	--- Space is permanently repurposed to launch, so jumping is disabled
	--- once per character and never re-enabled -- including for players
	--- already in the game when this service starts.
	local function watchCharacters(player: Player): ()
		if player.Character then
			task.spawn(CharacterLock.DisableJumpingForever, player.Character)
			task.spawn(CharacterAnimations.Warm, player.Character)
		end
		player.CharacterAdded:Connect(function(character: Model)
			task.spawn(CharacterLock.DisableJumpingForever, character)
			CharacterAnimations.Forget(player)
			task.spawn(CharacterAnimations.Warm, character)
			if flights[player] then
				stopFlight(player, "CharacterReset")
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end
	Players.PlayerAdded:Connect(watchCharacters)

	-- Something OUTSIDE this service reset the player (death, Reset
	-- Character, a destroyed wall): all of those land on NORMAL through
	-- TraversalStateService.ForceReset. A flight still supervised must stop.
	GameEvents.OnTraversalStateChanged:Connect(function(player: Player, newState: string)
		if newState ~= TraversalState.NORMAL then
			return
		end
		launches[player] = nil
		-- Safety: nothing of the sequence may keep playing on a player back
		-- at NORMAL (the other players would see it loop).
		CharacterAnimations.StopAll(player.Character)
		local flight = flights[player]
		if flight then
			flights[player] = nil
			if flight.SupervisorHandle then
				flight.SupervisorHandle:Disconnect()
			end
			log:Debug("%s: flight orphaned by an external reset -- torn down.", player.Name)
			NetworkEvents.FireAllClients("ProbeStopped", player, "Interrupted", nil)
		end
	end)

	-- Animation watchdog (1 Hz): no pose of the mechanic may outlive its
	-- owner. An orphan track is always stopped; and a player back at NORMAL
	-- who is not training on a fan plays no pose at all -- so whatever path
	-- forgot to stop one, it never loops for the other players for long.
	Scheduler.Every("ProbeService_AnimationSweep", 1, function()
		for _, player in Players:GetPlayers() do
			local idle = TraversalStateService.Get(player) == TraversalState.NORMAL
				and not TreadmillService.IsTraining(player)
			CharacterAnimations.Sweep(player, idle)
		end
	end)

	NetworkEvents.OnServerEvent("ProbeStartRequest", onProbeStartRequest)
	NetworkEvents.OnServerEvent("ProbeStopRequest", onProbeStopRequest)
	NetworkEvents.OnServerEvent("ProbeAimUpdate", onProbeAimUpdate)

	log:Info("Started.")
end

return ProbeService
