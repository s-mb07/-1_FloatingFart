--!strict
--[[
	@module Panels.StarterPack.Controller
	@description Starter Pack panel over the Studio-authored
	PlayerGui/StarterPackUI/MainFrame, opened by MainHUD/StarterPack.

	Texts come from StarterPackConfig (Offer1 "+Length" with the plane icon, Offer2 "+Wins",
	Container/Price and the HUD button's Price). Container/ClaimBtn only
	asks for the gamepass prompt (NetworkEvents "PromptGamePassPurchase", "StarterPack"); owning it grants it.

	Server-truth: once the `StarterPackClaimed` data flag is true the HUD
	button hides and the panel closes. Prewarmed at boot (Panels/init.lua)
	so a player who already claimed never sees the HUD button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local StarterPackConfig = require(ReplicatedStorage.Config.StarterPackConfig)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local PRICE_TEXT = BoostConfig.PriceText(StarterPackConfig.PriceRobux)
-- Offer1 (+Length) icon: the paper plane, same art as the Length boosts.
local PLANE_ICON = "rbxassetid://82109037700647"

local StarterPackController = {}
StarterPackController.__index = StarterPackController

StarterPackController.Config = require(script.Parent.Config)

export type StarterPackController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(StarterPackController.Config),
		_deps: any,
		_connections: { RBXScriptConnection },
		_hudButton: GuiObject?,
		_claimed: boolean,
	},
	StarterPackController
))

function StarterPackController.new(): StarterPackController
	return setmetatable({
		Root = nil,
		Config = StarterPackController.Config,
		_deps = nil,
		_connections = {},
		_hudButton = nil,
		_claimed = false,
	}, StarterPackController) :: any
end

local function setWithStroke(instance: Instance, text: string): ()
	local label = instance :: TextLabel
	label.Text = text
	local stroke = label:FindFirstChild("TextStroke")
	if stroke and stroke:IsA("TextLabel") then
		stroke.Text = text
	end
end

function StarterPackController._render(self: StarterPackController): ()
	if self._hudButton then
		self._hudButton.Visible = not self._claimed
	end
	if
		self._claimed
		and self._deps
		and self._deps.Navigation.GetActivePanelId() == "StarterPack"
	then
		self._deps.Navigation.Pop()
	end
end

function StarterPackController._absorb(self: StarterPackController, data: any): ()
	if type(data) == "table" and data.StarterPackClaimed ~= nil then
		self._claimed = data.StarterPackClaimed == true
		self:_render()
	end
end

function StarterPackController._claim(self: StarterPackController): ()
	if self._claimed then
		return
	end
	NetworkEvents.FireServer("PromptGamePassPurchase", "StarterPack")
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function StarterPackController.Init(self: StarterPackController, deps: any): ()
	self._deps = deps

	PlayerDataFetcher.OnReady(function(data: any)
		self:_absorb(data)
	end)
	table.insert(
		self._connections,
		deps.EventBus.Data.Updated:Connect(function(data: any)
			self:_absorb(data)
		end)
	)

	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/StarterPack", function(button)
		self._hudButton = button :: GuiObject
		setWithStroke(button:WaitForChild("Price"), PRICE_TEXT)
		self:_render()
	end)

	SafeUIResolver.WaitForPathAsync(playerGui, { "StarterPackUI", "MainFrame" }, function(mainFrame)
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

		local container = frame:WaitForChild("Container")
		local lengthIcon = container:WaitForChild("Offer1"):WaitForChild("Image") :: ImageLabel
		lengthIcon.Image = PLANE_ICON
		-- Offer1 holds two labels named "Text" ("+25,000" and the "OP!" badge):
		-- only the amount one (starting with "+") is rewritten.
		for _, child in container:WaitForChild("Offer1"):GetChildren() do
			if child:IsA("TextLabel") and child.Name == "Text" and child.Text:sub(1, 1) == "+" then
				child.Text = "+" .. NumberUtil.Format(StarterPackConfig.Length)
			end
		end
		local winsLabel = container:WaitForChild("Offer2"):WaitForChild("Text") :: TextLabel
		winsLabel.Text = "+" .. NumberUtil.Format(StarterPackConfig.Wins)
		setWithStroke(container:WaitForChild("Price"), PRICE_TEXT)

		local claim = container:WaitForChild("ClaimBtn") :: GuiButton
		for _, conn in UXEffects.ButtonFX.attach(claim :: any) do
			table.insert(self._connections, conn)
		end
		table.insert(
			self._connections,
			claim.Activated:Connect(function()
				self:_claim()
			end)
		)
	end)
end

function StarterPackController.Activate(_self: StarterPackController): () end

function StarterPackController.Deactivate(_self: StarterPackController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function StarterPackController.Destroy(self: StarterPackController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return StarterPackController
