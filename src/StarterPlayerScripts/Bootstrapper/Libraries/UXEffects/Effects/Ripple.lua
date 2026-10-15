--!strict
--[[
	@module UXEffects.Effects.Ripple
	@description Wave effect on click/tap.

	Creates a circle that expands from the click point with a fade.
	Satisfying visual feedback for user interactions.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local Pool = require(script.Parent.Parent.Core.Pool)

local Ripple = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_SIZE = 100
local DEFAULT_DURATION = 0.34
local DEFAULT_THICKNESS = 3
local MAX_CONCURRENT = 15

--============================================================================--
-- STATE
--============================================================================--

local player = Players.LocalPlayer
local container: ScreenGui? = nil
local ripplePool: Pool.Pool<Frame>? = nil

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

--- Creates a ripple frame for the pool.
local function createRipple(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Ripple"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(0, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.ZIndex = 997
	
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = DEFAULT_THICKNESS
	stroke.Color = DEFAULT_COLOR
	stroke.Transparency = 0
	stroke.Parent = frame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	
	local currentContainer = ensureContainer()
	if currentContainer then
		frame.Parent = currentContainer
	end
	
	return frame
end

--- Resets a ripple for reuse.
local function resetRipple(frame: Frame): ()
	frame.Visible = false
	frame.Size = UDim2.fromOffset(0, 0)
	
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		stroke.Color = DEFAULT_COLOR
		stroke.Thickness = DEFAULT_THICKNESS
	end
end

--- Initializes the pool.
local function ensurePool(): Pool.Pool<Frame>
	if not ripplePool then
		ripplePool = Pool.new(createRipple, resetRipple, 5, MAX_CONCURRENT)
	end

	local pool = ripplePool
	assert(pool, "Ripple pool failed to initialize")
	return pool
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the ripple effect at a position.
--- @param position Vector2 Position of the ripple center
--- @param config any Optional configuration
function Ripple.play(position: Vector2, config: Types.RippleConfig?): ()
	local currentContainer = ensureContainer()
	if not currentContainer then
		return
	end
	
	local pool = ensurePool()
	local ripple = pool:acquire()
	
	if not ripple then
		return
	end
	
	local settings: Types.RippleConfig = config or {}
	local color = settings.color or DEFAULT_COLOR
	local size = settings.size or DEFAULT_SIZE
	local duration = settings.duration or DEFAULT_DURATION
	local thickness = settings.thickness or DEFAULT_THICKNESS
	local fadeOut = settings.fadeOut ~= false
	
	-- Configures the ripple
	ripple.Position = UDim2.fromOffset(position.X, position.Y)
	ripple.Size = UDim2.fromOffset(0, 0)
	ripple.Visible = true
	
	local stroke = ripple:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = 0
	end
	
	-- Expansion animation
	local expandTween = TweenService:Create(
		ripple,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(size, size) }
	)

	-- Fade animation
	if fadeOut and stroke then
		local fadeTween = TweenService:Create(
			stroke,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1 }
		)
		fadeTween:Play()
	end
	
	expandTween:Play()
	expandTween.Completed:Once(function()
		pool:release(ripple)
	end)
end

--- Plays a ripple at the center of a UI element.
--- @param target GuiObject The target element
--- @param config any Optional configuration
function Ripple.playAt(target: GuiObject, config: Types.RippleConfig?): ()
	local targetX = target.AbsolutePosition.X + (target.AbsoluteSize.X / 2)
	local targetY = target.AbsolutePosition.Y + (target.AbsoluteSize.Y / 2)
	
	Ripple.play(Vector2.new(targetX, targetY), config)
end

--- Attaches an automatic ripple to a button.
--- @param button GuiButton The target button
--- @param config any Optional configuration
--- @return RBXScriptConnection The connection (to disconnect later)
function Ripple.attachToButton(button: GuiButton, config: Types.RippleConfig?): RBXScriptConnection
	return button.Activated:Connect(function()
		Ripple.playAt(button, config)
	end)
end

--- Standard white ripple.
--- @param position Vector2 Ripple position
function Ripple.white(position: Vector2): ()
	Ripple.play(position, {
		color = Color3.new(1, 1, 1),
		size = 80,
		duration = 0.3,
	})
end

--- Accented colored ripple.
--- @param position Vector2 Ripple position
--- @param color Color3 Ripple color
function Ripple.accent(position: Vector2, color: Color3): ()
	Ripple.play(position, {
		color = color,
		size = 120,
		duration = 0.38,
		thickness = 4,
	})
end

--- Cleans up resources.
function Ripple.cleanup(): ()
	if ripplePool then
		ripplePool:clear(function(frame: Frame)
			frame:Destroy()
		end)
		ripplePool = nil
	end
end

return Ripple
