--!strict
--[[
	@module GameEvents
	@description SERVER-INTERNAL signal bus (O(1)) to interconnect
	services. Replaces BindableEvents with a lightweight implementation based
	on cached coroutines.

	DO NOT CONFUSE with NetworkEvents (similar name, opposite scope):
	  • GameEvents    = server ↔ server, never replicated, no client.
	  • NetworkEvents = client ↔ server (Remotes + rate-limiting).
	A new event goes here if it never leaves the server, otherwise it goes in NetworkEvents.

	The list below is just an example -- clear it out and replace it with
	your game's real events as you write your Services.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

local GameEvents = {
	-- Data
	OnDataLoaded = Signal.new(), -- (player) -- profile loaded+reconciled, data ready to read/restore

	OnAdminDataChanged = Signal.new(), -- (player) -- AdminService changed skins/trails/data wholesale: re-sync what derives from it

	-- Economy (example of a generic earn/spend pattern)
	OnCurrencyEarned = Signal.new(), -- (player, currency, amount, source)
	OnCurrencySpent = Signal.new(), -- (player, currency, amount, reason)

	-- Progression (example)
	OnZoneUnlocked = Signal.new(), -- (player, zoneId)
	OnLevelUp = Signal.new(), -- (player, newLevel)

	-- Codes
	OnCodeRedeemed = Signal.new(), -- (player, codeId)

	-- Player lifecycle (PlayerService)
	OnPlayerRegistered = Signal.new(), -- (player) -- player added, use instead of Players.PlayerAdded directly
	OnPlayerUnregistered = Signal.new(), -- (player) -- player removing, use instead of Players.PlayerRemoving directly

	-- Teleport (TeleportService)
	OnPlayerTeleported = Signal.new(), -- (player, placeId) -- teleport call succeeded, not confirmation of arrival
	OnPlayerRelocated = Signal.new(), -- (player, reason: string, destination: CFrame) -- in-world server teleport (PlayerTeleportService), movement tracking already reset

	-- Traversal layer (TraversalStateService /
	-- TraversalProgressionService). Deliberately generic: none of these
	-- names says what the mechanic LOOKS like, so swapping the visual
	-- (tongue, hook + rope, stretching hand, tentacle, chain, vine, magic
	-- tether) touches no listener of any of them.
	OnTraversalStateChanged = Signal.new(), -- (player, newState, previousState) -- see Config/TraversalState
	OnTraversalWallLocked = Signal.new(), -- (player, wallNormal: Vector3, anchorPosition: Vector3)
	OnTraversalWallUnlocked = Signal.new(), -- (player, reason: string)
	OnTraversalXPChanged = Signal.new(), -- (player, xp: number)
	OnTraversalLevelChanged = Signal.new(), -- (player, newLevel: number, previousLevel: number)
	OnRebirthed = Signal.new(), -- (player) -- a rebirth was just applied (RebirthService, AdminService)

	-- Gameplay milestones (listened to by TutorialService)
	OnTreadmillEntered = Signal.new(), -- (player) -- stepped into a treadmill Hitbox (TreadmillService)
	OnTrophyPadClaimed = Signal.new(), -- (player, stage: number) -- a win pad paid out (TrophyPadService)
	OnCheckpointReached = Signal.new(), -- (player, stage: number) -- a new checkpoint this run (CheckpointService)
	OnSkinUnlocked = Signal.new(), -- (player, skinId: string) -- bought/unlocked on a skin pad (SkinService)

	-- Monetization (MonetizationService)
	OnProductPurchased = Signal.new(), -- (player, productId) -- receipt granted, safe to react to (grant items, log analytics...)
	OnGamePassOwned = Signal.new(), -- (player, passKey) -- pass became owned (join, purchase or gift): re-sync what it unlocks
}

return GameEvents
