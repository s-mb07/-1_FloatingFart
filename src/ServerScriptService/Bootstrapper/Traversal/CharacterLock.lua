--!strict
--[[
	@module Traversal.CharacterLock
	@description Server-only ownership of "the mechanic, not the player, is
	moving this character right now". Extracted verbatim in behavior from
	ProbeService (where it was three local functions threading an
	`originalWalkSpeed` through every call) for one concrete reason: the
	traversal state machine has to be able to RELEASE a character on death,
	reset, disconnect or a destroyed wall, from code that was never handed
	that saved WalkSpeed. Storing the pre-lock values here, keyed by player,
	makes every release path identical and impossible to half-do.

	Behavior preserved exactly as ProbeService had it:
	  - Anchored blocks ALL movement, including an already-airborne
	    character (WalkSpeed alone would not).
	  - WalkSpeed=0 AND Humanoid:Move(zero) too, because that pair is what
	    the default Animate script reads to pick Running vs Idle -- anchoring
	    alone left the run animation playing on a character that could no
	    longer move.
	  - The Animate script is disabled for exactly the same window, freeing
	    the rig for custom animation over the whole mechanic.

	Not a Service: no Init/Start, no state of its own beyond the per-player
	restore record, so it lives beside Services/ rather than inside it (the
	bootstrapper only scans direct children of Services/).
]]

--- What the character looked like before the mechanic touched it. Kept per
--- PLAYER rather than per character: the release path frequently runs after
--- the character it belongs to has already been replaced or destroyed.
type LockRecord = {
	Character: Model,
	WalkSpeed: number,
}

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterAnimations = require(script.Parent.CharacterAnimations)
local FlyConfig = require(ReplicatedStorage.Config.FlyConfig)
local PlayerCollisionService = require(script.Parent.Parent.Services.PlayerCollisionService)

local CharacterLock = {}

-- While flying, the character sits in a group that collides with nothing:
-- world physics must never snag the flight (obstacles come only from the
-- front attachment of the Fly model, which the flight controller casts).
local DEFAULT_GROUP = "Default"
if not PhysicsService:IsCollisionGroupRegistered(FlyConfig.CollisionGroup) then
	PhysicsService:RegisterCollisionGroup(FlyConfig.CollisionGroup)
end
PhysicsService:CollisionGroupSetCollidable(FlyConfig.CollisionGroup, DEFAULT_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(
	FlyConfig.CollisionGroup,
	FlyConfig.CollisionGroup,
	false
)

-- Players (other characters) never collide with a flying body either: neither
-- physically nor for the obstacle rays, which are cast as the Players group.
PhysicsService:CollisionGroupSetCollidable(
	FlyConfig.CollisionGroup,
	FlyConfig.PlayerCollisionGroup,
	false
)

local function setCollisionGroup(character: Model, group: string): ()
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

--- Undoes everything BeginFlight changed on a character (idempotent).
local function endFlightState(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end
	PlayerCollisionService.Apply(character)
end

local locks: { [Player]: LockRecord } = {}

--- Disables/re-enables the character's default Animate script (and, when
--- disabling, stops whatever it already had playing) -- Script.Disabled is a
--- normal replicated property, so toggling it from the server is what
--- actually stops it on every client watching this character, not just the
--- owner's.
local function setNativeAnimationsEnabled(character: Model?, enabled: boolean): ()
	local animateScript = character and character:FindFirstChild("Animate")
	if animateScript and (animateScript:IsA("Script") or animateScript:IsA("LocalScript")) then
		animateScript.Disabled = not enabled
	end

	if not enabled then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0)
			end
		end
	end
end

--- Freezes `character` and records what to restore later. Idempotent: a
--- second Lock on an already-locked player keeps the FIRST record, so a
--- relaunch straight out of WALL_LOCKED (where the character is already
--- frozen, and its WalkSpeed already 0) can never save 0 as the value to
--- restore on landing.
--- @param player Player
--- @param character Model
function CharacterLock.Lock(player: Player, character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not locks[player] and humanoid then
		locks[player] = { Character = character, WalkSpeed = humanoid.WalkSpeed }
	end

	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero, false)
	end
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.Anchored = true
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	-- Clears a leftover pose too (a relaunch straight out of WALL_LOCKED is
	-- the case: WallIdle is still playing on the character being re-frozen).
	CharacterAnimations.Stop(player, 0)
	setNativeAnimationsEnabled(character, false)
end

--- Gives the character back to the player. Safe to call for a player who was
--- never locked, whose character is gone, or who has since respawned into a
--- different one -- in every case the record is dropped and nothing is left
--- half-restored. This is the single function every cleanup path calls, so
--- "no player may remain permanently frozen" has exactly one implementation.
--- @param player Player
function CharacterLock.Release(player: Player): ()
	local record = locks[player]
	locks[player] = nil

	-- Restore the recorded character AND, if the player has since respawned
	-- into a different one, that one too: on a respawn the recorded
	-- character is usually already destroyed while the live one was never
	-- frozen, but unanchoring the live one is harmless and covers the case
	-- where a lock leaked onto it. Built without a table literal on purpose
	-- -- a `{ maybeNil, other }` literal has an ambiguous length.
	local targets: { Model } = {}
	if record then
		table.insert(targets, record.Character)
	end
	local liveCharacter = player.Character
	if liveCharacter and liveCharacter ~= (record and record.Character) then
		table.insert(targets, liveCharacter)
	end

	for _, target in targets do
		if not target.Parent then
			continue
		end
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local rootPart = target:FindFirstChild("HumanoidRootPart")
		-- A fresh character that was never locked has no record to restore
		-- from; leaving its WalkSpeed alone is correct.
		if humanoid and record and target == record.Character then
			humanoid.WalkSpeed = record.WalkSpeed
		end
		if rootPart and rootPart:IsA("BasePart") then
			rootPart.Anchored = false
		end
		endFlightState(target)
		CharacterAnimations.StopAll(target)
		setNativeAnimationsEnabled(target, true)
	end

	CharacterAnimations.Stop(player)
end

--- Hands the (still locked) character over to the flight: the root is
--- unanchored and given to the player's client, which steers it; the
--- Humanoid stops fighting (PlatformStand, no AutoRotate) and the whole body
--- leaves the collision groups of the world. Native animations stay
--- disabled (Lock did that). EndFlight / Release undo it.
--- @param player Player
--- @param character Model
function CharacterLock.BeginFlight(player: Player, character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
	end
	setCollisionGroup(character, FlyConfig.CollisionGroup)
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		rootPart.Anchored = false
		-- Owned by the player already (it is their character); asserted so the
		-- per-frame velocity of the client applies the instant it is unanchored.
		-- pcall: throws while the player is disconnecting.
		pcall(function()
			rootPart:SetNetworkOwner(player)
		end)
	end
end

--- Ends the flight without unlocking: the character keeps its WalkSpeed 0 /
--- disabled Animate (the End animation still plays) but is a normal
--- physical body again -- collisions back, Humanoid active, free to fall.
--- @param character Model
function CharacterLock.EndFlight(character: Model): ()
	endFlightState(character)
end

--- @param player Player
--- @return boolean
function CharacterLock.IsLocked(player: Player): boolean
	return locks[player] ~= nil
end

--- The WalkSpeed a Release would restore, for a caller that needs to reason
--- about it without releasing (diagnostics, tests).
--- @param player Player
--- @return number?
function CharacterLock.GetRestoreWalkSpeed(player: Player): number?
	local record = locks[player]
	return record and record.WalkSpeed
end

--- Drops the record WITHOUT touching any character -- for a player who has
--- left, where there is nothing left to restore and `player.Character` is
--- already meaningless.
--- @param player Player
function CharacterLock.Forget(player: Player): ()
	locks[player] = nil
	CharacterAnimations.Forget(player)
end

--- Space is permanently repurposed to launch (README/ProbeService: there is
--- no jump in this game), so this is applied once per character and never
--- re-enabled -- no per-flight toggle to get wrong. Applied on every
--- CharacterAdded by ProbeService, including for players already in the
--- game when the service starts.
--- @param character Model
function CharacterLock.DisableJumpingForever(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

return CharacterLock
