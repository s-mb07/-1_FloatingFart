--!strict
--[[
	@module Panels.GroupReward.Controller
	@description Free group reward pop-up over the Studio-authored
	PlayerGui/GroupRewardsUI/MainFrame, opened by walking into the circle
	around the big chest (Config/PadConfig "Hitbox_OpenWorld_GroupReward").
	Claim (`ClaimBtn`), in order:
	  1. Not liked yet: native favorite prompt + "You need to like the game
	     first!". Roblox has no API to read a like, so the favorite stands in
	     for it (checked client-side only: the server can't read favorites).
	  2. GroupRewardService ("ClaimGroupReward") checks the group membership
	     and grants GroupRewardConfig's wins + length once per profile.
	     NotInGroup: native group join prompt + "You need to join the group first!".
	Once claimed (data flag GroupRewardClaimed), PadController no longer opens
	this panel (PadConfig `HideWhen`).

	Studio names it looks for (anywhere under MainFrame): `ClaimBtn`, `Close`.
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bootstrapper = script.Parent.Parent.Parent

local EventBus = require(Bootstrapper.Events.EventBus)
local GroupRewardConfig = require(ReplicatedStorage.Config.GroupRewardConfig)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local WireCloseButton = require(Bootstrapper.Navigation.WireCloseButton)

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local ERROR_TEXT: { [string]: string } = {
	AlreadyClaimed = "Already claimed!",
	NotInGroup = "You need to join the group first!",
}

local function notifyError(message: string): ()
	EventBus.Notification.Show:Fire({ Message = message, Type = "Error" })
end

--- true when the place is favorited, or when that can't be read (Studio).
local function hasLiked(): boolean
	local ok, favorited = pcall(AvatarEditorService.GetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset)
	return not ok or favorited == true
end

local GroupRewardController = {}
GroupRewardController.__index = GroupRewardController

GroupRewardController.Config = require(script.Parent.Config)

export type GroupRewardController = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(GroupRewardController.Config),
		_connections: { RBXScriptConnection },
		_busy: boolean,
	},
	GroupRewardController
))

function GroupRewardController.new(): GroupRewardController
	return setmetatable({
		Root = nil,
		Config = GroupRewardController.Config,
		_connections = {},
		_busy = false,
	}, GroupRewardController) :: any
end

function GroupRewardController._claim(self: GroupRewardController, deps: any): ()
	if self._busy then
		return
	end
	self._busy = true
	if not hasLiked() then
		self._busy = false
		pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
		notifyError("You need to like the game first!")
		return
	end
	local result = NetworkEvents.InvokeServer("ClaimGroupReward")
	self._busy = false
	if type(result) == "table" and result.Success then
		deps.Navigation.Pop() -- the server's notification shows what was granted
		return
	end
	local reason = type(result) == "table" and result.Error or "RateLimited"
	if reason == "NotInGroup" then
		-- Native join prompt; fails silently where unavailable (Studio)
		task.spawn(pcall, GroupService.PromptJoinAsync, GroupService, GroupRewardConfig.GroupId)
	end
	notifyError(ERROR_TEXT[reason] or "Try again!")
end

local function onButton(self: GroupRewardController, frame: Frame, name: string, callback: () -> ()): ()
	local button = frame:FindFirstChild(name, true)
	if button and button:IsA("GuiButton") then
		table.insert(self._connections, button.Activated:Connect(callback))
	end
end

--============================================================================--
-- LIFECYCLE (PanelDefinition)
--============================================================================--

function GroupRewardController.Init(self: GroupRewardController, deps: any): ()
	SafeUIResolver.WaitForPathAsync(playerGui, { "GroupRewardsUI", "MainFrame" }, function(mainFrame)
		local frame = mainFrame :: Frame
		self.Root = frame
		local gui = frame.Parent :: ScreenGui
		gui.Enabled = true
		gui.DisplayOrder = 1 -- above MainHUD (0)
		frame.Visible = false

		local close = frame:FindFirstChild("Close", true)
		if close and close:IsA("GuiButton") then
			WireCloseButton.Wire(close, self._connections, function()
				deps.Navigation.Pop()
			end)
		end
		onButton(self, frame, "ClaimBtn", function()
			self:_claim(deps)
		end)
	end)
end

function GroupRewardController.Activate(_self: GroupRewardController): () end

function GroupRewardController.Deactivate(_self: GroupRewardController): () end

--- Never called as long as Config.Navigation.KeepAlive = true.
function GroupRewardController.Destroy(self: GroupRewardController): ()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	table.clear(self._connections)
end

return GroupRewardController
