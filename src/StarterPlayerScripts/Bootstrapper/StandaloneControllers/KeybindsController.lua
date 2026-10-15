--!strict
--[[
	@module KeybindsController
	@description Single entry point for keyboard AND gamepad keybinds.
	Listens globally to UserInputService and routes to the
	UITag.Handlers.Actions registry (TriggerKeybind/RegisterKeybindHandler) --
	no direct UI logic here, no bypassing handlers already registered per
	button (see Panels/init.lua's registerPanel, Navigation/WireCloseButton).

	Gamepad buttons arrive as normal Enum.KeyCode values
	(ButtonY, DPadUp, ...) through the same InputBegan -- so KeybindsConfig.Gamepad
	needs no separate handling, just its own section to stay
	readable on the config side.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local KeybindsConfig = require(script.Parent.Parent.Config.KeybindsConfig)
local Actions = require(script.Parent.Parent.Libraries.SafeUIResolver.UITag.Handlers.Actions)
local NavigationController = require(script.Parent.Parent.Navigation.Controller)

local log = Logger.new("KeybindsController")
local KeybindsController = {}

--- KeybindsConfig sections routed as-is to Actions.TriggerKeybind
--- (the key name serves as the key -- its logical category doesn't matter,
--- TriggerKeybind just looks up a handler registered under that name).
local ROUTED_SECTIONS = { "UI", "Gameplay", "Reserved", "Gamepad" }

function KeybindsController:Init(): ()
	log:Info("Initialized.")
end

function KeybindsController:Start(): ()
	-- Wait for PlayerGui to avoid dropping inputs at startup.
	local player = Players.LocalPlayer
	if player then
		player:WaitForChild("PlayerGui")
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end -- already handled by the engine (chat, clicked UI, ...)
		if UserInputService:GetFocusedTextBox() then return end

		-- Shift+P (Roblox's native FreeCam): closes all navigation at
		-- once before releasing any TextBox focus -- otherwise the
		-- keyboard/scroll wheel stay captured by Roblox after closing. A
		-- panic-close deliberately bypasses Pop() (which would only
		-- reveal whatever is underneath).
		if input.KeyCode == Enum.KeyCode.P and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			local focusedBox = UserInputService:GetFocusedTextBox()
			if focusedBox then
				focusedBox:ReleaseFocus()
			end
			NavigationController.CloseAll()
			return
		end

		for _, section in ROUTED_SECTIONS do
			local bindings = KeybindsConfig[section]
			if typeof(bindings) == "table" then
				for keyName, keyCode in pairs(bindings) do
					if input.KeyCode == keyCode then
						Actions.TriggerKeybind(keyName)
					end
				end
			end
		end
	end)

	log:Info("Started: global input router active.")
end

return KeybindsController
