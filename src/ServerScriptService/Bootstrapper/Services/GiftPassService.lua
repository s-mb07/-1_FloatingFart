--!strict
--[[
	@module GiftPassService
	@description Gift a gamepass to another player in this server. Roblox has
	no in-game gift API, so each giftable pass has its own Developer Product
	(GamePassConfig GiftProductId). The gift is saved in the RECIPIENT's
	profile (DataService GiftedPasses) and counts as owned everywhere.

	Request (NetworkEvents "RequestGiftPass": recipientUserId, passKey):
	validate input -> pass giftable -> recipient here with a profile, not self
	-> one active intent per buyer ("Busy") -> one intent per
	(recipient, pass) across buyers ("RecipientReserved") -> intent stored
	BEFORE the ownership check yields (closes the race) -> fresh check
	recipient doesn't own it -> revalidate after the yield -> prompt.
	Intents live 300 s, purged lazily on each request; a cancelled prompt
	frees its intent at once.

	Receipt (HandleReceipt, called by MonetizationService only): the pass
	comes from the ProductId, never from the client. One yield (fresh
	ownership check) BEFORE any grant, everything revalidated after it. When
	the gift can't be delivered (intent lost, recipient gone or already
	owner, grant failed) the Robux is already spent: the buyer gets
	CurrencySpent x GiftCompensationWinsPerRobux Wins instead (log
	"COMPENSATION"). A replayed receipt that already delivered the pass
	(same ReceiptId on the recipient) is confirmed without compensation.

	Eligibility (NetworkEvents "GetGiftEligibility": passKey) ->
	{ [tostring(userId)]: reason } for every other player. DISPLAY ONLY,
	never an authorization. Reasons (stable): Eligible, AlreadyOwns,
	VerificationFailed, RecipientReserved, RecipientNotReady.

	Config check at Init: a GiftProductId used twice, equal to a pass id, or
	also a catalogue product disables the gift for those passes (never crash,
	never an ambiguous mapping).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GamePassConfig = require(ReplicatedStorage.Config.GamePassConfig)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)
local MonetizationService = require(script.Parent.MonetizationService)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)

local log = Logger.new("GiftPassService")
local GiftPassService = {}

local INTENT_TTL = 300
local ELIGIBILITY_CACHE_TTL = 30
local ELIGIBILITY_TIMEOUT = 8
local MAX_API_CALLS = 10
local SLOT_TIMEOUT = 5

local Decision = Enum.ProductPurchaseDecision

type Intent = { RecipientUserId: number, PassKey: string, ExpiresAt: number }
type Result = { Success: boolean, Error: string? }

local giftProductToKey: { [number]: string } = {} -- valid gift products only
local intents: { [number]: Intent } = {} -- buyer UserId -> intent
local inFlightReceipts: { [string]: boolean } = {}
local eligibilityCache: { [number]: { [string]: { At: number, Reason: string } } } = {}
local eligibilityBusy: { [Player]: boolean } = {}
local apiCalls = 0

local function validateConfig(): ()
	local passIds: { [number]: boolean } = {}
	local uses: { [number]: { string } } = {}
	for key, def in GamePassConfig.Passes do
		passIds[def.Id] = true
		local giftId = def.GiftProductId
		if giftId and giftId > 0 then
			uses[giftId] = uses[giftId] or {}
			table.insert(uses[giftId], key)
		end
	end
	for giftId, keys in uses do
		if #keys > 1 then
			log:Error(
				"Gift product %d shared by %s -- gift disabled.",
				giftId,
				table.concat(keys, ", ")
			)
		elseif passIds[giftId] then
			log:Error("Gift product %d of %s equals a pass id -- gift disabled.", giftId, keys[1])
		elseif MonetizationService.IsCatalogueProduct(giftId) then
			log:Error(
				"Gift product %d of %s is also a catalogue product -- gift disabled.",
				giftId,
				keys[1]
			)
		else
			giftProductToKey[giftId] = keys[1]
		end
	end
end

--- Gift product id of `key`, nil when not giftable (unset or disabled).
local function giftIdOf(key: string): number?
	local def = GamePassConfig.Passes[key]
	local giftId = def and def.GiftProductId
	return if giftId and giftProductToKey[giftId] == key then giftId else nil
end

--- OwnsAnyAsync behind a concurrency cap. (verificationOk, owns). Yields.
local function freshOwns(player: Player, key: string): (boolean, boolean)
	local deadline = os.clock() + SLOT_TIMEOUT
	while apiCalls >= MAX_API_CALLS do
		if os.clock() > deadline then
			return false, false
		end
		task.wait(0.1)
	end
	apiCalls += 1
	local ok, verified, owns = pcall(GamePassService.OwnsAnyAsync, player, key)
	apiCalls -= 1
	return ok and verified == true, owns == true
end

local function purgeIntents(): ()
	local now = os.clock()
	for buyerId, intent in intents do
		if intent.ExpiresAt <= now then
			intents[buyerId] = nil
		end
	end
end

--- Buyer UserId holding (recipient, pass), if any.
-- ponytail: linear scan over intents (<= one per player), fine at server sizes.
local function reservedBy(recipientUserId: number, key: string): number?
	for buyerId, intent in intents do
		if intent.RecipientUserId == recipientUserId and intent.PassKey == key then
			return buyerId
		end
	end
	return nil
end

--============================================================================--
-- REQUEST
--============================================================================--

function GiftPassService.Request(player: Player, recipientUserId: any, key: any): Result
	if
		type(recipientUserId) ~= "number"
		or recipientUserId ~= math.floor(recipientUserId)
		or recipientUserId <= 0
	then
		return { Success = false, Error = "InvalidRecipient" }
	end
	if type(key) ~= "string" or #key > 64 then
		return { Success = false, Error = "InvalidPass" }
	end
	local giftId = giftIdOf(key)
	if not giftId then
		return { Success = false, Error = "NotGiftable" }
	end
	local recipient = Players:GetPlayerByUserId(recipientUserId)
	if not recipient or not DataService:IsProfileLoaded(recipient) then
		return { Success = false, Error = "RecipientNotReady" }
	end
	if recipient == player then
		return { Success = false, Error = "SelfGift" }
	end

	purgeIntents()
	if intents[player.UserId] then
		return { Success = false, Error = "Busy" }
	end
	if reservedBy(recipientUserId, key) then
		return { Success = false, Error = "RecipientReserved" }
	end
	local intent: Intent =
		{ RecipientUserId = recipientUserId, PassKey = key, ExpiresAt = os.clock() + INTENT_TTL }
	intents[player.UserId] = intent

	local verified, owns = freshOwns(recipient, key)
	local function fail(reason: string): Result
		if intents[player.UserId] == intent then
			intents[player.UserId] = nil
		end
		return { Success = false, Error = reason }
	end
	if intents[player.UserId] ~= intent then
		return { Success = false, Error = "Expired" }
	end
	if not verified then
		return fail("VerificationFailed")
	end
	if owns then
		return fail("AlreadyOwns")
	end
	if player.Parent ~= Players or recipient.Parent ~= Players then
		return fail("RecipientNotReady")
	end

	MonetizationService.PromptProductPurchase(player, giftId)
	return { Success = true }
end

--============================================================================--
-- ELIGIBILITY (display only)
--============================================================================--

function GiftPassService.GetEligibility(player: Player, key: any): { [string]: string }?
	if type(key) ~= "string" or not giftIdOf(key) or eligibilityBusy[player] then
		return nil
	end
	eligibilityBusy[player] = true
	purgeIntents()

	local result: { [string]: string } = {}
	local pending = 0
	local now = os.clock()
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local id = other.UserId
		local cached = eligibilityCache[id] and eligibilityCache[id][key]
		local holder = reservedBy(id, key)
		if not DataService:IsProfileLoaded(other) then
			result[tostring(id)] = "RecipientNotReady"
		elseif holder and holder ~= player.UserId then
			result[tostring(id)] = "RecipientReserved"
		elseif GamePassConfig.PlayerHasPass(other, key) then
			result[tostring(id)] = "AlreadyOwns"
		elseif cached and now - cached.At < ELIGIBILITY_CACHE_TTL then
			result[tostring(id)] = cached.Reason
		else
			result[tostring(id)] = "VerificationFailed" -- until it answers, never Eligible by default
			pending += 1
			task.spawn(function()
				local verified, owns = freshOwns(other, key)
				pending -= 1
				if verified then
					local reason = if owns then "AlreadyOwns" else "Eligible"
					result[tostring(id)] = reason
					eligibilityCache[id] = eligibilityCache[id] or {}
					eligibilityCache[id][key] = { At = os.clock(), Reason = reason }
				end
			end)
		end
	end

	local deadline = os.clock() + ELIGIBILITY_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	eligibilityBusy[player] = nil
	return table.clone(result) -- late answers stay out of what was sent
end

--============================================================================--
-- RECEIPT
--============================================================================--

function GiftPassService.IsGiftProduct(productId: number): boolean
	return giftProductToKey[productId] ~= nil
end

type ReceiptInfo = { PurchaseId: string, ProductId: number, CurrencySpent: number }

local function handle(buyer: Player, info: ReceiptInfo): Enum.ProductPurchaseDecision
	local key = giftProductToKey[info.ProductId]
	local purchaseId = info.PurchaseId
	local intent = intents[buyer.UserId]

	-- Robux already spent: give Wins back instead. Grant + mark, no yield between.
	local function compensate(cause: string): Enum.ProductPurchaseDecision
		local amount = info.CurrencySpent * MonetizationConfig.GiftCompensationWinsPerRobux
		if amount > 0 and not DataService:AddTrophies(buyer, amount) then
			return Decision.NotProcessedYet
		end
		if not DataService:MarkReceiptProcessed(buyer, purchaseId) then
			return Decision.NotProcessedYet
		end
		if intents[buyer.UserId] == intent then
			intents[buyer.UserId] = nil
		end
		log:Warn(
			"COMPENSATION %s: %s gift %s (product %d, purchase %s) -> +%d Wins.",
			cause,
			buyer.Name,
			key,
			info.ProductId,
			purchaseId,
			amount
		)
		NotificationService.Send(
			buyer,
			("Gift couldn't be delivered: +%d Wins instead."):format(amount),
			"Error"
		)
		return Decision.PurchaseGranted
	end

	if not intent or intent.PassKey ~= key then
		return compensate("IntentLost")
	end
	local recipient = Players:GetPlayerByUserId(intent.RecipientUserId)
	if not recipient or not DataService:IsProfileLoaded(recipient) then
		return compensate("RecipientGone")
	end
	local gifted = DataService:GetGiftedPass(recipient, key)
	if gifted and gifted.ReceiptId == purchaseId then
		-- Replay of a receipt that already delivered: confirm, no compensation.
		if not DataService:MarkReceiptProcessed(buyer, purchaseId) then
			return Decision.NotProcessedYet
		end
		intents[buyer.UserId] = nil
		return Decision.PurchaseGranted
	end

	local verified, owns = freshOwns(recipient, key) -- the only yield
	if not verified or buyer.Parent ~= Players or not DataService:IsProfileLoaded(buyer) then
		return Decision.NotProcessedYet
	end
	if intents[buyer.UserId] ~= intent then
		return compensate("IntentChanged")
	end
	if recipient.Parent ~= Players or not DataService:IsProfileLoaded(recipient) then
		return compensate("RecipientGone")
	end
	if owns then
		return compensate("RecipientOwns")
	end
	if not DataService:GrantGiftedPass(recipient, key, purchaseId) then
		return compensate("GrantFailed")
	end
	DataService:MarkReceiptProcessed(buyer, purchaseId) -- buyer profile checked above, same frame
	intents[buyer.UserId] = nil

	GamePassService.SetOwned(recipient, key)
	log:Info("%s gifted %s to %s (purchase %s).", buyer.Name, key, recipient.Name, purchaseId)
	NotificationService.Send(buyer, ("Gift sent to %s!"):format(recipient.DisplayName), "Success")
	NotificationService.Send(
		recipient,
		("%s gifted you %s!"):format(buyer.DisplayName, key),
		"Success"
	)
	return Decision.PurchaseGranted
end

function GiftPassService.HandleReceipt(
	buyer: Player,
	info: ReceiptInfo
): Enum.ProductPurchaseDecision
	if inFlightReceipts[info.PurchaseId] then
		return Decision.NotProcessedYet
	end
	inFlightReceipts[info.PurchaseId] = true
	local ok, decision = pcall(handle, buyer, info)
	inFlightReceipts[info.PurchaseId] = nil
	if not ok then
		log:Error(
			"Gift receipt %s (%s) errored: %s",
			info.PurchaseId,
			buyer.Name,
			tostring(decision)
		)
		return Decision.NotProcessedYet
	end
	return decision
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function GiftPassService:Init(): ()
	validateConfig()

	NetworkEvents.OnServerInvoke("RequestGiftPass", GiftPassService.Request, true)
	NetworkEvents.OnServerInvoke("GetGiftEligibility", GiftPassService.GetEligibility)

	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, isPurchased: boolean)
			if not isPurchased and giftProductToKey[productId] then
				intents[userId] = nil
			end
		end
	)

	Players.PlayerRemoving:Connect(function(player: Player)
		intents[player.UserId] = nil
		for buyerId, intent in intents do
			if intent.RecipientUserId == player.UserId then
				intents[buyerId] = nil
			end
		end
		eligibilityCache[player.UserId] = nil
		eligibilityBusy[player] = nil
	end)
end

function GiftPassService:Start(): ()
	-- Visual check of the mapping in the output.
	for giftId, key in giftProductToKey do
		local ok, info = pcall(
			MarketplaceService.GetProductInfo,
			MarketplaceService,
			giftId,
			Enum.InfoType.Product
		)
		log:Info(
			"Gift %s -> product %d: %s",
			key,
			giftId,
			if ok then tostring(info.Name) else "GetProductInfo failed"
		)
	end
end

return GiftPassService
