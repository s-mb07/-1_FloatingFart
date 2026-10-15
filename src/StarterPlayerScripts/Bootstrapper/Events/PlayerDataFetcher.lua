--!strict
--[[
	@module Events.PlayerDataFetcher
	@description Single entry point for fetching the player data snapshot
	in the Init() of a controller that needs it before the first server push
	(DataInitialized). Shares the fallback pull ("RequestData", a RemoteFunction
	rate-limited to 1 call/5s SERVER-SIDE -- see NetworkEvents.lua RATE_LIMITS
	-- SHARED across all callers, not 1 quota per controller).

	Before this module, every controller needing this safety net
	(SkillTree/Achievements/Rebirth/MainHUDHandler) duplicated its own
	task.wait(0.5) + InvokeServer("RequestData"). Since the rate limit is
	shared, several concurrent pulls at startup stepped on each other:
	only one succeeded, the others were silently rate-limited (nil).
	Here, a single real pull is issued for the whole client; every caller
	shares the same cached result.

	Usage (a controller's Init):
		PlayerDataFetcher.OnReady(function(data)
			-- data = full snapshot, same shape as the DataInitialized event
		end)

	The callback is ALWAYS invoked asynchronously (task.spawn), never
	directly in the thread calling Init() -- even if a snapshot is already
	cached -- so the caller never needs to distinguish "already ready" from
	"pending".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local EventBus = require(script.Parent.EventBus)

local PlayerDataFetcher = {}

local cachedData: any = nil
local pendingCallbacks: {(any) -> ()} = {}
local pullStarted = false

local function resolveAll(data: any): ()
	if cachedData then return end -- first to arrive (push or pull) wins
	cachedData = data
	local callbacks = pendingCallbacks
	pendingCallbacks = {}
	for _, callback in ipairs(callbacks) do
		task.spawn(callback, data)
	end
end

EventBus.Data.Initialized:Connect(function(data: any)
	if data then
		resolveAll(data)
	end
end)

-- Keep the cache current: every DataUpdated patch carries the COMPLETE
-- snapshot of each key it names (DataService contract), so overwriting those
-- keys yields the latest full data. Without this, a panel whose Init() runs
-- late (first opened minutes after join) would read the join-time snapshot
-- -- e.g. the Rebirth panel showing level 1 for a level-81 player.
EventBus.Data.Updated:Connect(function(patch: any)
	if cachedData and type(patch) == "table" then
		for key, value in patch do
			cachedData[key] = value
		end
	end
end)

-- Fallback pull: only if no push has arrived after a short delay
-- -- gives the normal server push (DataService, as soon as profile loading
-- finishes) a chance to arrive first. Only serves the missed case
-- (Studio hot-reload, Panel opened after an abnormally long load).
local function startFallbackPull(): ()
	if pullStarted or cachedData then return end
	pullStarted = true
	task.spawn(function()
		task.wait(0.5)
		if cachedData then return end
		local requestData = NetworkEvents.Get("RequestData")
		if not (requestData and requestData:IsA("RemoteFunction")) then return end
		local data = requestData:InvokeServer()
		if data then
			resolveAll(data)
		end
	end)
end

--- Registers `callback` to receive the player data snapshot as soon as it's
--- available (server push, or shared fallback pull if the push is late).
--- @param callback (data: any) -> ()
function PlayerDataFetcher.OnReady(callback: (any) -> ()): ()
	if cachedData then
		task.spawn(callback, cachedData)
		return
	end
	table.insert(pendingCallbacks, callback)
	startFallbackPull()
end

return PlayerDataFetcher
