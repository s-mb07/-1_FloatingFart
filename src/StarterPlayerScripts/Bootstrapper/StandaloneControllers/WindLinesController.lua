--!strict
--[[
	@module WindLinesController
	@description 2D wind streaks on the sides of the screen while the LOCAL
	player flies (anime "speed lines"). Pure cosmetic, display only.

	Each streak is a thin white bar spawned in the left or right band of the
	screen, aligned with the direction from the screen center (so the lines
	read as air rushing past the camera), and slides outward while it fades
	in then out. A short extra burst plays on take-off.

	Driven by EventBus.Traversal.Started / Stopped (local player only).
	The per-frame loop only exists while streaks are on screen. Spawn rate
	follows the graphics quality (QualityController preset), and sizes
	follow the viewport so phones get the same look as a 1080p screen.

	The wind is also heard: the "FlyWindLoop" Sound of Assets/sfx (Looped)
	plays for the whole flight,
	fading in at take-off and out at the stop (skipped when SFX are off).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local QualityController = require(script.Parent.QualityController)

local WindLinesController = {}

local LocalPlayer = Players.LocalPlayer

--- Streaks per second at High quality (scaled by CosmeticRateScale).
local SPAWN_RATE = 34
--- Extra streaks fired at once on take-off.
local LAUNCH_BURST = 18
--- Seconds a streak lives.
local LIFETIME_MIN, LIFETIME_MAX = 0.28, 0.5
--- Side band where streaks appear (screen-width fraction from the edge):
--- they start inside it and slide outward, so they stay on screen.
local SIDE_BAND_INNER, SIDE_BAND_OUTER = 0.32, 0.08
--- Streak length/thickness/speed in px at REFERENCE_HEIGHT.
local LENGTH_MIN, LENGTH_MAX = 180, 380
local THICKNESS_MIN, THICKNESS_MAX = 4, 8
local SPEED_MIN, SPEED_MAX = 380, 700
local REFERENCE_HEIGHT = 1080
local MAX_TRANSPARENCY = 0.1 -- most opaque a streak gets
local POOL_SIZE = 48
--- Wind loop fade times (s); the volume is the Sound's own (Assets/sfx).
local WIND_FADE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WIND_FADE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type Streak = {
	frame: Frame,
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	speed: number,
	age: number,
	lifetime: number,
}

local gui: ScreenGui? = nil
local free: { Frame } = {}
local live: { Streak } = {}
local loop: RBXScriptConnection? = nil
local flying = false
local spawnDebt = 0
local windSound: Sound? = nil -- one preloaded instance, faded in / out per flight
local windVolume = 0
local windFade: Tween? = nil

local function fadeWind(info: TweenInfo, volume: number, onDone: (() -> ())?): ()
	local sound = windSound
	if not sound then
		return
	end
	if windFade then
		windFade:Cancel()
	end
	local tween = TweenService:Create(sound, info, { Volume = volume })
	if onDone then
		tween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				onDone()
			end
		end)
	end
	windFade = tween
	tween:Play()
end

local function startWind(): ()
	if not Effects.IsSoundEnabled() then
		return
	end
	local sound = windSound
	if not sound then
		-- Shared preloaded copy of Assets/sfx/.../FlyWindLoop (volume authored there)
		sound = Effects.GetSound("FlyWindLoop")
		if not sound then
			return
		end
		windVolume = sound.Volume
		windSound = sound
	end
	if not sound.IsPlaying then
		sound.Volume = 0
		sound:Play()
	end
	fadeWind(WIND_FADE_IN, windVolume)
end

local function stopWind(): ()
	local sound = windSound
	if sound and sound.IsPlaying then
		fadeWind(WIND_FADE_OUT, 0, function()
			sound:Stop()
		end)
	end
end

local function createFrame(parent: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Streak"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Visible = false
	-- Soft ends: transparent at both tips, solid in the middle
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function ensureGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WindLinesFX"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = -1 -- under the HUD, over the world
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	gui = screenGui
	table.clear(free)
	table.clear(live)
	for _ = 1, POOL_SIZE do
		table.insert(free, createFrame(screenGui))
	end
	return screenGui
end

local function spawnStreak(screen: Vector2): ()
	local frame = table.remove(free)
	if not frame then
		return
	end
	local scale = math.max(screen.Y / REFERENCE_HEIGHT, 0.45)
	local leftSide = math.random() < 0.5
	local inset = (SIDE_BAND_OUTER + math.random() * (SIDE_BAND_INNER - SIDE_BAND_OUTER)) * screen.X
	local x = if leftSide then inset else screen.X - inset
	local y = screen.Y * (0.08 + math.random() * 0.84)

	-- Direction away from the screen center, flattened so streaks stay mostly horizontal
	local dirX, dirY = x - screen.X / 2, (y - screen.Y / 2) * 0.55
	local magnitude = math.sqrt(dirX * dirX + dirY * dirY)
	dirX, dirY = dirX / magnitude, dirY / magnitude

	local length = (LENGTH_MIN + math.random() * (LENGTH_MAX - LENGTH_MIN)) * scale
	local thickness = math.max(2, (THICKNESS_MIN + math.random() * (THICKNESS_MAX - THICKNESS_MIN)) * scale)
	frame.Size = UDim2.fromOffset(length, thickness)
	frame.Rotation = math.deg(math.atan2(dirY, dirX))
	frame.Position = UDim2.fromOffset(x, y)
	frame.BackgroundTransparency = 1
	frame.Visible = true

	table.insert(live, {
		frame = frame,
		x = x,
		y = y,
		dirX = dirX,
		dirY = dirY,
		speed = (SPEED_MIN + math.random() * (SPEED_MAX - SPEED_MIN)) * scale,
		age = 0,
		lifetime = LIFETIME_MIN + math.random() * (LIFETIME_MAX - LIFETIME_MIN),
	})
end

local function step(deltaTime: number): ()
	local screenGui = ensureGui()
	local screen = screenGui.AbsoluteSize

	if flying then
		spawnDebt += SPAWN_RATE * QualityController.GetPreset().CosmeticRateScale * deltaTime
		while spawnDebt >= 1 do
			spawnDebt -= 1
			spawnStreak(screen)
		end
	end

	for index = #live, 1, -1 do
		local streak = live[index]
		streak.age += deltaTime
		local t = streak.age / streak.lifetime
		if t >= 1 then
			streak.frame.Visible = false
			table.insert(free, streak.frame)
			table.remove(live, index)
		else
			streak.x += streak.dirX * streak.speed * deltaTime
			streak.y += streak.dirY * streak.speed * deltaTime
			streak.frame.Position = UDim2.fromOffset(streak.x, streak.y)
			-- Quick fade in, longer fade out
			local visibility = if t < 0.25 then t / 0.25 else 1 - (t - 0.25) / 0.75
			streak.frame.BackgroundTransparency = 1 - visibility * (1 - MAX_TRANSPARENCY)
		end
	end

	if not flying and #live == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function ensureLoop(): ()
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

function WindLinesController:Init(): () end

function WindLinesController:Start(): ()

	EventBus.Traversal.Started:Connect(function(player: Player)
		if player ~= LocalPlayer then
			return
		end
		flying = true
		spawnDebt = 0
		local screen = ensureGui().AbsoluteSize
		for _ = 1, LAUNCH_BURST do
			spawnStreak(screen)
		end
		ensureLoop()
		startWind()
	end)
	EventBus.Traversal.Stopped:Connect(function(player: Player)
		if player == LocalPlayer then
			flying = false -- live streaks finish their life, then the loop stops
			stopWind()
		end
	end)
end

return WindLinesController
