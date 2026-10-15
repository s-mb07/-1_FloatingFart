--!strict
--[[
	@module TrapController
	@description Client half of the world traps: starts the ReplicatedStorage
	Traps registry (each trap's `Client` part, e.g. the train visuals and
	lights). Cosmetic only, the server owns the hitboxes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = require(script.Parent.Parent.Effects)
local Traps = require(ReplicatedStorage.Traps)

local TrapController = {}

function TrapController:Init(): () end

function TrapController:Start(): ()
	Traps.Start({ SoundEnabled = Effects.IsSoundEnabled })
end

return TrapController
