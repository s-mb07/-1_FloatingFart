--!strict
--[[
	@module TutorialController
	@description Display side of the new-player tutorial (TutorialConfig):
	  - the guide banner: the Studio-authored StarterGui "TutorialGuide"
	    (Banner > Step/Label "STEP n/N", Title > Shadow + Text, Swoosh plane).
	    This module only drives it: texts, visibility, animations. A stage
	    change pops the banner out and back in while the Swoosh plane flies
	    across it; a progress-only change ("(1/3)" -> "(2/3)") just bounces
	    the title;
	  - a guide path from the CENTER of the player (HumanoidRootPart) to the
	    CENTER of the stage's target (a tagged BasePart, or a tagged Model's
	    bounding box): the studio-authored ReplicatedStorage/Assets/VFX/Tutorial
	    Beam (scrolling chevrons) cloned client-side only. Its two attachments
	    live in Workspace.Terrain and are re-placed every frame, oriented so
	    the ribbon stays flat (a Beam's width follows its attachments' Y axis).
	    The target itself is looked up RefreshHz times a second.
	Server-truth: the stage comes from the `Tutorial` data snapshot;
	TutorialService alone advances it. Nothing here grants or validates.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local TutorialConfig = require(ReplicatedStorage.Config.TutorialConfig)
local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local TutorialController = {}

local LocalPlayer = Players.LocalPlayer

--- Closer than this (studs) to the target's center: no path, you are there.
local MIN_PATH_LENGTH = 5

local stage = TutorialConfig.GetFinishedStage()
local level = 1

-- Banner (PlayerGui/TutorialGuide, resolved in Start)
local banner: GuiObject? = nil
local title: GuiObject? = nil
local titleLabels: { TextLabel } = {}
local stepLabel: TextLabel? = nil
local plane: GuiObject? = nil
local shownStage: number? = nil
local shownTitle = ""

-- Guide path: both attachments in Terrain, re-placed every frame
local guideStart: Attachment? = nil
local guideEnd: Attachment? = nil
local guideTarget: Instance? = nil
local guideLoop: RBXScriptConnection? = nil

--============================================================================--
-- BANNER
--============================================================================--

local function setTitle(text: string): ()
	for _, label in titleLabels do
		label.Text = text
	end
end

local function setStep(): ()
	if stepLabel then
		stepLabel.Text = ("STEP %d/%d"):format(stage, #TutorialConfig.Stages)
	end
end

--- Swoosh plane flying across the banner, left to right, slightly climbing.
local function swoosh(): ()
	local icon = plane
	if not icon then
		return
	end
	icon.Position = UDim2.fromScale(-0.1, 0.85)
	icon.Rotation = -10
	icon.Visible = true
	local tween = TweenService:Create(
		icon,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Position = UDim2.fromScale(1.1, 0.35), Rotation = 8 }
	)
	tween.Completed:Once(function()
		icon.Visible = false
	end)
	tween:Play()
end

local function render(): ()
	local root = banner
	if not root then
		return -- shown once the banner resolves (bindBanner calls render)
	end
	local def = TutorialConfig.Stages[stage]
	if not def then
		shownStage = nil
		shownTitle = ""
		if root.Visible then
			UXEffects.Scale.popOut(root, { duration = 0.25 })
		end
		return
	end

	local progress = if stage == 2 then math.min(level, TutorialConfig.TargetLevel) else 0
	local text = (def.Text:gsub("%%d", tostring(progress)))
	if stage == shownStage and text == shownTitle then
		return
	end
	local stageChanged = stage ~= shownStage
	-- A real step forward (not the first stage shown at load): chime
	if stageChanged and shownStage ~= nil then
		Effects.Play("TutorialStep")
	end
	shownStage = stage
	shownTitle = text

	if not stageChanged then
		-- Same objective, progress moved: just bounce the title
		setTitle(text)
		if title then
			UXEffects.Scale.bounce(title, { fromScale = 0.8, duration = 0.45 })
		end
		return
	end

	local function popNew()
		setTitle(text)
		setStep()
		UXEffects.Scale.popIn(root, { fromScale = 0.4, duration = 0.45 })
		swoosh()
	end
	if root.Visible then
		UXEffects.Scale.popOut(root, { toScale = 0.4, duration = 0.18, easingStyle = "Quad" }, popNew)
	else
		popNew()
	end
end

local function absorb(data: any): ()
	if type(data) ~= "table" then
		return
	end
	if type(data.Tutorial) == "table" and type(data.Tutorial.Stage) == "number" then
		stage = data.Tutorial.Stage
	end
	if type(data.Traversal) == "table" and type(data.Traversal.Level) == "number" then
		level = data.Traversal.Level
	end
	render()
end

--- Wires the Studio banner (PlayerGui/TutorialGuide, ResetOnSpawn = false).
local function bindBanner(gui: Instance): ()
	local root = gui:WaitForChild("Banner") :: GuiObject
	local titleFrame = root:WaitForChild("Title") :: GuiObject
	local step = root:WaitForChild("Step")
	local swooshPlane = root:FindFirstChild("Swoosh")

	titleLabels = {
		titleFrame:WaitForChild("Shadow") :: TextLabel,
		titleFrame:WaitForChild("Text") :: TextLabel,
	}
	stepLabel = step:WaitForChild("Label") :: TextLabel
	plane = if swooshPlane and swooshPlane:IsA("GuiObject") then swooshPlane else nil
	if plane then
		plane.Visible = false
	end
	title = titleFrame
	root.Visible = false -- popped in by render() once a stage is known
	banner = root
	if gui:IsA("ScreenGui") then
		gui.Enabled = true
	end

	shownStage = nil
	render()
end

--============================================================================--
-- GUIDE PATH (Assets/VFX/Tutorial)
--============================================================================--

--- The studio-authored Beam setup: `Start` / `End` Attachments with the Beam
--- under `End` already wired between them.
local function getTemplate(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	return vfx and vfx:FindFirstChild("Tutorial")
end

local function destroyGuide(): ()
	if guideLoop then
		guideLoop:Disconnect()
		guideLoop = nil
	end
	if guideStart then
		guideStart:Destroy()
		guideStart = nil
	end
	if guideEnd then
		guideEnd:Destroy() -- takes the Beam with it
		guideEnd = nil
	end
	guideTarget = nil
end

--- True when `instance` carries every attribute of `attributes` (a missing
--- one reads as false, so `Vip = false` matches a pad that never set it).
local function matchesAttributes(instance: Instance, attributes: { [string]: any }?): boolean
	for name, expected in attributes or {} do
		local value = instance:GetAttribute(name)
		if value ~= expected and not (expected == false and value == nil) then
			return false
		end
	end
	return true
end

--- World center of a target: a part's position, a model's bounding-box center.
local function centerOf(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		local boxCFrame = target:GetBoundingBox()
		return boxCFrame.Position
	end
	return nil
end

--- Nearest instance (part or model) carrying the stage target's tag and attributes.
local function findTarget(from: Vector3): Instance?
	local def = TutorialConfig.Stages[stage]
	local target = def and def.Target
	if not target then
		return nil
	end
	local best: Instance? = nil
	local bestDistance = math.huge
	for _, instance in CollectionService:GetTagged(target.Tag) do
		local center = centerOf(instance)
		if center and instance:IsDescendantOf(Workspace) and matchesAttributes(instance, target.Attributes) then
			local distance = (center - from).Magnitude
			if distance < bestDistance then
				best, bestDistance = instance, distance
			end
		end
	end
	return best
end

--- Center of the local character (HumanoidRootPart).
local function playerCenter(): Vector3?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

--- Re-places both attachments: flat ribbon from the player's center to the target's center.
local function placeGuide(): ()
	local startAttachment, endAttachment, target = guideStart, guideEnd, guideTarget
	if not (startAttachment and endAttachment and target) then
		return
	end
	local from = playerCenter()
	local to = centerOf(target)
	if not (from and to) then
		return
	end
	local beam = endAttachment:FindFirstChildOfClass("Beam")
	local offset = to - from
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if offset.Magnitude < MIN_PATH_LENGTH or flat.Magnitude < 1e-3 then
		if beam then
			beam.Enabled = false
		end
		return
	end
	if beam then
		beam.Enabled = true
	end
	-- X along the path, Y sideways (= the Beam's width axis), so it stays flat
	local forward = offset.Unit
	local side = Vector3.new(0, 1, 0):Cross(flat.Unit)
	startAttachment.WorldCFrame = CFrame.fromMatrix(from, forward, side)
	endAttachment.WorldCFrame = CFrame.fromMatrix(to, forward, side)
end

--- Builds the path once, or retargets it; removes it when there is no target.
local function updateGuide(): ()
	local from = playerCenter()
	local target = if from then findTarget(from) else nil
	if not target then
		destroyGuide()
		return
	end
	guideTarget = target
	if guideStart and guideEnd then
		return
	end

	local template = getTemplate()
	if not template then
		return
	end
	local clone = template:Clone()
	local startAttachment = clone:FindFirstChild("Start")
	local endAttachment = clone:FindFirstChild("End")
	if
		not (
			startAttachment
			and startAttachment:IsA("Attachment")
			and endAttachment
			and endAttachment:IsA("Attachment")
		)
	then
		clone:Destroy()
		return
	end
	local beam = endAttachment:FindFirstChildOfClass("Beam")
	if beam then
		beam.FaceCamera = false
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Segments = 1
	end
	startAttachment.Parent = Workspace.Terrain
	endAttachment.Parent = Workspace.Terrain
	clone:Destroy() -- empty shell: both attachments (and the Beam under End) were moved out
	guideStart = startAttachment
	guideEnd = endAttachment
	placeGuide()
	guideLoop = RunService.RenderStepped:Connect(placeGuide)
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function TutorialController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
end

function TutorialController:Start(): ()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	SafeUIResolver.WaitForPathStringAsync(playerGui, "TutorialGuide", bindBanner)
	Scheduler.Every("TutorialGuide", TutorialConfig.RefreshHz, updateGuide, true)
end

return TutorialController
