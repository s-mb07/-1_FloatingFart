--!strict
--[[
	@module Effects.Channels.Camera
	@description Effects' camera channel: shakes AND cinematics, single owner.

	Both live here on purpose. A shake is an additive offset, a cinematic is
	a base; splitting them into two modules would force each one to write
	CurrentCamera.CFrame without knowing about the other -- exactly what made
	the old shake drift as soon as the camera switched to Scriptable.

	Core rule: the output is never read back. `base` comes either from the
	timeline or from the default camera script; the shake is composed on top
	of it at the very last moment.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EffectsConfig = require(script.Parent.Parent.Parent.Config.EffectsConfig)
local Settings = require(script.Parent.Parent.Settings)
local Stage = require(script.Parent.Parent.Stage)

local Camera = {}

local BIND_NAME = "EffectsCamera"
local DEFAULT_FREQUENCY = 25
local DEFAULT_EASING = Enum.EasingStyle.Quad
-- Delay before an input can cut the cinematic short: without it, the click
-- that triggers the reward would cut it on the very next frame.
local SKIP_GRACE = 0.3

local LocalPlayer = Players.LocalPlayer

local bound = false
local generation = 0

-- Timeline
local owning = false
local steps: {EffectsConfig.CameraStep} = {}
local stepStarts: {number} = {}
local totalDuration = 0
local elapsed = 0
local stepIndex = 0
local baseCFrame = CFrame.identity
local entryCFrame = CFrame.identity
local stepEntryPosition = Vector3.zero
local stepEntryLook = Vector3.zAxis
local stepEntryFov = 70
local spinAccumulated = 0
local spinBase = 0

-- Saved camera
local savedType = Enum.CameraType.Custom
local savedSubject: Instance? = nil
local savedFov = 70

-- Shake, independent of the timeline: it can outlive it, and a shake recipe
-- can play during a cinematic without breaking it.
local shakeIntensity = 0
local shakeDuration = 0
local shakeElapsed = 0
local shakeFrequency = DEFAULT_FREQUENCY
local shakeSeed = 0

local guards: {RBXScriptConnection} = {}

--============================================================================--
-- ANCHORS
--============================================================================--

local function characterPivot(): CFrame?
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.CFrame
	end
	return nil
end

--- An anchor is always a space + an offset: no absolute coordinate
--- ever comes up from EffectsConfig.
local function resolveAnchor(anchor: EffectsConfig.AnchorSpec): Vector3
	local space = anchor.Space

	if space == "Subject" then
		local pivot = Stage.GetPivot()
		if pivot then
			return (pivot * CFrame.new(anchor.Offset)).Position
		end
	elseif space == "Character" then
		local pivot = characterPivot()
		if pivot then
			return (pivot * CFrame.new(anchor.Offset)).Position
		end
	elseif space == "Camera" then
		return (entryCFrame * CFrame.new(anchor.Offset)).Position
	elseif space == "World" then
		return anchor.Offset
	else
		warn("[Effects] Unknown anchor space: " .. tostring(space))
	end

	-- Subject or character missing: falls back to the step's entry position
	-- rather than teleporting the camera to the world origin.
	return stepEntryPosition
end

--============================================================================--
-- SHAKE
--============================================================================--

local function ensureBound(): ()
	if bound then return end
	bound = true
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
		Camera._render(deltaTime)
	end)
end

--- A new shake can only add: we keep the strongest amplitude and the
--- longest remaining duration, otherwise a small shake would cancel out a big one.
local function startShake(shake: EffectsConfig.ShakeSpec): ()
	if not Settings.Get("ScreenShake") then return end

	local remaining = math.max(shakeDuration - shakeElapsed, 0)
	local activeIntensity = if remaining > 0 then shakeIntensity else 0

	shakeIntensity = math.max(activeIntensity, shake.Intensity)
	shakeDuration = math.max(remaining, shake.Duration)
	shakeElapsed = 0
	shakeFrequency = shake.Frequency or DEFAULT_FREQUENCY
	shakeSeed = math.random() * 1000

	ensureBound()
end

local function shakeOffset(): CFrame
	if shakeElapsed >= shakeDuration then
		return CFrame.identity
	end

	local amplitude = shakeIntensity * (1 - shakeElapsed / shakeDuration)
	local t = shakeElapsed * shakeFrequency
	local offsetX = (math.noise(t, shakeSeed) :: number) * amplitude
	local offsetY = (math.noise(t, shakeSeed + 100) :: number) * amplitude

	return CFrame.new(offsetX, offsetY, 0)
end

--============================================================================--
-- TIMELINE
--============================================================================--

--- Ownership is inferred, never declared: only a movement or an FOV
--- change forces CameraType.Scriptable.
local function needsOwnership(list: {EffectsConfig.CameraStep}): boolean
	for _, step in list do
		if step.Travel or step.FieldOfView then
			return true
		end
	end
	return false
end

--- Entering a step: restarts from the computed base, never from the
--- actual camera, which carries the previous frame's shake.
local function beginStep(index: number): ()
	stepIndex = index
	stepEntryPosition = baseCFrame.Position
	stepEntryLook = baseCFrame.LookVector
	spinBase = spinAccumulated

	local camera = Workspace.CurrentCamera
	if camera then
		stepEntryFov = camera.FieldOfView
	end

	local step = steps[index]
	if step and step.Shake then
		startShake(step.Shake)
	end
end

local function easedAlpha(step: EffectsConfig.CameraStep, alpha: number): number
	local style = DEFAULT_EASING
	if step.Easing then
		local named = (Enum.EasingStyle :: any)[step.Easing]
		if named then
			style = named
		end
	end
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, Enum.EasingDirection.Out)
end

--- Position, orientation and FOV of the timeline at the current instant, excluding shake.
local function timelineBase(): (CFrame, number)
	local step = steps[stepIndex]
	if not step then
		return baseCFrame, stepEntryFov
	end

	local span = math.max(step.Duration, 1e-3)
	local alpha = easedAlpha(step, (elapsed - stepStarts[stepIndex]) / span)

	local travel = step.Travel
	local position = stepEntryPosition
	if travel then
		local from = if travel.From then resolveAnchor(travel.From) else stepEntryPosition
		position = from:Lerp(resolveAnchor(travel.To), alpha)
	end

	local lookTarget: Vector3
	if travel and travel.LookAt then
		lookTarget = resolveAnchor(travel.LookAt)
	else
		local pivot = Stage.GetPivot()
		lookTarget = if pivot then pivot.Position else position + stepEntryLook
	end

	if travel and travel.SpinDegrees then
		Stage.SetSpin(spinBase + travel.SpinDegrees * alpha)
	end

	local fov = stepEntryFov
	if step.FieldOfView then
		fov = stepEntryFov + (step.FieldOfView - stepEntryFov) * alpha
	end

	-- CFrame.lookAt is undefined if the camera sits exactly on its target.
	if (lookTarget - position).Magnitude < 1e-3 then
		return CFrame.lookAt(position, position + stepEntryLook), fov
	end
	return CFrame.lookAt(position, lookTarget), fov
end

local function advanceSteps(): ()
	while stepIndex < #steps and elapsed >= stepStarts[stepIndex + 1] do
		local finished = steps[stepIndex]
		if finished and finished.Travel and finished.Travel.SpinDegrees then
			spinAccumulated += finished.Travel.SpinDegrees
		end
		beginStep(stepIndex + 1)
	end
end

--============================================================================--
-- RELEASE
--============================================================================--

local function unbind(): ()
	if not bound then return end
	RunService:UnbindFromRenderStep(BIND_NAME)
	bound = false
end

--- Returns the camera to the game. Called by normal completion, skip,
--- respawn, timeout and any new Play: it's the only exit path, so it can't
--- be forgotten.
local function releaseOwnership(): ()
	for _, connection in guards do
		connection:Disconnect()
	end
	table.clear(guards)

	if owning then
		local camera = Workspace.CurrentCamera
		if camera then
			camera.FieldOfView = savedFov

			-- The saved subject may have been destroyed by a respawn that happened
			-- during the cinematic: falls back to the current Humanoid.
			local subject = savedSubject
			if not (subject and subject:IsDescendantOf(Workspace)) then
				local character = LocalPlayer.Character
				subject = character and character:FindFirstChildOfClass("Humanoid")
			end
			camera.CameraSubject = subject
			camera.CameraType = savedType
		end
		owning = false
	end

	steps = {}
	stepStarts = {}
	totalDuration = 0
	stepIndex = 0
	spinAccumulated = 0
	spinBase = 0

	Stage.Clear()
end

--============================================================================--
-- RENDER
--============================================================================--

function Camera._render(deltaTime: number): ()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local base: CFrame
	if owning then
		elapsed += deltaTime
		advanceSteps()

		local timelineCFrame, fov = timelineBase()
		baseCFrame = timelineCFrame
		base = timelineCFrame
		camera.FieldOfView = fov
	else
		-- Passthrough: the base is whatever the default camera script just
		-- wrote this frame. We never read our own output back.
		base = camera.CFrame
	end

	if shakeElapsed < shakeDuration then
		shakeElapsed += deltaTime
		camera.CFrame = base * shakeOffset()
	elseif owning then
		camera.CFrame = base
	end

	if owning and elapsed >= totalDuration then
		releaseOwnership()
	end

	if not owning and shakeElapsed >= shakeDuration then
		unbind()
	end
end

--============================================================================--
-- API
--============================================================================--

--- Returns the camera and tears down the staging, regardless of current state.
function Camera.Release(): ()
	generation += 1
	releaseOwnership()
	if shakeElapsed >= shakeDuration then
		unbind()
	end
end

local function armGuards(spec: EffectsConfig.CameraSpec): ()
	table.insert(guards, LocalPlayer.CharacterAdded:Connect(function()
		Camera.Release()
	end))

	if spec.Skippable ~= false then
		table.insert(guards, UserInputService.InputBegan:Connect(function(_, gameProcessed: boolean)
			-- `gameProcessed` filters out inputs consumed by the UI: on
			-- mobile, tapping a button on the reward panel shouldn't
			-- cut the cinematic.
			if gameProcessed then return end
			if elapsed < SKIP_GRACE then return end
			Camera.Release()
		end))
	end

	-- Hard safety net: if a step throws an error, the camera is still returned.
	local deadline = spec.MaxDuration or (totalDuration + 1)
	local armed = generation
	task.delay(deadline, function()
		if generation == armed and owning then
			Camera.Release()
		end
	end)
end

function Camera.Play(spec: EffectsConfig.CameraSpec, context: any): ()
	if #spec.Steps == 0 then return end

	if not needsOwnership(spec.Steps) then
		-- Shake-only recipe: it layers on top without touching a cinematic
		-- already in progress.
		local offset = 0
		for _, step in spec.Steps do
			local shake = step.Shake
			if shake then
				if offset <= 0 then
					startShake(shake)
				else
					task.delay(offset, startShake, shake)
				end
			end
			offset += step.Duration
		end
		return
	end

	Camera.Release()

	local camera = Workspace.CurrentCamera
	if not camera then return end

	steps = spec.Steps
	stepStarts = table.create(#steps)
	totalDuration = 0
	for index, step in steps do
		stepStarts[index] = totalDuration
		totalDuration += step.Duration
	end

	Stage.Setup(context and context.Subject)

	savedType = camera.CameraType
	savedSubject = camera.CameraSubject
	savedFov = camera.FieldOfView

	entryCFrame = camera.CFrame
	baseCFrame = camera.CFrame
	elapsed = 0
	owning = true
	camera.CameraType = Enum.CameraType.Scriptable

	beginStep(1)
	armGuards(spec)
	ensureBound()
end

return Camera
