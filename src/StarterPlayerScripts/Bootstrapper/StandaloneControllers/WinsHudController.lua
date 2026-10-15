--!strict
--[[
	@module WinsHudController
	@description Drives the trophy counter in MainHUD/LeftHUD/Wins: `Amount`
	(+ its `TextStroke` overlay) mirrors `Currencies.Trophies` from the server
	data snapshot (DataInitialized, then every DataUpdated). The "+" button
	next to it is wired by BoostController (X2Wins pass).

	MainHUD has ResetOnSpawn = false, so the UI is resolved once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)

local WinsHudController = {}

local trophies: number? = nil
local amountLabels: { TextLabel } = {}

local function render(): ()
	if trophies == nil then
		return
	end
	local text = NumberUtil.FormatCompact(trophies)
	for _, label in amountLabels do
		label.Text = text
	end
end

local function absorb(data: any): ()
	local value = data and data.Currencies and data.Currencies.Trophies
	if type(value) == "number" then
		trophies = value
		render()
	end
end

function WinsHudController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
end

function WinsHudController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	SafeUIResolver.WaitForPathStringAsync(
		playerGui,
		"MainHUD/LeftHUD/Wins/Amount",
		function(amount: Instance)
			amountLabels = { amount :: TextLabel, amount:WaitForChild("TextStroke") :: TextLabel }
			render()
		end
	)
end

return WinsHudController
