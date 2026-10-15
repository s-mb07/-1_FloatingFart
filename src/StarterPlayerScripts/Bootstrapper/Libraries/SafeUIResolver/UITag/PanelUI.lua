--!strict
--[[
	@module UITag.PanelUI
	@description Standard wiring for a full-screen panel and its buttons.

	Replaces the AddTag/SetAttribute sequence copy-pasted identically across
	a dozen UIHandlers. Tag names come from Handlers.Effects /
	Handlers.Actions (single source); the panel's tag comes from
	Config.PanelTagsConfig.

	@usage
	```lua
	local PanelUI = require(Bootstrapper.Libraries.SafeUIResolver.UITag.PanelUI)
	local PanelTags = require(Bootstrapper.Config.PanelTagsConfig).Tags

	PanelUI.RegisterPanel(window, PanelTags.INVENTORY)
	PanelUI.WireOpenButton(openBtn, PanelTags.INVENTORY, "Inventory")
	PanelUI.WireCloseButton(closeBtn, PanelTags.INVENTORY, "CloseUI, Inventory")
	```
]]

local CollectionService = game:GetService("CollectionService")

local Actions = require(script.Parent.Handlers.Actions)
local Effects = require(script.Parent.Handlers.Effects)

local PanelUI = {}

--- Default click sound for opening buttons.
local DEFAULT_SOUND_ID = "Click"

--- Registers a Frame as a panel: mutual exclusion tag + entry mode.
function PanelUI.RegisterPanel(window: Instance, panelTag: string): ()
	window:SetAttribute("mode", Actions.HOW_TO_OPEN_DEFAULT)
	CollectionService:AddTag(window, panelTag)
end

--- Wires an opening button (HUD button) to a panel.
--- Attributes are set BEFORE tags: the UITag handler reads ActionKeybind
--- on attach, it must already be present.
function PanelUI.WireOpenButton(button: Instance, panelTag: string, keybind: string?): ()
	button:SetAttribute("TargetTag", panelTag)
	button:SetAttribute("HowToOpen", Actions.HOW_TO_OPEN_DEFAULT)
	button:SetAttribute("SoundId", DEFAULT_SOUND_ID)
	if keybind then
		button:SetAttribute("ActionKeybind", keybind)
	end
	CollectionService:AddTag(button, Effects.TAGS.BUTTON)
	CollectionService:AddTag(button, Actions.TAGS.OPEN)
	CollectionService:AddTag(button, Actions.TAGS.SOUND)
end

--- Wires a closing button (header cross) to its panel.
function PanelUI.WireCloseButton(button: Instance, panelTag: string, keybind: string?): ()
	button:SetAttribute("TargetTag", panelTag)
	button:SetAttribute("HowToClose", Actions.HOW_TO_CLOSE_DEFAULT)
	if keybind then
		button:SetAttribute("ActionKeybind", keybind)
	end
	CollectionService:AddTag(button, Effects.TAGS.BUTTON)
	CollectionService:AddTag(button, Actions.TAGS.CLOSE)
end

return PanelUI
