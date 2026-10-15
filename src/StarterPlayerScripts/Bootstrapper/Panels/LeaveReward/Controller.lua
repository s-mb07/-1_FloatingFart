--!strict
--[[
	@module Panels.LeaveReward.Controller
	@description "Don't leave!" pop-up over the Studio-authored
	PlayerGui/LeaveRewardUI/MainFrame, while today's reward is unclaimed:

	  1. The player opens the Roblox menu (GuiService.MenuOpened -- Esc or the
	     Roblox icon, the way out of the game): the Studio-authored red light
	     (PlayerGui/BackgroundEffet/ImageEffet with its RedGradient) pulses
	     behind the menu like an alarm, the "LeaveWarning" Effects recipe
	     plays once, and this pop-up opens with the gift (drawn above the
	     red light, both visible behind the menu).
	  2. The player stays (Resume / Esc again, GuiService.MenuClosed): the
	     flashing stops, the pop-up stays open so the gift can be claimed.
	  3. Claim asks LeaveRewardService ("ClaimLeaveReward"), which decides and
	     grants (once per UTC day). On success: confetti cannons, the
	     "LeaveRewardClaimed" recipe, and a PurchaseRevealController reveal
	     ("THANK YOU FOR STAYING!", PurchaseRevealConfig.Items.LeaveReward),
	     which plays the gamepass fanfare: the same celebration as a purchase.

	Server-truth: once `LeaveRewardLastClaimDay` is today (UTC,
	DailyRewardConfig.GetDay on server time) neither the alarm nor the pop-up
	shows until the next day. Until the data has loaded it is treated as
	claimed, so nothing shows before the server knows.

	Studio names it looks for (anywhere under MainFrame, so the layout is
	free): `ClaimBtn` (GuiButton), `Close` (GuiButton), `Amount` (TextLabel,
	optional: gets "+100 Length" from LeaveRewardConfig).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bootstrapper = script.Parent.Parent.Parent

local DailyRewardConfig = require(ReplicatedStorage.Config.DailyRewardConfig)
local Effects = require(Bootstrapper.Effects)
local LeaveRewardConfig = require(ReplicatedStorage.Config.LeaveRewardConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

--- Red light pulse: ImageEffet's ImageTransparency swings between its
--- Studio value (brightest) and this one (dimmest).
local ALARM_DIM_TRANSPARENCY = 0.85
local ALARM_PULSES_PER_SECOND = 1.6
--- Assets/sfx Sound looped while the red light pulses.
local WARNING_SOUND = "LeaveWarning"
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 215, 70),
	Color3.fromRGB(110, 240, 120),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 130, 220),
}

local LeaveRewardController = {}
LeaveRewardController.__index = LeaveRewardController

LeaveRewardController.Config = require(script.Parent.Config)

export type LeaveRewardController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(LeaveRewardController.Config),
		_connections: { RBXScriptConnection },
		_lastClaimDay: number,
		_busy: boolean,
		_alarm: ImageLabel?,
		_alarmBrightest: number,
		_alarmLoop: RBXScriptConnection?,
	},
	LeaveRewardController
))

function LeaveRewardController.new(): LeaveRewardController
	return setmetatable({
		Root = nil,
		Config = LeaveRewardController.Config,
		_connections = {},
		_lastClaimDay = math.huge, -- claimed until the data says otherwise
		_busy = false,
		_alarm = nil,
		_alarmBrightest = 0,
		_alarmLoop = nil,
	}, LeaveRewardController) :: any
end

--============================================================================--
-- ALARM (red light pulsing behind the Roblox menu)
--============================================================================--

function LeaveRewardController._startAlarm(self: LeaveRewardController): ()
	local light = self._alarm
	if not light or self._alarmLoop then
		return
	end
	local gui = light.Parent :: ScreenGui
	local brightest = self._alarmBrightest
	gui.Enabled = true
	-- The warning sound loops for as long as the red light pulses.
	local warning = Effects.GetSound(WARNING_SOUND)
	if warning and Effects.IsSoundEnabled() then
		warning.Looped = true
		warning:Play()
	end
	local started = os.clock()
	self._alarmLoop = RunService.RenderStepped:Connect(function()
		-- 1 = brightest, 0 = dimmest; starts bright
		local k = (math.cos((os.clock() - started) * ALARM_PULSES_PER_SECOND * 2 * math.pi) + 1) / 2
		light.ImageTransparency = ALARM_DIM_TRANSPARENCY + (brightest - ALARM_DIM_TRANSPARENCY) * k
	end)
end

function LeaveRewardController._stopAlarm(self: LeaveRewardController): ()
	if self._alarmLoop then
		self._alarmLoop:Disconnect()
		self._alarmLoop = nil
		local warning = Effects.GetSound(WARNING_SOUND)
		if warning then
			warning:Stop()
			warning.Looped = false
		end
	end
	local light = self._alarm
	if light then
		(light.Parent :: ScreenGui).Enabled = false
		light.ImageTransparency = self._alarmBrightest
	end
end

--============================================================================--
-- CLAIM
--============================================================================--

--- True while today's reward (UTC, server clock) is still unclaimed.
function LeaveRewardController._canClaim(self: LeaveRewardController): boolean
	return DailyRewardConfig.GetDay(workspace:GetServerTimeNow()) > self._lastClaimDay
end

function LeaveRewardController._absorb(self: LeaveRewardController, data: any): ()
	if type(data) == "table" and type(data.LeaveRewardLastClaimDay) == "number" then
		self._lastClaimDay = data.LeaveRewardLastClaimDay
		if not self:_canClaim() then
			self:_stopAlarm()
		end
	end
end

function LeaveRewardController._claim(self: LeaveRewardController, deps: any): ()
	if self._busy or not self:_canClaim() then
		return
	end
	self._busy = true
	local result = NetworkEvents.InvokeServer("ClaimLeaveReward")
	self._busy = false
	if type(result) ~= "table" then
		return
	end
	-- Claimed now or already earlier today: either way, done until tomorrow
	-- (DataUpdated brings the real day too; this just closes without waiting)
	if result.Success or result.Error == "AlreadyClaimed" then
		self._lastClaimDay = DailyRewardConfig.GetDay(workspace:GetServerTimeNow())
		if deps.Navigation.GetActivePanelId() == "LeaveReward" then
			deps.Navigation.Pop()
		end
	end
	if result.Success then
		UXEffects.Confetti.cannons(CONFETTI_COLORS)
		Effects.Play("LeaveRewardClaimed")
		deps.EventBus.Purchase.Granted:Fire("LeaveReward")
	end
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function LeaveRewardController.Init(self: LeaveRewardController, deps: any): ()
	-- The red light: Studio-authored, off until the menu opens. Only the
	-- RedGradient tints it (the RainbowGradient belongs to another look).
	SafeUIResolver.WaitForPathAsync(playerGui, { "BackgroundEffet", "ImageEffet" }, function(image)
		local light = image :: ImageLabel
		local gui = light.Parent :: ScreenGui
		gui.Enabled = false
		self._alarmBrightest = light.ImageTransparency
		for _, child in light:GetChildren() do
			if child:IsA("UIGradient") then
				child.Enabled = child.Name == "RedGradient"
			end
		end
		self._alarm = light
	end)

	PlayerDataFetcher.OnReady(function(data: any)
		self:_absorb(data)
	end)
	table.insert(
		self._connections,
		deps.EventBus.Data.Updated:Connect(function(data: any)
			self:_absorb(data)
		end)
	)

	-- The way out: the Roblox menu. Alarm + gift as soon as it opens; the
	-- alarm stops when the player closes it and stays, the gift stays up to
	-- be claimed. Every time, until today's reward is claimed.
	table.insert(
		self._connections,
		GuiService.MenuOpened:Connect(function()
			local root = self.Root
			if not root or not self:_canClaim() then
				return
			end
			self:_startAlarm()
			-- Gift above the red light, whatever order Studio gave them
			local light = self._alarm
			if light then
				local gui = root.Parent :: ScreenGui
				gui.DisplayOrder =
					math.max(gui.DisplayOrder, (light.Parent :: ScreenGui).DisplayOrder + 1)
			end
			deps.Navigation.Push("LeaveReward") -- no-op if already open
		end)
	)
	table.insert(
		self._connections,
		GuiService.MenuClosed:Connect(function()
			self:_stopAlarm()
		end)
	)

	SafeUIResolver.WaitForPathAsync(playerGui, { "LeaveRewardUI", "MainFrame" }, function(mainFrame)
		local frame = mainFrame :: Frame
		local gui = frame.Parent :: ScreenGui
		gui.Enabled = true
		gui.DisplayOrder = 1 -- above MainHUD (0)
		frame.Visible = false

		local amount = frame:FindFirstChild("Amount", true)
		if amount and amount:IsA("TextLabel") then
			amount.Text = ("+%s Length"):format(
				NumberUtil.FormatShort(LeaveRewardConfig.Reward.Amount)
			)
		end
		local close = frame:FindFirstChild("Close", true)
		if close and close:IsA("GuiButton") then
			WireCloseButton.Wire(close, self._connections, function()
				deps.Navigation.Pop()
			end)
		end
		local claim = frame:FindFirstChild("ClaimBtn", true)
		if claim and claim:IsA("GuiButton") then
			table.insert(
				self._connections,
				claim.Activated:Connect(function()
					self:_claim(deps)
				end)
			)
		end
		self.Root = frame
	end)
end

function LeaveRewardController.Activate(_self: LeaveRewardController): () end

function LeaveRewardController.Deactivate(_self: LeaveRewardController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function LeaveRewardController.Destroy(self: LeaveRewardController): ()
	self:_stopAlarm()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return LeaveRewardController
