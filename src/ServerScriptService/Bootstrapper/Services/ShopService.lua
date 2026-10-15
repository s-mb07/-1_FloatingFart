--!strict
--[[
	@module ShopService
	@description Placeholder shop items (ReplicatedStorage/Config/ShopConfig):
	Trainer Pack has no gameplay effect yet -- claiming it only saves it as
	claimed (DataService:MarkShopItem) so the Shop shows "Claimed".
	The other Shop items reuse their own services (StarterPackService,
	BoostService); nothing here duplicates them.

	NetworkEvents "ClaimShopItem" (RemoteFunction: itemId) -> { Success, Error? }.
	TESTING ONLY: free.

	NetworkEvents "PromptShopPurchase" (RemoteFunction: itemKey) -> { Success, Error? }:
	opens the Robux prompt of a ShopConfig.Exclusive button. Granting is NOT
	here: gamepasses -> GamePassService, products -> MonetizationService receipts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local MonetizationService = require(script.Parent.MonetizationService)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local ShopConfig = require(ReplicatedStorage.Config.ShopConfig)

local log = Logger.new("ShopService")
local ShopService = {}

type Result = { Success: boolean, Error: string? }

--- Claims placeholder item `itemId` for `player` (once).
function ShopService.Claim(player: Player, itemId: any): Result
	if type(itemId) ~= "string" or not ShopConfig.Placeholders[itemId] then
		return { Success = false, Error = "UnknownItem" }
	end
	if DataService:HasShopItem(player, itemId) then
		return { Success = false, Error = "AlreadyClaimed" }
	end
	local ok, reason = DataService:MarkShopItem(player, itemId)
	if not ok then
		return { Success = false, Error = reason }
	end
	NotificationService.Send(player, itemId .. " claimed!", "Success")
	log:Info("%s claimed shop item %s.", player.Name, itemId)
	return { Success = true }
end

--- Opens the Robux prompt of Exclusive item `itemKey` (ShopConfig). The client
--- only names the button; the id comes from GamePassConfig / MonetizationConfig.
function ShopService.PromptPurchase(player: Player, itemKey: any): Result
	local item = if type(itemKey) == "string" and #itemKey <= 128
		then ShopConfig.Exclusive[itemKey]
		else nil
	if not item then
		log:Warn("%s asked for unknown shop item %s.", player.Name, tostring(itemKey))
		return { Success = false, Error = "UnknownItem" }
	end
	if item.Kind == "GamePass" then
		local ok, reason = GamePassService.Prompt(player, item.PassKey :: string)
		return { Success = ok, Error = reason }
	end
	local ok, reason = MonetizationService.PromptProduct(player, item.ProductKey :: string)
	return { Success = ok, Error = reason }
end

function ShopService:Init(): ()
	NetworkEvents.OnServerInvoke("ClaimShopItem", ShopService.Claim, true)
	NetworkEvents.OnServerInvoke("PromptShopPurchase", ShopService.PromptPurchase, true)
end

function ShopService:Start(): () end

return ShopService
