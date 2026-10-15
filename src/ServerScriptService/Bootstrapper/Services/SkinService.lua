--!strict
--[[
	@module SkinService
	@description Server authority for skins. Stepping on a skin pad (a Part
	tagged TagNames.SkinPad with an `Id` attribute, see Config/SkinConfig) does exactly one of:
	  - skin owned            -> equip it;
	  - not owned, affordable -> spend the trophies, unlock, equip;
	  - Robux skin, not owned -> gamepass prompt (the purchase unlocks it,
	                             the next step on the pad equips it);
	  - otherwise             -> nothing.

	The equipped skin is mirrored on the player as an attribute
	(SkinConfig.EquippedAttribute) so EVERY client can dress that player's
	probe and colour the pads, with no dedicated remote. Its XP rate is read
	through GetXPPerSecond (used by TraversalProgressionService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessGate = require(script.Parent.Parent.AccessGate)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local SkinConfig = require(ReplicatedStorage.Config.SkinConfig)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)

local log = Logger.new("SkinService")
local SkinService = {}

--- @return string -- equipped skin id, falling back to the default if the
--- saved id no longer exists in the catalogue.
function SkinService.GetEquipped(player: Player): string
	local id = DataService:GetEquippedSkin(player)
	return if SkinConfig.Skins[id] then id else SkinConfig.Default
end

--- Base XP/second of the equipped skin.
function SkinService.GetXPPerSecond(player: Player): number
	return SkinConfig.Skins[SkinService.GetEquipped(player)].XPPerSecond
end

local function syncAttribute(player: Player): ()
	player:SetAttribute(SkinConfig.EquippedAttribute, SkinService.GetEquipped(player))
	local owned: { [string]: boolean } = {}
	for id in SkinConfig.Skins do
		if DataService:OwnsSkin(player, id) then
			owned[id] = true
		end
	end
	player:SetAttribute(SkinConfig.OwnedAttribute, SkinConfig.EncodeOwned(owned))
end

local function onPadEntered(player: Player, skinId: string): ()
	local def = SkinConfig.Skins[skinId]
	if not def then
		return
	end

	if not DataService:OwnsSkin(player, skinId) then
		if def.GamePass then
			-- Robux skin: the gamepass is the ONLY way (never wins).
			if not AccessGate.OwnsPaid(player, def.GamePass) then
				GamePassService.Prompt(player, def.GamePass)
				return
			end
			DataService:UnlockSkin(player, skinId)
			log:Info("%s unlocked skin %s with Robux.", player.Name, skinId)
			GameEvents.OnSkinUnlocked:Fire(player, skinId)
		else
			-- Wins skins are bought in order: the previous one must be owned.
			local previous = SkinConfig.PreviousOf(skinId)
			if previous and not DataService:OwnsSkin(player, previous) then
				return
			end
			if DataService:GetTrophies(player) < def.Price then
				return -- cannot afford: nothing happens
			end
			local ok = DataService:SpendTrophies(player, def.Price)
			if not ok then
				return
			end
			DataService:UnlockSkin(player, skinId)
			log:Info("%s unlocked skin %s for %d trophies.", player.Name, skinId, def.Price)
			GameEvents.OnSkinUnlocked:Fire(player, skinId)
		end
	end

	if DataService:GetEquippedSkin(player) ~= skinId then
		DataService:SetEquippedSkin(player, skinId)
		syncAttribute(player)
		log:Info("%s equipped skin %s.", player.Name, skinId)
	end
end

--- Unlocks the Robux skins of pass `key` (bought or gifted).
local function grantPassSkins(player: Player, key: string): ()
	for id, def in SkinConfig.Skins do
		if def.GamePass == key and not DataService:OwnsSkin(player, id) then
			if DataService:UnlockSkin(player, id) then
				log:Info("%s unlocked skin %s with Robux.", player.Name, id)
				GameEvents.OnSkinUnlocked:Fire(player, id)
				syncAttribute(player)
			end
		end
	end
end

function SkinService:Init(): ()
	GamePassService.WhenOwned(grantPassSkins)
	log:Info("Initialized.")
end

function SkinService:Start(): ()
	GameEvents.OnDataLoaded:Connect(syncAttribute)
	GameEvents.OnAdminDataChanged:Connect(syncAttribute) -- skins unlocked / data reset by an admin
	for _, player in Players:GetPlayers() do
		syncAttribute(player)
	end

	PadTrigger.Bind(TagNames.SkinPad, {
		Reach = SkinConfig.PadReach,
		OnEnter = function(player: Player, pad: BasePart): ()
			local skinId = pad:GetAttribute(TagNames.Attr.Id)
			if type(skinId) ~= "string" then
				log:Warn("Skin pad '%s' has no Id attribute.", pad:GetFullName())
				return
			end
			onPadEntered(player, skinId)
		end,
	})
	log:Info("Started.")
end

return SkinService
