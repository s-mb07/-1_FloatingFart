--!strict
--[[
	@module SkinPadController
	@description Dresses the skin pads (parts tagged TagNames.SkinPad, `Id`
	attribute = skin id, see Config/SkinConfig) for the LOCAL player. Purely
	cosmetic -- buying and equipping is entirely SkinService.

	One state per pad, from the replicated EquippedSkin / OwnedSkins player
	attributes:
	  - equipped          yellow, GUI on,  WinCost = "EQUIPPED"
	  - owned, not worn   white,  GUI on,  WinCost = "POSSESSED"
	  - next to buy       red,    GUI on,  WinCost = price  (a Robux skin is
	                      always "next": it can be bought at any time; the
	                      VIP Golden Plane reads "VIP")
	  - everything else   black,  GUI off  (cannot be bought yet)
	`AddLengh` always shows the skin's "+N Length" (SkinConfig XPPerSecond).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local InstanceUtil = require(ReplicatedStorage.Libraries.Utils.Instance)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local SkinConfig = require(ReplicatedStorage.Config.SkinConfig)
local Skins = require(script.Parent.Parent.Libraries.Skins)
local EventBus = require(script.Parent.Parent.Events.EventBus)
local PlayerDataFetcher = require(script.Parent.Parent.Events.PlayerDataFetcher)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)

local log = Logger.new("SkinPadController")
local SkinPadController = {}

-- Slightly dimmed: full-intensity colors glare on the pads.
local COLORS = {
	Equipped = Color3.fromRGB(215, 172, 35),
	Owned = Color3.fromRGB(205, 205, 205),
	Next = Color3.fromRGB(185, 35, 35),
	Affordable = Color3.fromRGB(40, 170, 60),
	Locked = Color3.fromRGB(0, 0, 0),
}

-- Names inside the pad, authored in Studio: Touch.GUI (BillboardGui) holds the
-- TextLabels `WinCost` and `AddLengh`.
local GUI_NAME = "GUI"
local COST_LABEL_NAME = "WinCost"
local LENGTH_LABEL_NAME = "AddLengh"

local LocalPlayer = Players.LocalPlayer

-- Wins (Currencies.Trophies) from the server data snapshot; 0 until it lands.
local wins = 0

local function paint(pad: Instance): ()
	if not pad:IsA("BasePart") then
		return
	end
	local id = pad:GetAttribute(TagNames.Attr.Id)
	local def = if type(id) == "string" then SkinConfig.Skins[id] else nil
	if not def or type(id) ~= "string" then
		return
	end

	local owned = SkinConfig.DecodeOwned(LocalPlayer:GetAttribute(SkinConfig.OwnedAttribute))
	local state: string
	if Skins.GetEquipped(LocalPlayer) == id then
		state = "Equipped"
	elseif owned[id] then
		state = "Owned"
	elseif def.GamePass or SkinConfig.NextToBuy(owned) == id then
		state = if not def.GamePass and wins >= def.Price then "Affordable" else "Next"
	else
		state = "Locked"
	end

	pad.Color = COLORS[state]
	local gui = pad:FindFirstChild(GUI_NAME)
	if not gui then
		-- Streaming: the GUI may land after the pad itself
		InstanceUtil.OnDescendantNamed(pad, GUI_NAME, function()
			paint(pad)
		end)
		return
	end
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = state ~= "Locked"
	end
	local lengthLabel = gui and gui:FindFirstChild(LENGTH_LABEL_NAME)
	if lengthLabel and lengthLabel:IsA("TextLabel") then
		lengthLabel.Text = ("+%s Length"):format(NumberUtil.Format(def.XPPerSecond))
	end
	local label = gui and gui:FindFirstChild(COST_LABEL_NAME)
	if label and label:IsA("TextLabel") then
		if state == "Equipped" then
			label.Text = "EQUIPPED"
		elseif state == "Owned" then
			label.Text = "POSSESSED"
		elseif def.PriceRobux then
			label.Text = BoostConfig.PriceText(def.PriceRobux)
		elseif def.GamePass then
			label.Text = "👑 VIP"
		else
			label.Text = ("%s %s Required"):format(
				NumberUtil.FormatShort(def.Price),
				if def.Price == 1 then "Win" else "Wins"
			)
		end
	end
end

local function paintAll(): ()
	for _, pad in CollectionService:GetTagged(TagNames.SkinPad) do
		paint(pad)
	end
end

function SkinPadController:Init(): ()
	log:Info("Initialized.")
end

local function absorb(data: any): ()
	local value = data and data.Currencies and data.Currencies.Trophies
	if type(value) == "number" and value ~= wins then
		wins = value
		paintAll()
	end
end

function SkinPadController:Start(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
	-- Present and future (streaming) pads.
	paintAll()
	CollectionService:GetInstanceAddedSignal(TagNames.SkinPad):Connect(paint)
	LocalPlayer:GetAttributeChangedSignal(SkinConfig.EquippedAttribute):Connect(paintAll)
	LocalPlayer:GetAttributeChangedSignal(SkinConfig.OwnedAttribute):Connect(paintAll)
	log:Info("Started.")
end

return SkinPadController
