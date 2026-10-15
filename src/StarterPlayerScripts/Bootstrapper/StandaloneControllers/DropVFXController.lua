--!strict
--[[
	@module DropVFXController
	@description Landing puff, for EVERY player (everyone sees everyone's).
	Assets/VFX/Player/DropVFX (an Attachment of disabled ParticleEmitters) is
	cloned once per character into the HumanoidRootPart, just above the feet,
	so it follows the model. It bursts when a player actually TOUCHES THE
	GROUND after their flight ended -- not at the stop itself: leaving the
	ACTIVE traversal state arms it (Traversal.StateChanged is broadcast for
	every player), a short ray under the feet fires it. A new launch or a
	respawn disarms it.

	Feet height is read from the rig, not hard-coded, so any skin works:
	R15 -> HipHeight + half the root height (Roblox's own root-to-sole
	distance, follows body scaling); R6 (HipHeight 0) -> lowest character part.
	The ground test is a raycast, not Humanoid.FloorMaterial, because that
	property is only reliable on the client that simulates the character.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerVFX = require(Bootstrapper.Libraries.PlayerVFX)

local DropVFXController = {}

--- Studs above the sole where the puff spawns.
local FOOT_LIFT = 0.3
--- Ray reach below the soles that still counts as "on the ground".
local GROUND_TOLERANCE = 0.6
--- Another player's puff is skipped beyond this distance from the camera.
local VFX_DISTANCE = 300

local attachments: { [Player]: Attachment } = {}
local watchers: { [Player]: RBXScriptConnection } = {}

local function disarm(player: Player): ()
	local watcher = watchers[player]
	if watcher then
		watcher:Disconnect()
		watchers[player] = nil
	end
end

--- Y offset of the soles relative to the HumanoidRootPart centre (negative).
local function soleOffset(character: Model, root: BasePart, humanoid: Humanoid): number
	if humanoid.HipHeight > 0 then
		return -(humanoid.HipHeight + root.Size.Y / 2)
	end
	local lowest = 0
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			lowest = math.min(lowest, root.CFrame:PointToObjectSpace(part.Position).Y - part.Size.Y / 2)
		end
	end
	return lowest
end

--- The character's rig parts, or nil while it is not ready / is gone.
local function rigOf(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and root and root:IsA("BasePart") then
		return character, root, humanoid
	end
	return nil, nil, nil
end

--- True when something solid is right under the player's soles.
local function onGround(player: Player): boolean
	local character, root, humanoid = rigOf(player)
	if not (character and root and humanoid) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	local reach = -soleOffset(character, root, humanoid) + GROUND_TOLERANCE
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

local function emitAtFeet(player: Player): ()
	local character, root, humanoid = rigOf(player)
	local attachment = attachments[player]
	if not (attachment and attachment.Parent == root and character and root and humanoid) then
		return
	end
	if player ~= Players.LocalPlayer then
		local camera = workspace.CurrentCamera
		if camera and (root.Position - camera.CFrame.Position).Magnitude > VFX_DISTANCE then
			return
		end
	end
	attachment.Position = Vector3.new(0, soleOffset(character, root, humanoid) + FOOT_LIFT, 0)
	PlayerVFX.Burst(attachment)
end

local function arm(player: Player): ()
	disarm(player)
	watchers[player] = RunService.Heartbeat:Connect(function()
		if onGround(player) then
			disarm(player)
			emitAtFeet(player)
		end
	end)
end

local function onCharacter(player: Player, character: Model): ()
	disarm(player)
	attachments[player] = nil
	local folder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild("Player")
	local template = folder:WaitForChild("DropVFX")
	local root = character:WaitForChild("HumanoidRootPart")
	if player.Character ~= character then
		return -- respawned while the assets were loading
	end
	local clone = template:Clone()
	clone.Parent = root
	attachments[player] = clone :: Attachment
end

local function track(player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function DropVFXController:Init(): () end

function DropVFXController:Start(): ()
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		disarm(player)
		attachments[player] = nil
	end)

	EventBus.Traversal.StateChanged:Connect(function(player: Player, newState: string, previousState: string)
		if newState == TraversalState.ACTIVE or newState == TraversalState.PRE_LAUNCH then
			disarm(player)
		elseif previousState == TraversalState.ACTIVE then
			arm(player) -- the flight just ended: wait for the feet to touch down
		end
	end)
end

return DropVFXController
