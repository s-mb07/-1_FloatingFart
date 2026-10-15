--!strict
--[[
	@module FlyModelService
	@description Puts the rigged `Fly` model on every character's back (config:
	Config/FlyConfig). The rig ReplicatedStorage.Assets.Player.AnimationFly
	already holds the model joined to its UpperTorso by a Motor6D; here the
	same joint (same name, same C0/C1) is recreated on the live character, so
	the animations authored on that rig drive the model like part of the
	player. The model is purely cosmetic -- non-colliding, massless, not
	queryable -- except its front Attachment, which the flight reads.

	Skins (Assets.Skins.<Id>): the model never changes, only its mesh part.
	  - New format: the folder holds a MeshPart with its children. The mesh is
	    applied at the rig's size and its children replace the cube's, scaled
	    by the same factor and welded (see applySkinMesh).
	  - Old format: MeshId NumberValue + SurfaceAppearance (no SurfaceAppearance
	    = the plain base look).
	TrailColor (Color3Value) in the folder colours the wing trails, both formats.
]]

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FlyConfig = require(ReplicatedStorage.Config.FlyConfig)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local PlayerService = require(script.Parent.PlayerService)
local SkinConfig = require(ReplicatedStorage.Config.SkinConfig)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)

local log = Logger.new("FlyModelService")
local FlyModelService = {}

local function getRig(): Model?
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local folder = assets and assets:WaitForChild("Player", 10)
	local rig = folder and folder:WaitForChild(FlyConfig.RigName, 10)
	return if rig and rig:IsA("Model") then rig else nil
end

local function makeCosmetic(model: Instance): ()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

-- Size of the rig's own mesh part, recorded once: every skin mesh is resized
-- back to it so a different mesh never changes the model's dimensions.
local baseSize: Vector3? = nil
-- One loaded MeshPart per mesh id (skins can share a mesh).
local meshParts: { [number]: MeshPart } = {}

local function getMeshPart(meshId: number): MeshPart?
	local cached = meshParts[meshId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync("rbxassetid://" .. meshId)
	end)
	if not ok then
		log:Warn("Cannot load mesh %d: %s", meshId, tostring(result))
		return nil
	end
	meshParts[meshId] = result
	return result
end

-- Marks what a skin added under the cube, so the next skin removes it.
local SKIN_PART_ATTRIBUTE = "SkinPart"

local function scaleBy(v: Vector3, s: Vector3): Vector3
	return Vector3.new(v.X * s.X, v.Y * s.Y, v.Z * s.Z)
end

--- New skin format: Assets.Skins.<Id> holds a MeshPart with its children
--- (VFX parts, textures, SurfaceAppearance...). The cube takes its mesh at the
--- rig's size; every child is cloned onto the cube, and each BasePart (any
--- depth) is resized and repositioned by the same factor the mesh went
--- through (rig size / source size), then held by a Weld to the cube so the
--- animated model carries it without any physics.
local function applySkinMesh(cube: MeshPart, source: MeshPart, size: Vector3): ()
	for _, child in cube:GetChildren() do
		child:Destroy()
	end
	cube:ApplyMesh(source)
	cube.Size = size

	local scale = Vector3.new(size.X / source.Size.X, size.Y / source.Size.Y, size.Z / source.Size.Z)
	local copy = source:Clone()
	for _, d in copy:GetDescendants() do
		CollectionService:RemoveTag(d, TagNames.SkinShow)
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = copy.CFrame:ToObjectSpace(d.CFrame)
			-- Size along the part's own axes = length of each scaled axis.
			local partScale = Vector3.new(
				scaleBy(rel.RightVector, scale).Magnitude,
				scaleBy(rel.UpVector, scale).Magnitude,
				scaleBy(-rel.LookVector, scale).Magnitude
			)
			d.Size = scaleBy(d.Size, partScale)
			for _, a in d:GetChildren() do
				if a:IsA("Attachment") then
					a.Position = scaleBy(a.Position, partScale)
				end
			end
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			local weld = Instance.new("Weld")
			weld.Part0 = cube
			weld.Part1 = d
			weld.C0 = CFrame.new(scaleBy(rel.Position, scale)) * rel.Rotation
			weld.Parent = d
		elseif d:IsA("Attachment") and d.Parent == copy then
			d.Position = scaleBy(d.Position, scale)
		end
	end
	for _, child in copy:GetChildren() do
		child:SetAttribute(SKIN_PART_ATTRIBUTE, true)
		child.Parent = cube
	end
	copy:Destroy()
end

--- A skin = its mesh (Assets.Skins.<Id>.MeshId NumberValue, applied then
--- resized to the rig's original size) + its SurfaceAppearance
--- (Assets.Skins.<Id>.SurfaceAppearance). A skin folder without a SurfaceAppearance
--- means the model has NO SurfaceAppearance at all (plain base look); without a
--- MeshId the mesh is left as is.
local function applySkin(player: Player, character: Model): ()
	local fly = character:FindFirstChild(FlyConfig.ModelName)
	local cube = fly and fly:FindFirstChild(FlyConfig.JointName)
	if not (cube and cube:IsA("MeshPart")) then
		return
	end

	local id = player:GetAttribute(SkinConfig.EquippedAttribute)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local skins = assets and assets:FindFirstChild("Skins")
	local skinFolder = skins
		and skins:FindFirstChild(if type(id) == "string" then id else SkinConfig.Default)
	local wanted = skinFolder and skinFolder:FindFirstChildOfClass("SurfaceAppearance")
	local meshValue = skinFolder and skinFolder:FindFirstChild("MeshId")
	local source = skinFolder and skinFolder:FindFirstChildWhichIsA("MeshPart")

	if source then
		applySkinMesh(cube, source, baseSize or cube.Size)
	else
		-- Old format (MeshId + SurfaceAppearance), kept until every skin folder holds a MeshPart.
		if meshValue and meshValue:IsA("NumberValue") and meshValue.Value > 0 then
			local meshPart = getMeshPart(meshValue.Value)
			-- The load yields: drop the result if the skin changed or the model went away meanwhile.
			if player:GetAttribute(SkinConfig.EquippedAttribute) ~= id or not cube:IsDescendantOf(character) then
				return
			end
			if meshPart then
				cube:ApplyMesh(meshPart)
				if baseSize then
					cube.Size = baseSize
				end
			end
		end
		for _, child in cube:GetChildren() do
			if child:IsA("SurfaceAppearance") or child:GetAttribute(SKIN_PART_ATTRIBUTE) then
				child:Destroy()
			end
		end
		if wanted then
			wanted:Clone().Parent = cube
		end
	end

	local trailValue = skinFolder and skinFolder:FindFirstChild("TrailColor")
	local color = if trailValue and trailValue:IsA("Color3Value") then trailValue.Value else Color3.new(1, 1, 1)
	for _, trail in fly:GetDescendants() do
		if trail:IsA("Trail") then
			trail.Color = ColorSequence.new(color)
		end
	end
end

--- One thin Trail per wing-tip Attachment, off until the flight is ACTIVE.
local function addTrails(fly: Model): ()
	if not FlyConfig.TrailsEnabled then
		return
	end
	for _, name in FlyConfig.WingAttachmentNames do
		local wing = fly:FindFirstChild(name, true)
		if wing and wing:IsA("Attachment") then
			local tip = Instance.new("Attachment")
			tip.Name = name .. "TrailEnd"
			tip.CFrame = wing.CFrame * CFrame.new(0, FlyConfig.TrailWidth, 0)
			tip.Parent = wing.Parent
			local trail = Instance.new("Trail")
			trail.Attachment0 = wing
			trail.Attachment1 = tip
			trail.Lifetime = FlyConfig.TrailLifetime
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Transparency = NumberSequence.new(0, 1)
			trail.Enabled = false
			trail.Parent = wing
		else
			log:Warn("Fly model has no '%s' attachment.", name)
		end
	end
end

--- Trails burn only while the flight is ACTIVE (not while preparing / stowing).
local function setTrails(player: Player, enabled: boolean): ()
	local fly = player.Character and player.Character:FindFirstChild(FlyConfig.ModelName)
	if not fly then
		return
	end
	for _, trail in fly:GetDescendants() do
		if trail:IsA("Trail") then
			trail.Enabled = enabled
		end
	end
end

local function attach(player: Player, character: Model): ()
	local upperTorso = character:WaitForChild("UpperTorso", 10)
	local rig = getRig()
	if not (upperTorso and upperTorso:IsA("BasePart") and rig) then
		log:Warn("%s: cannot attach the Fly model (no UpperTorso or rig).", player.Name)
		return
	end
	local rigJoint = rig:FindFirstChild("UpperTorso")
		and rig.UpperTorso:FindFirstChild(FlyConfig.JointName)
	local template = rig:FindFirstChild(FlyConfig.ModelName)
	if not (rigJoint and rigJoint:IsA("Motor6D") and template) then
		log:Warn("Rig '%s' is missing the Fly model or its joint.", rig:GetFullName())
		return
	end

	-- Re-apply cleanly (respawn keeps nothing, but a second call must not stack).
	local old = character:FindFirstChild(FlyConfig.ModelName)
	if old then
		old:Destroy()
	end
	local oldJoint = upperTorso:FindFirstChild(FlyConfig.JointName)
	if oldJoint then
		oldJoint:Destroy()
	end

	local fly = template:Clone()
	fly.Name = FlyConfig.ModelName
	makeCosmetic(fly)
	local cube = fly:FindFirstChild(FlyConfig.JointName)
	if not (cube and cube:IsA("BasePart")) then
		fly:Destroy()
		log:Warn("Fly model has no '%s' part.", FlyConfig.JointName)
		return
	end

	baseSize = baseSize or (template:FindFirstChild(FlyConfig.JointName) :: BasePart).Size

	local joint = Instance.new("Motor6D")
	joint.Name = FlyConfig.JointName
	joint.Part0 = upperTorso
	joint.Part1 = cube
	joint.C0 = rigJoint.C0
	joint.C1 = rigJoint.C1
	joint.Parent = upperTorso
	addTrails(fly)
	fly.Parent = character

	applySkin(player, character)
end

local function watchPlayer(player: Player): ()
	local function onCharacter(character: Model): ()
		attach(player, character)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	-- The saved skin arrives with the profile, later than the first spawn.
	player:GetAttributeChangedSignal(SkinConfig.EquippedAttribute):Connect(function()
		if player.Character then
			applySkin(player, player.Character)
		end
	end)
end

function FlyModelService:Init(): ()
	log:Info("Initialized.")
end

function FlyModelService:Start(): ()
	GameEvents.OnPlayerRegistered:Connect(watchPlayer)
	GameEvents.OnTraversalStateChanged:Connect(function(player: Player, newState: string)
		setTrails(player, newState == TraversalState.ACTIVE)
	end)
	for _, player in PlayerService.GetRegisteredPlayers() do
		watchPlayer(player)
	end
end

return FlyModelService
