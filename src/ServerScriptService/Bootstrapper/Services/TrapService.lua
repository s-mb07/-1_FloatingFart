--!strict
--[[
	@module TrapService
	@description Server half of the world traps: starts the ReplicatedStorage
	Traps registry (each trap's `Server` part, e.g. the train's kill hitbox).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Traps = require(ReplicatedStorage.Traps)

local TrapService = {}

function TrapService:Init(): () end

function TrapService:Start(): ()
	Traps.Start()
end

return TrapService
