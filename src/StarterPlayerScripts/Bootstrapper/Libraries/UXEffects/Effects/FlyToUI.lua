--!strict
--[[
	@module UXEffects.Effects.FlyToUI
	@description Effect of icons flying toward a UI element.

	Creates a satisfying animation where icons leave a point
	and fly toward an interface element (e.g. resource collection).

	Characteristics:
	- Spawn with slight random spread
	- Arc animation with easing
	- Pulse on the target element on arrival
	- Pooling management for performance
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local Pool = require(script.Parent.Parent.Core.Pool)

local FlyToUI = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_ICON_SIZE = 40
local DEFAULT_DURATION = 0.5
local DEFAULT_SPREAD = 60
local DEFAULT_COUNT = 1
local MAX_CONCURRENT = 20

--============================================================================--
-- STATE
--============================================================================--

local player = Players.LocalPlayer
local container: ScreenGui? = nil
local activeCount = 0
local originalSizes: {[GuiObject]: UDim2} = {}

-- ImageLabel pool
local iconPool: Pool.Pool<ImageLabel>? = nil

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Creates the VFX container if necessary.
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

--- Creates an ImageLabel for the pool.
local function createIcon(): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = "FlyIcon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromOffset(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
	icon.Visible = false
	icon.ZIndex = 1000
	
	local currentContainer = ensureContainer()
	if currentContainer then
		icon.Parent = currentContainer
	end
	
	return icon
end

--- Resets an ImageLabel for reuse.
local function resetIcon(icon: ImageLabel): ()
	icon.Visible = false
	icon.Position = UDim2.new(0, 0, 0, 0)
	icon.Size = UDim2.fromOffset(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
	icon.ImageTransparency = 0
	icon.Rotation = 0
end

--- Initializes the pool.
local function ensurePool(): Pool.Pool<ImageLabel>
	if not iconPool then
		iconPool = Pool.new(createIcon, resetIcon, 10, MAX_CONCURRENT)
	end

	local pool = iconPool
	assert(pool, "FlyToUI icon pool failed to initialize")
	return pool
end

--- Plays the pulse effect on the target element.
local function playTargetPulse(target: GuiObject): ()
	if not originalSizes[target] then
		originalSizes[target] = target.Size
	end

	local baseSize = originalSizes[target]

	-- Reset to the original size before the pulse
	target.Size = baseSize
	
	local pulseTween = TweenService:Create(
		target,
		TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
		{
			Size = UDim2.new(
				baseSize.X.Scale * 1.2,
				baseSize.X.Offset * 1.2,
				baseSize.Y.Scale * 1.2,
				baseSize.Y.Offset * 1.2
			)
		}
	)
	
	pulseTween:Play()
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the FlyToUI effect.
--- @param startPosition Vector2 Starting position in screen pixels
--- @param targetUI GuiObject Destination UI element
--- @param config any Effect configuration
function FlyToUI.play(
	startPosition: Vector2,
	targetUI: GuiObject,
	config: Types.FlyToUIConfig
): ()
	local currentContainer = ensureContainer()
	if not currentContainer then
		return
	end
	
	local pool = ensurePool()
	local count = math.clamp(config.count or DEFAULT_COUNT, 1, 10)
	local spread = config.spread or DEFAULT_SPREAD
	local duration = config.duration or DEFAULT_DURATION
	local iconSize = config.iconSize or DEFAULT_ICON_SIZE
	
	for i = 1, count do
		task.spawn(function()
			-- Random delay for the burst
			if i > 1 then
				task.wait(math.random(3, 12) / 100)
			end

			-- Checks the global limit
			if activeCount >= MAX_CONCURRENT then
				return
			end

			local icon = pool:acquire()
			if not icon then
				return
			end

			activeCount += 1

			-- Starting position with spread
			local spawnX = startPosition.X + math.random(-spread, spread)
			local spawnY = startPosition.Y + math.random(-spread, spread)
			
			icon.Image = config.iconId
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
			icon.Position = UDim2.fromOffset(spawnX, spawnY)
			icon.ImageTransparency = 0
			icon.Rotation = math.random(-15, 15)
			icon.Visible = true
			
			-- Phase 1: Small initial jump
			local jumpTween = TweenService:Create(
				icon,
				TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{
					Size = UDim2.fromOffset(iconSize * 1.3, iconSize * 1.3),
					Position = UDim2.fromOffset(
						spawnX + math.random(-20, 20),
						spawnY - 30 + math.random(-10, 10)
					),
					Rotation = math.random(-25, 25)
				}
			)
			
			jumpTween:Play()
			jumpTween.Completed:Wait()
			
			-- Target position (center of the UI)
			local targetX = targetUI.AbsolutePosition.X + (targetUI.AbsoluteSize.X / 2)
			local targetY = targetUI.AbsolutePosition.Y + (targetUI.AbsoluteSize.Y / 2)

			-- Phase 2: Flight toward the target
			local flyTween = TweenService:Create(
				icon,
				TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{
					Position = UDim2.fromOffset(targetX, targetY),
					Size = UDim2.fromOffset(iconSize * 0.5, iconSize * 0.5),
					ImageTransparency = 0.3,
					Rotation = 0
				}
			)
			
			flyTween:Play()
			flyTween.Completed:Wait()
			
			-- Effect on the target
			playTargetPulse(targetUI)

			-- Releases the icon
			activeCount -= 1
			pool:release(icon)

			-- Callback
			if config.onComplete and i == count then
				config.onComplete()
			end
		end)
	end
end

--- Plays the effect from a 3D world position.
--- @param worldPosition Vector3 Position in the world
--- @param targetUI GuiObject Destination UI element
--- @param config any Effect configuration
function FlyToUI.playFromWorld(
	worldPosition: Vector3,
	targetUI: GuiObject,
	config: Types.FlyToUIConfig
): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	
	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)
	
	if onScreen then
		FlyToUI.play(Vector2.new(screenPosition.X, screenPosition.Y), targetUI, config)
	end
end

--- Plays the effect from the center of the screen.
--- @param targetUI GuiObject Destination UI element
--- @param config any Effect configuration
function FlyToUI.playFromCenter(
	targetUI: GuiObject,
	config: Types.FlyToUIConfig
): ()
	local currentContainer = ensureContainer()
	if not currentContainer then
		return
	end
	
	local screenSize = currentContainer.AbsoluteSize
	local centerPosition = Vector2.new(screenSize.X / 2, screenSize.Y / 2)
	
	FlyToUI.play(centerPosition, targetUI, config)
end

--- Cleans up resources and resets the size cache.
function FlyToUI.cleanup(): ()
	if iconPool then
		iconPool:clear(function(icon: ImageLabel)
			icon:Destroy()
		end)
		iconPool = nil
	end
	
	table.clear(originalSizes)
	activeCount = 0
end

return FlyToUI
