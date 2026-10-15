--!strict
--[[
	@module MonetizationService
	@description Developer Product receipts + the two prompt helpers.

	RULE: this is the ONLY script that assigns `MarketplaceService.ProcessReceipt`.
	A second assignment anywhere silently replaces this one (last one wins)
	and every purchase breaks. Gamepass ownership lives in GamePassService,
	gifts in GiftPassService.

	processReceipt, in this exact order (any doubt = NotProcessedYet, Roblox
	re-delivers the receipt later, on the next join if the player left):
	  1. buyer not in this server, or profile not loaded   -> NotProcessedYet
	  2. PurchaseId already in the profile                  -> PurchaseGranted (no re-grant)
	  3. ProductId is a gift product                        -> GiftPassService.HandleReceipt
	  4. ProductId unknown to MonetizationConfig.Products   -> warn + NotProcessedYet
	  5. grantProduct fails                                 -> NotProcessedYet
	  6. MarkReceiptProcessed fails                         -> NotProcessedYet
	  7. log + PurchaseGranted
	Steps 5 and 6 never yield in between: the reward and its receipt marker
	land in the same profile in the same frame (DataService).

	The reward comes ONLY from the server catalogue by ProductId; the price
	paid is ignored except by Kind "WinsPerRobux" (by design, see config).

	Clients prompt a catalogue product by key: NetworkEvents
	"PromptProductPurchase" -> PromptProduct (refused when the product can't
	be bought anymore: rebirths maxed).

	Prompts: always open them through `PromptGamepassPurchase` /
	`PromptProductPurchase`, never `MarketplaceService` directly -- they also
	fire `NetworkEvents "PurchasePromptShown"` so the client can play its
	purchase backdrop (PurchasePromptController). Cosmetic only.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)

type ProductDef = MonetizationConfig.ProductDef
type ReceiptInfo = { PurchaseId: string, PlayerId: number, ProductId: number, CurrencySpent: number }

local MonetizationService = {}
local log = Logger.new("MonetizationService")

local productsById: { [number]: ProductDef } = {}
--- def -> its MonetizationConfig.Products key (sent to the client's reveal).
local keyOf: { [ProductDef]: string } = {}
for key, def in MonetizationConfig.Products do
	keyOf[def] = key
	if def.Id > 0 then
		if productsById[def.Id] then
			log:Warn("Product id %d used twice (%s).", def.Id, key)
		end
		productsById[def.Id] = def
	end
end

--- True when `productId` is a catalogue product (GiftPassService refuses to
--- reuse one as a gift product: two receipt paths for one id).
function MonetizationService.IsCatalogueProduct(productId: number): boolean
	return productsById[productId] ~= nil
end

--- Prompt a player with a gamepass purchase dialog. Prefer GamePassService.Prompt
--- (pass key, "already owned" guard).
function MonetizationService.PromptGamepassPurchase(player: Player, gamepassId: number): ()
	NetworkEvents.FireClient("PurchasePromptShown", player, "GamePass", gamepassId)
	MarketplaceService:PromptGamePassPurchase(player, gamepassId)
end

--- Prompt a player with a developer product purchase dialog.
function MonetizationService.PromptProductPurchase(player: Player, productId: number): ()
	NetworkEvents.FireClient("PurchasePromptShown", player, "Product", productId)
	MarketplaceService:PromptProductPurchase(player, productId)
end

--- false when `def` can't be bought by `player` anymore (one-time / maxed).
local function canBuy(player: Player, def: ProductDef): boolean
	if def.Kind == "SkipRebirth" then
		return DataService:GetRebirths(player) < RebirthConfig.GetMaxRebirths()
	end
	return true
end

--- Opens the prompt of catalogue product `key` (MonetizationConfig.Products).
--- false = unknown key, id not set yet, or not buyable anymore.
function MonetizationService.PromptProduct(player: Player, key: string): (boolean, string?)
	local def = MonetizationConfig.Products[key]
	if not def or def.Id <= 0 then
		return false, "NotConfigured"
	end
	if not canBuy(player, def) then
		return false, "AlreadyOwned"
	end
	MonetizationService.PromptProductPurchase(player, def.Id)
	return true
end

--- Gives the reward of `def`. Never yields. false = nothing confirmed.
local function grantProduct(player: Player, def: ProductDef, receiptInfo: ReceiptInfo): boolean
	if def.Kind == "Wins" then
		return (DataService:AddTrophies(player, def.Amount))
	elseif def.Kind == "WinsPerRobux" then
		return (DataService:AddTrophies(player, receiptInfo.CurrencySpent * def.Amount))
	end
	-- Required here, not at the top: both reach GamePassService (through
	-- RewardGrant), which requires this module.
	if def.Kind == "Length" then
		return (require :: any)(script.Parent.BoostService).GrantLength(player, def.Amount)
	elseif def.Kind == "SkipRebirth" then
		return (require :: any)(script.Parent.RebirthService).Rebirth(player, true).Success
	elseif def.Kind == "SkipDailyReward" then
		return (require :: any)(script.Parent.DailyRewardService).Skip(player).Success
	elseif def.Kind == "Revive" then
		if (require :: any)(script.Parent.LifeService).PaidRevive(player) then
			return true
		end
		-- The offer is gone (lapsed, cleared, rejoined): pay it back in Wins.
		local wins = receiptInfo.CurrencySpent * MonetizationConfig.GiftCompensationWinsPerRobux
		log:Warn("%s: revive bought without an offer, refunded %d Wins.", player.Name, wins)
		return (DataService:AddTrophies(player, wins))
	end
	log:Warn("Unsupported product Kind %s (product %d).", tostring(def.Kind), def.Id)
	return false
end

local function processReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not DataService:IsProfileLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if DataService:IsReceiptProcessed(player, receiptInfo.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Required here, not at the top: GiftPassService requires this module.
	local GiftPassService = (require :: any)(script.Parent.GiftPassService)
	if GiftPassService.IsGiftProduct(receiptInfo.ProductId) then
		return GiftPassService.HandleReceipt(player, receiptInfo)
	end

	local def = productsById[receiptInfo.ProductId]
	if not def then
		log:Warn(
			"Unknown product %d (purchase %s, %s) -- not granted.",
			receiptInfo.ProductId,
			receiptInfo.PurchaseId,
			player.Name
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(grantProduct, player, def, receiptInfo)
	if not ok or not granted then
		log:Error(
			"Grant failed for %s, product %d (purchase %s): %s",
			player.Name,
			receiptInfo.ProductId,
			receiptInfo.PurchaseId,
			tostring(granted)
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local marked, reason = DataService:MarkReceiptProcessed(player, receiptInfo.PurchaseId)
	if not marked then
		log:Error(
			"Receipt %s not marked for %s: %s",
			receiptInfo.PurchaseId,
			player.Name,
			tostring(reason)
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	log:Info(
		"%s bought product %d (%s x%d, purchase %s).",
		player.Name,
		receiptInfo.ProductId,
		def.Kind,
		def.Amount,
		receiptInfo.PurchaseId
	)
	GameEvents.OnProductPurchased:Fire(player, receiptInfo.ProductId)
	-- Cosmetic: the client reveals what was bought.
	NetworkEvents.FireClient("PurchaseGranted", player, keyOf[def])
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:Init(): ()
	MarketplaceService.ProcessReceipt = processReceipt :: any
	NetworkEvents.OnServerEvent("PromptProductPurchase", function(player: Player, key: any)
		if type(key) == "string" and #key <= 64 then
			MonetizationService.PromptProduct(player, key)
		end
	end)
end

function MonetizationService:Start(): () end

return MonetizationService
