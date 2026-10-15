--!strict
--[[
	@module Navigation.WireCloseButton
	@description Wires up a standard close button (header cross) for a
	migrated panel: hover/press FX, click -> onClose(), AND the global
	"CloseUI" keybind (Escape, see KeybindsConfig.Reserved.CloseUI) via the
	same registry Actions.RegisterKeybindHandler uses for HUD buttons
	(Panels/init.lua).

	Without this last part, Escape no longer closes any migrated panel: an
	older tag-based system set this keybind via a tag read by an
	InputRouter -> Actions.TriggerKeybind("CloseUI") -> keybindRegistry,
	which a panel migrated to Navigation.Controller no longer carries.

	Actions.TriggerKeybind ignores a handler whose instance (or a GuiObject
	ancestor) has Visible = false (see Actions.lua): Escape therefore only
	triggers the button of the panel that's actually open, even if several
	KeepAlive panels each have a "CloseUI" handler permanently registered.
]]

local Bootstrapper = script.Parent.Parent
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local Actions = require(Bootstrapper.Libraries.SafeUIResolver.UITag.Handlers.Actions)

local CLOSE_KEYBIND = "CloseUI"

local WireCloseButton = {}

--- @param button GuiButton
--- @param connections { RBXScriptConnection } table to add the created connections to (for Destroy())
--- @param onClose () -> () typically `function() Navigation.Pop() end`
function WireCloseButton.Wire(button: GuiButton, connections: { RBXScriptConnection }, onClose: () -> ()): ()
	for _, conn in UXEffects.ButtonFX.attach(button :: any) do
		table.insert(connections, conn)
	end
	table.insert(connections, button.Activated:Connect(onClose))

	button:SetAttribute("ActionKeybind", CLOSE_KEYBIND)
	Actions.RegisterKeybindHandler(button, onClose)
end

return WireCloseButton
