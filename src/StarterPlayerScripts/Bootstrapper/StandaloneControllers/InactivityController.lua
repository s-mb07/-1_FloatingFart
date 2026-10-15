--!strict
--[[
	@module InactivityController
	@description Tells the server the player is active so InactivityService can
	reset its idle timer (anti-kick). Any input pings, throttled to
	InactivityConfig.PingThrottle; one initial ping on Start. Zero payload.
	A player who only watches without touching anything is genuinely idle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InactivityConfig = require(ReplicatedStorage.Config.InactivityConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local InactivityController = {}

local lastPing = 0

local function ping(): ()
	local now = os.clock()
	if now - lastPing < InactivityConfig.PingThrottle then
		return
	end
	lastPing = now
	NetworkEvents.FireServer("PlayerActivityPing")
end

function InactivityController:Init(): ()
	UserInputService.InputBegan:Connect(ping)
	UserInputService.InputChanged:Connect(ping)
end

function InactivityController:Start(): ()
	ping()
end

return InactivityController
