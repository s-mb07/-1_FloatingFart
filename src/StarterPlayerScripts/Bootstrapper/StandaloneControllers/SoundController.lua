--!strict
--[[
	@module SoundController
	@description The one map "game event -> sound" for everything that already
	has a signal. Plays EffectsConfig recipes through Effects.Play (which owns
	the SFX setting and the reusable, preloaded Sound instances); the ids
	live in Config/AssetIds/SoundIds.

	On Start it preloads every recipe's sound (Effects.PreloadSounds), so
	none waits for its asset the first time it plays.

	Listens to (all display-only, nothing is decided here):
	  - panels: EventBus.Navigation.PanelOpened / PanelClosed, fired by
	    Navigation when the transition STARTS (open and close share the
	    "Panel" sound group: one cuts the other);
	  - flight: Gameplay.LaunchStarted (take-off animation), Gameplay.ProbeStopped
	    (obstacle impact or paper flutter), Traversal.WallLocked,
	    ReviveOffered (run lost) -- all in the "Flight"/"Jingle" groups;
	  - progression / rewards: the data snapshot (Traversal.Rebirths up =
	    rebirth, Currencies.Trophies up = win, DailyRewards.Claimed /
	    PlaytimeRewards.Claimed up = reward claimed, StarterPackClaimed
	    false -> true = starter pack bought);
	  - notifications: Notification.Received / Show, by type. A chime is
	    skipped while a celebration ("Jingle" group) is playing, and a
	    celebration arriving right after silences it (Stops = { "Chime" }).

	Sounds tied to a moment another controller owns are played there: level
	up (LevelUpController), XP icon landing (XPGainController), tutorial
	step (TutorialController), button click / hover (ButtonHoverController),
	purchase (PurchasePromptController).
]]

local Players = game:GetService("Players")

local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)

local SoundController = {}

local LocalPlayer = Players.LocalPlayer

local NOTIFY_RECIPES: { [string]: string } = {
	Success = "NotifySuccess",
	Error = "NotifyError",
	Warning = "NotifyError",
	Info = "NotifyInfo",
}

local rebirths: number? = nil
local trophies: number? = nil
local dailyClaimed: number? = nil
local playtimeClaimed: number? = nil
local starterPackClaimed: boolean? = nil

--- Calls `onUp` when `value` (a number) went up since `previous`; returns the new value.
local function rising(previous: number?, value: any, onUp: () -> ()): number?
	if type(value) ~= "number" then
		return previous
	end
	if previous and value > previous then
		onUp()
	end
	return value
end

local function onNotification(payload: any): ()
	if Effects.IsSoundGroupPlaying("Jingle") then
		return -- a celebration is on: the chime would clash with it
	end
	local kind = type(payload) == "table" and payload.Type or "Info"
	Effects.Play(NOTIFY_RECIPES[kind] or "NotifyInfo")
end

--- Rebirths / trophies going UP (the first snapshot only records the values).
local function absorb(data: any): ()
	if type(data) ~= "table" then
		return
	end
	-- The Starter Pack grants Wins in the same snapshot that flips its flag:
	-- its sound is the purchase cascade only, so the Win jingle is skipped.
	local starterPackBought = false
	if data.StarterPackClaimed ~= nil then
		local claimed = data.StarterPackClaimed == true
		starterPackBought = claimed and starterPackClaimed == false
		if starterPackBought then
			Effects.Play("StarterPackClaimed")
		end
		starterPackClaimed = claimed
	end
	local traversal = data.Traversal
	if type(traversal) == "table" and type(traversal.Rebirths) == "number" then
		if rebirths and traversal.Rebirths > rebirths then
			Effects.Play("Rebirth")
		end
		rebirths = traversal.Rebirths
	end
	local currencies = data.Currencies
	if type(currencies) == "table" and type(currencies.Trophies) == "number" then
		if trophies and currencies.Trophies > trophies and not starterPackBought then
			Effects.Play("Win")
		end
		trophies = currencies.Trophies
	end
	if type(data.DailyRewards) == "table" then
		dailyClaimed = rising(dailyClaimed, data.DailyRewards.Claimed, function()
			Effects.Play("DailyClaim")
		end)
	end
	if type(data.PlaytimeRewards) == "table" then
		playtimeClaimed = rising(playtimeClaimed, data.PlaytimeRewards.Claimed, function()
			Effects.Play("PlaytimeClaim")
		end)
	end
end

function SoundController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
end

function SoundController:Start(): ()
	task.spawn(Effects.PreloadSounds)

	EventBus.Navigation.PanelOpened:Connect(function()
		Effects.Play("PanelOpen")
	end)
	EventBus.Navigation.PanelClosed:Connect(function()
		Effects.Play("PanelClose")
	end)

	-- Take-off: when the Start animation begins (not when the flight goes ACTIVE)
	EventBus.Gameplay.LaunchStarted:Connect(function()
		Effects.Play("FlyLaunch")
	end)
	EventBus.Gameplay.ProbeStopped:Connect(function(reason: string)
		Effects.Play(if reason == "Obstacle" then "FlyImpact" else "FlyStop")
	end)
	EventBus.Traversal.WallLocked:Connect(function(player: Player)
		if player == LocalPlayer then
			Effects.Play("WallLock")
		end
	end)
	EventBus.Traversal.ReviveOffered:Connect(function()
		Effects.Play("RunLost")
	end)

	EventBus.Notification.Received:Connect(onNotification)
	EventBus.Notification.Show:Connect(onNotification)
end

return SoundController
