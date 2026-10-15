--!strict
--[[
	@module Effects.Stage
	@description Staging of the subject presented by a recipe (object reveal).

	The model is cloned far above the map: nothing occludes it, no other
	player sees it lying around, and there's no geometry to work around to
	frame it. Every Camera exit path goes through `Stage.Clear`, so the
	clone can never survive an interrupted cinematic.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Stage = {}

local STAGE_ORIGIN = CFrame.new(0, 5000, 0)
local FOLDER_NAME = "EffectsStage"

local folder: Folder? = nil
local staged: Model? = nil
local stagedPivot: CFrame = STAGE_ORIGIN

local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	return created
end

--- Looks for `name` anywhere under ReplicatedStorage/Assets (Sticks/, Models/...).
local function findAsset(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end

	local found = assets:FindFirstChild(name, true)
	if not found or not found:IsA("Model") then
		return nil
	end
	return found
end

--- Stages the subject and returns its pivot, or nil if there's nothing to present.
--- @param subject (string | Model)? Asset name to clone, or an already-instantiated model
function Stage.Setup(subject: (string | Model)?): CFrame?
	Stage.Clear()
	if not subject then return nil end

	local model: Model?
	if typeof(subject) == "Instance" then
		model = (subject :: Model):Clone()
	else
		local template = findAsset(subject :: string)
		if not template then
			warn("[Effects] Subject not found under Assets: " .. (subject :: string))
			return nil
		end
		model = template:Clone()
	end

	local resolved = model :: Model
	for _, descendant in resolved:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	resolved:PivotTo(STAGE_ORIGIN)
	resolved.Parent = ensureFolder()

	staged = resolved
	stagedPivot = STAGE_ORIGIN
	return STAGE_ORIGIN
end

--- The subject's current pivot, or nil if there's no active staging.
function Stage.GetPivot(): CFrame?
	if not staged then return nil end
	return stagedPivot
end

--- Spins the subject around its vertical axis (used by TravelSpec.SpinDegrees).
--- @param degrees number Absolute angle from the starting orientation
function Stage.SetSpin(degrees: number): ()
	local model = staged
	if not model then return end

	stagedPivot = STAGE_ORIGIN * CFrame.Angles(0, math.rad(degrees), 0)
	model:PivotTo(stagedPivot)
end

--- Destroys the staged subject. Idempotent: callable from any Camera exit
--- path without checking whether staging is currently active.
function Stage.Clear(): ()
	local model = staged
	if model then
		model:Destroy()
		staged = nil
	end
	stagedPivot = STAGE_ORIGIN
end

return Stage
