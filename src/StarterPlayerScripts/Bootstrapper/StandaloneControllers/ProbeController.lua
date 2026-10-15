--!strict
--[[
	@module ProbeController
	@description Space launches the flight: the player's OWN character flies,
	steered by this client (zero input latency), validated by the server (see
	ProbeService.lua). Jumping is permanently disabled game-wide (Space is
	fully repurposed), never toggled per-flight.

	Sequence seen from here:
	  1. press         -> controls locked, ProbeStartRequest with the camera
	     aim; during PRE_LAUNCH the aim keeps streaming (ProbeAimUpdate) and
	     the server turns the character toward it, away from any part.
	  2. ProbeStarted  -> (server plays the Start animation, lifts a grounded
	     player) the camera zooms out with a light shake from ZoomStartTime
	     to the end of that animation, then returns to normal.
	  3. state ACTIVE  -> beginFlight: a LinearVelocity + AlignOrientation on
	     the character root, Humanoid in PlatformStand, heading = launch arc
	     then the camera look (same steering as the former probe part).
	     Every Heartbeat a ray from the Fly model's front Attachment looks
	     for obstacles; a hit stops the flight at once and asks the server
	     (ProbeStopRequest + normal) which verifies and decides the outcome.
	  4. ProbeStopped  -> the rebound (knock-back along the normal, decaying)
	     plays here for an obstacle, then the body is upright and physical
	     again; the server plays the End animation and returns control
	     (state NORMAL).

	Traversal layer (kept): this controller also mirrors the server's
	authoritative traversal state so it can keep movement controls disabled
	for exactly the right window, clamp wall aim into the legal outward
	hemisphere, and refuse a launch it already knows would be rejected. All
	of that is PREDICTION -- ProbeService/LaunchValidator re-derive it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EventBus = require(script.Parent.Parent.Events.EventBus)
local FlyConfig = require(ReplicatedStorage.Config.FlyConfig)
local KeybindsConfig = require(script.Parent.Parent.Config.KeybindsConfig)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NavigationController = require(script.Parent.Parent.Navigation.Controller)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local ProbeConfig = require(ReplicatedStorage.Config.ProbeConfig)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TraversalConfig = require(ReplicatedStorage.Config.TraversalConfig)
local TraversalGeometry = require(ReplicatedStorage.Libraries.TraversalGeometry)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)

local log = Logger.new("ProbeController")
local ProbeController = {}

local LocalPlayer = Players.LocalPlayer
local ZOOM_BIND_NAME = "ProbeControllerFlyStartCamera"

--============================================================================--
-- LOCAL MIRROR OF THE SERVER'S TRAVERSAL STATE
--
-- Every value below is a REPLICATED COPY, never an authority. It exists so
-- the client can be responsive: keep movement controls disabled for exactly
-- the right window, clamp aim against a wall, and refuse a launch it already
-- knows the server would refuse -- without a round trip.
--============================================================================--

local localState: TraversalState.State = TraversalState.NORMAL
-- The authoritative wall normal for the local player's current lock, as sent
-- by the server. nil unless localState == WALL_LOCKED.
local localWallNormal: Vector3? = nil
-- Local estimate only: the server owns the real cooldown. Used to avoid
-- firing a request that is certain to be refused, never to allow one.
local localCooldownUntil = 0
local aimBlocked = false
-- Last aim sent to the server for the current launch (start request or
-- ProbeAimUpdate), so the stream only sends real changes.
local lastSentAim: Vector3? = nil

local cachedControls: any = nil
-- Watches the default Animate script's Disabled flag for the local
-- character -- see the native-animation suppression block below.
local animateWatcher: RBXScriptConnection? = nil
-- Live only while native animation is suppressed: catches any native track
-- that manages to start during the window and stops it immediately.
local nativeAnimationGuard: RBXScriptConnection? = nil

--- The running flight of the local character (nil when not flying).
type Flight = {
	Character: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	RootAttachment: Attachment,
	Velocity: LinearVelocity,
	Align: AlignOrientation,
	Params: RaycastParams,
	Connection: RBXScriptConnection?,
	StartClock: number,
	Forward: Vector3,
	Direction: Vector3,
	--- Current roll (radians) of the banking, + = left wing down.
	Roll: number,
	--- Inside a usable fan Hitbox on the last step (see insideUsableFan).
	InFan: boolean,
}

local flight: Flight? = nil
-- Rebound in progress (after the flight itself ended).
local reboundConnection: RBXScriptConnection? = nil

function ProbeController.IsFlying(): boolean
	return flight ~= nil
end

--- The local player's replicated traversal state. Read-only mirror.
--- @return TraversalState.State
function ProbeController.GetState(): TraversalState.State
	return localState
end

--- @return boolean -- true while suspended against a wall (§5)
function ProbeController.IsWallLocked(): boolean
	return localState == TraversalState.WALL_LOCKED
end

--- Space never jumps in this game -- disabled once per character, never
--- toggled per-flight (there is no jump state to save/restore).
--- Also disables FallingDown + Ragdoll for good: a hard landing (the
--- bounce after a probe) or a server teleport right after one could trip
--- the Humanoid into those states, leaving the player lying down and unable
--- to move for seconds. Humanoid state is owned by THIS client for its own
--- character, so it must be disabled here -- the server can't prevent it.
local function disableJumpForever(character: Model?): ()
	if not character then
		return
	end
	-- FindFirstChildOfClass alone races the character rig: Humanoid can
	-- still be loading in when CharacterAdded fires, so the jump-disable
	-- would silently no-op and Space would work for one respawn.
	-- WaitForChild blocks (briefly, off the main thread) until it exists.
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 5) :: Humanoid?
		if humanoid then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
	end)
end

--- Is this track one of Roblox's own default-character animations?
---
--- Decided by PROVENANCE, not by name: the default Animate script owns its
--- Animation instances as its own children (Animate/run/RunAnim, and so on),
--- so a track whose Animation descends from that script is native and
--- anything else is not.
---
--- This distinction is the whole point. The mechanic has to block Roblox's
--- animations for its full duration so custom ones can drive the rig -- but
--- a blanket "stop everything" would also kill those custom animations the
--- moment they were added, which is exactly what this system exists to make
--- possible.
local function isNativeAnimationTrack(track: AnimationTrack, animate: Instance): boolean
	local animation = track.Animation
	return animation ~= nil and animation:IsDescendantOf(animate)
end

--- Stops every native track currently playing on the LOCAL character.
---
--- Why this has to happen on the client: ProbeService disables the Animate
--- script server-side, which stops NEW native tracks from starting, but
--- cannot stop the ones already playing -- those were started by this
--- client's own Animate script, and a Stop() issued from the server never
--- reaches them. (Roblox's own guidance is the same pair: disable the
--- script AND explicitly Stop each playing track, from the client.) Left
--- alone, a player who launched while running stayed visibly mid-run for
--- the entire flight, the whole walk-back, and the entire time they were
--- pinned to a wall.
---
--- Stopping them here, on the client that owns the Animator, is what clears
--- the rig -- and it replicates outward, so spectators see it too.
local function stopNativeAnimationTracks(character: Model, animate: Instance): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if isNativeAnimationTrack(track, animate) then
			track:Stop(TraversalConfig.Animation.SuppressFadeOut)
		end
	end
end

--- Blocks native animation for as long as the mechanic owns the rig, rather
--- than only clearing it once at the start.
---
--- The one-shot clear was not enough on its own: `Animate.Disabled` is set
--- by the server, so there is a short window before it replicates in which
--- this client's still-live Animate script can start a fresh track (an
--- idle-to-run transition, a Freefall reaction to being anchored). That
--- track would then play untouched for the rest of the mechanic. The
--- AnimationPlayed guard below closes that window and keeps it closed.
local function beginNativeSuppression(character: Model, animate: Instance): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	stopNativeAnimationTracks(character, animate)

	if nativeAnimationGuard then
		nativeAnimationGuard:Disconnect()
	end
	if not animator then
		nativeAnimationGuard = nil
		return
	end

	nativeAnimationGuard = animator.AnimationPlayed:Connect(function(track: AnimationTrack)
		-- Custom animations are deliberately left alone -- see
		-- isNativeAnimationTrack.
		if isNativeAnimationTrack(track, animate) then
			track:Stop(TraversalConfig.Animation.SuppressFadeOut)
		end
	end)
end

--- Hands the rig back: the guard comes off so the re-enabled Animate script
--- can drive the character normally again.
local function endNativeSuppression(): ()
	if nativeAnimationGuard then
		nativeAnimationGuard:Disconnect()
		nativeAnimationGuard = nil
	end
end

--- Binds suppression to the exact moment native animation is switched off.
---
--- Keyed off the Animate script's own Disabled flag rather than off a
--- traversal state event on purpose: that flag IS the definition of "the rig
--- is no longer being driven natively", it flips for every path that locks a
--- character (launch, relaunch, anything added later), and it carries no
--- assumption about whether it replicates before or after the state
--- broadcast.
local function watchNativeAnimations(character: Model?): ()
	if animateWatcher then
		animateWatcher:Disconnect()
		animateWatcher = nil
	end
	endNativeSuppression()
	if not character then
		return
	end

	task.spawn(function()
		-- WaitForChild: Animate is added as the rig loads, so a
		-- FindFirstChild on a fresh CharacterAdded routinely misses it.
		local animate = character:FindFirstChild("Animate")
			or character:WaitForChild("Animate", 5) :: Instance?
		if not animate or not animate:IsA("LocalScript") then
			return
		end
		if character ~= LocalPlayer.Character then
			return -- respawned again while waiting; a newer watcher owns it
		end

		animateWatcher = animate:GetPropertyChangedSignal("Disabled"):Connect(function()
			if animate.Disabled then
				beginNativeSuppression(character, animate)
			else
				endNativeSuppression()
			end
		end)

		-- Already suppressed by the time this ran (a respawn mid-mechanic).
		if animate.Disabled then
			beginNativeSuppression(character, animate)
		end
	end)
end

--- Roblox's own default character-control module -- disabling it blocks
--- WASD/thumbstick movement input outright, which is what "lock keyboard
--- movement input, even mid-air" needs: WalkSpeed/state tricks alone only
--- affect the Humanoid, not the input that feeds it. No exported Luau types
--- on this vendored default module, so `any` here is the real boundary
--- README §9.1 allows, not a shortcut around typing our own code.
local function getControls(): any
	if cachedControls then
		return cachedControls
	end

	local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	local moduleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end

	local ok, controls = pcall(function()
		return (require(moduleScript) :: any):GetControls()
	end)
	if ok then
		cachedControls = controls
		return controls
	end
	return nil
end

--- Blocks/restores the player's own movement input for the mechanic.
---
--- IMPORTANT, verified in this place: this is a BEST-EFFORT convenience, not
--- the thing that actually holds the player still. Two findings from testing
--- here:
---
---   * PlayerModule is NOT present in PlayerScripts in this place (only
---     RbxCharacterSounds and the project's own Bootstrapper are), so
---     `getControls()` returns nil and this does nothing at all. It used to
---     fail silently, which made it look like input was being held back when
---     it never was.
---   * Sinking `Enum.PlayerActions.Character*` through ContextActionService
---     -- the usual module-independent fallback -- was measured to have no
---     effect either: with the sink bound, a held W still moved the
---     character the full 16 studs/s. Whatever is driving movement in this
---     place does not route through those actions, so that fallback was
---     removed rather than shipped as dead code.
---
--- What actually stops the player is server-side: ProbeService anchors the
--- HumanoidRootPart before the flight (see Traversal/CharacterLock) and
--- PlatformStand holds the Humanoid still during it. The
--- animation side -- the visible symptom this lock was originally added to
--- fix -- is handled properly now by the native-animation suppression above.
---
--- This is kept because it DOES work in a place that has PlayerModule, and
--- costs nothing where it doesn't.
local function setControlsLocked(locked: boolean): ()
	local controls = getControls()
	if not controls then
		return
	end
	if locked then
		controls:Disable()
	else
		controls:Enable()
	end
end

--============================================================================--
-- AIM (§7 -- client side is UX only)
--============================================================================--

--- The direction this client is asking to launch in.
---
--- From a wall the CAMERA is the aim: the character is pinned facing the
--- surface, so its own LookVector points straight INTO the wall and would be
--- rejected outright. The raw camera look is then clamped into the legal
--- outward hemisphere with the same shared function the server validates
--- with (TraversalGeometry) -- aiming past the wall slides the launch along
--- it rather than through it, which is the "cannot naturally aim through the
--- wall" constraint §7 asks for.
---
--- On the ground the camera look is the aim too (the player's point of
--- view); the character's own facing is only the fallback without a camera.
--- The server turns the character toward it over the Start animation.
---
--- Clamping here is a convenience for an honest client. The server re-runs
--- the hemisphere test on whatever actually arrives, so a modified client
--- that skips the clamp is refused, not corrected.
--- @return Vector3? -- unit, Y = 0, or nil when nothing usable is available
local function computeAimDirection(): Vector3?
	if localState == TraversalState.WALL_LOCKED then
		local normal = localWallNormal
		local camera = Workspace.CurrentCamera
		if not normal or not camera then
			return nil
		end
		return TraversalGeometry.ClampOutward(camera.CFrame.LookVector, normal)
	end

	local camera = Workspace.CurrentCamera
	local cameraAim = camera and TraversalGeometry.FlattenDirection(camera.CFrame.LookVector)
	if cameraAim then
		return cameraAim
	end
	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return TraversalGeometry.FlattenDirection(rootPart.CFrame.LookVector)
	end
	return nil
end

--- While the Start animation plays (PRE_LAUNCH), streams the aim so the
--- server can turn the character toward where the player is looking. Only
--- sent when it moved enough; the server picks the actual heading.
local function streamPrepAim(): ()
	if localState ~= TraversalState.PRE_LAUNCH then
		return
	end
	local aim = computeAimDirection()
	if not aim then
		return
	end
	local last = lastSentAim
	if last and aim:Dot(last) >= math.cos(math.rad(FlyConfig.PrepAimMinDegrees)) then
		return
	end
	lastSentAim = aim
	NetworkEvents.FireServer("ProbeAimUpdate", aim)
end

--- Publishes "you are currently aiming into the wall" for the HUD. Purely
--- informational -- the launch is rejected by the server either way.
local function refreshAimBlocked(): ()
	local blocked = false
	if localState == TraversalState.WALL_LOCKED then
		local normal = localWallNormal
		local camera = Workspace.CurrentCamera
		if normal and camera then
			blocked = not TraversalGeometry.IsOutward(camera.CFrame.LookVector, normal)
		end
	end

	if blocked ~= aimBlocked then
		aimBlocked = blocked
		EventBus.Traversal.AimBlocked:Fire(blocked)
	end
end

--- The deliberately PARTIAL client-side mirror of the server's launch rules
--- (Traversal/LaunchValidator). Only the things this client already holds a
--- local copy of are checked -- state, cooldown, training, ground -- so
--- an obviously-doomed request never leaves the machine and the player gets
--- an instant answer instead of a silent one. An open panel also blocks the
--- launch: that rule is client-only (UI is client state), a click or Space
--- meant for the panel must never start the windup.
---
--- It is NOT authority and NOT complete: liveness, character validity,
--- direction sanity, the wall record and anti-cheat are all server-only.
--- @return string? -- a reason when locally known to be refused, else nil
local function localLaunchRejection(): string?
	if not TraversalState.IsLaunchable(localState) then
		return localState
	end
	if os.clock() < localCooldownUntil then
		return "OnCooldown"
	end
	if NavigationController.GetActivePanelId() ~= nil then
		return "PanelOpen"
	end
	-- Mirrors LaunchValidator's Training: no launch from a trainer (fan).
	if LocalPlayer:GetAttribute(TreadmillConfig.TrainingAttribute) ~= nil then
		return "Training"
	end
	-- Mirrors LaunchValidator's NotGrounded: this client simulates its own
	-- character, so its FloorMaterial is the freshest answer available.
	if localState == TraversalState.NORMAL then
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
			return "NotGrounded"
		end
	end
	return nil
end

--============================================================================--
-- FLIGHT (the character itself)
--============================================================================--

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

--- The front Attachment of the Fly model (obstacle detector); nil until the
--- model is on the character.
local function findFront(character: Model): Attachment?
	local fly = character:FindFirstChild(FlyConfig.ModelName)
	local attachment = fly and fly:FindFirstChild(FlyConfig.AttachmentName, true)
	return if attachment and attachment:IsA("Attachment") then attachment else nil
end

local function disconnectRebound(): ()
	if reboundConnection then
		reboundConnection:Disconnect()
		reboundConnection = nil
	end
end

--- Heading for this step. First LaunchRiseDuration seconds: up AND forward,
--- the pitch decaying to level like the start of a parabola. After that: the
--- camera's look direction -- the camera is the default Custom camera on the
--- character, so "where the screen faces" and "where the body flies" cannot
--- disagree. Eased along the great circle; the speed is always full Speed.
local function steer(active: Flight, dt: number): Vector3
	local camera = Workspace.CurrentCamera
	local elapsed = os.clock() - active.StartClock
	local target: Vector3
	if elapsed < ProbeConfig.LaunchRiseDuration then
		local pitch = math.rad(ProbeConfig.LaunchPitchDegrees)
			* (1 - elapsed / ProbeConfig.LaunchRiseDuration)
		target = Vector3.new(
			active.Forward.X * math.cos(pitch),
			math.sin(pitch),
			active.Forward.Z * math.cos(pitch)
		)
	elseif camera then
		target = camera.CFrame.LookVector
	else
		target = active.Forward
	end

	target = target.Unit
	local current = active.Direction
	local angle = math.acos(math.clamp(current:Dot(target), -1, 1))
	local rate = ProbeConfig.DirectionSmoothing
		/ (1 + ProbeConfig.LargeTurnEasing * angle / math.pi)
	local blend = 1 - math.exp(-rate * dt)
	local direction = target
	if angle > 1e-4 then
		local axis = current:Cross(target)
		-- exact reversal: pick up as the pivot
		axis = if axis.Magnitude > 1e-4 then axis.Unit else Vector3.yAxis
		direction = CFrame.fromAxisAngle(axis, angle * blend):VectorToWorldSpace(current)
	end
	return direction
end

--- Upright again (pure yaw, no pitch/roll) where the body is: the Humanoid
--- takes over from a flying pose without a tumble.
local function standUp(character: Model, root: BasePart): ()
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.zAxis
	end
	character:PivotTo(CFrame.lookAt(root.Position, root.Position + look.Unit))
	root.AssemblyAngularVelocity = Vector3.zero
end

--- Hands the character back to the Humanoid (constraints off, physical).
local function releaseBody(active: Flight, upright: boolean): ()
	active.Velocity:Destroy()
	active.Align:Destroy()
	active.RootAttachment:Destroy()
	if active.Humanoid.Parent then
		active.Humanoid.PlatformStand = false
		active.Humanoid.AutoRotate = true
	end
	if upright and active.Root.Parent then
		standUp(active.Character, active.Root)
	end
end

--- Ends the local flight at once. `reason` is the server's stop reason (or
--- the local one for an obstacle / cancel). An "Obstacle" with a normal
--- rebounds: the body is knocked back along the normal, decaying to rest.
local function stopLocalFlight(reason: string, normal: Vector3?): ()
	local active = flight
	if not active then
		return
	end
	flight = nil
	if active.Connection then
		active.Connection:Disconnect()
	end
	disconnectRebound()

	local teleported = reason == "WallLock" or reason == "KillPart" or reason == "WinPad"
	-- Only a plain obstacle hit rebounds (knocked back along the surface
	-- normal). A mid-air stop (stamina, cancel...) drops straight away, and
	-- special hits / resets are decided by the server.
	if reason == "Obstacle" and normal then
		local direction = (normal + Vector3.yAxis * FlyConfig.ReboundUpward).Unit
		local startClock = os.clock()
		active.Velocity.VectorVelocity = direction * FlyConfig.ReboundSpeed
		reboundConnection = RunService.Heartbeat:Connect(function(): ()
			local alpha = (os.clock() - startClock) / FlyConfig.ReboundDuration
			if alpha >= 1 or not active.Root.Parent then
				disconnectRebound()
				releaseBody(active, true)
				return
			end
			active.Velocity.VectorVelocity = direction * FlyConfig.ReboundSpeed * (1 - alpha)
		end)
	else
		active.Velocity.VectorVelocity = Vector3.zero
		releaseBody(active, not teleported)
	end

	EventBus.Traversal.Stopped:Fire(LocalPlayer, reason)
	EventBus.Gameplay.ProbeStopped:Fire(reason)
end

--- True when `position` is inside a fan Hitbox the local player may train in
--- (TreadmillConfig.AccessAttribute, published by the server).
local function insideUsableFan(position: Vector3): boolean
	local access = LocalPlayer:GetAttribute(TreadmillConfig.AccessAttribute)
	if type(access) ~= "string" or access == "" then
		return false
	end
	local ids = access:split(",")
	for _, hitbox in CollectionService:GetTagged(TagNames.Treadmill) do
		local id = hitbox:GetAttribute(TagNames.Attr.Id)
		if hitbox:IsA("BasePart") and type(id) == "string" and table.find(ids, id) then
			local rel = hitbox.CFrame:PointToObjectSpace(position)
			local half = hitbox.Size * 0.5
			if
				math.abs(rel.X) <= half.X
				and math.abs(rel.Y) <= half.Y
				and math.abs(rel.Z) <= half.Z
			then
				return true
			end
		end
	end
	return false
end

local function onFlightStep(dt: number): ()
	local active = flight
	if not active then
		return
	end
	if not active.Root.Parent or active.Humanoid.Health <= 0 then
		stopLocalFlight("Interrupted", nil)
		return
	end

	-- Flying into a usable fan: stop dead inside it. Waiting for the server
	-- (10 Hz pad poll + a round trip) let the body cross the whole Hitbox
	-- first, so training never started. The server then sees the player
	-- inside and starts the session (TreadmillService).
	-- Entry only: a flight that starts inside a fan (training is refused at
	-- launch, but a locked fan is not training) must be able to leave it.
	local inFan = insideUsableFan(active.Root.Position)
	local entered = inFan and not active.InFan
	active.InFan = inFan
	if entered then
		local root = active.Root
		stopLocalFlight("Stopped", nil)
		root.AssemblyLinearVelocity = Vector3.zero -- no momentum out of the fan
		NetworkEvents.FireServer("ProbeStopRequest")
		return
	end

	local previous = active.Direction
	local direction = steer(active, dt)
	active.Direction = direction
	active.Velocity.VectorVelocity = direction * ProbeConfig.Speed

	-- Banking: signed turn rate of the heading seen from above (+ = left),
	-- turned into a target roll, eased so it never snaps.
	local yawStep = math.atan2(
		previous.X * direction.Z - previous.Z * direction.X,
		previous.X * direction.X + previous.Z * direction.Z
	)
	local yawRate = math.deg(-yawStep) / math.max(dt, 1e-3)
	local targetRoll = math.rad(
		math.clamp(
			yawRate * FlyConfig.BankDegreesPerYawRate,
			-FlyConfig.BankMaxDegrees,
			FlyConfig.BankMaxDegrees
		)
	)
	active.Roll += (targetRoll - active.Roll) * (1 - math.exp(-FlyConfig.BankSmoothing * dt))
	active.Align.CFrame = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, active.Roll)

	-- Obstacle ray from the front attachment: one frame of travel plus the
	-- padding, so the stop happens before the body gets into the surface.
	local front = findFront(active.Character)
	local origin = if front then front.WorldPosition else active.Root.Position
	local reach = ProbeConfig.Speed * dt + ProbeConfig.RaycastPadding
	local hit = Workspace:Raycast(origin, direction * reach, active.Params)
	if not hit then
		return
	end

	-- Kill part, win pad and Honey are decided by the server; everything else
	-- rebounds. The server re-casts the ray itself either way.
	local special = taggedAncestor(hit.Instance, TagNames.KillPart)
		or taggedAncestor(hit.Instance, TagNames.WinPad)
		or (
			taggedAncestor(hit.Instance, TagNames.Vertical)
			and TraversalGeometry.IsVerticalFace(hit.Normal)
		)
	stopLocalFlight(if special then "Stopped" else "Obstacle", hit.Normal)
	NetworkEvents.FireServer("ProbeStopRequest", hit.Normal)
end

--- State ACTIVE: the server just handed this character over.
local function beginFlight(): ()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid) then
		return
	end
	disconnectRebound()
	if flight then
		stopLocalFlight("Interrupted", nil)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlyRootAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	-- Not rigid: the pitch of the launch arc is reached over a few frames
	-- instead of snapping the body to it the instant the flight starts.
	align.RigidityEnabled = false
	align.Responsiveness = 25
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.CFrame = root.CFrame.Rotation
	align.Parent = root

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	-- Cast as a "Players" body: other characters are not obstacles.
	params.CollisionGroup = FlyConfig.PlayerCollisionGroup

	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.zAxis

	local active: Flight = {
		Character = character,
		Root = root,
		Humanoid = humanoid,
		RootAttachment = attachment,
		Velocity = velocity,
		Align = align,
		Params = params,
		Connection = nil,
		StartClock = os.clock(),
		Forward = forward,
		Direction = forward,
		Roll = 0,
		InFan = insideUsableFan(root.Position),
	}
	flight = active
	active.Connection = RunService.Heartbeat:Connect(onFlightStep)

	EventBus.Gameplay.ProbeStarted:Fire()
	EventBus.Traversal.Started:Fire(LocalPlayer)
end

--============================================================================--
-- START-ANIMATION CAMERA (zoom out + light shake, then back to normal)
--============================================================================--

local function safeUnbindRenderStep(name: string): ()
	pcall(function()
		RunService:UnbindFromRenderStep(name)
	end)
end

local function stopZoom(): ()
	safeUnbindRenderStep(ZOOM_BIND_NAME)
end

--- From ZoomStartTime to the end of the Start animation: the camera pulls
--- back, widens and shakes; it eases back to normal once the animation is
--- over. Applied AFTER the default camera has placed itself (priority
--- Camera + 1), so it never fights it and leaves no residue.
local function startZoom(startDuration: number): ()
	local zoomEnd = startDuration
	if zoomEnd <= FlyConfig.ZoomStartTime + 0.05 then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	stopZoom()
	local baseFov = camera.FieldOfView
	local startClock = os.clock()

	-- The pull-back stops short of any solid behind the camera: it never
	-- enters a part. Distance actually applied: shrinks at once when a wall
	-- is near (never inside), grows back smoothly.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character :: Instance }
	params.RespectCanCollide = true
	params.CollisionGroup = FlyConfig.PlayerCollisionGroup
	local applied = 0
	local lastClock = startClock
	RunService:BindToRenderStep(ZOOM_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - startClock
		local intensity: number
		if t < FlyConfig.ZoomStartTime then
			intensity = 0
		elseif t < zoomEnd then
			intensity = math.min(1, (t - FlyConfig.ZoomStartTime) / FlyConfig.ZoomEaseSeconds)
		elseif t < zoomEnd + FlyConfig.ZoomRestoreSeconds then
			intensity = 1 - (t - zoomEnd) / FlyConfig.ZoomRestoreSeconds
		else
			camera.FieldOfView = baseFov
			stopZoom()
			return
		end

		camera.FieldOfView = baseFov + FlyConfig.ZoomFovBoost * intensity
		local shake = if FlyConfig.ShakeEnabled
				and t >= FlyConfig.ZoomStartTime
				and t <= zoomEnd
			then FlyConfig.ShakeAmplitude
			else 0
		local x = math.noise(t * FlyConfig.ShakeFrequency, 0.37) * shake
		local y = math.noise(t * FlyConfig.ShakeFrequency, 5.91) * shake
		local desired = FlyConfig.ZoomBackDistance * intensity
		local back = -camera.CFrame.LookVector
		local hit = Workspace:Raycast(
			camera.CFrame.Position,
			back * (desired + FlyConfig.ZoomWallMargin),
			params
		)
		local allowed = if hit then math.max(0, hit.Distance - FlyConfig.ZoomWallMargin) else desired
		local now = os.clock()
		local blend = 1 - math.exp(-10 * (now - lastClock))
		lastClock = now
		applied = if allowed < applied then allowed else applied + (allowed - applied) * blend
		camera.CFrame = camera.CFrame * CFrame.new(x, y, applied)
	end)
end

--============================================================================--
-- NETWORK HANDLERS
--============================================================================--

local function onProbeStarted(player: Player, startDuration: number): ()
	if player == LocalPlayer then
		startZoom(startDuration)
		EventBus.Gameplay.LaunchStarted:Fire()
	end
end

--- The server ended the flight (stamina, cancel, speed, kill part, wall...).
--- If the client already stopped itself (obstacle) this does nothing more.
local function onProbeStopped(player: Player, reason: string, hitNormal: Vector3?): ()
	if player == LocalPlayer then
		stopLocalFlight(reason, hitNormal)
	end
end

--- The server refused a launch. The client locked its movement controls
--- optimistically the moment the player pressed, so this gives them back.
--- Exception: WALL_LOCKED keeps controls locked by design.
local function onTraversalLaunchRejected(reason: string): ()
	log:Debug("Launch rejected by the server (%s).", tostring(reason))
	if localState ~= TraversalState.WALL_LOCKED then
		setControlsLocked(false)
	end
end

--- Server says the local player is now suspended against a wall (§5).
--- Movement controls deliberately STAY disabled.
local function onTraversalWallLocked(player: Player, wallNormal: Vector3): ()
	if player ~= LocalPlayer then
		return
	end
	localWallNormal = wallNormal
	setControlsLocked(true)
	localCooldownUntil = os.clock() + ProbeConfig.RelaunchCooldown
	refreshAimBlocked()
end

local function onTraversalWallUnlocked(player: Player): ()
	if player ~= LocalPlayer then
		return
	end
	localWallNormal = nil
	refreshAimBlocked()
end

--- The local mirror's single write point for state. Also the safety net for
--- every cleanup path on the server (death, reset, a destroyed wall): those
--- all land on NORMAL, and a client sitting on NORMAL must never still be
--- flying or have its movement controls disabled.
local function onTraversalStateChanged(player: Player, newState: TraversalState.State): ()
	if player ~= LocalPlayer then
		return
	end

	localState = newState
	if newState ~= TraversalState.WALL_LOCKED then
		localWallNormal = nil
	end
	if newState == TraversalState.ACTIVE then
		beginFlight()
	elseif newState == TraversalState.NORMAL then
		stopLocalFlight("Interrupted", nil)
		stopZoom()
		setControlsLocked(false)
		-- The server starts a relaunch cooldown at exactly this moment.
		localCooldownUntil = os.clock() + ProbeConfig.RelaunchCooldown
	end
	refreshAimBlocked()
end

--============================================================================--
-- INPUT
--============================================================================--

--- Space and left-click share one launch/stop trigger, matching how
--- KeybindsConfig documents both as read-directly Reserved entries.
local function isProbeTrigger(input: InputObject): boolean
	return input.KeyCode == KeybindsConfig.Reserved.ProbeLaunch
		or input.UserInputType == KeybindsConfig.Reserved.ProbeLaunchMouse
end

--- The launch/stop action itself, shared by the keyboard/mouse trigger and
--- the touch LAUNCH button (MobileLaunchController, via ProbeController.Trigger).
local function trigger(): ()
	if flight then
		-- Pressing the trigger again mid-flight stops it where it is.
		stopLocalFlight("PlayerCanceled", nil)
		NetworkEvents.FireServer("ProbeStopRequest")
		return
	end

	-- Cheap local pre-check (§9): state and cooldown. Everything real is
	-- re-checked server-side in Traversal/LaunchValidator.
	local rejection = localLaunchRejection()
	if rejection then
		log:Debug("Launch suppressed locally (%s).", rejection)
		return
	end

	-- Read the aim BEFORE the server round trip (the server's replicated copy
	-- of an owned character visibly lags an active turn).
	local aimDirection = computeAimDirection()
	if not aimDirection then
		return
	end

	-- Lock input IMMEDIATELY, not just once the state changes: Controls keeps
	-- calling Humanoid:Move() every client frame while a key is held.
	setControlsLocked(true)

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end

	lastSentAim = aimDirection
	NetworkEvents.FireServer("ProbeStartRequest", aimDirection)

	-- Last-resort safety net: a refusal arrives explicitly and releases the
	-- controls (onTraversalLaunchRejected); this only covers that message
	-- itself never arriving, i.e. the state never left NORMAL.
	task.delay(2, function()
		if localState == TraversalState.NORMAL then
			setControlsLocked(false)
		end
	end)
end

local function onInputBegan(input: InputObject, processed: boolean): ()
	if processed then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if isProbeTrigger(input) then
		trigger()
	end
end

--- Launch, or stop the current flight -- exactly what Space / left-click do.
--- Public for on-screen buttons (touch devices have neither key).
function ProbeController.Trigger(): ()
	trigger()
end

--- True while the local player's own flight is active.
--- @return boolean
function ProbeController.IsFlying(): boolean
	return flight ~= nil
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function ProbeController:Init(): ()
	log:Info("Initialized.")
end

function ProbeController:Start(): ()
	-- Never first-person: this zoom floor applies to the character camera.
	LocalPlayer.CameraMinZoomDistance = ProbeConfig.NormalCameraMinZoom

	disableJumpForever(LocalPlayer.Character)
	watchNativeAnimations(LocalPlayer.Character)
	LocalPlayer.CharacterAdded:Connect(function(character: Model)
		stopLocalFlight("Interrupted", nil)
		disableJumpForever(character)
		watchNativeAnimations(character)
	end)

	UserInputService.InputBegan:Connect(onInputBegan)

	NetworkEvents.OnClientEvent("ProbeStarted", onProbeStarted)
	NetworkEvents.OnClientEvent("ProbeStopped", onProbeStopped)

	-- The traversal layer arrives through EventBus (NetworkBridgeController
	-- owns those remotes), not directly off the network like the two probe
	-- events above.
	EventBus.Traversal.LaunchRejected:Connect(onTraversalLaunchRejected)
	EventBus.Traversal.StateChanged:Connect(onTraversalStateChanged)
	EventBus.Traversal.WallLocked:Connect(onTraversalWallLocked)
	EventBus.Traversal.WallUnlocked:Connect(onTraversalWallUnlocked)

	-- Wall-aim feedback: cheap, only does anything while wall-locked, and
	-- purely cosmetic (the server rejects an inward launch regardless), so
	-- it takes the cosmetic flag and scales down with graphics quality.
	Scheduler.Every("ProbeController_WallAim", 15, refreshAimBlocked, true)
	-- Start-sequence aim: gameplay (decides the launch heading), never cosmetic.
	Scheduler.Every("ProbeController_PrepAim", FlyConfig.PrepAimHz, streamPrepAim)

	log:Info("Started.")
end

return ProbeController
