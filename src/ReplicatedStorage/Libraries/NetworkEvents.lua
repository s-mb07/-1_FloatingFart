--!strict
--[[
	@module NetworkEvents
	@description Creates and exposes RemoteEvents/RemoteFunctions for network communication.

	Must be required on BOTH the server and the client.
	The server creates the events, the client fetches them.

	DO NOT CONFUSE with GameEvents (similar name, opposite scope):
	  • NetworkEvents = client ↔ server (Remotes + rate-limiting).
	  • GameEvents    = server-internal bus, never replicated.
	A new event goes here if it crosses the client/server boundary.

	EVENT_DEFINITIONS / RATE_LIMITS below are only examples -- clear them
	out and fill them in with your game's real events. The ENGINE part
	(initialize/Get/FireClient/.../checkRateLimit) shouldn't need to change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetworkEvents = {}

-- Folder that holds all the events
local EVENTS_FOLDER_NAME = "NetworkEvents"

local EVENT_DEFINITIONS = {
	-- Data sync
	DataInitialized = "RemoteEvent", -- Server → Client: initial data
	DataUpdated = "RemoteEvent", -- Server → Client: partial update
	RequestData = "RemoteFunction", -- Client → Server: requests the data

	-- Zones
	ZoneChanged = "RemoteEvent", -- Server → Client: player changed zone
	RequestCurrentZone = "RemoteEvent", -- Client → Server: requests the current zone (catch-up on startup)

	-- Settings
	UpdateSetting = "RemoteEvent", -- Client → Server: updates a setting

	-- Universal action system (example of a generic request/result pattern)
	ActionRequest = "RemoteEvent", -- Client → Server: requests an action
	ActionResult = "RemoteEvent", -- Server → Client: action result (for UI feedback)

	-- Admin
	-- AdminService: ONLY the server decides who is an admin (AdminConfig, under
	-- ServerScriptService, keyed by the engine-set Player.UserId). The client
	-- sends an action NAME + whitelisted arguments; never an identity.
	AdminRequest = "RemoteFunction", -- Client → Server: (action: string, payload: table?) -> { Success: boolean, Message: string }
	CheckAdminStatus = "RemoteFunction", -- Client → Server: () -> boolean (UI convenience only, grants nothing)

	-- Analytics (AnalyticsService is a SERVER-ONLY service -- the client can
	-- never call it directly, it only reports a candidate event, which is
	-- revalidated/logged server-side)
	AnalyticsEvent = "RemoteEvent", -- Client → Server: { EventName: string, Value: number? }

	-- Codes
	RedeemCode = "RemoteFunction", -- Client → Server: attempts to redeem a code

	-- Daily rewards (DailyRewardService). No payload: the server decides which
	-- day is claimable; the new state comes back through "DataUpdated".
	ClaimDailyReward = "RemoteFunction", -- Client → Server: () -> { Success: boolean, Error: string? }
	-- Playtime rewards (PlaytimeRewardService). Session state rides on player
	-- attributes (PlaytimeRewardConfig), so only the claim crosses the wire.
	ClaimPlaytimeReward = "RemoteFunction", -- Client → Server: (index: number) -> { Success: boolean, Error: string? }
	-- Rebirth (RebirthService). The server decides which rebirth comes next;
	-- the client only says whether it is a skip (no level requirement).
	RequestRebirth = "RemoteFunction", -- Client → Server: () -> { Success: boolean, Error: string? } (skip = product "SkipRebirth")
	PopTrainingBubble = "RemoteEvent", -- Client → Server: (slot: number) pop that fan boost bubble (TrainingBubbleService)
	-- Character trails (TrailService). State comes back through "DataUpdated" (Trails).
	BuyTrail = "RemoteFunction", -- Client → Server: (id: string, currency: "Wins" | "Robux") -> { Success, Error? }
	EquipTrail = "RemoteFunction", -- Client → Server: (id: string, "" = unequip) -> { Success, Error? }
	ClaimLeaveReward = "RemoteFunction", -- Client → Server: () -> { Success, Error? } (LeaveRewardService, once per UTC day)
	ClaimGroupReward = "RemoteFunction", -- Client → Server: () -> { Success, Error? } (GroupRewardService, once per profile)
	PromptFavorite = "RemoteEvent", -- Server → Client: () show the native "add to favorites" prompt (FavoritePromptService)
	-- Tutorial (TutorialService). Stage state comes back through "DataUpdated" (Tutorial).
	RebirthFocusShown = "RemoteEvent", -- Client → Server: () the one-time rebirth focus was shown
	-- Shop placeholder items (ShopService). State comes back through "DataUpdated" (ShopClaimed).
	ClaimShopItem = "RemoteFunction", -- Client → Server: (itemId: string) -> { Success, Error? }

	-- Anti-kick (InactivityService). No payload: any ping just re-arms the player's idle timer.
	PlayerActivityPing = "RemoteEvent", -- Client → Server: ()

	-- Notifications (NotificationService, server-only -- the client only
	-- ever displays what it receives here)
	Notify = "RemoteEvent", -- Server → Client: { Message: string, Type: string?, Duration: number? }

	-- Purchase prompt (MonetizationService): the engine's "...Requested" events are
	-- not readable by game scripts, so the server announces each prompt it opens.
	PurchasePromptShown = "RemoteEvent", -- Server → Client: (kind: "GamePass" | "Product", id: number)
	-- A purchase was granted (MonetizationService receipt / GamePassService pass):
	-- the client plays its item reveal (PurchaseRevealController). Cosmetic only.
	PurchaseGranted = "RemoteEvent", -- Server → Client: (itemKey: string, detail: number?) product or pass key
	-- Store (GamePassService / ShopService / GiftPassService). The client only ever
	-- sends LOGICAL keys (pass key, ShopConfig.Exclusive key), never a Roblox id.
	PromptGamePassPurchase = "RemoteEvent", -- Client → Server: (passKey: string)
	PromptProductPurchase = "RemoteEvent", -- Client → Server: (productKey: string) MonetizationConfig.Products key
	PromptShopPurchase = "RemoteFunction", -- Client → Server: (itemKey: string) -> { Success, Error? }
	GetGiftEligibility = "RemoteFunction", -- Client → Server: (passKey: string) -> { [userId: string]: reason }? (display only)
	RequestGiftPass = "RemoteFunction", -- Client → Server: (recipientUserId: number, passKey: string) -> { Success, Error? }

	-- Character-flight mechanic (see ProbeService/ProbeController): the player's
	-- own character is flown by its client; the server validates and supervises.
	-- Only the aim hint is trusted at launch (the start position is the
	-- replicated character) and only to orient the launch.
	ProbeStartRequest = "RemoteEvent", -- Client → Server: (forwardHint: Vector3?) start a flight
	ProbeAimUpdate = "RemoteEvent", -- Client → Server: (aim: Vector3) camera aim while the Start animation plays;
	-- the server turns the character toward it (only outward from a wall, and away from parts).
	ProbeStopRequest = "RemoteEvent", -- Client → Server: (hitNormal: Vector3?) end the flight (voluntary, or the
	-- front attachment of the Fly model hit something). The server re-verifies the hit itself.
	ProbeStarted = "RemoteEvent", -- Server → Client: (ownerPlayer, startDuration: number) -- Start animation playing
	ProbeStopped = "RemoteEvent", -- Server → Client: (ownerPlayer, reason: string, hitNormal: Vector3?)
	-- Traversal layer (stamina / progression / wall lock) built on top of the
	-- probe flight above -- see TraversalStateService,
	-- TraversalProgressionService. ALL server → client: the traversal layer
	-- has no client → server event of its own, because the only action it
	-- exposes (launching) already goes through ProbeStartRequest. Nothing
	-- here is ever accepted FROM a client, so none of it needs a rate limit.
	TraversalLaunchRejected = "RemoteEvent", -- Server → Client (owner only): (reason: string)
	-- Sent whenever the launch validator refuses a request. Exists so the
	-- client can undo its OPTIMISTIC control lock the instant a launch is
	-- refused: without it the client has no way to tell a refusal from a
	-- slow accept, and had to sit on a blind timer -- which is what left
	-- movement input frozen for about a second after an ill-timed press.
	TraversalStateChanged = "RemoteEvent", -- Server → Client: (player, newState, previousState) -- see Config/TraversalState
	TraversalWallLocked = "RemoteEvent", -- Server → Client: (player, wallNormal: Vector3, anchorPosition: Vector3)
	TraversalWallUnlocked = "RemoteEvent", -- Server → Client: (player, reason: string)
	TraversalStaminaChanged = "RemoteEvent", -- Server → Client (owner only): (remaining: number, max: number) -- studs of real length left while a probe is active (HUD bar only)
	TraversalProgressChanged = "RemoteEvent", -- Server → Client (owner only): (level: number, xp: number, nextThreshold: number?)
	-- nextThreshold is the total XP needed to leave the current level
	-- (TraversalProgressionConfig tiers, cumulative). It is nil at the max
	-- level: the HUD must never invent a denominator.
	ProbeXPGranted = "RemoteEvent", -- Server → Client (owner only): (amount: number) -- per-second XP grant while the probe is active
	-- Level-up / rebirth seen by the OTHER players (CelebrationService): VFX on the
	-- character + 3D sound. Cosmetic only.
	PlayerCelebration = "RemoteEvent", -- Server → Client (everyone but the owner): (player, kind: "LevelUp" | "Rebirth")
	-- Lost run / revive (LifeService).
	ReviveOffered = "RemoteEvent", -- Server → Client (owner only): (seconds: number, stage: number) show the Revive button (back to checkpoint `stage`) for this long
	ReviveClosed = "RemoteEvent", -- Server → Client (owner only): hide it (used, lapsed or cancelled)
	ReviveRequest = "RemoteEvent", -- Client → Server: ask to return to the saved checkpoint (re-validated server-side)
}

-- OBFUSCATION MAPPING (Internal Name -> Real Name on the network), optional.
local EVENT_ALIASES: { [string]: string } = {}

--============================================================================--
-- RATE LIMITING CONFIGURATION
-- Format: EventName = { MaxCalls = calls/second, Cooldown = seconds between calls }
-- If undefined, no limit
--============================================================================--

local RATE_LIMITS: { [string]: { MaxCalls: number?, Cooldown: number? } } = {
	RequestData = { MaxCalls = 1, Cooldown = 5.0 }, -- Max 1x every 5s (heavy data)
	UpdateSetting = { MaxCalls = 5, Cooldown = 0.2 }, -- Max 5/s for settings
	ActionRequest = { MaxCalls = 10, Cooldown = 0.1 }, -- Action system
	AdminRequest = { MaxCalls = 8 }, -- admin actions/second
	CheckAdminStatus = { Cooldown = 2.0 },
	RedeemCode = { MaxCalls = 1, Cooldown = 1.0 }, -- Max 1 code/second
	ClaimDailyReward = { MaxCalls = 1, Cooldown = 1.0 },
	ClaimPlaytimeReward = { MaxCalls = 3, Cooldown = 0.2 }, -- several cards can be ready at once
	RequestRebirth = { MaxCalls = 1, Cooldown = 1.0 }, -- a double-click must never rebirth twice
	PopTrainingBubble = { MaxCalls = 6 }, -- up to 3 bubbles clicked in a row; no Cooldown, a dropped pop loses the bubble
	BuyTrail = { Cooldown = 0.5 }, -- a double-click must never spend twice (owned check also guards it)
	EquipTrail = { Cooldown = 0.3 },
	ClaimLeaveReward = { Cooldown = 1.0 },
	ClaimGroupReward = { Cooldown = 1.0 },
	RebirthFocusShown = { Cooldown = 5.0 },
	ClaimShopItem = { Cooldown = 0.5 },
	PromptGamePassPurchase = { Cooldown = 2.0 },
	PromptProductPurchase = { Cooldown = 1.0 },
	PromptShopPurchase = { Cooldown = 1.0 },
	GetGiftEligibility = { Cooldown = 2.0 },
	RequestGiftPass = { Cooldown = 3.0 },
	RequestCurrentZone = { MaxCalls = 1, Cooldown = 10.0 }, -- Max 1x every 10s
	AnalyticsEvent = { MaxCalls = 5, Cooldown = 0.2 }, -- Anti-spam for client events
	ProbeStartRequest = { Cooldown = 1.0 }, -- one flight at a time anyway (ProbeService), this just stops spam-firing
	ProbeStopRequest = { Cooldown = 0.5 },
	ProbeAimUpdate = { Cooldown = 0.05 }, -- streamed at FlyConfig.PrepAimHz (10 Hz); this only stops flooding
	ReviveRequest = { MaxCalls = 1, Cooldown = 1.0 },
	PlayerActivityPing = { Cooldown = 55 }, -- below InactivityConfig.PingThrottle (60s); extra pings are dropped, no MaxCalls needed
}

-- State for rate limiting
local playerCallCounts: { [Player]: { [string]: { Count: number, LastReset: number, LastCall: number } } } =
	{}

-- Event cache
local events: { [string]: RemoteEvent | RemoteFunction } = {}

--- Initializes the events (called automatically)
local function initialize()
	local eventsFolder = ReplicatedStorage:FindFirstChild(EVENTS_FOLDER_NAME)

	if RunService:IsServer() then
		-- Server side: creates the folder and the events
		if not eventsFolder then
			eventsFolder = Instance.new("Folder")
			eventsFolder.Name = EVENTS_FOLDER_NAME
			eventsFolder.Parent = ReplicatedStorage
		end

		for eventName, eventType in pairs(EVENT_DEFINITIONS) do
			local realName = EVENT_ALIASES[eventName] or eventName
			local existing = eventsFolder:FindFirstChild(realName)
			if not existing then
				local event: Instance
				if eventType == "RemoteEvent" then
					event = Instance.new("RemoteEvent")
				else
					event = Instance.new("RemoteFunction")
				end
				event.Name = realName
				event.Parent = eventsFolder
				events[eventName] = event :: any
			else
				events[eventName] = existing :: any
			end
		end
	else
		-- Client side: waits for and fetches the events
		if not eventsFolder then
			eventsFolder = ReplicatedStorage:WaitForChild(EVENTS_FOLDER_NAME, 10)
		end

		if eventsFolder then
			for eventName, _ in pairs(EVENT_DEFINITIONS) do
				local realName = EVENT_ALIASES[eventName] or eventName
				local event = eventsFolder:WaitForChild(realName, 5)
				if event then
					events[eventName] = event :: any
				else
					warn(string.format("[NetworkEvents] Event not found: %s", realName))
				end
			end
		end
	end
end

--- Checks the rate limit for a player and an event
--- @param player Player
--- @param eventName string
--- @return boolean True if the call is allowed
local function checkRateLimit(player: Player, eventName: string): boolean
	local limits = RATE_LIMITS[eventName]
	if not limits then
		return true
	end -- No limit configured

	local now = os.clock()

	-- Initializes tracking for this player
	if not playerCallCounts[player] then
		playerCallCounts[player] = {}
	end

	if not playerCallCounts[player][eventName] then
		playerCallCounts[player][eventName] = {
			Count = 0,
			LastReset = now,
			LastCall = 0,
		}
	end

	local tracker = playerCallCounts[player][eventName]

	-- Resets the counter every second
	if now - tracker.LastReset >= 1 then
		tracker.Count = 0
		tracker.LastReset = now
	end

	-- Checks the cooldown between calls
	if limits.Cooldown then
		if now - tracker.LastCall < limits.Cooldown then
			warn(
				string.format(
					"[RATE LIMIT] %s: %s (cooldown %.2fs)",
					player.Name,
					eventName,
					limits.Cooldown
				)
			)
			return false
		end
	end

	-- Checks the max calls/second
	if limits.MaxCalls then
		if tracker.Count >= limits.MaxCalls then
			warn(
				string.format(
					"[RATE LIMIT] %s: %s (%d/%d calls/s)",
					player.Name,
					eventName,
					tracker.Count,
					limits.MaxCalls
				)
			)
			return false
		end
	end

	-- Increments and allows
	tracker.Count += 1
	tracker.LastCall = now
	return true
end

--- Fetches an event by its name
--- @param name string
--- @return RemoteEvent | RemoteFunction | nil
function NetworkEvents.Get(name: string): (RemoteEvent | RemoteFunction)?
	return events[name]
end

--- Shortcut to fire a RemoteEvent to a client
--- @param eventName string
--- @param player Player
function NetworkEvents.FireClient(eventName: string, player: Player, ...: any): ()
	local event = events[eventName]
	if event and event:IsA("RemoteEvent") then
		event:FireClient(player, ...)
	end
end

--- Shortcut to fire a RemoteEvent to all clients
--- @param eventName string
function NetworkEvents.FireAllClients(eventName: string, ...: any): ()
	local event = events[eventName]
	if event and event:IsA("RemoteEvent") then
		event:FireAllClients(...)
	end
end

--- Shortcut to fire a RemoteEvent to the server (client side)
--- @param eventName string
function NetworkEvents.FireServer(eventName: string, ...: any): ()
	local event = events[eventName]
	if event and event:IsA("RemoteEvent") then
		event:FireServer(...)
	end
end

--- Shortcut to connect a callback to an event
--- @param eventName string
--- @param callback function
--- @return RBXScriptConnection?
function NetworkEvents.OnClientEvent(
	eventName: string,
	callback: (...any) -> ()
): RBXScriptConnection?
	local event = events[eventName]
	if event and event:IsA("RemoteEvent") then
		return event.OnClientEvent:Connect(callback)
	end
	return nil
end

--- Shortcut to connect a server callback (with automatic rate limiting)
--- @param eventName string
--- @param callback function
--- @return RBXScriptConnection?
function NetworkEvents.OnServerEvent(
	eventName: string,
	callback: (Player, ...any) -> ()
): RBXScriptConnection?
	local event = events[eventName]
	if event and event:IsA("RemoteEvent") then
		return event.OnServerEvent:Connect(function(player: Player, ...)
			-- Rate limit check
			if not checkRateLimit(player, eventName) then
				return -- Blocked by rate limit
			end

			-- Call allowed. pcall so an error inside a callback never affects
			-- other players/events connected to the same RemoteEvent.
			local callOk, callErr = pcall(callback :: (Player, ...any) -> ...any, player, ...)
			if not callOk then
				warn(
					string.format(
						"[NetworkEvents] Error in callback for %s: %s",
						eventName,
						tostring(callErr)
					)
				)
			end
		end)
	end
	return nil
end

--- Shortcut to call a RemoteFunction on the server (client side)
--- @param functionName string
--- @return any
function NetworkEvents.InvokeServer(functionName: string, ...: any): any
	local remoteFunc = events[functionName]
	if remoteFunc and remoteFunc:IsA("RemoteFunction") then
		return remoteFunc:InvokeServer(...)
	end
	return nil
end

--- Shortcut to connect a server callback to a RemoteFunction (with rate limiting)
--- @param functionName string
--- @param callback function
--- @param explicitRateLimitError boolean? If true, a rate-limit rejection returns
--- { Success = false, Error = "RateLimited" } instead of nil, so the client
--- can distinguish an anti-spam block from a server/logic error. Defaults to
--- false so it doesn't change the existing contract of other RemoteFunctions.
function NetworkEvents.OnServerInvoke(
	functionName: string,
	callback: (Player, ...any) -> any,
	explicitRateLimitError: boolean?
): ()
	local remoteFunc = events[functionName]
	if remoteFunc and remoteFunc:IsA("RemoteFunction") then
		remoteFunc.OnServerInvoke = function(player: Player, ...)
			-- Rate limit check
			if not checkRateLimit(player, functionName) then
				if explicitRateLimitError then
					return { Success = false, Error = "RateLimited" }
				end
				return nil -- Blocked by rate limit
			end

			return callback(player, ...)
		end
	end
end

-- Initializes on require
initialize()

-- Cleans up rate limit data when a player leaves (server side only)
if RunService:IsServer() then
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		playerCallCounts[player] = nil
	end)
end

return NetworkEvents
