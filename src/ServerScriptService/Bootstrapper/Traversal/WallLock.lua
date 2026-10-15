--!strict
--[[
	@module Traversal.WallLock
	@description Vertical-surface classification and the physical suspension
	of a character against one. Pure functions plus a CFrame write -- it
	owns no per-player state at all (TraversalStateService holds the lock
	record), so it can be called from the probe supervisor, the walk-back,
	and the cleanup path without any of them coordinating.

	The pure maths -- classification (§4) and the outward hemisphere (§7) --
	lives in ReplicatedStorage/Libraries/TraversalGeometry, because the
	client needs the identical functions to clamp aim and pre-check a
	launch. This module is the half that cannot be shared: raycasting the
	real surface, suspending a real character, and judging whether a lock is
	still real.

	The normal used here is always the SERVER'S own RaycastResult.Normal,
	taken from the same swept validation raycast that already decides where
	a probe stops. Nothing a client sends is ever classified.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TraversalConfig = require(ReplicatedStorage.Config.TraversalConfig)
local TraversalGeometry = require(ReplicatedStorage.Libraries.TraversalGeometry)

local WallLock = {}

--- Everything needed to (a) re-validate the lock later and (b) judge a
--- launch direction against it. Captured once, at lock time, from server
--- data only.
export type WallRecord = {
	--- The authoritative surface normal. Every gameplay decision about this
	--- lock reads THIS, never the avatar's orientation (which is cosmetic,
	--- see TraversalConfig.WallLock.FaceIntoWall).
	Normal: Vector3,
	--- Where the character was placed. Drift from it invalidates the lock.
	AnchorPosition: Vector3,
	--- The exact point on the surface the character is held off of.
	SurfacePosition: Vector3,
	--- The part that was hit, so a wall destroyed underneath a locked
	--- player can be detected and the lock dropped.
	Part: BasePart,
	LockedAt: number,
}

--============================================================================--
-- SUSPENSION
--============================================================================--

--- Re-finds the exact surface behind `fromPosition` along -normal and builds
--- the record for it. Done as its own raycast rather than reusing the
--- flight's hit point because the character ends the walk-back at a PADDED
--- stop (ProbeConfig.RaycastPadding) whose distance from the surface is
--- approximate -- measuring here is what guarantees the clearance below is
--- exact and the HumanoidRootPart is never embedded.
--- @param fromPosition Vector3 -- where the walk-back actually ended
--- @param normal Vector3 -- the validated wall normal
--- @param ignore { Instance } -- character/probe to exclude from the raycast
--- @return WallRecord? -- nil when the surface can no longer be found
function WallLock.BuildRecord(
	fromPosition: Vector3,
	normal: Vector3,
	ignore: { Instance }
): WallRecord?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true

	local reach = TraversalConfig.WallLock.SurfaceSearchDistance
	local result = Workspace:Raycast(fromPosition + normal * reach, -normal * (reach * 2), params)
	if not result or not TraversalGeometry.IsVerticalFace(result.Normal) then
		return nil
	end
	-- Only parts tagged "Vertical" can be grabbed.
	if not CollectionService:HasTag(result.Instance, "Vertical") then
		return nil
	end

	local surfacePosition = result.Position
	local anchorPosition = surfacePosition + result.Normal * TraversalConfig.WallLock.Clearance

	return {
		Normal = result.Normal,
		AnchorPosition = anchorPosition,
		SurfacePosition = surfacePosition,
		Part = result.Instance :: BasePart,
		LockedAt = os.clock(),
	}
end

--- Places `character` at the record's anchor point, upright, facing the wall
--- (or away from it, per config). The character is expected to already be
--- frozen by CharacterLock -- an Anchored root is what actually removes
--- residual velocity and keeps gravity from applying, so no constraint,
--- BodyMover or force is created here and none has to be cleaned up later.
--- @param character Model
--- @param record WallRecord
function WallLock.Suspend(character: Model, record: WallRecord): ()
	local facing = if TraversalConfig.WallLock.FaceIntoWall then -record.Normal else record.Normal
	local flatFacing = TraversalGeometry.FlattenDirection(facing)

	local pivot: CFrame
	if flatFacing then
		-- Upright: pure yaw, no pitch or roll, so the rig stands against the
		-- wall instead of lying along its normal.
		pivot = CFrame.lookAt(record.AnchorPosition, record.AnchorPosition + flatFacing)
	else
		pivot = CFrame.new(record.AnchorPosition) * character:GetPivot().Rotation
	end

	character:PivotTo(pivot)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- AutoRotate would fight the pivot above the moment anything nudges
		-- MoveDirection; restored by ReleaseSuspension.
		humanoid.AutoRotate = false
	end
end

--- Undoes everything Suspend changed on the character itself. Does NOT
--- unanchor -- whether the character stays frozen depends on what it is
--- transitioning to (a relaunch keeps it frozen, a death/cleanup releases it
--- via CharacterLock), and deciding that here would make one of those wrong.
--- @param character Model?
function WallLock.ReleaseSuspension(character: Model?): ()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
end

--- Is this lock still something the server is willing to launch from?
--- Re-checked at launch time rather than trusted from when it was taken:
--- the wall may have been destroyed, and the character may have been moved
--- by something outside this system.
--- @param record WallRecord
--- @param character Model
--- @return boolean, string? -- valid, failure detail for logging
function WallLock.IsRecordValid(record: WallRecord, character: Model): (boolean, string?)
	if not record.Part.Parent or not record.Part:IsDescendantOf(Workspace) then
		return false, "wall part no longer in Workspace"
	end
	if not TraversalGeometry.IsVerticalFace(record.Normal) then
		return false, "stored normal is not a vertical face"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false, "no HumanoidRootPart"
	end

	local drift = (rootPart.Position - record.AnchorPosition).Magnitude
	if drift > TraversalConfig.WallLock.MaxAnchorDrift then
		return false, string.format("character drifted %.1f studs from the anchor", drift)
	end

	return true
end

return WallLock
