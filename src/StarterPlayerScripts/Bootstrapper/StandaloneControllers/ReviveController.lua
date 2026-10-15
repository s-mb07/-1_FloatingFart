--!strict
--[[
	@module ReviveController
	@description The "Revive" button (StarterGui.MainHUD.TopHUD.Revive). Hidden
	by default; shown for the window the server announces after a lost run,
	hidden again when it lapses or the server closes the offer. Clicking the
	ImageButton only ASKS -- LifeService re-validates everything (saved
	checkpoint, window, payment) and does the teleport.

	Presentation (built once in code on top of the Studio frame, so the
	Studio asset stays the single visual source):
	  - two lines: "REVIVE" (the Studio `Text` label) + "Checkpoint N"
	    (a clone of it, N = the checkpoint the server will send you back to);
	  - a countdown bar under the button draining over the offer window;
	  - pops in (UXEffects.Scale), the button breathes (UXEffects.Pulse) and
	    the wings flap while it is up, pops out when it closes;
	  - placed at REVIVE_POSITION in TopHUD, under the tutorial title so the
	    two never overlap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local log = Logger.new("ReviveController")
local ReviveController = {}

local LocalPlayer = Players.LocalPlayer

--- Inside TopHUD (scale): below the tutorial title at the top of the screen.
local REVIVE_POSITION = UDim2.fromScale(0.5, 0.62)
local WING_FLAP_DEGREES = 12
local TIMER_COLOR = Color3.fromRGB(255, 225, 90)
local TIMER_BACK = Color3.fromRGB(20, 40, 25)

type Parts = {
	Frame: Frame,
	Button: GuiButton,
	SubLabels: { TextLabel },
	TimerFill: Frame,
	Wings: { GuiObject },
}

-- Frames already wired (the gui can be re-cloned on respawn).
local bound: { [Instance]: Parts } = {}
local token: {}? = nil
local timerTween: Tween? = nil
local wingTweens: { Tween } = {}

local function setTexts(label: Instance, text: string): ()
	if label:IsA("TextLabel") then
		label.Text = text
		local stroke = label:FindFirstChild("TextStroke")
		if stroke and stroke:IsA("TextLabel") then
			stroke.Text = text
		end
	end
end

--- Builds the extra pieces (sub line, countdown bar) once per frame.
local function build(frame: Frame): Parts?
	local button = frame:FindFirstChild("ImageButton")
	if not (button and button:IsA("GuiButton")) then
		return nil
	end
	frame.Position = REVIVE_POSITION

	-- Main line: short and big, between the wings
	local main = button:FindFirstChild("Text")
	local subLabels: { TextLabel } = {}
	if main and main:IsA("TextLabel") then
		main.Size = UDim2.fromScale(0.52, 0.5)
		main.Position = UDim2.fromScale(0.5, 0.36)
		setTexts(main, "REVIVE")
		local sub = main:Clone()
		sub.Name = "Sub"
		sub.Size = UDim2.fromScale(0.52, 0.3)
		sub.Position = UDim2.fromScale(0.5, 0.76)
		sub.Parent = button
		table.insert(subLabels, sub)
		local subStroke = sub:FindFirstChild("TextStroke")
		if subStroke and subStroke:IsA("TextLabel") then
			table.insert(subLabels, subStroke)
		end
	end

	-- Countdown bar under the button
	local timer = Instance.new("Frame")
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.fromScale(0.5, 1.1)
	timer.Size = UDim2.fromScale(0.7, 0.13)
	timer.BackgroundColor3 = TIMER_BACK
	timer.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = timer
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = timer
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = TIMER_COLOR
	fill.BorderSizePixel = 0
	corner:Clone().Parent = fill
	fill.Parent = timer
	timer.Parent = frame

	local wings: { GuiObject } = {}
	for _, name in { "Wing L", "Wing R" } do
		local wing = button:FindFirstChild(name)
		if wing and wing:IsA("GuiObject") then
			table.insert(wings, wing)
		end
	end

	button.Activated:Connect(function()
		-- The server freezes the window while the Robux prompt is open: keep
		-- the button up until it says ReviveClosed.
		token = {}
		if timerTween then
			timerTween:Pause()
		end
		NetworkEvents.FireServer("ReviveRequest")
	end)

	return {
		Frame = frame,
		Button = button,
		SubLabels = subLabels,
		TimerFill = fill,
		Wings = wings,
	}
end

--- The Revive parts, built on first sight, or nil if the HUD is not there.
local function getParts(): Parts?
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	local mainHud = gui and gui:FindFirstChild("MainHUD")
	local topHud = mainHud and mainHud:FindFirstChild("TopHUD")
	local frame = topHud and topHud:FindFirstChild("Revive")
	if not frame or not frame:IsA("Frame") then
		return nil
	end
	local parts = bound[frame]
	if not parts then
		parts = build(frame)
		if parts then
			bound[frame] = parts
		end
	end
	return parts
end

local function stopLoops(parts: Parts): ()
	if timerTween then
		timerTween:Cancel()
		timerTween = nil
	end
	for _, tween in wingTweens do
		tween:Cancel()
	end
	table.clear(wingTweens)
	for _, wing in parts.Wings do
		wing.Rotation = 0
	end
	UXEffects.Pulse.stop(parts.Button)
end

local function show(seconds: number, stage: number): ()
	local parts = getParts()
	if not parts then
		return
	end
	stopLoops(parts)
	for _, label in parts.SubLabels do
		label.Text = ("Checkpoint %d"):format(stage)
	end

	UXEffects.Scale.popIn(parts.Frame, { fromScale = 0, duration = 0.4 })
	UXEffects.Pulse.playLoop(parts.Button, { scale = 1.06, duration = 0.9 })

	parts.TimerFill.Size = UDim2.fromScale(1, 1)
	local tween = TweenService:Create(
		parts.TimerFill,
		TweenInfo.new(seconds, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(0, 1) }
	)
	timerTween = tween
	tween:Play()

	for index, wing in parts.Wings do
		local direction = if index == 1 then 1 else -1
		wing.Rotation = -direction * WING_FLAP_DEGREES / 2
		local flap = TweenService:Create(
			wing,
			TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = direction * WING_FLAP_DEGREES / 2 }
		)
		table.insert(wingTweens, flap)
		flap:Play()
	end
end

local function hide(): ()
	local parts = getParts()
	if not parts then
		return
	end
	stopLoops(parts)
	if parts.Frame.Visible then
		UXEffects.Scale.popOut(parts.Frame, { duration = 0.2 })
	end
end

function ReviveController:Init(): ()
	log:Info("Initialized.")
end

function ReviveController:Start(): ()
	task.spawn(function()
		-- Hidden until a loss: wait for the HUD to replicate.
		local gui = LocalPlayer:WaitForChild("PlayerGui")
		local mainHud = gui:WaitForChild("MainHUD", 10)
		if mainHud then
			mainHud:WaitForChild("TopHUD", 10)
		end
		local parts = getParts()
		if parts then
			parts.Frame.Visible = false
		end
	end)

	EventBus.Traversal.ReviveOffered:Connect(function(seconds: number, stage: number)
		local mine = {}
		token = mine
		show(seconds, stage)
		task.delay(seconds, function()
			if token == mine then
				hide()
			end
		end)
	end)

	EventBus.Traversal.ReviveClosed:Connect(function()
		token = nil
		hide()
	end)
	log:Info("Started.")
end

return ReviveController
