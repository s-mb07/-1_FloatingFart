--!strict
--[[
	@module Panels.Codes.Controller
	@description Codes panel over the Studio-authored PlayerGui/CodesUI/MainFrame.
	The player types in Container/TextBox/Input and presses Claim (or Enter);
	the raw text goes to CodeService (NetworkEvents "RedeemCode"), which
	decides everything. The answer is shown as a success / error notification
	(EventBus.Notification.Show, rendered by NotificationController).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local EventBus = require(Bootstrapper.Events.EventBus)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local ERROR_TEXT: { [string]: string } = {
	InvalidCode = "Invalid code",
	AlreadyRedeemed = "Already redeemed",
	RateLimited = "Slow down!",
}

local CodesController = {}
CodesController.__index = CodesController

CodesController.Config = require(script.Parent.Config)

export type CodesController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(CodesController.Config),
		_connections: { RBXScriptConnection },
		_input: TextBox?,
		_redeeming: boolean,
	},
	CodesController
))

function CodesController.new(): CodesController
	return setmetatable({
		Root = nil,
		Config = CodesController.Config,
		_connections = {},
		_input = nil,
		_redeeming = false,
	}, CodesController) :: any
end

function CodesController._redeem(self: CodesController): ()
	local input = self._input
	if self._redeeming or not input or input.Text:match("^%s*$") then
		return
	end
	self._redeeming = true
	local result = NetworkEvents.InvokeServer("RedeemCode", input.Text)
	self._redeeming = false

	if type(result) == "table" and result.Success then
		input.Text = ""
		EventBus.Notification.Show:Fire({ Message = tostring(result.Message), Type = "Success" })
	else
		local reason = type(result) == "table" and result.Error or "RateLimited"
		EventBus.Notification.Show:Fire({ Message = ERROR_TEXT[reason] or "Something went wrong", Type = "Error" })
	end
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function CodesController.Init(self: CodesController, deps: any): ()
	SafeUIResolver.WaitForPathAsync(playerGui, { "CodesUI", "MainFrame" }, function(mainFrame)
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

		local input = container:WaitForChild("TextBox"):WaitForChild("Input") :: TextBox
		self._input = input
		table.insert(
			self._connections,
			input.FocusLost:Connect(function(enterPressed: boolean)
				if enterPressed then
					self:_redeem()
				end
			end)
		)

		local claim = container:WaitForChild("Claim") :: GuiButton
		for _, conn in UXEffects.ButtonFX.attach(claim :: any) do
			table.insert(self._connections, conn)
		end
		table.insert(
			self._connections,
			claim.Activated:Connect(function()
				self:_redeem()
			end)
		)
	end)
end

function CodesController.Activate(_self: CodesController): () end

function CodesController.Deactivate(_self: CodesController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function CodesController.Destroy(self: CodesController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return CodesController
