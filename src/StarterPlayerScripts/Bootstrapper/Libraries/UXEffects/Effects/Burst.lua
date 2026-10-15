--!strict
--[[
	@module UXEffects.Effects.Burst
	@description 2D particle burst effect.

	Creates an explosion of colored particles from a point.
	Perfect for rewards, level up, big collections.

	Features:
	- Particles with simplified physics (gravity)
	- Multiple colors
	- Randomized size and speed
	- Pooling for performance
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local Pool = require(script.Parent.Parent.Core.Pool)

local Burst = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_PARTICLE_COUNT = 20
local DEFAULT_LIFETIME = 1.0
local DEFAULT_SPREAD = 360
local DEFAULT_SPEED_MIN = 150
local DEFAULT_SPEED_MAX = 350
local DEFAULT_SIZE_MIN = 6
local DEFAULT_SIZE_MAX = 14
local DEFAULT_GRAVITY = 400
local MAX_CONCURRENT = 100

local DEFAULT_COLORS = {
	Color3.fromRGB(255, 215, 0),   -- Gold
	Color3.fromRGB(255, 100, 100), -- Red
	Color3.fromRGB(100, 255, 100), -- Green
	Color3.fromRGB(100, 200, 255), -- Blue
	Color3.fromRGB(255, 150, 255), -- Pink
}

--============================================================================--
-- TYPES
--============================================================================--

type Particle = {
	frame: Frame,
	x: number,
	y: number,
	velocityX: number,
	velocityY: number,
	lifetime: number,
	maxLifetime: number,
	rotation: number,
	rotationSpeed: number,
}

--============================================================================--
-- STATE
--============================================================================--

local player = Players.LocalPlayer
local container: ScreenGui? = nil
local activeParticles: {Particle} = {}
local updateConnection: RBXScriptConnection? = nil
local particlePool: Pool.Pool<Frame>? = nil

--============================================================================--
-- PRIVATE FUNCTIONS
--============================================================================--

--- Creates the container if needed.
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

--- Creates a particle for the pool.
local function createParticle(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "BurstParticle"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(10, 10)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 998

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local currentContainer = ensureContainer()
	if currentContainer then
		frame.Parent = currentContainer
	end

	return frame
end

--- Resets a particle for reuse.
local function resetParticle(frame: Frame): ()
	frame.Visible = false
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundTransparency = 0
	frame.Rotation = 0
end

--- Initializes the pool.
local function ensurePool(): Pool.Pool<Frame>
	if not particlePool then
		particlePool = Pool.new(createParticle, resetParticle, 20, MAX_CONCURRENT)
	end

	local pool = particlePool
	assert(pool, "Burst particle pool failed to initialize")
	return pool
end

--- Starts the update loop if needed.
local function ensureUpdateLoop(): ()
	if updateConnection then
		return
	end

	updateConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
		local pool = ensurePool()
		local toRemove: {number} = {}

		for i, particle in activeParticles do
			particle.lifetime -= deltaTime

			if particle.lifetime <= 0 then
				table.insert(toRemove, i)
				particle.frame.Visible = false
				pool:release(particle.frame)
			else
				-- Physics
				particle.velocityY += DEFAULT_GRAVITY * deltaTime
				particle.x += particle.velocityX * deltaTime
				particle.y += particle.velocityY * deltaTime
				particle.rotation += particle.rotationSpeed * deltaTime

				-- Fade out
				local alpha = particle.lifetime / particle.maxLifetime
				particle.frame.BackgroundTransparency = 1 - alpha

				-- Position
				particle.frame.Position = UDim2.fromOffset(particle.x, particle.y)
				particle.frame.Rotation = particle.rotation
			end
		end

		-- Removes dead particles (in reverse order)
		for i = #toRemove, 1, -1 do
			table.remove(activeParticles, toRemove[i])
		end

		-- Stops the loop when no particles are left
		if #activeParticles == 0 and updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end
	end)
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the burst effect.
--- @param position Vector2 Center position of the explosion
--- @param config any Optional configuration
function Burst.play(position: Vector2, config: Types.BurstConfig?): ()
	local currentContainer = ensureContainer()
	if not currentContainer then
		return
	end

	local settings: Types.BurstConfig = config or {}
	local particleCount = settings.particleCount or DEFAULT_PARTICLE_COUNT
	local colors = settings.colors or DEFAULT_COLORS
	local lifetime = settings.lifetime or DEFAULT_LIFETIME
	local spread = settings.spread or DEFAULT_SPREAD

	local sizeRange = settings.size or NumberRange.new(DEFAULT_SIZE_MIN, DEFAULT_SIZE_MAX)
	local speedRange = settings.speed or NumberRange.new(DEFAULT_SPEED_MIN, DEFAULT_SPEED_MAX)

	local pool = ensurePool()

	for _ = 1, particleCount do
		if #activeParticles >= MAX_CONCURRENT then
			break
		end

		local frame = pool:acquire()
		if not frame then
			break
		end

		-- Random parameters
		local angle = math.rad(math.random(0, spread) - spread / 2 - 90)
		local speed = math.random(speedRange.Min :: number, speedRange.Max :: number)
		local size = math.random(sizeRange.Min :: number, sizeRange.Max :: number)
		local color = colors[math.random(1, #colors)]

		-- Configures the particle
		frame.Size = UDim2.fromOffset(size, size)
		frame.Position = UDim2.fromOffset(position.X, position.Y)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0
		frame.Visible = true

		local particle: Particle = {
			frame = frame,
			x = position.X,
			y = position.Y,
			velocityX = math.cos(angle) * speed,
			velocityY = math.sin(angle) * speed,
			lifetime = lifetime,
			maxLifetime = lifetime,
			rotation = 0,
			rotationSpeed = math.random(-360, 360),
		}

		table.insert(activeParticles, particle)
	end

	ensureUpdateLoop()
end

--- Plays the effect from a 3D world position.
--- @param worldPosition Vector3 Position in the world
--- @param config any Optional configuration
function Burst.playFromWorld(worldPosition: Vector3, config: Types.BurstConfig?): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local screenPosition, onScreen = camera:WorldToScreenPoint(worldPosition)

	if onScreen then
		Burst.play(Vector2.new(screenPosition.X, screenPosition.Y), config)
	end
end

--- Plays the effect at the center of a UI element.
--- @param target GuiObject The reference UI element
--- @param config any Optional configuration
function Burst.playAt(target: GuiObject, config: Types.BurstConfig?): ()
	local targetX = target.AbsolutePosition.X + (target.AbsoluteSize.X / 2)
	local targetY = target.AbsolutePosition.Y + (target.AbsoluteSize.Y / 2)

	Burst.play(Vector2.new(targetX, targetY), config)
end

--- Golden burst (reward).
--- @param position Vector2 Center position
function Burst.gold(position: Vector2): ()
	Burst.play(position, {
		colors = {
			Color3.fromRGB(255, 215, 0),
			Color3.fromRGB(255, 180, 0),
			Color3.fromRGB(255, 240, 150),
		},
		particleCount = 25,
	})
end

--- Rainbow burst (level up, rare).
--- @param position Vector2 Center position
function Burst.rainbow(position: Vector2): ()
	Burst.play(position, {
		colors = {
			Color3.fromRGB(255, 0, 0),
			Color3.fromRGB(255, 127, 0),
			Color3.fromRGB(255, 255, 0),
			Color3.fromRGB(0, 255, 0),
			Color3.fromRGB(0, 0, 255),
			Color3.fromRGB(139, 0, 255),
		},
		particleCount = 40,
		speed = NumberRange.new(200, 450),
	})
end

--- Cleans up all particles and resources.
function Burst.cleanup(): ()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	if particlePool then
		particlePool:clear(function(frame: Frame)
			frame:Destroy()
		end)
		particlePool = nil
	end

	table.clear(activeParticles)
end

return Burst
