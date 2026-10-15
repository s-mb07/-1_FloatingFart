--!strict
--[[
	@module DataService
	@description Handles loading, saving, and accessing player data via
	ProfileStore. Minimal ADAPTABLE example -- add your own mutators as you
	go, keeping the same shape:

	WRITE FACADE:
	- Every mutation of profile.Data goes through a public mutator of this module.
	- Each mutator writes synchronously, then calls markDirty(player, key).
	- A coalesced flush (task.defer) fires a SINGLE "DataUpdated" per player per
	  frame: { [key] = COMPLETE snapshot of profile.Data[key] } (never a
	  partial diff) -- avoids a player triggering 10 mutations in the same
	  frame sending 10 remotes.
	- Direct FireClient("DataUpdated") calls outside this module are forbidden.
	- Common error signature: (boolean, string?) -- success + stable
	  PascalCase reason code ("NoProfile", "InvalidAmount", ...), never
	  assert/error on runtime input (the client can lie).

	CAVEAT (do NOT replicate this as-is on a real game): DataService remains
	the service most tempted to become a "god service" (66 public
	methods in this kit's source project) -- as soon as a data domain grows
	(inventory, progression...), split off a dedicated service that
	READS/WRITES via the mutators here rather than piling its own methods on
	top of this one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataTemplateModule = require(script.Parent.Parent.Config.DataTemplate)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local ProfileStore = require(ServerScriptService.Packages.ProfileStore)

local DataService = {}
local log = Logger.new("DataService")

type PlayerProfile = DataTemplateModule.PlayerProfile

DataService.ErrorCodes = {
	NoProfile = "NoProfile",
	InvalidAmount = "InvalidAmount",
	InvalidLevel = "InvalidLevel",
	InsufficientFunds = "InsufficientFunds",
	SkinNotOwned = "SkinNotOwned",
	TrailNotOwned = "TrailNotOwned",
	InvalidSetting = "InvalidSetting",
}

local STORE_NAME = "PlayerData_V1"
-- Receipt markers older than this are dropped on load. Roblox only re-sends a
-- receipt that was never confirmed, within days; 90 days is margin.
local RECEIPT_TTL = 90 * 24 * 3600
local DATA_TEMPLATE = DataTemplateModule
local TEMPLATE: any = DATA_TEMPLATE -- dynamic view of the template to validate markDirty keys

local IS_STUDIO = RunService:IsStudio()
local Store = ProfileStore.New(STORE_NAME, DATA_TEMPLATE)
-- In Studio, .Mock avoids writing to the real DataStore while iterating.
local SessionStore = if IS_STUDIO then Store.Mock else Store

local Profiles: { [Player]: typeof(assert(SessionStore:StartSessionAsync("", {}))) } = {}
local DirtyKeys: { [Player]: { [string]: boolean } } = {}
local FlushScheduled: { [Player]: boolean } = {}

--============================================================================--
-- WRITE COALESCING (markDirty -> flushDirty, at most 1x/frame/player)
--============================================================================--

local function flushDirty(player: Player): ()
	FlushScheduled[player] = nil
	local keys = DirtyKeys[player]
	DirtyKeys[player] = nil
	if keys == nil then
		return
	end

	local profile = Profiles[player]
	if profile == nil then
		return
	end -- session ended between markDirty and the defer

	local patch: { [string]: any } = {}
	local hasAny = false
	for key in pairs(keys) do
		patch[key] = (profile.Data :: any)[key]
		hasAny = true
	end
	if hasAny then
		NetworkEvents.FireClient("DataUpdated", player, patch)
	end
end

local function markDirty(player: Player, key: string): ()
	if TEMPLATE[key] == nil then
		log:Warn("markDirty: key unknown to the template ignored: %s", tostring(key))
		return
	end
	if Profiles[player] == nil then
		return
	end -- post-session: no-op

	local keys = DirtyKeys[player]
	if keys == nil then
		keys = {}
		DirtyKeys[player] = keys
	end
	keys[key] = true

	if not FlushScheduled[player] then
		FlushScheduled[player] = true
		task.defer(flushDirty, player)
	end
end

--============================================================================--
-- PUBLIC MUTATORS (example -- add your own in the same format)
--============================================================================--

--- @return number
function DataService:GetGold(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Currencies.Gold or 0
end

--- @return boolean, string?
function DataService:AddGold(player: Player, amount: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(amount) ~= "number" or amount ~= amount then -- NaN check
		return false, DataService.ErrorCodes.InvalidAmount
	end

	profile.Data.Currencies.Gold += amount
	markDirty(player, "Currencies")
	return true
end

--- @return number
function DataService:GetTrophies(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Currencies.Trophies or 0
end

--- Adds (amount > 0) trophies.
--- @return boolean, string?
function DataService:AddTrophies(player: Player, amount: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, DataService.ErrorCodes.InvalidAmount
	end

	profile.Data.Currencies.Trophies += amount
	markDirty(player, "Currencies")
	return true
end

--- Removes `amount` trophies; refuses (no partial spend) if the balance is short.
--- @return boolean, string?
function DataService:SpendTrophies(player: Player, amount: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return false, DataService.ErrorCodes.InvalidAmount
	end
	if profile.Data.Currencies.Trophies < amount then
		return false, DataService.ErrorCodes.InsufficientFunds
	end

	profile.Data.Currencies.Trophies -= amount
	markDirty(player, "Currencies")
	return true
end

--============================================================================--
-- SKINS (persisted values only; the rules live in SkinService)
--============================================================================--

--- @return boolean
function DataService:OwnsSkin(player: Player, skinId: string): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.Data.Skins.Owned[skinId] == true
end

--- @return string -- the template default when no profile is loaded
function DataService:GetEquippedSkin(player: Player): string
	local profile = Profiles[player]
	return profile and profile.Data.Skins.Equipped or DATA_TEMPLATE.Skins.Equipped
end

--- @return boolean, string?
function DataService:UnlockSkin(player: Player, skinId: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.Skins.Owned[skinId] = true
	markDirty(player, "Skins")
	return true
end

--- Equips a skin the player must already own.
--- @return boolean, string?
function DataService:SetEquippedSkin(player: Player, skinId: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if profile.Data.Skins.Owned[skinId] ~= true then
		return false, DataService.ErrorCodes.SkinNotOwned
	end
	profile.Data.Skins.Equipped = skinId
	markDirty(player, "Skins")
	return true
end

--============================================================================--
-- TRAVERSAL PROGRESSION (persisted values only)
--
-- Mutators, not logic: threshold crossing, multi-level-ups and the
-- recalculation a level-up triggers all live in TraversalProgressionService.
-- This is the §5 split in practice -- the write facade stays here so every
-- mutation is typed, coalesced and replicated the same way, while the domain
-- logic that would otherwise grow this file into a god-service does not.
--============================================================================--

--- @param player Player
--- @return number -- 1 (the template default) when no profile is loaded
function DataService:GetTraversalLevel(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Traversal.Level or 1
end

--- @param player Player
--- @return number
function DataService:GetTraversalXP(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Traversal.XP or 0
end

--- Adds XP. Does NOT level anyone up -- see TraversalProgressionService.
--- @param player Player
--- @param amount number -- finite, > 0
--- @return boolean, string?
function DataService:AddTraversalXP(player: Player, amount: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	-- NaN fails every comparison and inf survives them, so both are caught
	-- by requiring a finite positive number, same shape as AddGold above.
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, DataService.ErrorCodes.InvalidAmount
	end

	profile.Data.Traversal.XP += amount
	markDirty(player, "Traversal")
	return true
end

--- Sets the level outright. Internal to the progression service, which is
--- the only thing that knows when a threshold has actually been crossed --
--- exposed (rather than kept private) because the level is persisted data
--- and §5 requires every write to it to go through a mutator here.
--- @param player Player
--- @param level number -- integer >= 1
--- @return boolean, string?
function DataService:SetTraversalLevel(player: Player, level: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(level) ~= "number" or level ~= level or level < 1 or level % 1 ~= 0 then
		return false, DataService.ErrorCodes.InvalidLevel
	end

	profile.Data.Traversal.Level = level
	markDirty(player, "Traversal")
	return true
end

--- @param player Player
--- @return number -- 0 when no profile is loaded
function DataService:GetRebirths(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Traversal.Rebirths or 0
end

--- Records a rebirth in ONE write: Rebirths = `rebirths`, Level = 1, XP = 0.
--- Atomic on purpose so the three can never be observed out of sync. The
--- rules (which rebirth is allowed when) live in RebirthService.
--- @param player Player
--- @param rebirths number -- the new rebirth count, integer >= 1
--- @return boolean, string?
function DataService:ApplyRebirth(player: Player, rebirths: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(rebirths) ~= "number" or rebirths ~= rebirths or rebirths < 1 or rebirths % 1 ~= 0 then
		return false, DataService.ErrorCodes.InvalidAmount
	end

	local traversal = profile.Data.Traversal
	traversal.Rebirths = rebirths
	traversal.Level = 1
	traversal.XP = 0
	markDirty(player, "Traversal")
	return true
end

--============================================================================--
-- TUTORIAL (persisted values only; the rules live in TutorialService)
--============================================================================--

--- @return number? -- current tutorial stage, nil when no profile is loaded
function DataService:GetTutorialStage(player: Player): number?
	local profile = Profiles[player]
	return profile and profile.Data.Tutorial.Stage
end

--- @param stage number -- integer >= 1
--- @return boolean, string?
function DataService:SetTutorialStage(player: Player, stage: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(stage) ~= "number" or stage < 1 or stage % 1 ~= 0 then
		return false, DataService.ErrorCodes.InvalidAmount
	end
	profile.Data.Tutorial.Stage = stage
	markDirty(player, "Tutorial")
	return true
end

--- @return boolean, string?
function DataService:MarkRebirthFocusShown(player: Player): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.Tutorial.RebirthFocusShown = true
	markDirty(player, "Tutorial")
	return true
end

--============================================================================--
-- SETTINGS
--============================================================================--

--- Writes one user setting. Only keys of the template's Settings are
--- accepted, with the same type as their default (the client can lie).
--- @param key string -- a DataTemplate.Settings key
--- @param value any -- same type as the template default
--- @return boolean, string?
function DataService:SetSetting(player: Player, key: any, value: any): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	local default = if type(key) == "string" then TEMPLATE.Settings[key] else nil
	if
		default == nil
		or type(value) ~= type(default)
		or (type(value) == "string" and #value > 16)
	then
		return false, DataService.ErrorCodes.InvalidSetting
	end
	(profile.Data.Settings :: any)[key] = value
	markDirty(player, "Settings")
	return true
end

--============================================================================--
-- SHOP (persisted flags only; the rules live in ShopService)
--============================================================================--

--- @return boolean
function DataService:HasShopItem(player: Player, itemId: string): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.Data.ShopClaimed[itemId] == true
end

--- @return boolean, string?
function DataService:MarkShopItem(player: Player, itemId: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.ShopClaimed[itemId] = true
	markDirty(player, "ShopClaimed")
	return true
end

--============================================================================--
-- STARTER PACK (persisted flag only; the rules live in StarterPackService)
--============================================================================--

--- @return boolean -- true once claimed (also true when no profile is loaded,
--- so nothing can be granted before the profile exists)
function DataService:HasClaimedStarterPack(player: Player): boolean
	local profile = Profiles[player]
	return profile == nil or profile.Data.StarterPackClaimed == true
end

--- @return boolean, string?
function DataService:MarkStarterPackClaimed(player: Player): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.StarterPackClaimed = true
	markDirty(player, "StarterPackClaimed")
	return true
end

--============================================================================--
-- ONE-TIME FLAGS (group reward, favorite prompt; rules in their services)
--============================================================================--

type FlagKey = "GroupRewardClaimed" | "FavoritePrompted"

--- @param key FlagKey
--- @return boolean -- true once set (also true when no profile is loaded,
--- so nothing is granted / prompted before the profile exists)
function DataService:HasFlag(player: Player, key: FlagKey): boolean
	local profile = Profiles[player]
	return profile == nil or (profile.Data :: any)[key] == true
end

--- @param key FlagKey
--- @return boolean, string?
function DataService:SetFlag(player: Player, key: FlagKey): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	(profile.Data :: any)[key] = true
	markDirty(player, key)
	return true
end

--============================================================================--
-- LEAVE REWARD (persisted value only; the once-per-day rule lives in LeaveRewardService)
--============================================================================--

--- @return number -- UTC day index of the last claim, 0 = never (math.huge
--- when no profile is loaded, so nothing is granted before it exists)
function DataService:GetLeaveRewardLastClaimDay(player: Player): number
	local profile = Profiles[player]
	return if profile then profile.Data.LeaveRewardLastClaimDay else math.huge
end

--- @param day number -- UTC day index of this claim
--- @return boolean, string?
function DataService:SetLeaveRewardLastClaimDay(player: Player, day: number): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(day) ~= "number" or day % 1 ~= 0 then
		return false, DataService.ErrorCodes.InvalidAmount
	end
	profile.Data.LeaveRewardLastClaimDay = day
	markDirty(player, "LeaveRewardLastClaimDay")
	return true
end

--============================================================================--
-- TRAILS (persisted values only; the rules live in TrailService / TrailConfig)
--============================================================================--

--- @return boolean
function DataService:OwnsTrail(player: Player, trailId: string): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.Data.Trails.Owned[trailId] == true
end

--- @return string -- equipped trail id, "" for none (also when no profile is loaded)
function DataService:GetEquippedTrail(player: Player): string
	local profile = Profiles[player]
	return profile and profile.Data.Trails.Equipped or ""
end

--- @return boolean, string?
function DataService:UnlockTrail(player: Player, trailId: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.Trails.Owned[trailId] = true
	markDirty(player, "Trails")
	return true
end

--- Equips an owned trail, or unequips with "".
--- @return boolean, string?
function DataService:SetEquippedTrail(player: Player, trailId: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if trailId ~= "" and profile.Data.Trails.Owned[trailId] ~= true then
		return false, DataService.ErrorCodes.TrailNotOwned
	end
	profile.Data.Trails.Equipped = trailId
	markDirty(player, "Trails")
	return true
end

--============================================================================--
-- BOOSTS (persisted values only; the rules live in BoostService / BoostConfig)
--============================================================================--

--- @param player Player
--- @return number -- per-second XP coefficient (1 = none), 1 when no profile is loaded
function DataService:GetLengthMultiplier(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Boosts.LengthMultiplier or 1
end

--- @param player Player
--- @return number -- treadmill pace (1 = normal, 2 = Fast Train), 1 when no profile is loaded
function DataService:GetTreadmillSpeed(player: Player): number
	local profile = Profiles[player]
	return profile and profile.Data.Boosts.TreadmillSpeed or 1
end

--- Sets Boosts[key] (a multiplier coefficient). Replaces, never multiplies.
--- @param key string -- "LengthMultiplier" | "TreadmillSpeed"
--- @param value number -- integer >= 1
--- @return boolean, string?
function DataService:SetBoostMultiplier(
	player: Player,
	key: "LengthMultiplier" | "TreadmillSpeed",
	value: number
): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if type(value) ~= "number" or value ~= value or value < 1 or value % 1 ~= 0 then
		return false, DataService.ErrorCodes.InvalidAmount
	end
	profile.Data.Boosts[key] = value
	markDirty(player, "Boosts")
	return true
end

--============================================================================--
-- DAILY REWARDS (persisted values only; the rules live in DailyRewardService)
--============================================================================--

--- @return number, number -- claimed days in the cycle, UTC day of the last claim
function DataService:GetDailyRewards(player: Player): (number, number)
	local profile = Profiles[player]
	if not profile then
		return 0, 0
	end
	return profile.Data.DailyRewards.Claimed, profile.Data.DailyRewards.LastClaimDay
end

--- @param claimed number -- integer 1..7
--- @param lastClaimDay number -- UTC day index of this claim
--- @return boolean, string?
function DataService:SetDailyRewards(
	player: Player,
	claimed: number,
	lastClaimDay: number
): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if
		type(claimed) ~= "number"
		or claimed < 0
		or claimed % 1 ~= 0
		or type(lastClaimDay) ~= "number"
	then
		return false, DataService.ErrorCodes.InvalidAmount
	end

	profile.Data.DailyRewards.Claimed = claimed
	profile.Data.DailyRewards.LastClaimDay = lastClaimDay
	markDirty(player, "DailyRewards")
	return true
end

--============================================================================--
-- PLAYTIME REWARDS (persisted values only; the rules live in PlaytimeRewardService)
--============================================================================--

--- @return number, number, number -- UTC day, seconds played that day, claimed bitmask
function DataService:GetPlaytimeRewards(player: Player): (number, number, number)
	local profile = Profiles[player]
	if not profile then
		return 0, 0, 0
	end
	local data = profile.Data.PlaytimeRewards
	return data.Day, data.Seconds, data.Claimed
end

--- @return boolean, string?
function DataService:SetPlaytimeRewards(
	player: Player,
	day: number,
	seconds: number,
	claimed: number
): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	if
		type(day) ~= "number"
		or type(seconds) ~= "number"
		or seconds ~= seconds
		or seconds < 0
		or type(claimed) ~= "number"
		or claimed < 0
		or claimed % 1 ~= 0
	then
		return false, DataService.ErrorCodes.InvalidAmount
	end
	local data = profile.Data.PlaytimeRewards
	data.Day = day
	data.Seconds = seconds
	data.Claimed = claimed
	markDirty(player, "PlaytimeRewards")
	return true
end

--============================================================================--
-- CODES (persisted values only; the rules live in CodeService)
--============================================================================--

--- @param code string -- normalized (lowercase) code id
--- @return boolean
function DataService:HasRedeemedCode(player: Player, code: string): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.Data.RedeemedCodes[code] == true
end

--- @param code string -- normalized (lowercase) code id
--- @return boolean, string?
function DataService:MarkCodeRedeemed(player: Player, code: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.RedeemedCodes[code] = true
	markDirty(player, "RedeemedCodes")
	return true
end

--============================================================================--
-- ADMIN RESET (called by AdminService only, after its own authorization)
--============================================================================--

--============================================================================--
-- PURCHASES (receipts + gifted passes; rules in MonetizationService /
-- GiftPassService). All synchronous, never yield: a grant and its receipt
-- marker land in the same profile in the same frame. Not pushed to the
-- client (no markDirty); ProfileStore saves profile.Data whole.
--============================================================================--

--- @return boolean -- true once the profile is loaded (purchases need it)
function DataService:IsProfileLoaded(player: Player): boolean
	return Profiles[player] ~= nil
end

--- @return boolean
function DataService:IsReceiptProcessed(player: Player, purchaseId: string): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.Data.ProcessedReceipts[purchaseId] ~= nil
end

--- @return boolean, string?
function DataService:MarkReceiptProcessed(player: Player, purchaseId: string): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.ProcessedReceipts[purchaseId] = os.time()
	return true
end

--- @return GiftedPass? -- nil when not gifted (or no profile)
function DataService:GetGiftedPass(player: Player, passKey: string): DataTemplateModule.GiftedPass?
	local profile = Profiles[player]
	return if profile then profile.Data.GiftedPasses[passKey] else nil
end

--- @return boolean, string?
function DataService:GrantGiftedPass(
	player: Player,
	passKey: string,
	receiptId: string
): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	profile.Data.GiftedPasses[passKey] = { At = os.time(), ReceiptId = receiptId }
	return true
end

-- Everything a reset puts back to the template. Settings and Stats stay.
local RESET_KEYS = {
	"Currencies",
	"Traversal",
	"Skins",
	"Trails",
	"Boosts",
	"DailyRewards",
	"PlaytimeRewards",
	"StarterPackClaimed",
	"GroupRewardClaimed",
	"LeaveRewardLastClaimDay",
	"FavoritePrompted",
	"Tutorial",
	"ShopClaimed",
	"RedeemedCodes",
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

--- Puts the progress of `player` back to a brand-new profile (skins, trails,
--- levels, XP, rebirths, currencies, boosts, rewards, tutorial...).
--- @return boolean, string?
function DataService:ResetPlayerData(player: Player): (boolean, string?)
	local profile = Profiles[player]
	if not profile then
		return false, DataService.ErrorCodes.NoProfile
	end
	for _, key in RESET_KEYS do
		(profile.Data :: any)[key] = deepCopy((DATA_TEMPLATE :: any)[key])
		markDirty(player, key)
	end
	return true
end

--============================================================================--
-- PROFILE LIFECYCLE
--============================================================================--

local function sendDataToClient(player: Player): ()
	local profile = Profiles[player]
	if not profile then
		return
	end
	NetworkEvents.FireClient("DataInitialized", player, profile.Data)
end

local function initializeProfile(player: Player): ()
	local profile = SessionStore:StartSessionAsync(tostring(player.UserId), {})
	if not profile then
		player:Kick("Unable to load your profile (session already active elsewhere?).")
		return
	end

	profile:Reconcile() -- fills in missing fields from DATA_TEMPLATE (does not touch arrays)

	local receiptCutoff = os.time() - RECEIPT_TTL
	for purchaseId, at in profile.Data.ProcessedReceipts do
		if at < receiptCutoff then
			profile.Data.ProcessedReceipts[purchaseId] = nil
		end
	end

	profile.Data.Stats.LastLogin = os.time()
	if profile.Data.Stats.CreatedAt == 0 then
		profile.Data.Stats.CreatedAt = os.time()
	end

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Your data session has ended (logged in elsewhere?).")
	end)

	if not player:IsDescendantOf(Players) then
		profile:EndSession() -- the player left while loading
		return
	end

	Profiles[player] = profile
	log:Info("Profile loaded for %s", player.Name)

	sendDataToClient(player)
	GameEvents.OnDataLoaded:Fire(player) -- signals other services that data is ready
end

local function releaseProfile(player: Player): ()
	local profile = Profiles[player]
	if profile then
		flushDirty(player) -- force pending keys through BEFORE ending the session
		profile:EndSession()
		Profiles[player] = nil
		log:Debug("Profile released for %s", player.Name)
	end
	DirtyKeys[player] = nil
	FlushScheduled[player] = nil
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function DataService:Init(): ()
	log:Info(
		"Persistence: %s — DataStoreState=%s",
		IS_STUDIO and "MOCK (Studio)" or "LIVE",
		tostring(ProfileStore.DataStoreState)
	)

	Players.PlayerAdded:Connect(initializeProfile)
	Players.PlayerRemoving:Connect(releaseProfile)

	NetworkEvents.OnServerEvent("UpdateSetting", function(player: Player, payload: any)
		if type(payload) == "table" then
			DataService:SetSetting(player, payload.Setting, payload.Value)
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(initializeProfile, player)
	end
end

return DataService
