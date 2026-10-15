--!strict
--[[
	@module ShiftLockController
	@description Shift lock for every device, with ONE state shared by all its
	entry points: the Shift key, the TopbarPlus "Lock" toggle, and the on-screen
	button of touch devices (MainHUD/LockFrame/LockBtn, the frame is shown on
	touch devices only). Toggling from any of them updates the others.

	It reproduces Roblox's own shift lock (same mechanics, because the native
	one cannot be driven from a button nor exists on mobile; the native Shift
	toggle is disabled in default.project.json, StarterPlayer.EnableMouseLockOption,
	so the two never fight): the camera sits over the right shoulder
	(Humanoid.CameraOffset), the character always faces where the camera looks,
	and on mouse devices the cursor is locked to the centre of the screen. The
	cursor is replaced by a small white dot there (a "target").

	The look (shoulder camera, locked mouse, dot) stays on in every state, flight
	included. Only the character's FACING follows the camera while plainly
	walking: in flight, against a wall or on a fan (treadmill) other systems
	(ProbeController...) own the rotation. Seated or dead: the lock is dropped
	but the choice is kept and applies again by itself.

	Facade: IsLocked / SetLocked / Toggle, and the Changed signal (isLocked).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Bootstrapper = script.Parent.Parent
local Icon = require(ReplicatedStorage.Packages.TopbarPlus)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local ProbeController = require(script.Parent.ProbeController)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local Signal = require(ReplicatedStorage.Libraries.Signal)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)

local log = Logger.new("ShiftLockController")
local ShiftLockController = {}

--- Fires with the new state whenever the lock is switched on or off.
ShiftLockController.Changed = Signal.new()

local IMAGE_OFF = "rbxasset://textures/ui/mouseLock_off@2x.png"
local IMAGE_ON = "rbxasset://textures/ui/mouseLock_on@2x.png"
local SHOULDER_OFFSET = Vector3.new(1.75, 0, 0)
local DOT_SIZE = 6 -- pixels
local RENDER_STEP_NAME = "ShiftLockStep"
-- Just after the default camera (Enum.RenderPriority.Camera) has moved.
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local HUD_BUTTON_PATH = "MainHUD/LockFrame/LockBtn"

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local LocalPlayer = Players.LocalPlayer
local isTouchDevice = UserInputService.TouchEnabled

local locked = false
--- True while the lock is currently applied to the character (needs undoing).
local applied = false
local dot: Frame? = nil
local topbarIcon: any = nil
local hudButton: ImageButton? = nil
local syncing = false

--- @return boolean -- the player's choice (it may be suspended, see header)
function ShiftLockController.IsLocked(): boolean
	return locked
end

--- Switches the lock on or off from any entry point.
--- @param on boolean
function ShiftLockController.SetLocked(on: boolean): ()
	if on == locked then
		return
	end
	locked = on
	ShiftLockController.Changed:Fire(on)
end

function ShiftLockController.Toggle(): ()
	ShiftLockController.SetLocked(not locked)
end

--============================================================================--
-- APPLYING THE LOCK
--============================================================================--

--- True while this module (not the flight code) holds the humanoid's
--- AutoRotate off, so it is only ever handed back by its owner.
local ownsRotation = false

--- The local character's humanoid and root while the lock's look (shoulder
--- camera, locked mouse, dot) may show: alive and not seated. It stays on in
--- flight too; only the character's facing is left to the flight code there.
local function lockableCharacter(): (Humanoid?, BasePart?)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		return nil, nil
	end
	if humanoid.Health <= 0 or humanoid.Sit then
		return nil, nil
	end
	return humanoid, root
end

--- True when the character should also turn with the camera: plain walking
--- only (flight, wall, fan, platform stand and anchored bodies are driven by
--- other systems).
local function mayRotate(humanoid: Humanoid, root: BasePart): boolean
	return ProbeController.GetState() == TraversalState.NORMAL
		and LocalPlayer:GetAttribute(TreadmillConfig.TrainingAttribute) == nil
		and not humanoid.PlatformStand
		and not root.Anchored
end

--- Undoes what the lock did to the character / mouse.
local function release(): ()
	applied = false
	if dot then
		dot.Visible = false
	end
	if not isTouchDevice then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
		if ownsRotation and ProbeController.GetState() == TraversalState.NORMAL then
			humanoid.AutoRotate = true
		end
	end
	ownsRotation = false
end

local function step(): ()
	if not locked then
		if applied then
			release()
		end
		return
	end
	local humanoid, root = lockableCharacter()
	local camera = workspace.CurrentCamera
	if not (humanoid and root and camera) then
		if applied then
			release()
		end
		return
	end

	applied = true
	humanoid.CameraOffset = SHOULDER_OFFSET
	if not isTouchDevice then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false -- the dot is the target
	end
	if dot then
		dot.Visible = true
	end

	if mayRotate(humanoid, root) then
		ownsRotation = true
		humanoid.AutoRotate = false
		-- Face where the camera looks (yaw only), keep the position.
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-3 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	elseif ownsRotation then
		-- Another system takes the character over (flight launch): let go of
		-- AutoRotate without touching it, the flight code sets what it needs.
		ownsRotation = false
	end
end

--============================================================================--
-- ENTRY POINTS (all just reach SetLocked / Toggle)
--============================================================================--

local function buildDot(): ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiftLockDot"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local point = Instance.new("Frame")
	point.Name = "Dot"
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.fromScale(0.5, 0.5)
	point.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	point.BackgroundColor3 = WHITE
	point.BorderSizePixel = 0
	point.Visible = false
	point.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = point
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Transparency = 0.5
	stroke.Thickness = 1
	stroke.Parent = point

	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	dot = point
end

local function buildTopbarIcon(): ()
	topbarIcon = Icon.new()
		:setName("ShiftLock")
		:setImage(IMAGE_OFF)
		:setLabel("Lock")
		:modifyTheme({
			{ "IconButton", "BackgroundColor3", BLACK, "Deselected" },
			{ "IconButton", "BackgroundTransparency", 0, "Deselected" },
			{ "IconLabel", "TextColor3", WHITE, "Deselected" },
			{ "IconImage", "ImageColor3", WHITE, "Deselected" },
			{ "IconButton", "BackgroundColor3", WHITE, "Selected" },
			{ "IconButton", "BackgroundTransparency", 0, "Selected" },
			{ "IconLabel", "TextColor3", BLACK, "Selected" },
			{ "IconImage", "ImageColor3", BLACK, "Selected" },
		})
		:bindEvent("selected", function()
			if not syncing then
				ShiftLockController.SetLocked(true)
			end
		end)
		:bindEvent("deselected", function()
			if not syncing then
				ShiftLockController.SetLocked(false)
			end
		end)
end

--- Brings the TopbarPlus toggle and the touch button in line with `locked`.
local function syncViews(on: boolean): ()
	if topbarIcon and topbarIcon.isSelected ~= on then
		syncing = true
		if on then
			topbarIcon:select()
		else
			topbarIcon:deselect()
		end
		syncing = false
	end
	if hudButton then
		hudButton.Image = if on then IMAGE_ON else IMAGE_OFF
	end
end

local function wireHudButton(): ()
	SafeUIResolver.WaitForPathStringAsync(
		LocalPlayer:WaitForChild("PlayerGui"),
		HUD_BUTTON_PATH,
		function(instance: Instance)
			if not instance:IsA("ImageButton") then
				return
			end
			-- LockFrame is for touch devices only
			local frame = instance.Parent
			if frame and frame:IsA("GuiObject") then
				frame.Visible = isTouchDevice
			end
			hudButton = instance
			instance.Image = if locked then IMAGE_ON else IMAGE_OFF
			instance.Activated:Connect(ShiftLockController.Toggle)
		end
	)
end

function ShiftLockController:Init(): ()
	log:Info("Initialized.")
end

function ShiftLockController:Start(): ()
	buildDot()
	buildTopbarIcon()
	wireHudButton()
	ShiftLockController.Changed:Connect(syncViews)

	ContextActionService:BindAction(
		"ShiftLockToggle",
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				ShiftLockController.Toggle()
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift
	)

	RunService:BindToRenderStep(RENDER_STEP_NAME, RENDER_PRIORITY, step)
	LocalPlayer.CharacterAdded:Connect(function()
		applied = false -- the new character starts clean
	end)
	log:Info("Started.")
end

return ShiftLockController
