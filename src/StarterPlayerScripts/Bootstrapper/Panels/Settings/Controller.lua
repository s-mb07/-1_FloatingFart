--!strict
--[[
	@module Panels.Settings.Controller
	@description Settings panel -- a list of toggles (Switch on/off) generated
	from a generic template ("Setting_Template"), regenerated on every
	Data.Initialized/Updated received from the server (server-truth).

	KeepAlive (cf. Config.lua): Init() only runs once per session -- the
	"SettingsUI" ScreenGui must have ResetOnSpawn = false (set in Studio), so
	no defensive re-cache is needed on CharacterAdded.

	State.lua (cf. Panels/Settings/State.lua): the knownSettings +
	hasReceivedInitialData cache lives in a separate State rather than
	directly on self (cf. PanelDefinition's CaptureState/RestoreState contract).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Bootstrapper = script.Parent.Parent.Parent

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local PanelTags = require(Bootstrapper.Config.PanelTagsConfig).Tags
local PanelUI = require(Bootstrapper.Libraries.SafeUIResolver.UITag.PanelUI)
local ResponsiveScale = require(Bootstrapper.Libraries.ResponsiveScale)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local State = require(script.Parent.State)
local GraphicsQualityConfig = require(Bootstrapper.Config.GraphicsQualityConfig)
local QualityController = require(Bootstrapper.StandaloneControllers.QualityController)

local SCROLLBAR_REF_RESOLUTION = Vector2.new(1920, 1080)

local ON_COLOR = Color3.fromRGB(90, 200, 110)
local OFF_COLOR = Color3.fromRGB(255, 255, 255)

local player: Player = Players.LocalPlayer
local playerGui: PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local SettingsController = {}
SettingsController.__index = SettingsController

SettingsController.Config = require(script.Parent.Config)

export type SettingsController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(SettingsController.Config),
		_deps: any,
		_connections: { RBXScriptConnection },
		_content: ScrollingFrame?,
		_settingTemplate: Frame?,
		_activeSettingFrames: { Instance },
		_state: State.SettingsState,
	},
	SettingsController
))

function SettingsController.new(): SettingsController
	return setmetatable({
		Root = nil,
		Config = SettingsController.Config,
		_deps = nil,
		_connections = {},
		_content = nil,
		_settingTemplate = nil,
		_activeSettingFrames = {},
		_state = State.new(),
	}, SettingsController) :: any
end

--============================================================================--
-- SETTING GENERATOR (Toggle)
--============================================================================--

function SettingsController._createToggleSetting(
	self: SettingsController,
	displayName: string,
	settingKey: string?,
	defaultValue: boolean,
	layoutOrder: number
): ()
	if not self._settingTemplate or not self._content then return end

	local row = self._settingTemplate:Clone()
	row.Visible = true
	row.LayoutOrder = layoutOrder
	row.Parent = self._content
	table.insert(self._activeSettingFrames, row)

	local nameLabel = row:FindFirstChild("DisplayName") :: TextLabel?
	if nameLabel then
		nameLabel.Text = displayName
	end

	local switch = row:FindFirstChild("Switch") :: ImageButton?
	if not switch then return end

	local isOn = defaultValue
	local stateLabel = switch:FindFirstChild("Label") :: TextLabel?

	local function updateVisual(animate: boolean)
		if stateLabel then
			stateLabel.Text = isOn and "ON" or "OFF"
		end
		local targetColor = isOn and ON_COLOR or OFF_COLOR
		if animate then
			TweenService:Create(switch, TweenInfo.new(0.15), { ImageColor3 = targetColor }):Play()
		else
			switch.ImageColor3 = targetColor
		end
	end

	updateVisual(false)
	UXEffects.ButtonFX.attach(switch :: any)

	switch.Activated:Connect(function()
		isOn = not isOn
		updateVisual(true)

		if settingKey then
			NetworkEvents.FireServer("UpdateSetting", {
				Setting = settingKey,
				Value = isOn,
			})
		end
	end)
end

--============================================================================--
-- SETTING GENERATOR (Cycle)
--============================================================================--

--- N-value setting, on the SAME row template as the toggles: the Switch no
--- longer toggles on/off, it advances through `values` and the current
--- value is displayed next to the label. Avoids having to draw a real
--- selector widget in Studio for a single three-position setting.
function SettingsController._createCycleSetting(
	self: SettingsController,
	displayName: string,
	values: { string },
	currentValue: string,
	layoutOrder: number,
	onChanged: (string) -> ()
): ()
	if not self._settingTemplate or not self._content then return end
	if #values == 0 then return end

	local row = self._settingTemplate:Clone()
	row.Visible = true
	row.LayoutOrder = layoutOrder
	row.Parent = self._content
	table.insert(self._activeSettingFrames, row)

	local index = table.find(values, currentValue) or 1

	local nameLabel = row:FindFirstChild("DisplayName") :: TextLabel?
	local function updateLabel()
		if nameLabel then
			nameLabel.Text = string.format("%s: %s", displayName, values[index])
		end
	end
	updateLabel()

	local switch = row:FindFirstChild("Switch") :: ImageButton?
	if not switch then return end
	local switchLabel = switch:FindFirstChild("Label") :: TextLabel?
	if switchLabel then
		switchLabel.Text = "CHANGE"
	end

	local function updateVisual(animate: boolean)
		-- The first value is the "default" mode (e.g. Auto): neutral color.
		-- Any explicitly chosen value shows as active.
		local targetColor = index > 1 and ON_COLOR or OFF_COLOR
		if animate then
			TweenService:Create(switch, TweenInfo.new(0.15), { ImageColor3 = targetColor }):Play()
		else
			switch.ImageColor3 = targetColor
		end
	end

	updateVisual(false)
	UXEffects.ButtonFX.attach(switch :: any)

	switch.Activated:Connect(function()
		index = (index % #values) + 1
		updateLabel()
		updateVisual(true)
		onChanged(values[index])
	end)
end

--- (Re)generates the settings list from the latest known values.
function SettingsController._populateAllSettings(self: SettingsController): ()
	if not self._settingTemplate then return end

	debug.profilebegin("SETTINGS_Populate")

	for _, frame in self._activeSettingFrames do
		frame:Destroy()
	end
	table.clear(self._activeSettingFrames)

	local known = self._state.knownSettings
	local musicEnabled = known.MusicEnabled
	if musicEnabled == nil then
		musicEnabled = true
	end
	local sfxEnabled = known.SfxEnabled
	if sfxEnabled == nil then
		sfxEnabled = true
	end
	local screenShakeEnabled = known.ScreenShakeEnabled
	if screenShakeEnabled == nil then
		screenShakeEnabled = true
	end

	-- AUDIO
	self:_createToggleSetting("Music", "MusicEnabled", musicEnabled, 51)
	self:_createToggleSetting("SFX", "SfxEnabled", sfxEnabled, 52)

	-- GAMEPLAY
	self:_createToggleSetting("Screen Shake", "ScreenShakeEnabled", screenShakeEnabled, 101)

	-- GRAPHICS -- persistence goes through QualityController (which also
	-- applies the preset locally right away), not through the generic
	-- FireServer used by the toggles.
	self:_createCycleSetting(
		"Graphics",
		GraphicsQualityConfig.SETTING_VALUES :: { string },
		QualityController.GetSetting(),
		151,
		function(value: string)
			QualityController.SetSetting(value :: any)
		end
	)

	debug.profileend()
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

--- Resolves all STATIC content once (cf. Config.lua, KeepAlive) and
--- subscribes to EventBus.Data to (re)generate the server-truth toggles.
function SettingsController.Init(self: SettingsController, deps: any): ()
	self._deps = deps

	-- OnReady covers both the normal server push AND the async fallback
	-- pull if Init() runs before the push has arrived (cf. PlayerDataFetcher).
	PlayerDataFetcher.OnReady(function(data: any)
		if data and data.Settings then
			for key, value in data.Settings do
				self._state.knownSettings[key] = value
			end
		end
		self._state.hasReceivedInitialData = true
		if self._settingTemplate then
			self:_populateAllSettings()
		end
	end)

	table.insert(self._connections, deps.EventBus.Data.Updated:Connect(function(data: any)
		if not (data and data.Settings) then return end
		local changed = false
		for _, key in { "MusicEnabled", "SfxEnabled", "ScreenShakeEnabled", GraphicsQualityConfig.SETTING_KEY } do
			if data.Settings[key] ~= nil and data.Settings[key] ~= self._state.knownSettings[key] then
				self._state.knownSettings[key] = data.Settings[key]
				changed = true
			end
		end
		if changed and self._settingTemplate then
			self:_populateAllSettings()
		end
	end))

	SafeUIResolver.WaitForPathAsync(playerGui, { "SettingsUI", "MainFrame" }, function(containerFrame)
		if not containerFrame:IsA("Frame") then return end
		local frame = containerFrame :: Frame
		self.Root = frame

		local gui = frame.Parent :: ScreenGui
		gui.Enabled = true
		frame.Visible = false
		PanelUI.RegisterPanel(frame, PanelTags.SETTINGS)

		SafeUIResolver.WaitForPathAsync(frame, { "TopFrame", "Close" }, function(btn)
			if not btn:IsA("ImageButton") then return end
			WireCloseButton.Wire(btn, self._connections, function()
				(self._deps.Navigation :: any).Pop()
			end)
		end)

		SafeUIResolver.WaitForPathAsync(frame, { "Container", "List" }, function(contentFrame)
			local scrolling = contentFrame :: ScrollingFrame
			self._content = scrolling
			ResponsiveScale.AttachScrollBar(scrolling, SCROLLBAR_REF_RESOLUTION)

			SafeUIResolver.WaitForPathAsync(scrolling, { "Setting_Template" }, function(tpl)
				if not tpl:IsA("Frame") then return end
				local tplFrame = tpl:Clone()
				tplFrame.Visible = true
				self._settingTemplate = tplFrame

				for _, child in scrolling:GetChildren() do
					if child:IsA("Frame") and child.Name == "Setting_Template" then
						child:Destroy()
					end
				end

				if self._state.hasReceivedInitialData then
					self:_populateAllSettings()
				end
			end)
		end)
	end)
end

--- Nothing to reconnect (KeepAlive) -- re-populates in case settings
--- changed while the panel was hidden (Updated is already listened to
--- continuously, but an Activate() costs nothing extra as a safety net).
function SettingsController.Activate(self: SettingsController): ()
	if self._state.hasReceivedInitialData and self._settingTemplate then
		self:_populateAllSettings()
	end
end

--- KeepAlive: nothing to suspend, Data.Initialized/Updated must keep
--- running while the panel is hidden (behavior already in place before the
--- migration).
function SettingsController.Deactivate(_self: SettingsController): () end

--- No CaptureState/RestoreState here: self._state.knownSettings is a
--- server-truth cache, not a local preference -- Activate() already
--- re-populates it from the last known value, capturing/restoring a
--- snapshot would just be reapplying exactly the same thing (cf.
--- PanelDefinition.lua doc: "a server-truth panel... a re-fetch on
--- Activate() is enough and avoids any risk of staleness").

--- Never called as long as Config.Navigation.KeepAlive = true.
function SettingsController.Destroy(self: SettingsController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._connections = {}

	for _, frame in self._activeSettingFrames do
		frame:Destroy()
	end
	table.clear(self._activeSettingFrames)
end

return SettingsController
