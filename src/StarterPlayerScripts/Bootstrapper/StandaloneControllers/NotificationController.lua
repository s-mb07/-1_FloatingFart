--!strict
--[[
	@module NotificationController
	@description Renders every player notification in the Studio-authored
	MainHUD/NotificationsFrame (UIListLayout + hidden `TextTemplate`), in the
	HUD's text style: the template is the dark shadow, its `TextStroke` child
	is the front text, tinted by type.

	Two sources, same look:
	  - `EventBus.Notification.Received` -- server-pushed (NotificationService,
	    bridged by NetworkBridgeController);
	  - `EventBus.Notification.Show` -- client-local feedback fired by any
	    controller/panel (a code redeemed, ...).

	Each line pops in (UXEffects.Scale), stays `Duration` seconds (default
	DEFAULT_DURATION), then fades out and is destroyed. Newest on top, at most
	MAX_VISIBLE lines (the oldest leaves early). The same message arriving
	again while still on screen does not stack: it bounces, shows a "x2"
	count and restarts its timer.

	Kept as its own controller rather than folded into NetworkBridgeController
	-- that controller only bridges network -> EventBus, it never touches UI.
	MainHUD has ResetOnSpawn = false: resolved once; lines arriving before
	that are queued.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local NotificationController = {}

type NotificationType = "Info" | "Success" | "Warning" | "Error"

type NotificationPayload = {
	Message: string,
	Type: NotificationType?,
	Duration: number?,
}

type Line = {
	Key: string,
	Message: string,
	Shadow: TextLabel,
	Front: TextLabel,
	Count: number,
	Token: number,
}

local DEFAULT_DURATION = 3
local MAX_VISIBLE = 4
local FADE_SECONDS = 0.35

--- Front text color per type (the shadow keeps the template's dark color).
local TYPE_COLORS: { [NotificationType]: Color3 } = {
	Info = Color3.fromRGB(255, 255, 255),
	Success = Color3.fromRGB(125, 255, 120),
	Warning = Color3.fromRGB(255, 205, 80),
	Error = Color3.fromRGB(255, 95, 95),
}

local container: Frame? = nil
local template: TextLabel? = nil
local pending: { NotificationPayload } = {}
local lines: { Line } = {} -- oldest first
local order = 0

local function setText(line: Line): ()
	local text = if line.Count > 1 then ("%s x%d"):format(line.Message, line.Count) else line.Message
	line.Shadow.Text = text
	line.Front.Text = text
end

local function removeLine(line: Line): ()
	local index = table.find(lines, line)
	if index then
		table.remove(lines, index)
	end
end

--- Fades both labels (and their strokes) out, then destroys the line.
local function fadeOut(line: Line, seconds: number): ()
	removeLine(line)
	line.Token += 1 -- cancels its pending hold timer
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, label in { line.Shadow, line.Front } do
		TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(seconds, function()
		line.Shadow:Destroy()
	end)
end

--- (Re)starts the line's hold timer.
local function hold(line: Line, seconds: number): ()
	line.Token += 1
	local token = line.Token
	task.delay(seconds, function()
		if line.Token == token then
			fadeOut(line, FADE_SECONDS)
		end
	end)
end

local function show(payload: NotificationPayload): ()
	local list, base = container, template
	if not (list and base) then
		table.insert(pending, payload)
		return
	end
	if type(payload) ~= "table" or type(payload.Message) ~= "string" or payload.Message == "" then
		return
	end
	local kind: NotificationType = if payload.Type and TYPE_COLORS[payload.Type] then payload.Type else "Info"
	local duration = if type(payload.Duration) == "number" then payload.Duration else DEFAULT_DURATION
	local key = kind .. "|" .. payload.Message

	-- Same message still on screen: count it instead of stacking a copy
	for _, line in lines do
		if line.Key == key then
			line.Count += 1
			setText(line)
			UXEffects.Scale.bounce(line.Shadow, { fromScale = 0.8, duration = 0.4 })
			hold(line, duration)
			return
		end
	end

	while #lines >= MAX_VISIBLE do
		fadeOut(lines[1], 0.15)
	end

	local shadow = base:Clone()
	shadow.Name = "Notification"
	shadow.Visible = true -- only the template itself stays hidden
	order -= 1
	shadow.LayoutOrder = order -- newest on top
	local front = shadow:FindFirstChild("TextStroke")
	if not (front and front:IsA("TextLabel")) then
		shadow:Destroy()
		return
	end
	front.TextColor3 = TYPE_COLORS[kind]

	local line: Line = {
		Key = key,
		Message = payload.Message,
		Shadow = shadow,
		Front = front,
		Count = 1,
		Token = 0,
	}
	setText(line)
	shadow.Parent = list
	table.insert(lines, line)
	UXEffects.Scale.popIn(shadow, { fromScale = 0.4, duration = 0.3 })
	hold(line, duration)
end

function NotificationController:Init(): ()
	EventBus.Notification.Received:Connect(show)
	EventBus.Notification.Show:Connect(show)
end

function NotificationController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/NotificationsFrame", function(frame: Instance)
		local base = frame:WaitForChild("TextTemplate") :: TextLabel
		base.Visible = false
		container = frame :: Frame
		template = base
		local queued = pending
		pending = {}
		for _, payload in queued do
			show(payload)
		end
	end)
end

return NotificationController
