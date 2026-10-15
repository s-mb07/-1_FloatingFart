--!strict
--[[
	@module PaperPlaneLoadingScreen
	@description Plays the Blender-made paper plane loading animation
	(`LoadingAnimData`, next to this file: a 3D paper plane mesh plus 30 fps baked
	motion) inside a ViewportFrame. No image or mesh assets: the plane is built
	at runtime from WedgeParts and the clouds from Ball parts, so nothing can
	fail moderation or load late.

	Sequence: intro from the left, a figure-8 twirl loop that repeats while
	loading runs, then -- once `RequestFinale` is called -- a sharp left-up
	exit and a dive down the middle into the camera that ends on a white flash.
	The finale always starts from the loop's start pose, so a request made
	mid-loop finishes the current pass first (at most one loop, 4 s).

	Usage (see LoadingController):
		local screen = PaperPlaneLoadingScreen.new(playerGui)
		screen:SetProgress(ratio)
		screen:RequestFinale()
		screen:OnSkip(callback)    -- bottom-right Skip button pressed
		screen:Skip()              -- fast fade to white, ending the animation now
		screen:WaitForWhiteout()   -- yields until the screen is fully white
		screen:Reveal()            -- fades the white away and destroys

	Sound: the screen is a pure view and plays nothing itself. It fires
	`OnCue` at key frames -- "Swoop" (plane enters),
	"Roll" (each barrel roll), "Turn" (sharp exit), "Dive", "Through" (rush
	into the camera) -- and the controller maps cues to Effects recipes.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Data = require(script.LoadingAnimData)

local PaperPlaneLoadingScreen = {}
PaperPlaneLoadingScreen.__index = PaperPlaneLoadingScreen

-- Matches the Blender sky (sampled from the render), top -> bottom.
local SKY = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("76C3F8")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("8FD1FB")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("A2DDFF")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("BEE8FF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("D5F1FF")),
})
local INK = Color3.fromHex("1D3557")
local PAPER = Color3.fromRGB(245, 247, 250)
local CLOUD = Color3.fromRGB(255, 255, 255)
local TITLE_WORDS = { "Paper", "Plane", "Escape" }
local TITLE_TILTS = { -5, 3, -2 } -- degrees per word: goofy, hand-placed look
local TITLE_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local TITLE_FILL = ColorSequence.new(Color3.fromHex("FFF27A"), Color3.fromHex("FF9A2E"))
local TITLE_BOTTOM_OFFSET = -104 -- px above the screen bottom (clears the bar + its label)
local TITLE_TEXT_RATIO = 0.095 -- text size as a fraction of the screen height
local WHITEOUT_FRAMES = 7 -- last finale frames fade to white (same as the Blender preview)
local REVEAL_SECONDS = 0.6
local SKIP_FADE_SECONDS = 0.3 -- Skip: quick fade to white instead of the dive
local SKIP_TILT = 3 -- degrees, same hand-placed tilt as the title words
local SKIP_HOVER_SCALE = 1.08

-- Camera: vertical FOV chosen so exactly SCREEN_H units are visible at depth 0,
-- which makes the baked Blender coordinates map 1:1 onto the viewport.
local FOV = 70
local CAMERA_DISTANCE = (Data.SCREEN_H / 2) / math.tan(math.rad(FOV / 2))
local CLOUD_DEPTH = 4 -- clouds sit this far behind the plane
local CLOUD_DEPTH_SCALE = (CAMERA_DISTANCE + CLOUD_DEPTH) / CAMERA_DISTANCE -- cancels perspective shrink
local CLOUD_SIZE = 0.72 -- solid balls read bigger than the Blender metaballs; shrink to match
local CLOUD_SQUASH = 0.8 -- slightly flattened puffs
local PLANE_THICKNESS = 0.02

type Row = { number }
type Clip = { Row }

-- Frame index -> cue name, per clip. Frames come from tools/loading_anim/motion.py:
-- the loop's two barrel rolls start at 5% and 55%, the finale's dive at
-- F1 + PAUSE and the rush at F1 + PAUSE + DESC.
local CUES: { [string]: { [number]: string } } = {
	Intro = { [0] = "Swoop" },
	Loop = { [6] = "Roll", [66] = "Roll" },
	Finale = { [0] = "Turn", [30] = "Dive", [54] = "Through" },
}

export type Screen = typeof(setmetatable(
	{} :: {
		_gui: ScreenGui,
		_sky: Frame,
		_track: Frame,
		_title: Frame,
		_skipButton: TextButton,
		_titleLabels: { TextLabel },
		_viewport: ViewportFrame,
		_plane: Model,
		_clouds: { Model },
		_white: Frame,
		_barFill: Frame,
		_label: TextLabel,
		_conn: RBXScriptConnection?,
		_clip: Clip,
		_clipName: string,
		_t: number,
		_elapsed: number,
		_finaleRequested: boolean,
		_lastFrame: number,
		_onCue: ((string) -> ())?,
		_onSkip: (() -> ())?,
		_skipped: boolean,
		_whiteout: BindableEvent,
		_isWhite: boolean,
	},
	PaperPlaneLoadingScreen
))

local wedgeTemplate = Instance.new("WedgePart")
wedgeTemplate.Anchored = true
wedgeTemplate.CanCollide = false
wedgeTemplate.CanQuery = false
wedgeTemplate.CastShadow = false
wedgeTemplate.TopSurface = Enum.SurfaceType.Smooth
wedgeTemplate.BottomSurface = Enum.SurfaceType.Smooth
wedgeTemplate.Material = Enum.Material.SmoothPlastic
wedgeTemplate.Color = PAPER

--- Two WedgeParts that exactly fill triangle a-b-c (standard right-angle split).
local function drawTriangle(a: Vector3, b: Vector3, c: Vector3, parent: Instance): ()
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local w1 = wedgeTemplate:Clone()
	w1.Size = Vector3.new(PLANE_THICKNESS, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w1.Parent = parent

	local w2 = wedgeTemplate:Clone()
	w2.Size = Vector3.new(PLANE_THICKNESS, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	w2.Parent = parent
end

local function buildPlane(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "PaperPlane"
	for _, tri in Data.Triangles do
		drawTriangle(tri[1], tri[2], tri[3], model)
	end
	model.WorldPivot = CFrame.identity
	model.Parent = parent
	return model
end

local function buildCloud(index: number, parent: Instance): Model
	local row = Data.Clouds[index]
	local shape = Data.CloudShapes[row[1]]
	local s = row[4] * CLOUD_DEPTH_SCALE * CLOUD_SIZE
	local model = Instance.new("Model")
	model.Name = "Cloud" .. index
	for _, ball in shape do
		-- Block + SpecialMesh sphere: a Ball part ignores non-uniform Size.
		local part = Instance.new("Part")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = CLOUD
		local d = ball[3] * 2 * s
		part.Size = Vector3.new(d, d * CLOUD_SQUASH, d)
		part.CFrame = CFrame.new(ball[1] * s, ball[2] * s, 0)
		part.Parent = model
	end
	model.WorldPivot = CFrame.identity
	model.Parent = parent
	return model
end

local function build(parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- IgnoreGuiInset alone maps to DeviceSafeInsets, which leaves the notch /
	-- rounded-corner strip uncovered on phones. None = edge to edge.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 10000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local sky = Instance.new("Frame")
	sky.Name = "Sky"
	sky.Size = UDim2.fromScale(1, 1)
	sky.BackgroundColor3 = Color3.new(1, 1, 1)
	sky.BorderSizePixel = 0
	-- Active swallows GUI clicks so nothing underneath can be pressed.
	sky.Active = true
	sky.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = SKY
	gradient.Rotation = 90
	gradient.Parent = sky

	-- 16:9 viewport sized to cover the screen (Blender camera space).
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Stage"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(105, 125, 160)
	viewport.LightColor = Color3.fromRGB(255, 252, 245)
	viewport.LightDirection = Vector3.new(-0.35, -0.6, -0.72)
	viewport.Parent = sky

	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, CAMERA_DISTANCE), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local clouds = {}
	for i in Data.Clouds do
		table.insert(clouds, buildCloud(i, viewport))
	end
	local plane = buildPlane(viewport)

	local white = Instance.new("Frame")
	white.Name = "Whiteout"
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.BorderSizePixel = 0
	white.ZIndex = 5
	white.Parent = gui

	-- Progress pill, bottom centre; drawn above the whiteout so it stays
	-- readable if loading outlasts the finale.
	local track = Instance.new("Frame")
	track.Name = "BarTrack"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -36)
	track.Size = UDim2.new(0.32, 0, 0, 18)
	track.BackgroundColor3 = INK
	track.ZIndex = 10
	track.Parent = gui
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "BarFill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.ZIndex = 11
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Color = ColorSequence.new(Color3.fromHex("6FE3FF"), Color3.fromHex("2F8BFF"))
	fillGradient.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "PhaseLabel"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -6)
	label.Size = UDim2.new(1, 0, 0, 26)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 22
	label.Text = "Loading..."
	label.ZIndex = 12
	label.Parent = track
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = INK
	textStroke.Thickness = 2.5
	textStroke.Parent = label

	-- Title above the bar: one label per word so each word tilts its own way
	-- (FredokaOne, same goofy face as the HUD's big buttons).
	local title = Instance.new("Frame")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 1, TITLE_BOTTOM_OFFSET)
	title.Size = UDim2.fromScale(1, 0)
	title.AutomaticSize = Enum.AutomaticSize.Y
	title.BackgroundTransparency = 1
	title.ZIndex = 10
	title.Parent = gui
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	titleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	titleLayout.Padding = UDim.new(0, 14)
	titleLayout.Parent = title

	local titleLabels = {}
	for i, word in TITLE_WORDS do
		local wordLabel = Instance.new("TextLabel")
		wordLabel.Name = word
		wordLabel.LayoutOrder = i
		wordLabel.AutomaticSize = Enum.AutomaticSize.XY
		wordLabel.BackgroundTransparency = 1
		wordLabel.FontFace = TITLE_FONT
		wordLabel.TextColor3 = Color3.new(1, 1, 1)
		wordLabel.Text = word
		wordLabel.Rotation = TITLE_TILTS[i]
		wordLabel.ZIndex = 11
		wordLabel.Parent = title
		local wordStroke = Instance.new("UIStroke")
		wordStroke.Color = INK
		wordStroke.Thickness = 4
		wordStroke.LineJoinMode = Enum.LineJoinMode.Round
		wordStroke.Parent = wordLabel
		local wordFill = Instance.new("UIGradient")
		wordFill.Color = TITLE_FILL
		wordFill.Rotation = 90
		wordFill.Parent = wordLabel
		table.insert(titleLabels, wordLabel)
	end

	-- Skip pill, bottom right: same ink pill + white stroke as the bar, label in
	-- the title's FredokaOne with its yellow-orange fill. The fill lives on a
	-- child label because a UIGradient on the button would tint its ink too.
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipButton"
	skipButton.AnchorPoint = Vector2.new(1, 1)
	skipButton.Position = UDim2.new(1, -28, 1, -26)
	skipButton.Size = UDim2.fromOffset(150, 52)
	skipButton.Rotation = SKIP_TILT
	skipButton.BackgroundColor3 = INK
	skipButton.AutoButtonColor = false
	skipButton.Text = ""
	skipButton.ZIndex = 10
	skipButton.Parent = gui
	Instance.new("UICorner", skipButton).CornerRadius = UDim.new(1, 0)
	local skipScale = Instance.new("UIScale")
	skipScale.Parent = skipButton
	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = Color3.new(1, 1, 1)
	skipStroke.Thickness = 3
	skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	skipStroke.Parent = skipButton

	local skipLabel = Instance.new("TextLabel")
	skipLabel.Name = "Label"
	skipLabel.Size = UDim2.fromScale(1, 1)
	skipLabel.BackgroundTransparency = 1
	skipLabel.FontFace = TITLE_FONT
	skipLabel.TextColor3 = Color3.new(1, 1, 1)
	skipLabel.TextSize = 30
	skipLabel.Text = "Skip >>"
	skipLabel.ZIndex = 11
	skipLabel.Parent = skipButton
	local skipTextStroke = Instance.new("UIStroke")
	skipTextStroke.Color = INK
	skipTextStroke.Thickness = 2.5
	skipTextStroke.LineJoinMode = Enum.LineJoinMode.Round
	skipTextStroke.Parent = skipLabel
	local skipFill = Instance.new("UIGradient")
	skipFill.Color = TITLE_FILL
	skipFill.Rotation = 90
	skipFill.Parent = skipLabel

	gui.Parent = parent
	return gui,
		sky,
		track,
		title,
		titleLabels,
		skipButton,
		viewport,
		plane,
		clouds,
		white,
		fill,
		label
end

function PaperPlaneLoadingScreen.new(parent: Instance): Screen
	local gui, sky, track, title, titleLabels, skipButton, viewport, plane, clouds, white, fill, label =
		build(parent)
	local self = setmetatable({
		_gui = gui,
		_sky = sky,
		_track = track,
		_title = title,
		_skipButton = skipButton,
		_titleLabels = titleLabels,
		_viewport = viewport,
		_plane = plane,
		_clouds = clouds,
		_white = white,
		_barFill = fill,
		_label = label,
		_conn = nil,
		_clip = Data.Intro :: Clip,
		_clipName = "Intro",
		_t = 0,
		_elapsed = 0,
		_finaleRequested = false,
		_lastFrame = -1,
		_onCue = nil,
		_onSkip = nil,
		_skipped = false,
		_whiteout = Instance.new("BindableEvent"),
		_isWhite = false,
	}, PaperPlaneLoadingScreen)

	-- Sized from the ScreenGui, not workspace.CurrentCamera.ViewportSize: the
	-- camera reports 1x1 until its first frame, which left the stage invisible.
	local function fitStage()
		local v = gui.AbsoluteSize
		if v.X < 2 or v.Y < 2 then
			v = Vector2.new(1920, 1080)
		end
		local aspect = Data.SCREEN_W / Data.SCREEN_H
		local w, h = v.X, v.X / aspect
		if h < v.Y then
			w, h = v.Y * aspect, v.Y
		end
		viewport.Size = UDim2.fromOffset(w, h)
		for _, wordLabel in titleLabels do
			wordLabel.TextSize = math.floor(v.Y * TITLE_TEXT_RATIO)
		end
	end
	fitStage()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStage)

	local skipScale = skipButton:FindFirstChildOfClass("UIScale") :: UIScale
	local hoverInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	skipButton.MouseEnter:Connect(function()
		TweenService:Create(skipScale, hoverInfo, { Scale = SKIP_HOVER_SCALE }):Play()
	end)
	skipButton.MouseLeave:Connect(function()
		TweenService:Create(skipScale, hoverInfo, { Scale = 1 }):Play()
	end)
	skipButton.Activated:Connect(function()
		if self._skipped or self._isWhite then
			return
		end
		if self._onSkip then
			self._onSkip()
		end
	end)

	self:_step(0)
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)

	return self
end

function PaperPlaneLoadingScreen.SetProgress(self: Screen, ratio: number): ()
	self._barFill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	self._label.Text = string.format("Loading... %d%%", math.floor(ratio * 100))
end

--- Registers the cue listener (see the module header for the cue names).
function PaperPlaneLoadingScreen.OnCue(self: Screen, callback: (string) -> ()): ()
	self._onCue = callback
end

--- Registers the Skip button listener. The screen does not skip by itself:
--- the owner decides what skipping means (cancel loading) and calls `Skip`.
function PaperPlaneLoadingScreen.OnSkip(self: Screen, callback: () -> ()): ()
	self._onSkip = callback
end

--- Ends the animation now: hides the Skip button and fades quickly to white,
--- firing the whiteout `WaitForWhiteout` waits on. No-op once already white.
function PaperPlaneLoadingScreen.Skip(self: Screen): ()
	if self._skipped or self._isWhite then
		return
	end
	self._skipped = true
	self._skipButton.Visible = false
	local fade = TweenService:Create(
		self._white,
		TweenInfo.new(SKIP_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 0 }
	)
	fade.Completed:Once(function()
		self._isWhite = true
		self._whiteout:Fire()
	end)
	fade:Play()
end

function PaperPlaneLoadingScreen.RequestFinale(self: Screen): ()
	self._finaleRequested = true
end

function PaperPlaneLoadingScreen.WaitForWhiteout(self: Screen): ()
	if not self._isWhite then
		self._whiteout.Event:Wait()
	end
end

function PaperPlaneLoadingScreen._stepClouds(self: Screen, dt: number): ()
	self._elapsed += dt
	-- Title bobs and each word rocks a little, like it hangs in the wind.
	self._title.Position =
		UDim2.new(0.5, 0, 1, TITLE_BOTTOM_OFFSET + 4 * math.sin(self._elapsed * 2))
	for i, wordLabel in self._titleLabels do
		wordLabel.Rotation = TITLE_TILTS[i] + 1.5 * math.sin(self._elapsed * 2 + i)
	end
	local span = 2 * Data.CLOUD_WRAP
	for i, c in Data.Clouds do
		local x = ((c[2] - c[5] * self._elapsed + Data.CLOUD_WRAP) % span) - Data.CLOUD_WRAP
		self._clouds[i]:PivotTo(
			CFrame.new(x * CLOUD_DEPTH_SCALE, c[3] * CLOUD_DEPTH_SCALE, -CLOUD_DEPTH)
		)
	end
end

function PaperPlaneLoadingScreen._step(self: Screen, dt: number): ()
	self:_stepClouds(dt)
	if self._isWhite or self._skipped then
		return
	end

	self._t += dt * Data.FPS
	-- Clip hand-offs: intro and every loop pass end on the finale's start pose.
	while self._t >= #self._clip do
		if self._clipName == "Finale" then
			self._white.BackgroundTransparency = 0
			self._isWhite = true
			self._whiteout:Fire()
			return
		end
		self._t -= #self._clip
		self._lastFrame = -1
		if self._finaleRequested then
			self._clip, self._clipName = Data.Finale :: Clip, "Finale"
		else
			self._clip, self._clipName = Data.Loop :: Clip, "Loop"
		end
	end

	local f = math.floor(self._t)
	local a = self._t - f
	local cues = CUES[self._clipName]
	if self._onCue and cues then
		for frame = self._lastFrame + 1, f do
			local cue = cues[frame]
			if cue then
				self._onCue(cue)
			end
		end
	end
	self._lastFrame = f
	local r0 = self._clip[f + 1]
	local r1 = self._clip[f + 2] or r0
	local x = r0[1] + (r1[1] - r0[1]) * a
	local y = r0[2] + (r1[2] - r0[2]) * a
	local s = r0[3] + (r1[3] - r0[3]) * a
	local rot0 = CFrame.new(0, 0, 0, r0[4], r0[5], r0[6], r0[7])
	local rot1 = CFrame.new(0, 0, 0, r1[4], r1[5], r1[6], r1[7])

	self._plane:ScaleTo(s)
	self._plane:PivotTo(CFrame.new(x, y, 0) * rot0:Lerp(rot1, a))

	if self._clipName == "Finale" then
		local w = math.clamp((self._t - (#self._clip - WHITEOUT_FRAMES)) / WHITEOUT_FRAMES, 0, 1)
		self._white.BackgroundTransparency = 1 - w
	end
end

function PaperPlaneLoadingScreen.Reveal(self: Screen): ()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	-- Under the opaque white: drop the sky so the fade uncovers the game.
	self._sky.Visible = false
	local info = TweenInfo.new(REVEAL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- A dark stroke still reads at half transparency once the text has
	-- faded out: the strokes go out in half the time.
	local strokeInfo =
		TweenInfo.new(REVEAL_SECONDS / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self._white, info, { BackgroundTransparency = 1 }):Play()
	for _, container in { self._track, self._title, self._skipButton } do
		for _, d in container:GetDescendants() do
			if d:IsA("UIStroke") then
				TweenService:Create(d, strokeInfo, { Transparency = 1 }):Play()
			elseif d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1 }):Play()
			elseif d:IsA("Frame") then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			end
		end
	end
	TweenService:Create(self._track, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(self._skipButton, info, { BackgroundTransparency = 1 }):Play()
	task.wait(REVEAL_SECONDS)
	self:Destroy()
end

function PaperPlaneLoadingScreen.Destroy(self: Screen): ()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._whiteout:Destroy()
	self._gui:Destroy()
end

return PaperPlaneLoadingScreen
