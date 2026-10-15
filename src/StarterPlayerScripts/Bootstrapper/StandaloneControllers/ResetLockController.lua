--!strict
--[[
	@module ResetLockController
	@description Disables "Reset Character" in the Roblox escape menu, so a
	player can't respawn on demand (e.g. to dodge a lost run or skip the walk
	back). Death and respawn stay fully server-driven (LifeService,
	PlayerTeleportService).

	`StarterGui:SetCore("ResetButtonCallback", false)` greys the button out.
	SetCore throws until the CoreScripts have registered the callback, which
	can be a little after the client starts, so it is retried until it sticks
	(off the bootstrap thread, see README §9.8).

	Client-side by engine design (SetCore only exists on the client). It is a
	comfort lock, not a security boundary: an exploiter can still kill their
	own Humanoid, so nothing on the server may assume a death came from
	gameplay.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Logger = require(ReplicatedStorage.Libraries.Logger)

local log = Logger.new("ResetLockController")
local ResetLockController = {}

local RETRY_SECONDS = 0.5
local MAX_ATTEMPTS = 60 -- ~30 s, far longer than CoreScripts ever take

function ResetLockController:Init(): () end

function ResetLockController:Start(): ()
	task.spawn(function()
		for attempt = 1, MAX_ATTEMPTS do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				log:Debug("Reset button disabled (attempt %d).", attempt)
				return
			end
			task.wait(RETRY_SECONDS)
		end
		log:Warn("Could not disable the Reset button: CoreScripts never registered it.")
	end)
end

return ResetLockController
