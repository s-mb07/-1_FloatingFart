--!strict
--[[
	@module UXEffects.Effects.Counter
	@description Animated floating counter effect.

	Displays floating text with animation (e.g. "+100 Coins").
	Perfect for feedback on resource gains, damage, XP, etc.

	Characteristics:
	- Upward floating animation
	- Customizable color
	- Prefix/suffix support
	- Pooling for performance
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local Pool = require(script.Parent.Parent.Core.Pool)

local Counter = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_DURATION = 1.0
local DEFAULT_FLOAT_DISTANCE = 80
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local MAX_CONCURRENT = 30

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

--============================================================================--
-- STATE
--============================================================================--

local player = Players.LocalPlayer
local container: ScreenGui? = nil
local activeCount = 0

-- TextLabel pool
local labelPool: Pool.Pool<TextLabel>? = nil

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Creates the container if necessary.
local function ensureContainer(): ScreenGui?
	if container then
		return container
	end
	
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	
	container = playerGui:FindFirstChild("UXEffectsContainer") :: ScreenGui?
	
	if not container then
		local newContainer = Instance.new("ScreenGui")
		newContainer.Name = "UXEffectsContainer"
		newContainer.IgnoreGuiInset = true
		newContainer.DisplayOrder = 999
		newContainer.ResetOnSpawn = false
		newContainer.Parent = playerGui
		container = newContainer
	end
	
	return container
end

--- Creates a TextLabel for the pool.
local function createLabel(): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "FloatingCounter"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(200, 50)
	label.FontFace = FONT
	label.TextSize = 28
	label.TextColor3 = DEFAULT_COLOR
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Visible = false
	label.ZIndex = 1001
	
	local currentContainer = ensureContainer()
	if currentContainer then
		label.Parent = currentContainer
	end
	
	return label
end

--- Resets a TextLabel for reuse.
local function resetLabel(label: TextLabel): ()
	label.Visible = false
	label.Position = UDim2.new(0, 0, 0, 0)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.5
	label.TextColor3 = DEFAULT_COLOR
	label.TextSize = 28
	label.Rotation = 0
end

--- Initializes the pool.
local function ensurePool(): Pool.Pool<TextLabel>
	if not labelPool then
		labelPool = Pool.new(createLabel, resetLabel, 10, MAX_CONCURRENT)
	end

	local pool = labelPool
	assert(pool, "Counter label pool failed to initialize")
	return pool
end

--- Formats the counter text.
local function formatText(value: number, prefix: string?, suffix: string?): string
	local sign = value >= 0 and "+" or ""
	local formatted = sign .. tostring(math.floor(value))
	
	if prefix then
		formatted = prefix .. formatted
	end
	
	if suffix then
		formatted = formatted .. suffix
	end
	
	return formatted
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the floating counter effect.
--- @param position Vector2 Starting position in screen pixels
--- @param config any Effect configuration
function Counter.play(position: Vector2, config: Types.CounterConfig): ()
	local currentContainer = ensureContainer()
	if not currentContainer then
		return
	end
	
	if activeCount >= MAX_CONCURRENT then
		return
	end
	
	local pool = ensurePool()
	local label = pool:acquire()
	
	if not label then
		return
	end
	
	activeCount += 1
	
	local duration = config.duration or DEFAULT_DURATION
	local floatUp = config.floatUp ~= false
	local floatDistance = config.floatDistance or DEFAULT_FLOAT_DISTANCE
	local color = config.color or DEFAULT_COLOR
	
	-- Configures the label
	label.Text = formatText(config.value, config.prefix, config.suffix)
	label.TextColor3 = color
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.5
	label.Visible = true

	-- Entrance animation (scale up)
	label.TextSize = 16
	local entranceTween = TweenService:Create(
		label,
		TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = 28 }
	)
	entranceTween:Play()
	
	-- Float direction
	local targetY = floatUp and (position.Y - floatDistance) or (position.Y + floatDistance)
	local randomX = position.X + math.random(-20, 20)

	-- Floating animation
	local floatTween = TweenService:Create(
		label,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(randomX, targetY),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	
	floatTween:Play()
	floatTween.Completed:Once(function()
		activeCount -= 1
		pool:release(label)
	end)
end

--- Plays the effect from a 3D world position.
--- @param worldPosition Vector3 Position in the world
--- @param config any Effect configuration
function Counter.playFromWorld(worldPosition: Vector3, config: Types.CounterConfig): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	
	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)
	
	if onScreen then
		Counter.play(Vector2.new(screenPosition.X, screenPosition.Y), config)
	end
end

--- Plays the effect next to a UI element.
--- @param target GuiObject The reference UI element
--- @param config any Effect configuration
function Counter.playNear(target: GuiObject, config: Types.CounterConfig): ()
	local targetX = target.AbsolutePosition.X + (target.AbsoluteSize.X / 2)
	local targetY = target.AbsolutePosition.Y + (target.AbsoluteSize.Y / 2)
	
	Counter.play(Vector2.new(targetX, targetY), config)
end

--- Shortcut to display a positive gain (green).
--- @param position Vector2 Starting position
--- @param value number Value to display
--- @param suffix string? Optional suffix
function Counter.gain(position: Vector2, value: number, suffix: string?): ()
	Counter.play(position, {
		value = math.abs(value),
		suffix = suffix,
		color = Color3.fromRGB(100, 255, 100),
		floatUp = true,
	})
end

--- Shortcut to display a negative loss (red).
--- @param position Vector2 Starting position
--- @param value number Value to display
--- @param suffix string? Optional suffix
function Counter.loss(position: Vector2, value: number, suffix: string?): ()
	Counter.play(position, {
		value = -math.abs(value),
		suffix = suffix,
		color = Color3.fromRGB(255, 100, 100),
		floatUp = true,
	})
end

--- Cleans up resources.
function Counter.cleanup(): ()
	if labelPool then
		labelPool:clear(function(label: TextLabel)
			label:Destroy()
		end)
		labelPool = nil
	end
	
	activeCount = 0
end

return Counter
