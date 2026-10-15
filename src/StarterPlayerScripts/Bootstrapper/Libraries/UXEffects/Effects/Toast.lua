--!strict
--[[
	@module UXEffects.Effects.Toast
	@description Stackable toast notifications.

	Displays temporary notifications with different types
	(info, success, warning, error). Toasts stack automatically.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Types = require(script.Parent.Parent.Types)
local AssetManifest = require(ReplicatedFirst.AssetManifest)

local Toast = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_DURATION = 3
local TOAST_HEIGHT = 50
local TOAST_WIDTH = 300
local TOAST_MARGIN = 10
local SLIDE_DURATION = 0.25
local MAX_TOASTS = 5

local TYPE_COLORS = {
	Info = Color3.fromRGB(60, 130, 200),
	Success = Color3.fromRGB(60, 180, 80),
	Warning = Color3.fromRGB(230, 170, 50),
	Error = Color3.fromRGB(200, 60, 60),
}

local TYPE_ICONS = AssetManifest.Toast

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)

--============================================================================--
-- STATE
--============================================================================--

local player = Players.LocalPlayer
local container: Frame? = nil
local screenGui: ScreenGui? = nil
local activeToasts: {Frame} = {}

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Creates the toast container.
local function ensureContainer(): Frame?
	if container and screenGui then
		return container
	end
	
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	
	-- ScreenGui dedicated to toasts
	local gui = playerGui:FindFirstChild("UXToasts") :: ScreenGui?

	if not gui then
		local newGui = Instance.new("ScreenGui")
		newGui.Name = "UXToasts"
		newGui.IgnoreGuiInset = true
		newGui.DisplayOrder = 1000
		newGui.ResetOnSpawn = false
		newGui.Parent = playerGui
		gui = newGui
	end

	assert(gui, "Toast ScreenGui failed to initialize")
	screenGui = gui

	local newContainerCandidate = gui:FindFirstChild("Container") :: Frame?

	if not newContainerCandidate then
		local newContainer = Instance.new("Frame")
		newContainer.Name = "Container"
		newContainer.AnchorPoint = Vector2.new(1, 0)
		newContainer.Position = UDim2.new(1, -20, 0, 80)
		newContainer.Size = UDim2.new(0, TOAST_WIDTH, 1, -100)
		newContainer.BackgroundTransparency = 1
		newContainer.Parent = gui
		newContainerCandidate = newContainer
	end

	container = newContainerCandidate
	return newContainerCandidate
end

--- Repositions all active toasts.
local function repositionToasts(): ()
	for i, toast in activeToasts do
		local targetY = (i - 1) * (TOAST_HEIGHT + TOAST_MARGIN)
		
		local tween = TweenService:Create(
			toast,
			TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, targetY) }
		)
		tween:Play()
	end
end

--- Creates a toast frame.
local function createToastFrame(
	message: string,
	toastType: string,
	icon: string?
): Frame
	local toastFrame = Instance.new("Frame")
	toastFrame.Name = "Toast"
	toastFrame.Size = UDim2.new(1, 0, 0, TOAST_HEIGHT)
	toastFrame.Position = UDim2.new(1, 50, 0, 0)
	toastFrame.BackgroundColor3 = TYPE_COLORS[toastType] or TYPE_COLORS.Info
	toastFrame.BackgroundTransparency = 0.1
	toastFrame.ClipsDescendants = true
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toastFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.8
	stroke.Thickness = 1
	stroke.Parent = toastFrame
	
	-- Icon
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.Position = UDim2.new(0, 12, 0.5, 0)
	iconImage.Size = UDim2.fromOffset(24, 24)
	iconImage.BackgroundTransparency = 1
	iconImage.Image = icon or TYPE_ICONS[toastType] or TYPE_ICONS.Info
	iconImage.ImageColor3 = Color3.new(1, 1, 1)
	iconImage.Parent = toastFrame
	
	-- Message
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(0, 44, 0.5, 0)
	label.Size = UDim2.new(1, -54, 0, 30)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = message
	label.Parent = toastFrame
	
	-- Progress bar
	local progressBar = Instance.new("Frame")
	progressBar.Name = "Progress"
	progressBar.AnchorPoint = Vector2.new(0, 1)
	progressBar.Position = UDim2.fromScale(0, 1)
	progressBar.Size = UDim2.new(1, 0, 0, 3)
	progressBar.BackgroundColor3 = Color3.new(1, 1, 1)
	progressBar.BackgroundTransparency = 0.5
	progressBar.BorderSizePixel = 0
	progressBar.Parent = toastFrame
	
	return toastFrame
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Displays a toast.
--- @param config any Toast configuration
function Toast.show(config: Types.ToastConfig): ()
	local toastContainer = ensureContainer()
	if not toastContainer then
		return
	end

	-- Limits the number of toasts
	local evicted = false
	while #activeToasts >= MAX_TOASTS do
		local oldest = table.remove(activeToasts, 1)
		if oldest then
			oldest:Destroy()
			evicted = true
		end
	end
	if evicted then
		-- Without this, the remaining toasts keep the Y offset of their old rank
		-- and leave a visible gap until one expires naturally.
		repositionToasts()
	end

	local toastType = config.type or "Info"
	local duration = config.duration or DEFAULT_DURATION

	-- Creates the toast
	local toastFrame = createToastFrame(config.message, toastType, config.icon)
	toastFrame.Parent = toastContainer

	-- Positions before animation
	local targetY = #activeToasts * (TOAST_HEIGHT + TOAST_MARGIN)
	toastFrame.Position = UDim2.new(1, 50, 0, targetY)

	table.insert(activeToasts, toastFrame)

	-- Entrance animation
	local entranceTween = TweenService:Create(
		toastFrame,
		TweenInfo.new(SLIDE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, targetY) }
	)
	entranceTween:Play()
	
	-- Progress bar animation
	local progressBar = toastFrame:FindFirstChild("Progress") :: Frame?
	if progressBar then
		local progressTween = TweenService:Create(
			progressBar,
			TweenInfo.new(duration, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromOffset(0, 3) }
		)
		progressTween:Play()
	end
	
	-- Disappearance after delay
	task.delay(duration, function()
		if not toastFrame.Parent then
			return
		end

		-- Exit animation
		local exitTween = TweenService:Create(
			toastFrame,
			TweenInfo.new(SLIDE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, 50, 0, toastFrame.Position.Y.Offset) }
		)
		exitTween:Play()
		exitTween.Completed:Once(function()
			local index = table.find(activeToasts, toastFrame)
			if index then
				table.remove(activeToasts, index)
			end
			toastFrame:Destroy()
			repositionToasts()
		end)
	end)
end

--- Displays an info toast.
--- @param message string The message to display
--- @param duration number? Display duration
function Toast.info(message: string, duration: number?): ()
	Toast.show({
		message = message,
		type = "Info",
		duration = duration,
	})
end

--- Displays a success toast.
--- @param message string The message to display
--- @param duration number? Display duration
function Toast.success(message: string, duration: number?): ()
	Toast.show({
		message = message,
		type = "Success",
		duration = duration,
	})
end

--- Displays a warning toast.
--- @param message string The message to display
--- @param duration number? Display duration
function Toast.warning(message: string, duration: number?): ()
	Toast.show({
		message = message,
		type = "Warning",
		duration = duration,
	})
end

--- Displays an error toast.
--- @param message string The message to display
--- @param duration number? Display duration
function Toast.error(message: string, duration: number?): ()
	Toast.show({
		message = message,
		type = "Error",
		duration = duration,
	})
end

--- Cleans up all toasts.
function Toast.cleanup(): ()
	for _, toast in activeToasts do
		toast:Destroy()
	end
	
	table.clear(activeToasts)
end

return Toast
