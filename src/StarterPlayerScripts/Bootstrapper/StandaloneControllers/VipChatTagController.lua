--!strict
--[[
	@module VipChatTagController
	@description Prefixes chat messages with "[🔱 Owner]" / "[🔧 Dev]" (admins,
	replicated `ChatRole` attribute set by AdminService) and a gold "[👑 VIP]"
	for VIP gamepass owners (TextChatService). Display only: VIP ownership
	comes from the replicated pass attribute GamePassService caches.

	TextChatService.OnIncomingMessage holds ONE callback per client: this is
	the only module allowed to set it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local GamePassConfig = require(ReplicatedStorage.Config.GamePassConfig)

local VIP_PASS = "VIP"
local VIP_PREFIX = '<font color="#FFCD28"><b>[👑 VIP]</b></font> '

-- Set by AdminService on admins ("Owner" for the owner, "Dev" for the rest).
local ROLE_ATTRIBUTE = "ChatRole"
local ROLE_PREFIXES: { [any]: string } = {
	Owner = '<font color="#FF4B4B"><b>[🔱 Owner]</b></font> ',
	Dev = '<font color="#5AD2FF"><b>[🔧 Dev]</b></font> ',
}

local VipChatTagController = {}

function VipChatTagController:Init(): () end

function VipChatTagController:Start(): ()
	TextChatService.OnIncomingMessage = function(
		message: TextChatMessage
	): TextChatMessageProperties?
		local source = message.TextSource
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if not player then
			return nil
		end
		local prefix = ROLE_PREFIXES[player:GetAttribute(ROLE_ATTRIBUTE)] or ""
		if GamePassConfig.PlayerHasPass(player, VIP_PASS) then
			prefix ..= VIP_PREFIX
		end
		if prefix == "" then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = prefix .. message.PrefixText
		return properties
	end
end

return VipChatTagController
