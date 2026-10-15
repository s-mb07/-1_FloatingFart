--!strict
--[[
	@module Traversal.LaunchClearance
	@description Keeps a launch from starting straight into a part: the
	heading the player aims at is checked (sphere casts, level and along the
	launch arc) and, when blocked, turned to the nearest free heading.

	Server-only: the server owns the character's facing during the Start
	sequence (it is anchored), so the server is the one place this decides.
	The client just streams its camera aim; it never picks the heading.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FlyConfig = require(ReplicatedStorage.Config.FlyConfig)
local ProbeConfig = require(ReplicatedStorage.Config.ProbeConfig)
local TraversalGeometry = require(ReplicatedStorage.Libraries.TraversalGeometry)

local LaunchClearance = {}

local function buildParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	-- Behave like a character: other players never block a launch.
	params.CollisionGroup = FlyConfig.PlayerCollisionGroup
	return params
end

local function isClear(origin: Vector3, flat: Vector3, params: RaycastParams): boolean
	local pitch = math.rad(ProbeConfig.LaunchPitchDegrees)
	local arc = flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
	for _, direction in { flat, arc } do
		if
			Workspace:Spherecast(
				origin,
				FlyConfig.ClearanceRadius,
				direction * FlyConfig.ClearanceDistance,
				params
			)
		then
			return false
		end
	end
	return true
end

--- The free heading closest to `desired`: `desired` itself when clear,
--- otherwise rotated by ClearanceStepDegrees steps, alternating sides. From a
--- wall (`wallNormal`), only outward headings are candidates. When nothing is
--- free, `desired` is returned unchanged.
--- @param character Model -- excluded from the casts
--- @param origin Vector3 -- launch point (the root)
--- @param desired Vector3 -- unit, Y = 0
--- @param wallNormal Vector3? -- set when launching off a wall
--- @return Vector3 -- unit, Y = 0
function LaunchClearance.FindClearDirection(
	character: Model,
	origin: Vector3,
	desired: Vector3,
	wallNormal: Vector3?
): Vector3
	local params = buildParams(character)
	local step = math.rad(FlyConfig.ClearanceStepDegrees)
	local steps = math.floor(math.pi / step)
	for i = 0, steps do
		for _, sign in (if i == 0 then { 1 } else { 1, -1 }) :: { number } do
			local candidate = CFrame.Angles(0, sign * i * step, 0):VectorToWorldSpace(desired)
			local outward = wallNormal == nil
				or TraversalGeometry.IsOutward(candidate, wallNormal :: Vector3)
			if outward and isClear(origin, candidate, params) then
				return candidate
			end
		end
	end
	return desired
end

return LaunchClearance
