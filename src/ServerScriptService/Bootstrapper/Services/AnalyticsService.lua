--!strict
--[[
	@module AnalyticsService
	@description Thin wrapper over Roblox's built-in `AnalyticsService` (the
	engine service, not this module -- unfortunate name collision, kept
	because it's the platform's own name). Centralizes event names/shapes so
	the rest of the codebase never calls the engine service directly (same
	reasoning as NetworkEvents for Remotes: one seam, no divergent copies).

	Auto-wired to GameEvents.OnCurrencyEarned/OnCurrencySpent (economy) and
	OnDataLoaded (progression) as examples -- extend `Init()` as you add more
	GameEvents worth tracking. Every method below maps 1:1 to a real
	AnalyticsService method; see the official reference before adding a new
	one, the exact enum values matter (Enum.AnalyticsEconomyFlowType.Source/Sink).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = game:GetService("AnalyticsService")

local GameEvents = require(script.Parent.Parent.GameEvents)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local AnalyticsService = {}

-- Whitelist of event names a CLIENT is allowed to report (see
-- AnalyticsEvent, NetworkEvents.lua) -- the client can lie about `EventName`,
-- a server-side whitelist prevents an exploit from polluting the Analytics
-- dashboard with arbitrary event names.
local CLIENT_EVENT_WHITELIST = {
	TutorialCompleted = true,
	FirstPurchaseViewed = true,
}

--- Economy: currency earned. `endingBalance` MUST be the balance after
--- the operation (not the amount earned) -- this is what Roblox uses to
--- rebuild per-player wealth curves.
--- @param player Player
--- @param currencyType string -- e.g. "Gold"
--- @param amount number -- always positive
--- @param endingBalance number
--- @param source string -- e.g. "Quest", "Shop", "Gameplay"
function AnalyticsService.LogCurrencyEarned(player: Player, currencyType: string, amount: number, endingBalance: number, source: string): ()
	Engine:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, currencyType, amount, endingBalance, source)
end

--- Economy: currency spent (purchase, upgrade...).
--- @param itemSku string -- identifier of the purchased item/service
function AnalyticsService.LogCurrencySpent(player: Player, currencyType: string, amount: number, endingBalance: number, transactionType: string, itemSku: string): ()
	Engine:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, currencyType, amount, endingBalance, transactionType, itemSku)
end

--- Custom funnel (custom onboarding, not Roblox's built-in one).
--- `funnelSessionId` must be STABLE for a given player across the whole
--- funnel (e.g. their UserId as a string) -- otherwise each step counts as
--- a different session and the funnel doesn't reconstruct on the Analytics side.
--- @param step number -- 1-indexed, increasing
function AnalyticsService.LogFunnelStep(player: Player, funnelName: string, funnelSessionId: string, step: number, stepName: string): ()
	Engine:LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName)
end

--- Roblox's BUILT-IN onboarding funnel (visible directly in the
--- Creator Dashboard with no Analytics-side setup) -- reserve it for a new
--- player's very first journey (tutorial, first earning, first
--- purchase...), not a recurring gameplay funnel (see LogFunnelStep).
function AnalyticsService.LogOnboardingStep(player: Player, step: number, stepName: string): ()
	Engine:LogOnboardingFunnelStepEvent(player, step, stepName)
end

--- Free-form event, for anything that doesn't fit economy/funnel.
--- @param value number? -- optional numeric value (e.g. duration, quantity)
function AnalyticsService.LogCustomEvent(player: Player, eventName: string, value: number?): ()
	Engine:LogCustomEvent(player, eventName, value)
end

function AnalyticsService:Init(): ()
	GameEvents.OnCurrencyEarned:Connect(function(player: Player, currency: string, amount: number, source: string)
		-- Example: assumes `source` is already a readable label. A real
		-- project would read the actual post-earning balance from DataService
		-- rather than recomputing it here (avoids a 2nd source of truth).
		AnalyticsService.LogCurrencyEarned(player, currency, amount, amount, source)
	end)

	GameEvents.OnCurrencySpent:Connect(function(player: Player, currency: string, amount: number, reason: string)
		AnalyticsService.LogCurrencySpent(player, currency, amount, 0, reason, reason)
	end)

	NetworkEvents.OnServerEvent("AnalyticsEvent", function(player: Player, payload: any)
		if type(payload) ~= "table" or type(payload.EventName) ~= "string" then return end
		if not CLIENT_EVENT_WHITELIST[payload.EventName] then return end
		local value = if type(payload.Value) == "number" then payload.Value else nil
		AnalyticsService.LogCustomEvent(player, payload.EventName, value)
	end)
end

return AnalyticsService
