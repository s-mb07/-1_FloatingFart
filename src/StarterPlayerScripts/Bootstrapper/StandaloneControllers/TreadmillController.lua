--!strict
--[[
	@module TreadmillController
	@description Purely cosmetic client side of the treadmill (the Fans): while
	the local player stands in a tagged treadmill Hitbox (TagNames.Treadmill)
	AND the server runs a training session for them (player attribute
	TreadmillConfig.TrainingAttribute set -- a fan whose access rule is not
	met never sets it, so a locked fan never looks like it trains)
	  - the character floats at the height of the middle of the Hitbox, as if
	    flying: the Humanoid HipHeight is raised just enough, so walking out
	    of the hitbox still works and nothing fights the physics.
	The surf motion on top of the float (waves, per-fan tricks) is
	SurfController's.
	Fires EventBus.Traversal.TreadmillActive on enter/leave. The "+N exp" for
	each grant is shown by XPGainController, not here. The fan blades turn in
	SpinController.

	XP itself is granted by TreadmillService the moment the player enters and
	every second after -- nothing here grants or validates anything. The Fly
	idle pose is played by the server too (TreadmillService), so the animation
	has a single author and never loops for the other players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EventBus = require(script.Parent.Parent.Events.EventBus)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)

local log = Logger.new("TreadmillController")
local TreadmillController = {}

local LocalPlayer = Players.LocalPlayer

--- Distance (studs) searched under the character for the floor.
local FLOOR_SEARCH = 60

type Hold = {
	Humanoid: Humanoid,
	Root: BasePart,
	Hitbox: BasePart,
	BaseHipHeight: number,
	Params: RaycastParams,
	Connection: RBXScriptConnection,
}

local hold: Hold? = nil
-- The fan Hitbox the local player stands in (nil = none), even while the
-- flight owns the character: the float resumes at NORMAL.
local zone: BasePart? = nil
-- False while the flight mechanic owns the character: a fan then does nothing
-- (no float, no idle animation of its own over the flight's).
local free = true

local function stopRun(): ()
	local active = hold
	if not active then
		return
	end
	hold = nil
	active.Connection:Disconnect()
	if active.Humanoid.Parent then
		active.Humanoid.HipHeight = active.BaseHipHeight
	end
	EventBus.Traversal.TreadmillActive:Fire(false)
end

local function step(): ()
	local active = hold
	if not active then
		return
	end
	if not active.Root.Parent or not active.Hitbox.Parent then
		stopRun()
		return
	end

	-- Float so the root sits at the middle of the hitbox: how high it would
	-- stand on the floor, compared to that height.
	local lift = 0
	local floor =
		Workspace:Raycast(active.Root.Position, Vector3.new(0, -FLOOR_SEARCH, 0), active.Params)
	if floor then
		local standingY = floor.Position.Y + active.BaseHipHeight + active.Root.Size.Y / 2
		lift = math.max(0, active.Hitbox.Position.Y - standingY)
	end

	active.Humanoid.HipHeight = active.BaseHipHeight + lift
end

local function isTraining(): boolean
	return LocalPlayer:GetAttribute(TreadmillConfig.TrainingAttribute) ~= nil
end

local function startRun(hitbox: BasePart): ()
	stopRun()
	if not free or not isTraining() then
		return
	end

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root and root:IsA("BasePart")) then
		log:Warn("Treadmill '%s' unusable: missing character.", hitbox:GetFullName())
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true

	hold = {
		Humanoid = humanoid,
		Root = root,
		Hitbox = hitbox,
		BaseHipHeight = humanoid.HipHeight,
		Params = params,
		Connection = RunService.Heartbeat:Connect(step),
	}
	EventBus.Traversal.TreadmillActive:Fire(true)
end

function TreadmillController:Init(): ()
	log:Info("Initialized.")
end

function TreadmillController:Start(): ()
	PadTrigger.Bind(TagNames.Treadmill, {
		Padding = 0, -- same zone as the server grant
		OnEnter = function(_player: Player, hitbox: BasePart): ()
			zone = hitbox
			startRun(hitbox)
		end,
		OnLeave = function(): ()
			zone = nil
			stopRun()
		end,
	})

	-- The flight takes the character over: the fan float must not fight it
	-- from the first frame of the launch. Back at NORMAL inside a fan (flight
	-- cut by it, or a launch that ended on it): the float resumes.
	EventBus.Traversal.StateChanged:Connect(function(player: Player, newState: string): ()
		if player ~= LocalPlayer then
			return
		end
		free = newState == "NORMAL"
		if not free then
			stopRun()
		elseif zone then
			startRun(zone)
		end
	end)

	-- The server confirms (or ends) the session: the training look follows it.
	LocalPlayer:GetAttributeChangedSignal(TreadmillConfig.TrainingAttribute):Connect(function(): ()
		if isTraining() and zone then
			startRun(zone)
		elseif not isTraining() then
			stopRun()
		end
	end)

	log:Info("Started.")
end

return TreadmillController
