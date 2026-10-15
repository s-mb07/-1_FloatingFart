--!strict
--[[
	@module LifeService
	@description Lost runs and the revive offer.

	A run is LOST (never a real death: the character is teleported to the
	lobby, not killed) when:
	  - the player touches a kill part while in control (NORMAL state). While
	    the probe system is running (flight, walk-back, landing) a kill part
	    is ignored -- and re-checked the moment control returns.
	The probe part touching a kill part does NOT lose the run: it stops like
	any obstacle.

	On a loss the furthest checkpoint reached is remembered for
	ReviveWindow seconds and the run restarts from zero at once. Within the
	window the client may ask for a revive: the server re-validates it and
	teleports the player back to that checkpoint. When the window lapses the
	saved checkpoint is gone.

	The revive is PAID: the request opens the "Revive" developer product
	prompt (MonetizationConfig.Products.Revive) and the window freezes while
	it is open. Declined = the offer closes. Bought = MonetizationService's
	receipt calls LifeService.PaidRevive. Free while the product id is 0 or
	MonetizationConfig.FreeMode is on.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CheckpointService = require(script.Parent.CheckpointService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)
local MonetizationService = require(script.Parent.MonetizationService)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local PlayerTeleportService = require(script.Parent.PlayerTeleportService)
local RespawnConfig = require(script.Parent.Parent.Config.RespawnConfig)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TraversalStateService = require(script.Parent.TraversalStateService)

local log = Logger.new("LifeService")
local LifeService = {}

-- Paying: the Revive prompt is open (the window is frozen until it closes).
type Offer = { Stage: number, Token: {}, Paying: boolean? }

local offers: { [Player]: Offer } = {}
-- Kill parts the player is currently over (PadTrigger enter/leave).
local touching: { [Player]: number } = {}

local REVIVE_PRODUCT = "Revive"

local function reviveIsFree(): boolean
	return MonetizationConfig.FreeMode or MonetizationConfig.Products[REVIVE_PRODUCT].Id <= 0
end

local function closeOffer(player: Player): ()
	offers[player] = nil
	NetworkEvents.FireClient("ReviveClosed", player)
end

--- Sends the player to the lobby as a lost run and opens the revive window.
--- May yield (waits for control). No-op while an offer is already open.
--- @param player Player
--- @param reason string
function LifeService.Lose(player: Player, reason: string): ()
	if offers[player] then
		return
	end
	local lobby = PlayerTeleportService.GetLobbyCFrame()
	if not lobby then
		log:Warn("No lobby SpawnLocation: cannot send %s back.", player.Name)
		return
	end

	local stage = CheckpointService.GetStage(player)
	if not PlayerTeleportService.TeleportTo(player, lobby, "Lost:" .. reason) then
		return
	end

	CheckpointService.Reset(player) -- the run restarts from zero right away
	local token = {}
	offers[player] = { Stage = stage, Token = token }
	log:Info("%s lost the run (%s), furthest checkpoint %d.", player.Name, reason, stage)
	if stage >= 1 then -- nothing to go back to otherwise (onReviveRequest refuses it)
		NetworkEvents.FireClient("ReviveOffered", player, RespawnConfig.ReviveWindow, stage)
	end

	task.delay(RespawnConfig.ReviveWindow, function()
		local offer = offers[player]
		if offer and offer.Token == token and not offer.Paying then
			closeOffer(player)
		end
	end)
end

--- Drops any open revive offer (new run started another way, e.g. a trophy
--- claim).
function LifeService.ClearOffer(player: Player): ()
	if offers[player] then
		closeOffer(player)
	end
end

--- Consumes the offer and sends the player back to its checkpoint. Yields
--- (teleport). Call only with a valid offer (Stage >= 1).
local function revive(player: Player, offer: Offer): ()
	local destination = CheckpointService.GetSpawnCFrame(offer.Stage)
	closeOffer(player) -- consumed before the (yielding) teleport: no double revive
	if destination and PlayerTeleportService.TeleportTo(player, destination, "Revive") then
		CheckpointService.RestoreTo(player, offer.Stage)
		log:Info("%s revived at checkpoint %d.", player.Name, offer.Stage)
	else
		log:Warn("%s: revive to checkpoint %d refused.", player.Name, offer.Stage)
	end
end

--- Grants a bought revive (MonetizationService receipt). Never yields: the
--- teleport is spawned. false = no offer anymore (lapsed, cleared, left):
--- the caller compensates the purchase.
--- @param player Player
--- @return boolean
function LifeService.PaidRevive(player: Player): boolean
	local offer = offers[player]
	if not (offer and offer.Stage >= 1) then
		return false
	end
	task.spawn(revive, player, offer)
	return true
end

local function onReviveRequest(player: Player): ()
	local offer = offers[player]
	if not offer or offer.Stage < 1 then
		return -- nothing to go back to
	end
	if reviveIsFree() then
		revive(player, offer)
	elseif MonetizationService.PromptProduct(player, REVIVE_PRODUCT) then
		offer.Paying = true
	end
end

function LifeService:Init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		offers[player] = nil
		touching[player] = nil
	end)
	-- Revive prompt declined: the frozen offer closes. Bought: the receipt
	-- (LifeService.PaidRevive) consumes it.
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, isPurchased: boolean)
			local player = Players:GetPlayerByUserId(userId)
			local offer = if player then offers[player] else nil
			if
				player
				and offer
				and offer.Paying
				and not isPurchased
				and productId == MonetizationConfig.Products[REVIVE_PRODUCT].Id
			then
				closeOffer(player)
			end
		end
	)
	log:Info("Initialized.")
end

function LifeService:Start(): ()
	NetworkEvents.OnServerEvent("ReviveRequest", onReviveRequest)

	PadTrigger.Bind(TagNames.KillPart, {
		Reach = RespawnConfig.KillPartReach,
		OnEnter = function(player: Player): ()
			touching[player] = (touching[player] or 0) + 1
			-- Protected while the probe system has control of the character:
			-- wait for it to come back, then re-check we are still over a kill
			-- part.
			while
				(touching[player] or 0) > 0
				and TraversalStateService.Get(player) ~= TraversalState.NORMAL
			do
				task.wait(0.1)
			end
			if (touching[player] or 0) > 0 then
				LifeService.Lose(player, "KillPart")
			end
		end,
		OnLeave = function(player: Player): ()
			touching[player] = math.max((touching[player] or 1) - 1, 0)
		end,
	})
	log:Info("Started.")
end

return LifeService
