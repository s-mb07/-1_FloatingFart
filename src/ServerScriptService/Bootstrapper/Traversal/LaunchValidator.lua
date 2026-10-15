--!strict
--[[
	@module Traversal.LaunchValidator
	@description THE one place that answers "may this player launch right
	now, in this direction". Every launch request passes through
	`Validate` -- there is no second path, and no caller re-implements a
	subset of these checks.

	Why centralized: the checks fall into four groups that used to live in
	three different places (the remote handler, the state flags, the
	anti-cheat layer), which is how a rule ends up enforced on one entry
	point and not another. Collecting them here also means the CLIENT can
	run the cheap subset for responsiveness (see ProbeController) while the
	server runs all of them regardless -- prediction and authority share a
	vocabulary instead of drifting.

	Returns a STRUCTURED result, never a bare boolean:
	    { Allowed: boolean, Reason: Reason?, Direction: Vector3? }
	`Direction` is the sanitized, flattened, normalized, server-side
	direction the caller should actually launch with -- the validator is
	the only thing that normalizes it, so no caller can skip that step.

	Theme-agnostic: nothing here names a visual, and nothing here knows how
	a probe flies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AntiCheatService = require(script.Parent.Parent.Services.AntiCheatService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local ProbeConfig = require(ReplicatedStorage.Config.ProbeConfig)
local TraversalGeometry = require(ReplicatedStorage.Libraries.TraversalGeometry)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TraversalStateService = require(script.Parent.Parent.Services.TraversalStateService)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)
local WallLock = require(script.Parent.WallLock)

local log = Logger.new("LaunchValidator")
local LaunchValidator = {}

--- Explicit rejection constants rather than ad-hoc strings: these are
--- compared, logged and (for the client-side subset) reasoned about, so a
--- typo in one of them must be a nil index and not a silently different
--- string.
local Reasons = {
	NoPlayer = "NoPlayer",
	NoCharacter = "NoCharacter",
	NoHumanoid = "NoHumanoid",
	NoRootPart = "NoRootPart",
	Dead = "Dead",
	CharacterReplacing = "CharacterReplacing",
	AlreadyLaunching = "AlreadyLaunching", -- PRE_LAUNCH
	AlreadyActive = "AlreadyActive", -- ACTIVE
	Ending = "Ending", -- ENDING
	OnCooldown = "OnCooldown",
	NotGrounded = "NotGrounded", -- NORMAL state but nothing under the feet (still falling)
	Training = "Training", -- a treadmill (fan) training session is running (TreadmillService)
	InvalidDirection = "InvalidDirection", -- not a Vector3, NaN, inf, or zero-length
	WallLockInvalid = "WallLockInvalid", -- wall gone, normal bad, character drifted off
	IntoWall = "IntoWall", -- failed the outward hemisphere test
	AntiCheat = "AntiCheat",
}

LaunchValidator.Reasons = table.freeze(Reasons)

export type Reason = string

export type Result = {
	Allowed: boolean,
	Reason: Reason?,
	--- Sanitized launch direction (unit, Y = 0). Present only when Allowed.
	Direction: Vector3?,
	--- The wall record the launch is leaving, when launching from WALL_LOCKED.
	WallRecord: WallLock.WallRecord?,
}

--- Rejections a state produces on its own, before anything else is checked.
--- NORMAL and WALL_LOCKED are absent because they are the launchable ones.
local STATE_REJECTIONS: { [TraversalState.State]: Reason } = {
	PRE_LAUNCH = Reasons.AlreadyLaunching,
	ACTIVE = Reasons.AlreadyActive,
	ENDING = Reasons.Ending,
}

local function reject(reason: Reason): Result
	return { Allowed = false, Reason = reason }
end

--- True when there is ground within LaunchGroundTolerance studs under the
--- character's feet (server raycast, the character itself excluded).
local function isGrounded(character: Model, rootPart: BasePart, humanoid: Humanoid): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local depth = humanoid.HipHeight + rootPart.Size.Y / 2 + ProbeConfig.LaunchGroundTolerance
	return Workspace:Raycast(rootPart.Position, Vector3.new(0, -depth, 0), params) ~= nil
end

--- Full authoritative check.
---
--- `requestedDirection` is the only client-supplied input, and it is treated
--- as a claim about INTENT, never about position or speed: it is type
--- checked, finite checked, flattened, normalized, and -- from a wall --
--- hemisphere checked, before anything downstream may use it. The launch
--- ORIGIN is never taken from it; ProbeService derives that from the
--- character's own replicated HumanoidRootPart.
---
--- @param player Player
--- @param requestedDirection any -- untrusted; typeof-checked here, not assumed
--- @return Result
function LaunchValidator.Validate(player: Player, requestedDirection: any): Result
	--== Identity / liveness =================================================--
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return reject(Reasons.NoPlayer)
	end

	local character = player.Character
	if not character or not character.Parent then
		return reject(Reasons.NoCharacter)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return reject(Reasons.NoHumanoid)
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return reject(Reasons.NoRootPart)
	end

	if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return reject(Reasons.Dead)
	end

	-- Mid-replacement: the model is still around but has already been
	-- detached from Workspace, so anything positional derived from it is
	-- about to be meaningless.
	if not character:IsDescendantOf(Workspace) then
		return reject(Reasons.CharacterReplacing)
	end

	--== State ===============================================================--
	local state = TraversalStateService.Get(player)
	local stateRejection = STATE_REJECTIONS[state]
	if stateRejection then
		return reject(stateRejection)
	end
	if not TraversalState.IsLaunchable(state) then
		-- Defensive: a state added later that nobody classified is refused
		-- rather than silently allowed.
		return reject(Reasons.AlreadyActive)
	end

	--== Budget ==============================================================--
	if TraversalStateService.GetCooldownRemaining(player) > 0 then
		return reject(Reasons.OnCooldown)
	end
	-- No launch from a trainer: the player walks out of the fan first
	if player:GetAttribute(TreadmillConfig.TrainingAttribute) ~= nil then
		return reject(Reasons.Training)
	end
	-- From NORMAL, only off the ground (a wall launch is the other launchable state)
	if state == TraversalState.NORMAL and not isGrounded(character, rootPart, humanoid) then
		return reject(Reasons.NotGrounded)
	end

	--== Direction ===========================================================--
	-- Two distinct cases, deliberately not collapsed into one fallback:
	--
	--   nil          -- no direction claimed at all. Falls back to the
	--                   character's own facing, which is SERVER data. This
	--                   preserves ProbeStartRequest's original contract,
	--                   where the hint was optional.
	--   anything else -- a direction WAS claimed, so it has to be usable.
	--                   Quietly substituting the character's facing for a
	--                   zero, NaN or infinite claim would mean a malformed
	--                   request still launches something, which is exactly
	--                   the "non-zero magnitude / no NaN / no infinity"
	--                   rule this validator exists to enforce.
	local launchDirection: Vector3
	if requestedDirection == nil then
		local fallback = TraversalGeometry.FlattenDirection(rootPart.CFrame.LookVector)
		if not fallback then
			return reject(Reasons.InvalidDirection)
		end
		launchDirection = fallback
	else
		if typeof(requestedDirection) ~= "Vector3" then
			return reject(Reasons.InvalidDirection)
		end
		local sanitized = TraversalGeometry.FlattenDirection(requestedDirection)
		if not sanitized then
			return reject(Reasons.InvalidDirection)
		end
		launchDirection = sanitized
	end

	--== Anti-cheat ==========================================================--
	-- The existing movement-sanity layer, asked rather than duplicated. A
	-- player already flagged for implausible movement does not get to start
	-- a mechanic that legitimately teleports their character around.
	if AntiCheatService.IsFlagged(player) then
		return reject(Reasons.AntiCheat)
	end

	--== Wall-specific rules (§7) ============================================--
	if state == TraversalState.WALL_LOCKED then
		local record = TraversalStateService.GetWallLock(player)
		if not record then
			return reject(Reasons.WallLockInvalid)
		end

		local valid, detail = WallLock.IsRecordValid(record, character)
		if not valid then
			log:Debug("%s: wall lock rejected (%s).", player.Name, tostring(detail))
			return reject(Reasons.WallLockInvalid)
		end

		if not TraversalGeometry.IsOutward(launchDirection, record.Normal) then
			return reject(Reasons.IntoWall)
		end

		return { Allowed = true, Direction = launchDirection, WallRecord = record }
	end

	return { Allowed = true, Direction = launchDirection }
end

return LaunchValidator
