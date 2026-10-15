--!strict
--[[
	@module AnalyticsController
	@description Client-side entry point for reporting an analytics event.
	`AnalyticsService` (the Roblox engine API) is callable ONLY from the
	server -- so this controller just does FireServer("AnalyticsEvent", ...),
	the server (see ServerScriptService/.../AnalyticsService.lua) alone
	decides whether the event is legitimate (whitelist) before actually logging it.

	ONLY register events here whose source of truth is the CLIENT
	(a player saw a given screen, spent a given time on a given panel...) --
	anything touching a game value (currency, purchase...) must be logged
	directly from the relevant server Service (see GameEvents.
	OnCurrencyEarned/OnCurrencySpent, already wired into AnalyticsService),
	never reported by the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)

local log = Logger.new("AnalyticsController")
local AnalyticsController = {}

--- @param eventName string -- MUST be present in the server whitelist (see AnalyticsService.lua)
--- @param value number?
function AnalyticsController.LogEvent(eventName: string, value: number?): ()
	NetworkEvents.FireServer("AnalyticsEvent", {
		EventName = eventName,
		Value = value,
	})
end

function AnalyticsController:Init(): ()
	log:Info("Initialized.")
end

function AnalyticsController:Start(): ()
end

return AnalyticsController
