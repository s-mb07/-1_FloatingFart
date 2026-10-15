--!strict
--[[
	@module PlayerCollisionService
	@description Players never collide with each other (character AND the Fly
	model), which removes the whole "fling" exploit class at the root: no
	contact = no impulse to abuse. Every part of every character sits in the
	`Players` collision group, which collides with the world (Default) but not
	with itself. The group is registered when this module is first required
	(CharacterLock also needs it, to put a character back after a flight), and
	parts added later (Fly model, accessories, tools) are caught by
	DescendantAdded.

	While flying, CharacterLock moves the character to FlyConfig.CollisionGroup
	(collides with nothing) and calls `Apply` to restore this group afterwards.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FlyConfig = require(ReplicatedStorage.Config.FlyConfig)
local GameEvents = require(script.Parent.Parent.GameEvents)
local PlayerService = require(script.Parent.PlayerService)

local PlayerCollisionService = {}

local GROUP = FlyConfig.PlayerCollisionGroup

if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
	PhysicsService:RegisterCollisionGroup(GROUP)
end
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

--- Puts every part of `character` in the player group.
--- @param character Model
function PlayerCollisionService.Apply(character: Model): ()
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = GROUP
		end
	end
end

local function watchPlayer(player: Player): ()
	local function onCharacter(character: Model): ()
		PlayerCollisionService.Apply(character)
		character.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") and descendant.CollisionGroup == "Default" then
				descendant.CollisionGroup = GROUP
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function PlayerCollisionService:Init(): ()
	GameEvents.OnPlayerRegistered:Connect(watchPlayer)
	for _, player in PlayerService.GetRegisteredPlayers() do
		watchPlayer(player)
	end
end

function PlayerCollisionService:Start(): () end

return PlayerCollisionService
