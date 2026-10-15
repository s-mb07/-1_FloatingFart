--!strict
--[[
	@module GamePassService
	@description Gamepass ownership (ReplicatedStorage/Config/GamePassConfig).
	The ONLY module that calls UserOwnsGamePassAsync.

	Ownership = real pass OR gifted pass (DataService GiftedPasses), cached in
	the player attribute GamePassConfig.Attribute(key):
	  - join: one API call per pass, each in its own task.spawn;
	  - profile loaded (OnDataLoaded): gifted passes set to owned, no API call;
	  - bought in session (PromptGamePassPurchaseFinished, a server signal the
	    client can't fake): trusted at once (the API answers false right
	    after a purchase anyway), so the client's reveal starts immediately.
	An API failure never writes the attribute, and an owned pass never goes
	back to false before the profile is loaded (a gift is not known yet).

	Reading:
	  - HasPass(player, key): attribute only, never yields -- the gameplay API.
	    MonetizationConfig.FreeMode makes every pass owned.
	  - OwnsAnyAsync(player, key): fresh, uncached, YIELDS. Returns
	    (verificationOk, owns); verificationOk = false -> refuse (fail closed).
	    Never call it between a grant and its MarkReceiptProcessed.

	Prompt: Prompt(player, key) server-side, or NetworkEvents
	"PromptGamePassPurchase" (passKey) from the client. Id 0 or already owned
	= no prompt.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassConfig = require(ReplicatedStorage.Config.GamePassConfig)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)
local MonetizationService = require(script.Parent.MonetizationService)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local log = Logger.new("GamePassService")
local GamePassService = {}

local Passes = GamePassConfig.Passes

--- Writes the cached ownership; fires OnGamePassOwned on a false -> true change.
local function setOwned(player: Player, key: string, owns: boolean): ()
	if player.Parent ~= Players then
		return
	end
	local attribute = GamePassConfig.Attribute(key)
	local was = player:GetAttribute(attribute) == true
	if was and not owns and not DataService:IsProfileLoaded(player) then
		return -- may be a gift we can't see yet
	end
	player:SetAttribute(attribute, owns)
	if owns and not was then
		GameEvents.OnGamePassOwned:Fire(player, key)
	end
end

--- (ok, owns) from the API; Id 0 = (true, false) without a call. Yields.
local function apiOwns(player: Player, id: number): (boolean, boolean)
	if id <= 0 then
		return true, false
	end
	local ok, owns =
		pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
	if not ok then
		log:Warn(
			"UserOwnsGamePassAsync failed for %s (pass %d): %s",
			player.Name,
			id,
			tostring(owns)
		)
		return false, false
	end
	return true, owns == true
end

--- Server gameplay check: cached, never yields.
function GamePassService.HasPass(player: Player, key: string): boolean
	return MonetizationConfig.FreeMode or GamePassConfig.PlayerHasPass(player, key)
end

--- Fresh ownership (real or gifted), uncached. YIELDS. (verificationOk, owns).
function GamePassService.OwnsAnyAsync(player: Player, key: string): (boolean, boolean)
	local def = Passes[key]
	if not def then
		return false, false
	end
	if DataService:GetGiftedPass(player, key) then
		return true, true
	end
	return apiOwns(player, def.Id)
end

--- Re-checks `key` for `player` and updates the cache. Yields.
function GamePassService.Refresh(player: Player, key: string): ()
	local ok, owns = GamePassService.OwnsAnyAsync(player, key)
	if ok then
		setOwned(player, key, owns)
	end
end

--- Re-checks every pass at once and waits for all of them (admin data reset:
--- drops a stale cached ownership, e.g. a Studio test purchase). Yields.
function GamePassService.RefreshAll(player: Player): ()
	local pending = 0
	for key in Passes do
		pending += 1
		task.spawn(function()
			GamePassService.Refresh(player, key)
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
end

--- Calls `grant(player, key)` when pass `key` becomes owned, and again for
--- every owned pass once the profile loads (the attribute can land first,
--- before data can be written). `grant` must be idempotent.
function GamePassService.WhenOwned(grant: (Player, string) -> ()): ()
	GameEvents.OnGamePassOwned:Connect(grant)
	GameEvents.OnDataLoaded:Connect(function(player: Player)
		for key in Passes do
			if GamePassConfig.PlayerHasPass(player, key) then
				grant(player, key)
			end
		end
	end)
end

--- Marks `key` owned now (GiftPassService after a gift grant).
function GamePassService.SetOwned(player: Player, key: string): ()
	setOwned(player, key, true)
end

--- Opens the purchase prompt of pass `key`. false = unknown key, id not set
--- yet, or already owned.
function GamePassService.Prompt(player: Player, key: string): (boolean, string?)
	local def = Passes[key]
	if not def then
		log:Warn("%s asked for unknown pass '%s'.", player.Name, key)
		return false, "UnknownPass"
	end
	if def.Id <= 0 then
		return false, "NotConfigured"
	end
	if GamePassConfig.PlayerHasPass(player, key) then
		return false, "AlreadyOwned"
	end
	MonetizationService.PromptGamepassPurchase(player, def.Id)
	return true
end

--- `reveal`: tell the client to play its item reveal for `key` (cosmetic).
local function grantAfterPurchase(player: Player, key: string, id: number, reveal: boolean): ()
	setOwned(player, key, true)
	log:Info("%s bought pass %s (%d).", player.Name, key, id)
	if reveal and player.Parent == Players then
		NetworkEvents.FireClient("PurchaseGranted", player, key)
	end
end

local function onPlayerAdded(player: Player): ()
	for key in Passes do
		task.spawn(GamePassService.Refresh, player, key)
	end
end

function GamePassService:Init(): ()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	GameEvents.OnDataLoaded:Connect(function(player: Player)
		for key in Passes do
			if DataService:GetGiftedPass(player, key) then
				setOwned(player, key, true)
			end
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, id: number, purchased: boolean)
			if not purchased or id <= 0 then
				return
			end
			for key, def in Passes do
				if def.Id == id then
					task.spawn(grantAfterPurchase, player, key, id, true)
				end
			end
		end
	)

	NetworkEvents.OnServerEvent("PromptGamePassPurchase", function(player: Player, key: any)
		if type(key) == "string" and #key <= 64 then
			GamePassService.Prompt(player, key)
		end
	end)
end

function GamePassService:Start(): () end

return GamePassService
