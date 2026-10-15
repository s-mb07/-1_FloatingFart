--!strict
--[[
	@module TrailEffectsController
	@description Purely cosmetic: the trail sparkles (TrailService puts a
	"TrailSparkles" ParticleEmitter on every trail wearer's HumanoidRootPart)
	only emit while that player is moving, like the ribbon itself. Checks
	every player's character a few times a second and toggles the emitter
	locally (TrailConfig.Effect.MovingSpeed). Nothing gameplay-related.

	Scheduler task flagged cosmetic: lower graphics quality may slow it down.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local TrailConfig = require(ReplicatedStorage.Config.TrailConfig)

-- Must match TrailService (server).
local SPARKLES_ATTACHMENT_NAME = "TrailSparklesAttachment"
local SPARKLES_NAME = "TrailSparkles"

local TrailEffectsController = {}

local function update(): ()
	local threshold = TrailConfig.Effect.MovingSpeed
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local attachment = root and root:FindFirstChild(SPARKLES_ATTACHMENT_NAME)
		local sparkles = attachment and attachment:FindFirstChild(SPARKLES_NAME)
		if sparkles and sparkles:IsA("ParticleEmitter") and root and root:IsA("BasePart") then
			sparkles.Enabled = root.AssemblyLinearVelocity.Magnitude > threshold
		end
	end
end

function TrailEffectsController:Init(): () end

function TrailEffectsController:Start(): ()
	Scheduler.Every("TrailSparkles", 8, update, true)
end

return TrailEffectsController
