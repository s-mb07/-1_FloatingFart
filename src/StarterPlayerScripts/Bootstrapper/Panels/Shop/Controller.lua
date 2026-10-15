--!strict
--[[
	@module Panels.Shop.Controller
	@description Shop panel over the Studio-authored
	PlayerGui/ShopUI/MainFrame/Container/Container (ScrollingFrame), opened by
	MainHUD/LeftHUD/Shop (the red cart button). See ShopConfig for what each
	item does.

	Every button only asks the server; state comes back through the data
	snapshot (Boosts, StarterPackClaimed, ShopClaimed) and, for gamepasses
	(X2WinsBtn, VipBtn...), the cached ownership attribute. An item that can't be
	bought anymore stays on screen in its claimed state (ClaimedButton: the
	"Claimed" overlay, held pressed, no hover) -- except StarterPackBtn, which
	hides. X2LenghBtn's title and price show the NEXT Length step (x2..x5), same
	as the HUD button; at x5 it is claimed. Boost prices: BoostConfig.Prices.

	Layout fixes applied once in code (the Studio tree is the source of the
	look, these only make it adapt):
	  - on a short screen (phone) MainFrame grows to COMPACT_SIZE
	    (ResponsiveScale.AttachCompactSize); its UIAspectRatioConstraint
	    keeps the proportions;
	  - the list scrolls vertically only (its AutomaticCanvasSize is XY, a
	    sideways drag on a phone used to pan it), with a scrollbar sized
	    for the screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local ClaimedButton = require(Bootstrapper.Libraries.ClaimedButton)
local GamePassConfig = require(ReplicatedStorage.Config.GamePassConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local ResponsiveScale = require(Bootstrapper.Libraries.ResponsiveScale)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local ShopConfig = require(ReplicatedStorage.Config.ShopConfig)
local StarterPackConfig = require(ReplicatedStorage.Config.StarterPackConfig)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

--- MainFrame size on a short (phone) screen; the aspect constraint clamps it.
local COMPACT_SIZE = UDim2.fromScale(0.72, 0.72)

type Item = {
	Button: GuiButton,
	--- Remote + args sent on click.
	Remote: string,
	Args: { any },
	IsInvoke: boolean,
	IsClaimed: () -> boolean,
	--- Claimed = button hidden (Starter Pack) instead of claimed state.
	HideWhenClaimed: boolean,
}

local ShopController = {}
ShopController.__index = ShopController

ShopController.Config = require(script.Parent.Config)

export type ShopController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(ShopController.Config),
		_connections: { RBXScriptConnection },
		_items: { Item },
		_lengthTitle: { TextLabel },
		_lengthPrice: TextLabel?,
		--- X2LenghBtn's prompt args: the NEXT step's pass key.
		_lengthArgs: { any },
		_lengthMultiplier: number,
		_starterClaimed: boolean,
		_shopClaimed: { [string]: boolean },
		_busy: boolean,
	},
	ShopController
))

function ShopController.new(): ShopController
	return setmetatable({
		Root = nil,
		Config = ShopController.Config,
		_connections = {},
		_items = {},
		_lengthTitle = {},
		_lengthPrice = nil,
		_lengthArgs = { "LengthX2" },
		_lengthMultiplier = 1,
		_starterClaimed = false,
		_shopClaimed = {},
		_busy = false,
	}, ShopController) :: any
end

function ShopController._render(self: ShopController): ()
	for _, item in self._items do
		local claimed = item.IsClaimed()
		if item.HideWhenClaimed then
			item.Button.Visible = not claimed
		else
			ClaimedButton.Set(item.Button, claimed)
		end
	end
	local nextStep = math.min(self._lengthMultiplier + 1, BoostConfig.MaxLengthMultiplier)
	self._lengthArgs[1] = "LengthX" .. nextStep
	for _, label in self._lengthTitle do
		label.Text = ("x%d Length"):format(nextStep)
	end
	if self._lengthPrice then
		self._lengthPrice.Text =
			BoostConfig.PriceText(BoostConfig.Prices.LengthMultiplier[nextStep])
	end
end

--- Absorbs a full snapshot or a DataUpdated patch (only the keys present).
function ShopController._absorb(self: ShopController, data: any): ()
	if type(data) ~= "table" then
		return
	end
	if type(data.Boosts) == "table" then
		self._lengthMultiplier = tonumber(data.Boosts.LengthMultiplier) or self._lengthMultiplier
	end
	if data.StarterPackClaimed ~= nil then
		self._starterClaimed = data.StarterPackClaimed == true
	end
	if type(data.ShopClaimed) == "table" then
		self._shopClaimed = data.ShopClaimed
	end
	self:_render()
end

function ShopController._buy(self: ShopController, item: Item): ()
	if self._busy or item.IsClaimed() then
		return
	end
	self._busy = true
	if item.IsInvoke then
		NetworkEvents.InvokeServer(item.Remote, table.unpack(item.Args))
	else
		NetworkEvents.FireServer(item.Remote, table.unpack(item.Args))
	end
	self._busy = false
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function ShopController.Init(self: ShopController, deps: any): ()
	PlayerDataFetcher.OnReady(function(data: any)
		self:_absorb(data)
	end)
	table.insert(
		self._connections,
		deps.EventBus.Data.Updated:Connect(function(data: any)
			self:_absorb(data)
		end)
	)

	SafeUIResolver.WaitForPathAsync(playerGui, { "ShopUI", "MainFrame" }, function(mainFrame)
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

		ResponsiveScale.AttachCompactSize(frame, COMPACT_SIZE)

		local list = frame:WaitForChild("Container"):WaitForChild("Container")
		if list:IsA("ScrollingFrame") then
			list.ScrollingDirection = Enum.ScrollingDirection.Y
			list.ElasticBehavior = Enum.ElasticBehavior.Always
			ResponsiveScale.AttachScrollBar(list)
		end
		local passes = list:WaitForChild("PassesFrame")

		local function add(
			button: GuiButton,
			remote: string,
			args: { any },
			isInvoke: boolean,
			isClaimed: () -> boolean,
			hideWhenClaimed: boolean?
		)
			local price = button:FindFirstChild("Price")
			-- A bare Studio-authored number ("400") gets the Robux glyph.
			if price and price:IsA("TextLabel") and tonumber(price.Text) then
				price.Text = BoostConfig.PriceText(tonumber(price.Text) :: number)
			end
			local item: Item = {
				Button = button,
				Remote = remote,
				Args = args,
				IsInvoke = isInvoke,
				IsClaimed = isClaimed,
				HideWhenClaimed = hideWhenClaimed == true,
			}
			table.insert(self._items, item)
			-- The button stays put on hover: its icon grows (ButtonHoverController)
			for _, conn in UXEffects.ButtonFX.attach(button :: any, { hoverScale = 1 }) do
				table.insert(self._connections, conn)
			end
			table.insert(
				self._connections,
				button.Activated:Connect(function()
					self:_buy(item)
				end)
			)
		end

		local starter = list:WaitForChild("StarterPackBtn") :: GuiButton
		local starterPrice = starter:WaitForChild("Price") :: TextLabel
		starterPrice.Text = tostring(StarterPackConfig.PriceRobux)
		add(starter, "PromptGamePassPurchase", { "StarterPack" }, false, function()
			return self._starterClaimed
		end, true)

		local lengthButton = passes:WaitForChild("X2LenghBtn") :: GuiButton
		local lengthTitle = lengthButton:WaitForChild("Title") :: TextLabel
		self._lengthTitle = { lengthTitle, lengthTitle:WaitForChild("TextStroke") :: TextLabel }
		self._lengthPrice = lengthButton:FindFirstChild("Price") :: TextLabel?
		add(lengthButton, "PromptGamePassPurchase", self._lengthArgs, false, function()
			return self._lengthMultiplier >= BoostConfig.MaxLengthMultiplier
		end)

		local winsButton = passes:WaitForChild("X2WinsBtn") :: GuiButton
		local winsPrice = winsButton:FindFirstChild("Price")
		if winsPrice and winsPrice:IsA("TextLabel") then
			winsPrice.Text = BoostConfig.PriceText(BoostConfig.Prices.X2Wins)
		end
		add(winsButton, "PromptGamePassPurchase", { "X2Wins" }, false, function()
			return GamePassConfig.PlayerHasPass(Players.LocalPlayer, "X2Wins")
		end)

		for itemId, buttonName in ShopConfig.Placeholders do
			local button = (
				passes:FindFirstChild(buttonName) or list:WaitForChild(buttonName)
			) :: GuiButton
			add(button, "ClaimShopItem", { itemId }, true, function()
				return self._shopClaimed[itemId] == true
			end)
		end

		-- Robux items: the key is the button path under the list; owned
		-- passes are claimed from the server-cached ownership attribute.
		for itemKey, sale in ShopConfig.Exclusive do
			local button: Instance = list
			for name in itemKey:gmatch("[^.]+") do
				button = button:WaitForChild(name)
			end
			add(button :: GuiButton, "PromptShopPurchase", { itemKey }, true, function()
				return sale.Kind == "GamePass"
					and GamePassConfig.PlayerHasPass(Players.LocalPlayer, sale.PassKey :: string)
			end)
		end
		table.insert(
			self._connections,
			Players.LocalPlayer.AttributeChanged:Connect(function()
				self:_render()
			end)
		)

		self:_render()
	end)
end

function ShopController.Activate(self: ShopController): ()
	self:_render()
end

function ShopController.Deactivate(_self: ShopController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function ShopController.Destroy(self: ShopController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return ShopController
