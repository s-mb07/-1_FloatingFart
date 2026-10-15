--!strict
--[[
	@module TraversalGeometry
	@description The pure vector maths behind traversal surface
	classification and the outward launch hemisphere. Numbers in, booleans
	and vectors out -- no Instance, no DataModel, no side effects.

	Agnostic by the README §2 test, so it lives in ReplicatedStorage/Libraries
	rather than on one side: the SERVER enforces every rule here (it is the
	authority on which faces are walls and which launches are legal), and the
	CLIENT runs the exact same functions to clamp aim and pre-check a launch
	so its prediction cannot drift from what the server will decide. One
	implementation, two callers -- the alternative is two copies of a dot
	product that disagree at the boundary.

	The server-side `Traversal/WallLock` builds on this with everything that
	touches Instances (raycasting the surface, suspending the character);
	nothing in that direction is reachable from here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TraversalConfig = require(ReplicatedStorage.Config.TraversalConfig)
local Utils = require(ReplicatedStorage.Libraries.Utils)

local TraversalGeometry = {}

--- Is this a wall-lockable vertical side face? True when the normal is
--- approximately HORIZONTAL.
---
--- That one test is deliberately all there is (§4):
---   - it covers the Front/Back/Left/Right faces of a part at ANY rotation,
---     because a raycast normal is already in world space -- no world-axis
---     assumption and no face enumeration, so rotated parts work by
---     construction;
---   - it rejects floors and top faces (normal.Y ~ +1) and ceilings and
---     bottom faces (normal.Y ~ -1) without naming any of them;
---   - it never reads a part's Name, tag or attribute.
--- @param normal Vector3 -- a RaycastResult.Normal, world space
--- @return boolean
function TraversalGeometry.IsVerticalFace(normal: Vector3): boolean
	return math.abs(normal.Y) <= TraversalConfig.Surface.VerticalNormalTolerance
end

--- Is this a horizontal surface a character can rest on? Used to decide
--- whether a landing counts as "successfully on a platform" for stamina
--- restoration. NOT the complement of IsVerticalFace: a steep ramp is
--- neither, and behaves as neither.
--- @param normal Vector3 -- a RaycastResult.Normal, world space
--- @return boolean
function TraversalGeometry.IsPlatformSurface(normal: Vector3): boolean
	return normal.Y >= TraversalConfig.Surface.PlatformNormalMinY
end

--- Flattens to the XZ plane and normalizes, or returns nil when nothing
--- usable survives: a non-finite component, a zero vector, or an aim so
--- close to straight up/down that its horizontal part is noise.
---
--- Every direction either side acts on passes through here, which is what
--- makes "reject NaN, infinity and zero-length" a single implementation
--- rather than a check each caller remembers or forgets.
--- @param vector Vector3
--- @return Vector3? -- unit, Y = 0
function TraversalGeometry.FlattenDirection(vector: Vector3): Vector3?
	-- NaN fails every comparison and infinity survives them, so both are
	-- caught by demanding each component be finite BEFORE any arithmetic --
	-- normalizing first would turn NaN into more NaN and hide it.
	for _, component in { vector.X, vector.Y, vector.Z } do
		if component ~= component or component == math.huge or component == -math.huge then
			return nil
		end
	end

	local flat = Utils.Vector.FlattenY(vector)
	if flat.Magnitude < TraversalConfig.Launch.MinDirectionMagnitude then
		return nil
	end
	return flat.Unit
end

--- The outward-hemisphere test (§7). A launch off a wall is legal when it
--- points into the half-space the wall's normal faces:
---
---     launchDir:Dot(wallDir) >= TraversalConfig.Launch.WallDotTolerance
---
--- with both vectors flattened to XZ first, so vertical aim never decides
--- legality -- pitch is deliberately unconstrained.
---
--- Straight out, out-left, out-right and parallel-to-the-wall all pass;
--- anything pointing back into the surface fails.
--- @param launchDirection Vector3
--- @param wallNormal Vector3
--- @return boolean
function TraversalGeometry.IsOutward(launchDirection: Vector3, wallNormal: Vector3): boolean
	local launchDir = TraversalGeometry.FlattenDirection(launchDirection)
	local wallDir = TraversalGeometry.FlattenDirection(wallNormal)
	if not launchDir or not wallDir then
		-- A degenerate wall normal is not something this system can reason
		-- about; refuse rather than let every direction through.
		return false
	end
	return launchDir:Dot(wallDir) >= TraversalConfig.Launch.WallDotTolerance
end

--- The nearest legal direction to `launchDirection` for this wall: the input
--- unchanged when it already passes, otherwise its projection onto the wall
--- plane -- slid to the hemisphere boundary, keeping whichever way along the
--- wall the player was aiming.
---
--- The CLIENT uses this so aim cannot point through the wall (UX only). The
--- SERVER never uses it to fix up a request -- it uses IsOutward to REJECT,
--- so a modified client that skips the clamp is refused rather than
--- silently corrected.
--- @param launchDirection Vector3
--- @param wallNormal Vector3
--- @return Vector3? -- unit and Y = 0, or nil when nothing usable survives
function TraversalGeometry.ClampOutward(launchDirection: Vector3, wallNormal: Vector3): Vector3?
	local launchDir = TraversalGeometry.FlattenDirection(launchDirection)
	local wallDir = TraversalGeometry.FlattenDirection(wallNormal)
	if not launchDir or not wallDir then
		return nil
	end

	local dot = launchDir:Dot(wallDir)
	if dot >= TraversalConfig.Launch.WallDotTolerance then
		return launchDir
	end

	-- Strip the inward component, leaving only the along-the-wall part.
	local projected = launchDir - wallDir * dot
	if projected.Magnitude < TraversalConfig.Launch.MinDirectionMagnitude then
		-- Aimed exactly at the wall: there is no left/right sense left to
		-- preserve, so straight out is the only sensible answer.
		return wallDir
	end
	return projected.Unit
end

return TraversalGeometry
