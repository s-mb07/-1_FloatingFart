--!strict
--[[
	@module Panels.Trails.Controller
	@description Trails panel over the Studio-authored
	PlayerGui/TrailsUI/MainFrame/Container/ScrollingFrame cards.

	Cards are driven by TrailConfig: each trail's `Card` Frame gets its
	Title (DisplayName), Bonus ("xN Points" = XPMultiplier) and prices
	(ImageButton/Price); cards with no trail in the config are hidden.
	Server-truth state from the `Trails` data snapshot:
	  - not owned -> the "Win" and "Robux" buttons, no Equip (no "Win" button
	                 on a trail without PriceWins; the VIP trail's Robux
	                 button reads "VIP" and opens the VIP prompt)
	  - owned     -> prices hidden, the "Equip/Unequip" button's Price label
	                 shows "Equip" or "Unequip" (if it's the equipped one)
	Buttons only ask (NetworkEvents "BuyTrail" / "EquipTrail"); TrailService decides.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local TrailConfig = require(ReplicatedStorage.Config.TrailConfig)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

type Card = {
	--- false: no Wins price (VIP trail), the Win button stays hidden.
	SoldForWins: boolean,
	WinsFrame: GuiObject,
	RobuxFrame: GuiObject,
	EquipFrame: GuiObject,
	EquipLabel: TextLabel,
}

local TrailsController = {}
TrailsController.__index = TrailsController

TrailsController.Config = require(script.Parent.Config)

export type TrailsController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(TrailsController.Config),
		_connections: { RBXScriptConnection },
		_cards: { [string]: Card },
		_owned: { [string]: boolean },
		_equipped: string,
		_requesting: boolean,
	},
	TrailsController
))

function TrailsController.new(): TrailsController
	return setmetatable({
		Root = nil,
		Config = TrailsController.Config,
		_connections = {},
		_cards = {},
		_owned = {},
		_equipped = "",
		_requesting = false,
	}, TrailsController) :: any
end

function TrailsController._render(self: TrailsController): ()
	for id, card in self._cards do
		local owned = self._owned[id] == true
		card.WinsFrame.Visible = not owned and card.SoldForWins
		card.RobuxFrame.Visible = not owned
		card.EquipFrame.Visible = owned
		card.EquipLabel.Text = if self._equipped == id then "Unequip" else "Equip"
	end
end

function TrailsController._absorb(self: TrailsController, data: any): ()
	local trails = data and data.Trails
	if type(trails) ~= "table" then
		return
	end
	self._owned = if type(trails.Owned) == "table" then trails.Owned else {}
	self._equipped = if type(trails.Equipped) == "string" then trails.Equipped else ""
	self:_render()
end

--- One request at a time; the new state arrives through DataUpdated.
function TrailsController._request(self: TrailsController, remote: string, ...: any): ()
	if self._requesting then
		return
	end
	self._requesting = true
	NetworkEvents.InvokeServer(remote, ...)
	self._requesting = false
end

function TrailsController._wire(self: TrailsController, button: GuiButton, onClick: () -> ()): ()
	for _, conn in UXEffects.ButtonFX.attach(button :: any) do
		table.insert(self._connections, conn)
	end
	table.insert(self._connections, button.Activated:Connect(onClick))
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function TrailsController.Init(self: TrailsController, deps: any): ()
	PlayerDataFetcher.OnReady(function(data: any)
		self:_absorb(data)
	end)
	table.insert(
		self._connections,
		deps.EventBus.Data.Updated:Connect(function(data: any)
			self:_absorb(data)
		end)
	)

	SafeUIResolver.WaitForPathAsync(playerGui, { "TrailsUI", "MainFrame" }, function(mainFrame)
		local frame = mainFrame :: Frame
		self.Root = frame
		local gui = frame.Parent :: ScreenGui
		gui.Enabled = true
		gui.DisplayOrder = 1 -- above MainHUD (0); equal orders draw in undefined order
		frame.Visible = false

		WireCloseButton.Wire(
			frame:WaitForChild("TopFrame"):WaitForChild("Close") :: GuiButton,
			self._connections,
			function()
				deps.Navigation.Pop()
			end
		)

		local list = frame:WaitForChild("Container"):WaitForChild("ScrollingFrame")
		local cardToTrail: { [string]: string } = {}
		for id, def in TrailConfig.Trails do
			cardToTrail[def.Card] = id
		end
		-- Cards with no configured trail are hidden.
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") and not cardToTrail[child.Name] then
				child.Visible = false
			end
		end

		for order, id in TrailConfig.Order do
			local def = TrailConfig.Trails[id]
			local cardFrame = list:WaitForChild(def.Card) :: GuiObject
			cardFrame.LayoutOrder = order
			local title = cardFrame:WaitForChild("Title") :: TextLabel
			title.Text = def.DisplayName
			local bonus = cardFrame:WaitForChild("Bonus") :: TextLabel
			bonus.Text = ("x%s Points"):format(tostring(def.XPMultiplier))

			local winsFrame = cardFrame:WaitForChild("Win") :: GuiObject
			local winsButton = winsFrame:WaitForChild("ImageButton") :: GuiButton
			local winsLabel = winsButton:WaitForChild("Price") :: TextLabel
			winsLabel.Text = if def.PriceWins then tostring(def.PriceWins) else ""
			local robuxFrame = cardFrame:WaitForChild("Robux") :: GuiObject
			local robuxButton = robuxFrame:WaitForChild("ImageButton") :: GuiButton
			local robuxLabel = robuxButton:WaitForChild("Price") :: TextLabel
			robuxLabel.Text = if def.PriceRobux
				then BoostConfig.PriceText(def.PriceRobux)
				else "👑 VIP"
			local equipFrame = cardFrame:WaitForChild("Equip/Unequip") :: GuiObject
			local equipButton = equipFrame:WaitForChild("ImageButton") :: GuiButton

			self._cards[id] = {
				SoldForWins = def.PriceWins ~= nil,
				WinsFrame = winsFrame,
				RobuxFrame = robuxFrame,
				EquipFrame = equipFrame,
				EquipLabel = equipButton:WaitForChild("Price") :: TextLabel,
			}

			self:_wire(winsButton, function()
				self:_request("BuyTrail", id, "Wins")
			end)
			self:_wire(robuxButton, function()
				self:_request("BuyTrail", id, "Robux")
			end)
			self:_wire(equipButton, function()
				self:_request("EquipTrail", if self._equipped == id then "" else id)
			end)
		end
		self:_render()
	end)
end

function TrailsController.Activate(self: TrailsController): ()
	self:_render()
end

function TrailsController.Deactivate(_self: TrailsController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function TrailsController.Destroy(self: TrailsController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return TrailsController
