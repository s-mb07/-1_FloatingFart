--!strict
--[[
	@module Panels.Rebirth.Controller
	@description Rebirth panel over the Studio-authored PlayerGui/RebirthUI/MainFrame.

	Server-truth: drawn from the `Traversal` data snapshot (Level, Rebirths)
	+ RebirthConfig. With R rebirths taken, the next one is R + 1:
	  - Stats.Before/After.Lengh : "Lengh: xN", x(R) -> x(R + 1)
	  - Stats.Before/After.Level : "Level: N", level rebirth R needed -> level R + 1 needs
	  - ProgessBar               : "Level cur/needed", Progress fill = current level / level R + 1 needs
	  - RebirthBtn               : "Rebirth" when the level is reached, else "No Levels"
	  - SkipRebirthBtn           : developer product "SkipRebirth", until MAX
	After the last rebirth every "after" value and both buttons show "MAX".
	The buttons only ask (NetworkEvents "RequestRebirth" / "PromptProductPurchase");
	the server decides.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

type Widgets = {
	MultiplierBefore: TextLabel,
	MultiplierAfter: TextLabel,
	LevelBefore: TextLabel,
	LevelAfter: TextLabel,
	Bar: GuiObject,
	BarText: TextLabel,
	RebirthText: TextLabel,
	SkipText: TextLabel,
}

local RebirthController = {}
RebirthController.__index = RebirthController

RebirthController.Config = require(script.Parent.Config)

export type RebirthController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(RebirthController.Config),
		_connections: { RBXScriptConnection },
		_widgets: Widgets?,
		_hudNotification: GuiObject?,
		_level: number,
		_rebirths: number,
		_requesting: boolean,
	},
	RebirthController
))

function RebirthController.new(): RebirthController
	return setmetatable({
		Root = nil,
		Config = RebirthController.Config,
		_connections = {},
		_widgets = nil,
		_hudNotification = nil,
		_level = 1,
		_rebirths = 0,
		_requesting = false,
	}, RebirthController) :: any
end

local function formatMultiplier(multiplier: number): string
	return ("Lengh: x%s"):format(tostring(math.round(multiplier * 100) / 100))
end

function RebirthController._render(self: RebirthController): ()
	-- HUD notification: only while the player can actually rebirth.
	if self._hudNotification then
		local nextRebirth = self._rebirths + 1
		self._hudNotification.Visible = nextRebirth <= RebirthConfig.GetMaxRebirths()
			and self._level >= RebirthConfig.GetRequiredLevel(nextRebirth)
	end

	local w = self._widgets
	if not w then
		return
	end
	local rebirths = self._rebirths
	local nextRebirth = rebirths + 1

	w.MultiplierBefore.Text = formatMultiplier(RebirthConfig.GetMultiplier(rebirths))
	w.LevelBefore.Text = ("Level: %d"):format(RebirthConfig.GetRequiredLevel(rebirths))

	local barSize = w.Bar.Size
	if nextRebirth > RebirthConfig.GetMaxRebirths() then
		w.MultiplierAfter.Text = "Lengh: MAX"
		w.LevelAfter.Text = "Level: MAX"
		w.BarText.Text = "MAX"
		w.Bar.Size = UDim2.new(1, 0, barSize.Y.Scale, barSize.Y.Offset)
		w.RebirthText.Text = "MAX"
		w.SkipText.Text = "MAX"
		return
	end

	local required = RebirthConfig.GetRequiredLevel(nextRebirth)
	w.MultiplierAfter.Text = formatMultiplier(RebirthConfig.GetMultiplier(nextRebirth))
	w.LevelAfter.Text = ("Level: %d"):format(required)
	w.BarText.Text = ("Level %d/%d"):format(self._level, required)
	w.Bar.Size =
		UDim2.new(math.clamp(self._level / required, 0, 1), 0, barSize.Y.Scale, barSize.Y.Offset)
	w.RebirthText.Text = if self._level >= required then "Rebirth" else "No Levels"
	w.SkipText.Text = "Skip Rebirth"
end

function RebirthController._absorb(self: RebirthController, data: any): ()
	local traversal = data and data.Traversal
	if type(traversal) ~= "table" then
		return
	end
	self._level = tonumber(traversal.Level) or 1
	self._rebirths = tonumber(traversal.Rebirths) or 0
	self:_render()
end

function RebirthController._request(self: RebirthController): ()
	if self._requesting or self._rebirths >= RebirthConfig.GetMaxRebirths() then
		return
	end
	if self._level < RebirthConfig.GetRequiredLevel(self._rebirths + 1) then
		return
	end
	self._requesting = true
	NetworkEvents.InvokeServer("RequestRebirth")
	self._requesting = false
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

local function wireButton(self: RebirthController, button: GuiButton, onClick: () -> ()): ()
	for _, conn in UXEffects.ButtonFX.attach(button :: any) do
		table.insert(self._connections, conn)
	end
	table.insert(self._connections, button.Activated:Connect(onClick))
end

function RebirthController.Init(self: RebirthController, deps: any): ()
	PlayerDataFetcher.OnReady(function(data: any)
		self:_absorb(data)
	end)
	table.insert(
		self._connections,
		deps.EventBus.Data.Updated:Connect(function(data: any)
			self:_absorb(data)
		end)
	)

	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/LeftHUD/Rebirth/Notification", function(dot)
		self._hudNotification = dot :: GuiObject
		self:_render()
	end)

	SafeUIResolver.WaitForPathAsync(playerGui, { "RebirthUI", "MainFrame" }, function(mainFrame)
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
		local stats = container:WaitForChild("Stats")
		local function stat(side: string, name: string): TextLabel
			return stats:WaitForChild(side):WaitForChild(name):WaitForChild("Text") :: TextLabel
		end
		local progressBar = container:WaitForChild("ProgessBar")
		local rebirthButton = container:WaitForChild("RebirthBtn") :: GuiButton
		local skipButton = container:WaitForChild("SkipRebirthBtn") :: GuiButton
		self._widgets = {
			MultiplierBefore = stat("Before", "Lengh"),
			MultiplierAfter = stat("After", "Lengh"),
			LevelBefore = stat("Before", "Level"),
			LevelAfter = stat("After", "Level"),
			Bar = progressBar:WaitForChild("Progress") :: GuiObject,
			BarText = progressBar:WaitForChild("Level") :: TextLabel,
			RebirthText = rebirthButton:WaitForChild("Price") :: TextLabel,
			SkipText = skipButton:WaitForChild("Price") :: TextLabel,
		}

		wireButton(self, rebirthButton, function()
			self:_request()
		end)
		wireButton(self, skipButton, function()
			if self._rebirths < RebirthConfig.GetMaxRebirths() then
				NetworkEvents.FireServer("PromptProductPurchase", "SkipRebirth")
			end
		end)
		self:_render()
	end)
end

function RebirthController.Activate(self: RebirthController): ()
	self:_render()
end

function RebirthController.Deactivate(_self: RebirthController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function RebirthController.Destroy(self: RebirthController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return RebirthController
