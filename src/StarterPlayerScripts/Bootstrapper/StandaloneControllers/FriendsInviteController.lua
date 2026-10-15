--!strict
--[[
	@module FriendsInviteController
	@description Wires the HUD Friends button
	(MainHUD/BottomRightFrame/FriendsBtn) to Roblox's native
	"Invite Friends" prompt (SocialService:PromptGameInvite). Nothing
	game-side is granted: this only opens the engine's own UI.

	CanSendGameInviteAsync is checked first -- it's false for accounts that
	can't send invites (and throws on web failures), in which case the
	button does nothing instead of erroring.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local Bootstrapper = script.Parent.Parent
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local log = Logger.new("FriendsInviteController")
local FriendsInviteController = {}

local player = Players.LocalPlayer

local function promptInvite(): ()
	local ok, canInvite = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if not ok or not canInvite then
		log:Warn("Game invites unavailable for this account (%s).", tostring(canInvite))
		return
	end
	SocialService:PromptGameInvite(player)
end

function FriendsInviteController:Init(): () end

function FriendsInviteController:Start(): ()
	local playerGui = player:WaitForChild("PlayerGui")
	SafeUIResolver.WaitForPathStringAsync(
		playerGui,
		"MainHUD/BottomRightFrame/FriendsBtn",
		function(instance)
			local button = instance :: GuiButton
			UXEffects.ButtonFX.attach(button :: any)
			button.Activated:Connect(promptInvite)
		end
	)
end

return FriendsInviteController
