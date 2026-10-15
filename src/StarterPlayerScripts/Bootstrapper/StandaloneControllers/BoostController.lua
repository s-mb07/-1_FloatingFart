--!strict
--[[
	@module BoostController
	@description Wires the HUD boost buttons to their Robux prompts (the
	server grants on purchase, see BoostService):
	- MainHUD/BottomHUD/BottomButtons/Boost1..4 -> product Length25K..Length1M
	- MainHUD/RightHUD/2XLengh                 -> pass "LengthX<next step>" (LengthX2..LengthX5)
	- MainHUD/RightHUD/2XWins (+ MainHUD/LeftHUD/Wins/More if the HUD has one) -> pass "X2Wins"
	  (unlocks the blue x2 win pads, nothing else)
	- MainHUD/FastTrain ("OP! Fast Train")     -> pass "FastTrain"; only visible
	  while on a treadmill (EventBus.Traversal.TreadmillActive) and not yet bought.

	Server-truth display from the `Boosts` data snapshot (BoostConfig rules):
	- 2XLengh's Title shows the NEXT step ("x2 Lengh", then "x3 Lengh"...)
	  and its Price that step's price; once the max (x5) is active it shows x5, claimed.
	- Price labels (Boost1..4, 2XLengh, FastTrain) come from BoostConfig.Prices.
	- 2XWins / maxed 2XLengh stay on screen in their claimed state
	  (ClaimedButton: "Claimed" overlay, held pressed, no hover) and stop
	  prompting. 2XWins reads the cached X2Wins ownership attribute.
	  Wins/More (the trophy icon) stays but loses its "+" badge and click.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostConfig = require(ReplicatedStorage.Config.BoostConfig)
local GamePassConfig = require(ReplicatedStorage.Config.GamePassConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local Bootstrapper = script.Parent.Parent
local ClaimedButton = require(Bootstrapper.Libraries.ClaimedButton)
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)

--- Index = BoostN button.
local BOOST_PRODUCTS = { "Length25K", "Length100K", "Length500K", "Length1M" }

local BoostController = {}

local X2_WINS_PASS = "X2Wins"

local lengthMultiplier = 1
local lengthFrame: GuiButton? = nil
local lengthLabels: { TextLabel } = {}
local lengthPriceLabels: { TextLabel } = {}
local trophyButtons: { GuiButton } = {}
local trophyIcon: GuiButton? = nil
local treadmillSpeed = 1
local onTreadmill = false
local fastTrainButton: GuiButton? = nil

local function lengthMaxed(): boolean
	return lengthMultiplier >= BoostConfig.MaxLengthMultiplier
end

local function fastTrainOwned(): boolean
	return treadmillSpeed >= BoostConfig.TreadmillSpeed
end

local function render(): ()
	if fastTrainButton then
		fastTrainButton.Visible = onTreadmill and not fastTrainOwned()
	end
	if lengthFrame then
		ClaimedButton.Set(lengthFrame, lengthMaxed())
	end
	local text = ("x%d Lengh"):format(
		math.min(lengthMultiplier + 1, BoostConfig.MaxLengthMultiplier)
	)
	for _, label in lengthLabels do
		label.Text = text
	end
	local price = BoostConfig.Prices.LengthMultiplier[math.min(
		lengthMultiplier + 1,
		BoostConfig.MaxLengthMultiplier
	)]
	for _, label in lengthPriceLabels do
		label.Text = "ONLY " .. BoostConfig.PriceText(price)
	end
	local trophyAvailable = not GamePassConfig.PlayerHasPass(Players.LocalPlayer, X2_WINS_PASS)
	for _, button in trophyButtons do
		ClaimedButton.Set(button, not trophyAvailable)
	end
	-- Wins/More is the trophy icon itself: it stays, only its "+" badge goes and the click stops.
	if trophyIcon then
		trophyIcon.Interactable = trophyAvailable
		local badge = trophyIcon:FindFirstChild("ImageLabel") :: GuiObject?
		if badge then
			badge.Visible = trophyAvailable
		end
	end
end

local function absorb(data: any): ()
	local boosts = data and data.Boosts
	if type(boosts) ~= "table" then
		return
	end
	lengthMultiplier = tonumber(boosts.LengthMultiplier) or 1
	treadmillSpeed = tonumber(boosts.TreadmillSpeed) or 1
	render()
end

local function wire(playerGui: Instance, path: string, onClick: () -> ()): ()
	SafeUIResolver.WaitForPathStringAsync(playerGui, path, function(instance)
		local button = instance :: GuiButton
		-- Hover/press FX: ButtonHoverController (icon grows + tilts, button stays)
		button.Activated:Connect(onClick)
	end)
end

function BoostController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
	EventBus.Traversal.TreadmillActive:Connect(function(active: boolean)
		onTreadmill = active
		render()
	end)
	Players.LocalPlayer
		:GetAttributeChangedSignal(GamePassConfig.Attribute(X2_WINS_PASS))
		:Connect(render)
end

function BoostController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for index, productKey in BOOST_PRODUCTS do
		wire(playerGui, ("MainHUD/BottomHUD/BottomButtons/Boost%d"):format(index), function()
			NetworkEvents.FireServer("PromptProductPurchase", productKey)
		end)
		SafeUIResolver.WaitForPathStringAsync(
			playerGui,
			("MainHUD/BottomHUD/BottomButtons/Boost%d/Price"):format(index),
			function(label)
				(label :: TextLabel).Text =
					BoostConfig.PriceText(BoostConfig.Prices.LengthBoosts[index])
			end
		)
	end

	wire(playerGui, "MainHUD/RightHUD/2XLengh", function()
		if not lengthMaxed() then
			NetworkEvents.FireServer("PromptGamePassPurchase", "LengthX" .. (lengthMultiplier + 1))
		end
	end)
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/RightHUD/2XLengh", function(frame)
		lengthFrame = frame :: GuiButton
		local label = frame:WaitForChild("Title") :: TextLabel
		lengthLabels = { label, label:WaitForChild("TextStroke") :: TextLabel }
		local price = frame:WaitForChild("Price") :: TextLabel
		lengthPriceLabels = { price, price:WaitForChild("TextStroke") :: TextLabel }
		render()
	end)

	-- Same X2Wins pass: the right-hand "2XWins", and the "+" on the Wins
	-- counter when the HUD has one (the reworked HUD dropped it: optional).
	wire(playerGui, "MainHUD/RightHUD/2XWins", function()
		if not GamePassConfig.PlayerHasPass(Players.LocalPlayer, X2_WINS_PASS) then
			NetworkEvents.FireServer("PromptGamePassPurchase", X2_WINS_PASS)
		end
	end)
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/RightHUD/2XWins", function(button)
		table.insert(trophyButtons, button :: GuiButton)
		render()
	end)
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/LeftHUD/Wins", function(wins)
		local more = wins:FindFirstChild("More")
		if more and more:IsA("GuiButton") then
			trophyIcon = more
			more.Activated:Connect(function()
				NetworkEvents.FireServer("PromptGamePassPurchase", X2_WINS_PASS)
			end)
			render()
		end
	end)

	wire(playerGui, "MainHUD/FastTrain", function()
		if not fastTrainOwned() then
			NetworkEvents.FireServer("PromptGamePassPurchase", "FastTrain")
		end
	end)
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/FastTrain", function(button)
		fastTrainButton = button :: GuiButton
		-- No dedicated Price label on this button: the price goes on its title.
		local title = button:FindFirstChild("Text")
		if title and title:IsA("TextLabel") then
			title.Text = "Fast Train " .. BoostConfig.PriceText(BoostConfig.Prices.FastTrain)
		end
		render()
	end)
end

return BoostController
