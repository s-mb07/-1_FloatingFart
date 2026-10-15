--!strict
--[[
	@module UXEffects.Effects.Confetti
	@description Confetti effect for celebrations.

	Two modes, same particles and physics:
	  - rain (default): confetti falls from the top of the screen;
	  - burst (`origins` + `angles`): confetti is shot from points on the
	    screen (e.g. the two bottom corners, see `cannons`), slows down
	    with air drag, then flutters down.
	Each piece "flips" (width oscillates) to fake a paper sheet turning in 3D.
	Sizes and speeds scale with the viewport so a phone gets the same look
	as a 1080p screen.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local Pool = require(script.Parent.Parent.Core.Pool)

local Confetti = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local DEFAULT_PARTICLE_COUNT = 60
local DEFAULT_DURATION = 2.5
local DEFAULT_VELOCITY = 300
local DEFAULT_GRAVITY = 200
local DEFAULT_SPREAD = 400
local DEFAULT_ANGLE_SPREAD = 18
--- Fraction of velocity kept per second (air drag, burst pieces slow down fast).
local DRAG_PER_SECOND = 0.12
--- Fall speed cap (px/s at 1080p): a paper sheet never free-falls.
local TERMINAL_VELOCITY = 260
--- Reference height the pixel constants above were tuned for.
local REFERENCE_HEIGHT = 1080
local MAX_CONCURRENT = 200

local DEFAULT_COLORS = {
	Color3.fromRGB(255, 100, 100),
	Color3.fromRGB(100, 255, 100),
	Color3.fromRGB(100, 150, 255),
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(255, 150, 255),
	Color3.fromRGB(100, 255, 255),
}

--============================================================================--
-- TYPES
--============================================================================--

type ConfettiParticle = {
	frame: Frame,
	x: number,
	y: number,
	velocityX: number,
	velocityY: number,
	rotationSpeed: number,
	swayPhase: number,
	swaySpeed: number,
	flipPhase: number,
	flipSpeed: number,
	width: number,
	height: number,
	gravity: number,
	drag: number,
	scale: number,
	lifetime: number,
	maxLifetime: number,
}

--============================================================================--
-- STATE
--============================================================================--

local player = Players.LocalPlayer
local container: ScreenGui? = nil
local activeParticles: {ConfettiParticle} = {}
local updateConnection: RBXScriptConnection? = nil
local particlePool: Pool.Pool<Frame>? = nil

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

--- Creates a confetti particle.
local function createParticle(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Confetti"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(10, 15)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 996
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = frame
	
	local currentContainer = ensureContainer()
	if currentContainer then
		frame.Parent = currentContainer
	end
	
	return frame
end

--- Resets a particle.
local function resetParticle(frame: Frame): ()
	frame.Visible = false
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundTransparency = 0
	frame.Rotation = 0
end

--- Initializes the pool.
local function ensurePool(): Pool.Pool<Frame>
	if not particlePool then
		particlePool = Pool.new(createParticle, resetParticle, 30, MAX_CONCURRENT)
	end

	local pool = particlePool
	assert(pool, "Confetti particle pool failed to initialize")
	return pool
end

--- Starts the update loop.
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
				local drag = particle.drag ^ deltaTime
				particle.velocityX *= drag
				particle.velocityY = particle.velocityY * drag + particle.gravity * deltaTime
				if particle.drag < 1 then
					particle.velocityY = math.min(particle.velocityY, TERMINAL_VELOCITY * particle.scale)
				end
				particle.x += particle.velocityX * deltaTime
				particle.y += particle.velocityY * deltaTime

				-- Sway grows as the piece slows down (fluttering paper)
				particle.swayPhase += particle.swaySpeed * deltaTime
				local swayOffset = math.sin(particle.swayPhase) * 24 * particle.scale

				particle.frame.Rotation += particle.rotationSpeed * deltaTime

				-- 3D flip: the width goes through 0 and back
				particle.flipPhase += particle.flipSpeed * deltaTime
				local flip = math.abs(math.cos(particle.flipPhase))
				particle.frame.Size = UDim2.fromOffset(particle.width * (0.15 + 0.85 * flip), particle.height)

				-- Fade only during the last 30% of its life
				local alpha = math.clamp(particle.lifetime / (particle.maxLifetime * 0.3), 0, 1)
				particle.frame.BackgroundTransparency = 1 - alpha

				particle.frame.Position = UDim2.fromOffset(particle.x + swayOffset, particle.y)
			end
		end

		-- Removes dead particles
		for i = #toRemove, 1, -1 do
			table.remove(activeParticles, toRemove[i])
		end

		-- Stops the loop if there are no more particles
		if #activeParticles == 0 and updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end
	end)
end

--============================================================================--
-- PUBLIC FUNCTIONS
--============================================================================--

--- Plays the confetti effect.
--- @param config any Optional configuration
function Confetti.play(config: Types.ConfettiConfig?): ()
	local currentContainer = ensureContainer()
	if not currentContainer then
		return
	end
	
	local settings: Types.ConfettiConfig = config or {}
	local particleCount = settings.particleCount or DEFAULT_PARTICLE_COUNT
	local colors = settings.colors or DEFAULT_COLORS
	local spread = settings.spread or DEFAULT_SPREAD
	local velocity = settings.velocity or DEFAULT_VELOCITY
	local duration = settings.duration or DEFAULT_DURATION
	
	local pool = ensurePool()
	local screenSize = currentContainer.AbsoluteSize
	local scale = math.max(screenSize.Y / REFERENCE_HEIGHT, 0.45)
	local gravity = (settings.gravity or DEFAULT_GRAVITY) * scale
	local origins = settings.origins
	local angles = settings.angles or {}
	local angleSpread = settings.angleSpread or DEFAULT_ANGLE_SPREAD

	for index = 1, particleCount do
		if #activeParticles >= MAX_CONCURRENT then
			break
		end

		local frame = pool:acquire()
		if not frame then
			break
		end

		local spawnX, spawnY, velocityX, velocityY
		if origins and #origins > 0 then
			-- Burst: round-robin over the origins, shot along that origin's angle
			local slot = (index - 1) % #origins + 1
			local origin = origins[slot]
			spawnX = origin.X * screenSize.X
			spawnY = origin.Y * screenSize.Y
			local angle = math.rad((angles[slot] or -90) + (math.random() * 2 - 1) * angleSpread)
			local speed = velocity * scale * (0.6 + math.random() * 0.8)
			velocityX = math.cos(angle) * speed
			velocityY = math.sin(angle) * speed
		else
			-- Rain: top of the screen, spread horizontally
			spawnX = screenSize.X / 2 + math.random(-spread, spread) * scale
			spawnY = -20
			velocityX = math.random(-50, 50) * scale
			velocityY = (velocity + math.random(-50, 50)) * scale
		end

		local width = math.random(8, 14) * scale * 1.4
		local height = math.random(12, 20) * scale * 1.4

		frame.Size = UDim2.fromOffset(width, height)
		frame.Position = UDim2.fromOffset(spawnX, spawnY)
		frame.BackgroundColor3 = colors[math.random(1, #colors)]
		frame.BackgroundTransparency = 0
		frame.Rotation = math.random(0, 360)
		frame.Visible = true

		local lifetime = duration + math.random() * 0.8
		local particle: ConfettiParticle = {
			frame = frame,
			x = spawnX,
			y = spawnY,
			velocityX = velocityX,
			velocityY = velocityY,
			rotationSpeed = math.random(-260, 260),
			swayPhase = math.random() * math.pi * 2,
			swaySpeed = 2 + math.random() * 3,
			flipPhase = math.random() * math.pi,
			flipSpeed = 4 + math.random() * 6,
			width = width,
			height = height,
			gravity = gravity,
			-- Rain keeps its speed, a burst slows down then flutters
			drag = if origins and #origins > 0 then DRAG_PER_SECOND else 1,
			scale = scale,
			lifetime = lifetime,
			maxLifetime = lifetime,
		}

		table.insert(activeParticles, particle)
	end

	ensureUpdateLoop()
end

--- Golden confetti (reward).
function Confetti.gold(): ()
	Confetti.play({
		colors = {
			Color3.fromRGB(255, 215, 0),
			Color3.fromRGB(255, 180, 0),
			Color3.fromRGB(255, 240, 150),
			Color3.fromRGB(200, 150, 0),
		},
		particleCount = 80,
	})
end

--- Rainbow confetti (major celebration).
function Confetti.rainbow(): ()
	Confetti.play({
		colors = {
			Color3.fromRGB(255, 0, 0),
			Color3.fromRGB(255, 127, 0),
			Color3.fromRGB(255, 255, 0),
			Color3.fromRGB(0, 255, 0),
			Color3.fromRGB(0, 0, 255),
			Color3.fromRGB(75, 0, 130),
			Color3.fromRGB(148, 0, 211),
		},
		particleCount = 100,
		velocity = 350,
	})
end

--- Light confetti (small success).
function Confetti.light(): ()
	Confetti.play({
		particleCount = 30,
		velocity = 200,
		duration = 1.5,
	})
end

--- Two cannons in the bottom corners shooting up toward the center
--- (level up, big reward).
--- @param colors {Color3}? Optional palette (default: the rainbow set)
function Confetti.cannons(colors: {Color3}?): ()
	Confetti.play({
		colors = colors,
		particleCount = 140,
		velocity = 2300,
		duration = 2.8,
		gravity = 480,
		origins = { Vector2.new(0, 1), Vector2.new(1, 1) },
		angles = { -58, -122 },
		angleSpread = 14,
	})
end

--- Cleans up resources.
function Confetti.cleanup(): ()
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

return Confetti
