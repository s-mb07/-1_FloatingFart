--!strict
--[[
	@module Panels.DailyRewards.Controller
	@description Daily rewards panel over the Studio-authored
	PlayerGui/DailyRewardsUI/MainFrame (Container/SmallGiftsContainer/Day1..Day6
	+ Container/BigGiftContainer/Day7, BottomButtons/ClaimDay + SkipDay).

	Server-truth: every state is derived from the `DailyRewards` data
	snapshot (DataInitialized / DataUpdated) + server time:
	  - card already claimed this cycle -> its ClaimedFrame is shown
	  - ClaimDay, today's reward ready  -> "Claim Day" (click = ClaimDailyReward)
	  - ClaimDay, claimed today         -> countdown to 00:00 UTC
	The claim itself is decided by DailyRewardService; the panel only asks.
	Card AmountText comes from DailyRewardConfig, so it always matches what is granted.
	SkipDay prompts developer product "SkipDailyReward" (next reward now,
	granted server-side on the receipt).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local DailyRewardConfig = require(ReplicatedStorage.Config.DailyRewardConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

type Card = { ClaimedFrame: GuiObject }

local DailyRewardsController = {}
DailyRewardsController.__index = DailyRewardsController

DailyRewardsController.Config = require(script.Parent.Config)

export type DailyRewardsController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(DailyRewardsController.Config),
		_deps: any,
		_connections: { RBXScriptConnection },
		_cards: { Card },
		_claimLabel: TextLabel?,
		_hudNotification: GuiObject?,
		_dataReady: boolean,
		_tick: Scheduler.Handle?,
		_claimed: number,
		_lastClaimDay: number,
		_active: boolean,
		_claiming: boolean,
	},
	DailyRewardsController
))

function DailyRewardsController.new(): DailyRewardsController
	return setmetatable({
		Root = nil,
		Config = DailyRewardsController.Config,
		_deps = nil,
		_connections = {},
		_cards = {},
		_claimLabel = nil,
		_hudNotification = nil,
		_dataReady = false,
		_tick = nil,
		_claimed = 0,
		_lastClaimDay = 0,
		_active = false,
		_claiming = false,
	}, DailyRewardsController) :: any
end

--- (claimed days in the cycle as displayed, is today's reward available)
function DailyRewardsController._progress(self: DailyRewardsController): (number, boolean)
	local available = DailyRewardConfig.GetDay(workspace:GetServerTimeNow()) > self._lastClaimDay
	local claimed = self._claimed
	-- A finished cycle shows as fresh once the next day's reward is available.
	if claimed >= #DailyRewardConfig.Rewards and available then
		claimed = 0
	end
	return claimed, available
end

local function formatCountdown(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d:%02d"):format(seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

function DailyRewardsController._render(self: DailyRewardsController): ()
	local claimed, available = self:_progress()
	local countdown =
		formatCountdown(DailyRewardConfig.SecondsUntilNextDay(workspace:GetServerTimeNow()))
	for day, card in self._cards do
		card.ClaimedFrame.Visible = day <= claimed
	end
	if self._hudNotification then
		self._hudNotification.Visible = self._dataReady and available
	end
	if self._claimLabel then
		self._claimLabel.Text = if available then "Claim Day" else countdown
	end
end

function DailyRewardsController._absorb(self: DailyRewardsController, data: any): ()
	local daily = data and data.DailyRewards
	if type(daily) ~= "table" then
		return
	end
	self._claimed = tonumber(daily.Claimed) or 0
	self._lastClaimDay = tonumber(daily.LastClaimDay) or 0
	self._dataReady = true
	self:_render()
end

function DailyRewardsController._tryClaim(self: DailyRewardsController, day: number): ()
	local claimed, available = self:_progress()
	if self._claiming or not available or day ~= claimed + 1 then
		return
	end
	self._claiming = true
	NetworkEvents.InvokeServer("ClaimDailyReward")
	self._claiming = false
end

--- "Skip Day": prompts the "SkipDailyReward" developer product; the server
--- grants the next reward on the receipt (MonetizationService).
function DailyRewardsController._skip(_self: DailyRewardsController): ()
	NetworkEvents.FireServer("PromptProductPurchase", "SkipDailyReward")
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function DailyRewardsController.Init(self: DailyRewardsController, deps: any): ()
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

	-- HUD notification dot: must stay right even while the panel is closed
	-- (the panel is prewarmed), including when 00:00 UTC unlocks the next reward.
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/LeftHUD/Daily/Notification", function(dot)
		self._hudNotification = dot :: GuiObject
		self:_render()
	end)
	self._tick = Scheduler.Every("DailyRewards", 1, function()
		self:_render()
	end)

	SafeUIResolver.WaitForPathAsync(
		playerGui,
		{ "DailyRewardsUI", "MainFrame" },
		function(mainFrame)
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
					self._deps.Navigation.Pop()
				end
			)

			local container = frame:WaitForChild("Container")
			local small = container:WaitForChild("SmallGiftsContainer")
			local big = container:WaitForChild("BigGiftContainer")
			for day, reward in DailyRewardConfig.Rewards do
				local cardFrame = if day < #DailyRewardConfig.Rewards
					then small:WaitForChild("Day" .. day)
					else big:WaitForChild("Day" .. day)
				local amountText = cardFrame:WaitForChild("AmountText") :: TextLabel
				amountText.Text = if reward.Kind == "Skin"
					then "???"
					else "+" .. NumberUtil.FormatCompact(reward.Amount or 0)
				local dayText = cardFrame:WaitForChild("DayText") :: TextLabel
				dayText.Text = "Day " .. day
				self._cards[day] = { ClaimedFrame = cardFrame:WaitForChild("ClaimedFrame") :: GuiObject }
			end

			local bottom = frame:WaitForChild("BottomButtons")
			local skipButton = bottom:WaitForChild("SkipDay") :: GuiButton
			for _, conn in UXEffects.ButtonFX.attach(skipButton :: any) do
				table.insert(self._connections, conn)
			end
			table.insert(
				self._connections,
				skipButton.Activated:Connect(function()
					self:_skip()
				end)
			)

			local claimButton = bottom:WaitForChild("ClaimDay") :: GuiButton
			self._claimLabel = claimButton:WaitForChild("Text") :: TextLabel
			for _, conn in UXEffects.ButtonFX.attach(claimButton :: any) do
				table.insert(self._connections, conn)
			end
			table.insert(
				self._connections,
				claimButton.Activated:Connect(function()
					self:_tryClaim(self:_progress() + 1)
				end)
			)
			self:_render()
		end
	)
end

--- Redraws, then ticks the countdown once a second while the panel is open.
function DailyRewardsController.Activate(self: DailyRewardsController): ()
	self._active = true
	self:_render()
	task.spawn(function()
		while self._active do
			task.wait(1)
			self:_render()
		end
	end)
end

function DailyRewardsController.Deactivate(self: DailyRewardsController): ()
	self._active = false
end

--- Never called as long as Config.Navigation.KeepAlive = true.
function DailyRewardsController.Destroy(self: DailyRewardsController): ()
	self._active = false
	if self._tick then
		self._tick:Disconnect()
		self._tick = nil
	end
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return DailyRewardsController
