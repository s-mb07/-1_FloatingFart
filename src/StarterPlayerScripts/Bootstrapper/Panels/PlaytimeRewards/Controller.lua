--!strict
--[[
	@module Panels.PlaytimeRewards.Controller
	@description Playtime rewards panel over the Studio-authored
	PlayerGui/PlaytimeRewardsUI/MainFrame (Container/RewardsContainer/Reward1..N in
	PlaytimeRewardConfig.Rewards order, ClaimFrame/ClaimBtn), plus the HUD gift button label
	(MainHUD/LeftHUD/Gift/Title, + its Notification dot while a reward is claimable).

	Server-truth: state comes from the local player's PlaytimeRewardConfig
	attributes (session start + claimed bitmask) and server time. Per card:
	  - claimed           -> ClaimedFrame shown
	  - time reached      -> Timer "Ready" (ClaimBtn = ClaimPlaytimeReward on the first ready one)
	  - otherwise         -> Timer = countdown until it unlocks
	HUD button: never "CLAIM!" -- always the countdown to the next locked
	reward, "READY" if the last one is claimable, "DONE" once all are claimed.

	Prewarmed at boot (Panels/init.lua) so the 1 Hz tick that drives the HUD
	label runs even before the panel is first opened.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local PlaytimeRewardConfig = require(ReplicatedStorage.Config.PlaytimeRewardConfig)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local player = Players.LocalPlayer
local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

type Card = { Timer: TextLabel, ClaimedFrame: GuiObject }

local PlaytimeRewardsController = {}
PlaytimeRewardsController.__index = PlaytimeRewardsController

PlaytimeRewardsController.Config = require(script.Parent.Config)

export type PlaytimeRewardsController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(PlaytimeRewardsController.Config),
		_deps: any,
		_connections: { RBXScriptConnection },
		_cards: { [number]: Card },
		_hudLabels: { TextLabel },
		_hudNotification: GuiObject?,
		_tick: Scheduler.Handle?,
		_claiming: boolean,
	},
	PlaytimeRewardsController
))

function PlaytimeRewardsController.new(): PlaytimeRewardsController
	return setmetatable({
		Root = nil,
		Config = PlaytimeRewardsController.Config,
		_deps = nil,
		_connections = {},
		_cards = {},
		_hudLabels = {},
		_hudNotification = nil,
		_tick = nil,
		_claiming = false,
	}, PlaytimeRewardsController) :: any
end

local function formatCountdown(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

--- (seconds played this session, claimed bitmask); nil until the server set them.
local function session(): (number?, number)
	local start = player:GetAttribute(PlaytimeRewardConfig.StartAttribute)
	local mask = player:GetAttribute(PlaytimeRewardConfig.ClaimedAttribute)
	if type(start) ~= "number" then
		return nil, 0
	end
	return workspace:GetServerTimeNow() - start, if type(mask) == "number" then mask else 0
end

function PlaytimeRewardsController._render(self: PlaytimeRewardsController): ()
	local elapsed, mask = session()
	if not elapsed then
		return
	end

	local anyReady = false
	local nextWait: number? = nil
	for index, reward in PlaytimeRewardConfig.Rewards do
		local claimed = PlaytimeRewardConfig.IsClaimed(mask, index)
		local text = ""
		if not claimed then
			local wait = reward.Minutes * 60 - elapsed
			if wait <= 0 then
				text = "Ready"
				anyReady = true
			else
				text = formatCountdown(wait)
				nextWait = math.min(nextWait or wait, wait)
			end
		end
		local card = self._cards[index]
		if card then
			card.ClaimedFrame.Visible = claimed
			card.Timer.Visible = not claimed
			card.Timer.Text = text
		end
	end

	-- Never "CLAIM!" on the HUD: always the timer of the next locked reward.
	-- Edge case: last reward ready but unclaimed -> nothing to count down.
	local hudText = if nextWait then formatCountdown(nextWait) elseif anyReady then "READY" else "DONE"
	for _, label in self._hudLabels do
		label.Text = hudText
	end
	if self._hudNotification then
		self._hudNotification.Visible = anyReady
	end
end

--- Index of the first reward whose time is reached and that is not claimed yet.
function PlaytimeRewardsController._firstReady(_self: PlaytimeRewardsController): number?
	local elapsed, mask = session()
	if not elapsed then
		return nil
	end
	for index, reward in PlaytimeRewardConfig.Rewards do
		if not PlaytimeRewardConfig.IsClaimed(mask, index) and elapsed >= reward.Minutes * 60 then
			return index
		end
	end
	return nil
end

function PlaytimeRewardsController._tryClaim(self: PlaytimeRewardsController, index: number): ()
	local elapsed, mask = session()
	local reward = PlaytimeRewardConfig.Rewards[index]
	if self._claiming or not elapsed or PlaytimeRewardConfig.IsClaimed(mask, index) then
		return
	end
	if elapsed < reward.Minutes * 60 then
		return
	end
	self._claiming = true
	NetworkEvents.InvokeServer("ClaimPlaytimeReward", index)
	self._claiming = false
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function PlaytimeRewardsController.Init(self: PlaytimeRewardsController, deps: any): ()
	self._deps = deps

	table.insert(
		self._connections,
		player:GetAttributeChangedSignal(PlaytimeRewardConfig.ClaimedAttribute):Connect(function()
			self:_render()
		end)
	)
	self._tick = Scheduler.Every("PlaytimeRewards", 1, function()
		self:_render()
	end)

	SafeUIResolver.WaitForPathStringAsync(
		playerGui,
		"MainHUD/LeftHUD/Gift/Title",
		function(title)
			self._hudLabels = { title :: TextLabel, title:WaitForChild("TextStroke") :: TextLabel }
			self._hudNotification = (title.Parent :: Instance):FindFirstChild("Notification") :: GuiObject?
			self:_render()
		end
	)

	SafeUIResolver.WaitForPathAsync(
		playerGui,
		{ "PlaytimeRewardsUI", "MainFrame" },
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

			-- Cards are Reward1..N in config order (the config's `Card` name is the old UI's).
			local rewards = frame:WaitForChild("Container"):WaitForChild("RewardsContainer")
			for index, reward in PlaytimeRewardConfig.Rewards do
				local card = rewards:WaitForChild("Reward" .. index)
				card.LayoutOrder = index
				local amount = card:WaitForChild("AmountText") :: TextLabel
				amount.Text = "+" .. NumberUtil.FormatCompact(reward.Amount)
				self._cards[index] = {
					Timer = card:WaitForChild("Timer") :: TextLabel,
					ClaimedFrame = card:WaitForChild("ClaimedFrame") :: GuiObject,
				}
			end

			local claimButton = frame:WaitForChild("ClaimFrame"):WaitForChild("ClaimBtn") :: GuiButton
			for _, conn in UXEffects.ButtonFX.attach(claimButton :: any) do
				table.insert(self._connections, conn)
			end
			table.insert(
				self._connections,
				claimButton.Activated:Connect(function()
					local index = self:_firstReady()
					if index then
						self:_tryClaim(index)
					end
				end)
			)
			self:_render()
		end
	)
end

function PlaytimeRewardsController.Activate(self: PlaytimeRewardsController): ()
	self:_render()
end

--- KeepAlive: the 1 Hz tick keeps running to drive the HUD label.
function PlaytimeRewardsController.Deactivate(_self: PlaytimeRewardsController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function PlaytimeRewardsController.Destroy(self: PlaytimeRewardsController): ()
	if self._tick then
		self._tick:Disconnect()
		self._tick = nil
	end
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return PlaytimeRewardsController
