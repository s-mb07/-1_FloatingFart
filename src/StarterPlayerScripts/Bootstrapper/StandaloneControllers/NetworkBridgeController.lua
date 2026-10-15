--!strict
--[[
	@module NetworkBridgeController
	@description Single bridge between NetworkEvents (network) and EventBus (local bus).

	This is the ONLY controller allowed to call NetworkEvents.OnClientEvent.
	Every other controller listens to EventBus instead.

	FireServer() calls stay in each controller (they're actions, not events).

	2 examples below (Data, Action) -- add a line per real event that your
	NetworkEvents.EVENT_DEFINITIONS defines.

	NOTE on the flight's own two events (ProbeStarted/ProbeStopped): those predate this bridge and are
	still handled directly inside ProbeController, which needs them at the
	lowest possible latency and consumes them itself rather than fanning
	them out. Every event added since, including the whole traversal layer
	below, goes through here as the convention requires.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Events.EventBus)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local NetworkBridgeController = {}

function NetworkBridgeController:Init(): ()
	-- Player data
	NetworkEvents.OnClientEvent("DataInitialized", function(data: any)
		EventBus.Data.Initialized:Fire(data)
	end)
	NetworkEvents.OnClientEvent("DataUpdated", function(patch: any)
		EventBus.Data.Updated:Fire(patch)
	end)

	-- Generic action system (example)
	NetworkEvents.OnClientEvent("ActionResult", function(result: any)
		EventBus.Action.Result:Fire(result)
	end)

	-- Notifications pushed by the server (NotificationService)
	NetworkEvents.OnClientEvent("Notify", function(payload: any)
		EventBus.Notification.Received:Fire(payload)
	end)

	-- STAGE 3+ win pad claimed, back in lobby: ask for the native "add to favorites" prompt (FavoritePromptService)
	NetworkEvents.OnClientEvent("PromptFavorite", function()
		EventBus.Gameplay.FavoritePromptRequested:Fire()
	end)

	-- A Roblox purchase prompt was opened for this player (MonetizationService)
	NetworkEvents.OnClientEvent("PurchasePromptShown", function(kind: string, id: number)
		EventBus.Purchase.PromptShown:Fire(kind, id)
	end)
	-- A purchase was granted: item reveal (PurchaseRevealController)
	NetworkEvents.OnClientEvent("PurchaseGranted", function(itemKey: string, detail: number?)
		EventBus.Purchase.Granted:Fire(itemKey, detail)
	end)

	-- Traversal layer (stamina / progression / wall lock). Broadcast for
	-- every player, so a visual layer can render other players' traversals;
	-- the two owner-only events below carry no player argument because the
	-- server only ever sends them to the player they describe.
	NetworkEvents.OnClientEvent("TraversalLaunchRejected", function(reason: string)
		EventBus.Traversal.LaunchRejected:Fire(reason)
	end)
	NetworkEvents.OnClientEvent(
		"TraversalStateChanged",
		function(player: Player, newState: string, previousState: string)
			EventBus.Traversal.StateChanged:Fire(player, newState, previousState)
		end
	)
	NetworkEvents.OnClientEvent(
		"TraversalWallLocked",
		function(player: Player, wallNormal: Vector3, anchorPosition: Vector3)
			EventBus.Traversal.WallLocked:Fire(player, wallNormal, anchorPosition)
		end
	)
	NetworkEvents.OnClientEvent("PlayerCelebration", function(player: Player, kind: string)
		EventBus.Traversal.Celebration:Fire(player, kind)
	end)
	NetworkEvents.OnClientEvent("TraversalWallUnlocked", function(player: Player, reason: string)
		EventBus.Traversal.WallUnlocked:Fire(player, reason)
	end)
	NetworkEvents.OnClientEvent("TraversalStaminaChanged", function(current: number, max: number)
		EventBus.Traversal.StaminaChanged:Fire(current, max)
	end)
	NetworkEvents.OnClientEvent(
		"TraversalProgressChanged",
		function(level: number, xp: number, nextThreshold: number?)
			-- Split into the two generic signals §12 asks for, plus the
			-- threshold the HUD needs alongside them. nextThreshold is nil
			-- while the real XP curve is unconfigured.
			EventBus.Traversal.XPChanged:Fire(xp, nextThreshold)
			EventBus.Traversal.LevelChanged:Fire(level)
		end
	)
	NetworkEvents.OnClientEvent("ReviveOffered", function(seconds: number, stage: number)
		EventBus.Traversal.ReviveOffered:Fire(seconds, stage)
	end)
	NetworkEvents.OnClientEvent("ReviveClosed", function()
		EventBus.Traversal.ReviveClosed:Fire()
	end)
	NetworkEvents.OnClientEvent("ProbeXPGranted", function(amount: number)
		EventBus.Traversal.XPGranted:Fire(amount)
	end)

	print("[CLIENT] NetworkBridgeController initialized -- all network events bridged to EventBus.")
end

function NetworkBridgeController:Start(): () end

return NetworkBridgeController
