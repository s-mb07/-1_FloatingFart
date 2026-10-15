--!strict
--[[
	@module SpinController
	@description Endless cosmetic rotation of tagged world objects, client side
	only (nothing here is gameplay):
	  - TagNames.Fan      : the model's `Rotation` child spins around the green
	                        (Y) axis of its PrimaryPart, fast.
	  - TagNames.SkinShow : each tagged part spins around its blue (Z) axis, all at the same,
	                        slower speed. It is the anchored PrimaryPart of a
	                        showcase Model; the Model's other parts are welded
	                        to it (unanchored), so they turn with it.
	Speeds: Config/SpinConfig. Objects streamed in later are picked up through
	the tag's added signal; each keeps its original pivot so the angle is
	absolute (no drift).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local SpinConfig = require(script.Parent.Parent.Config.SpinConfig)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)

local log = Logger.new("SpinController")
local SpinController = {}

type Spinner = {
	Target: PVInstance,
	--- Frame whose own axes the spin follows (the PrimaryPart of a fan), and
	--- the target's pivot expressed in that frame: both captured once, so the
	--- angle is absolute and a PivotOffset on the part cannot skew the axis.
	Reference: CFrame,
	PivotInReference: CFrame,
	Axis: Vector3,
	Speed: number,
}

local spinners: { [Instance]: Spinner } = {}
--- Fans still waiting for their reference part (streaming), by fan.
local waiting: { [Instance]: RBXScriptConnection } = {}

local function add(
	key: Instance,
	target: PVInstance,
	reference: CFrame,
	axis: Vector3,
	speed: number
): ()
	spinners[key] = {
		Target = target,
		Reference = reference,
		PivotInReference = reference:ToObjectSpace(target:GetPivot()),
		Axis = axis,
		Speed = speed,
	}
end

local function addFan(fan: Instance): ()
	local rotation = fan:FindFirstChild(SpinConfig.FanRotationModel)
	if not (rotation and rotation:IsA("Model")) then
		log:Warn("Fan '%s' has no '%s' model.", fan:GetFullName(), SpinConfig.FanRotationModel)
		return
	end
	-- The reference part is looked up BY NAME, not through Model.PrimaryPart:
	-- on a client with streaming that reference can still be nil while the
	-- part itself is already here -- or arrive a moment later.
	local function tryAdd(): boolean
		local primary = rotation:FindFirstChild(SpinConfig.FanPrimaryName, true)
		if primary and primary:IsA("BasePart") then
			add(fan, rotation, primary.CFrame, SpinConfig.FanAxis, SpinConfig.FanSpeed)
			return true
		end
		return false
	end
	if tryAdd() then
		return
	end
	waiting[fan] = rotation.DescendantAdded:Connect(function(): ()
		if tryAdd() and waiting[fan] then
			waiting[fan]:Disconnect()
			waiting[fan] = nil
		end
	end)
end

local function addShow(part: Instance): ()
	-- Only the lobby showcases: the skin MeshParts in ReplicatedStorage carry the
	-- same tag (copied from the showcase) and must not spin.
	if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
		add(part, part, part.CFrame, SpinConfig.SkinShowAxis, SpinConfig.SkinShowSpeed)
	end
end

local function bind(tag: string, handler: (Instance) -> ()): ()
	for _, instance in CollectionService:GetTagged(tag) do
		handler(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(handler)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		spinners[instance] = nil
		local pending = waiting[instance]
		if pending then
			pending:Disconnect()
			waiting[instance] = nil
		end
	end)
end

function SpinController:Init(): ()
	log:Info("Initialized.")
end

function SpinController:Start(): ()
	bind(TagNames.Fan, addFan)
	bind(TagNames.SkinShow, addShow)

	local startClock = os.clock()
	RunService.RenderStepped:Connect(function(): ()
		local elapsed = os.clock() - startClock
		for _, spinner in spinners do
			if spinner.Target.Parent then
				local angle = math.rad(elapsed * spinner.Speed) % (2 * math.pi)
				spinner.Target:PivotTo(
					spinner.Reference
						* CFrame.fromAxisAngle(spinner.Axis, angle)
						* spinner.PivotInReference
				)
			end
		end
	end)
	log:Info("Started.")
end

return SpinController
