--!strict
--[[
	@module CinematicModeController
	@description TopbarPlus toggle that hides every enabled ScreenGui in the
	local PlayerGui (cinematic mode) and restores exactly those on untoggle.
	Client only. The TopbarPlus guis themselves ("Topbar*") are skipped so
	the button stays clickable.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icon = require(ReplicatedStorage.Packages.TopbarPlus)

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local CinematicModeController = {}

local playerGui: PlayerGui
local hidden: { [ScreenGui]: boolean } = {}
local active = false
local addedConnection: RBXScriptConnection? = nil

local function isHideable(gui: Instance): boolean
	return gui:IsA("ScreenGui") and gui.Enabled and not string.find(gui.Name, "^Topbar")
end

local function hide(gui: ScreenGui)
	hidden[gui] = true
	gui.Enabled = false
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on

	if on then
		for _, child in playerGui:GetChildren() do
			if isHideable(child) then
				hide(child :: ScreenGui)
			end
		end
		-- GUIs created while active (toasts, effects...) get hidden too.
		addedConnection = playerGui.ChildAdded:Connect(function(child)
			-- Enabled may be set right after parenting; check next frame.
			task.defer(function()
				if active and isHideable(child) then
					hide(child :: ScreenGui)
				end
			end)
		end)
	else
		if addedConnection then
			addedConnection:Disconnect()
			addedConnection = nil
		end
		for gui in hidden do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hidden)
	end
end

function CinematicModeController:Init(): ()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

function CinematicModeController:Start(): ()
	Icon.new()
		:setName("CinematicMode")
		:setLabel("Cinematic Mode")
		:modifyTheme({
			{ "IconButton", "BackgroundColor3", BLACK, "Deselected" },
			{ "IconButton", "BackgroundTransparency", 0, "Deselected" },
			{ "IconLabel", "TextColor3", WHITE, "Deselected" },
			{ "IconButton", "BackgroundColor3", WHITE, "Selected" },
			{ "IconButton", "BackgroundTransparency", 0, "Selected" },
			{ "IconLabel", "TextColor3", BLACK, "Selected" },
		})
		:bindEvent("selected", function()
			setActive(true)
		end)
		:bindEvent("deselected", function()
			setActive(false)
		end)
end

return CinematicModeController
