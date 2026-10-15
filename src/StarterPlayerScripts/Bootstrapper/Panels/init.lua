--!strict
--[[
	@module Panels
	@description Registers each migrated panel in Navigation.PanelRegistry
	and wires its external (HUD) opening button to Navigation.Controller.

	Deliberately explicit, one entry per panel: no auto-discovery
	by folder -- one more panel = one more `registerPanel` call, no
	magic. `registerPanel` just factors out the MECHANICAL wiring shared by
	every HUD panel (button -> Push, keybind, FX).

	The HUD button wiring is done HERE, not in the panel's Controller:
	the button (e.g. MainHUD/Left/Buttons/Settings) is a permanent Instance
	independent of the panel itself, wired once for the whole
	session -- whereas Controller:Init() can, for a non-KeepAlive panel,
	be called again on every Push. Wiring it in Init() would multiply the
	Activated connections on THAT button on every reopen.

	Required once by Bootstrapper/init.client.lua, before anything can
	click an opening button.
]]

local Players = game:GetService("Players")

local SafeUIResolver = require(script.Parent.Libraries.SafeUIResolver)
local Actions = require(script.Parent.Libraries.SafeUIResolver.UITag.Handlers.Actions)

local NavigationController = require(script.Parent.Navigation.Controller)
local PanelRegistry = require(script.Parent.Navigation.PanelRegistry)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

--- Registers `panelId` in PanelRegistry (resolved from `script[panelId].Controller`)
--- and wires, if provided, the HUD button(s) `buttonPaths` (e.g. "MainHUD/Left/Buttons/Settings")
--- so a click (or the `keybindName` keybind) TOGGLES the panel -- Push(panelId)
--- if it's not active, Pop() if it already is (otherwise a second click on the
--- SAME HUD button would do nothing, since Push() is a no-op if already active).
--- `buttonPaths = nil` = panel with no dedicated HUD button (opened via a
--- world pad, wired by PadController -- see Config/PadConfig.lua).
---
--- Multiple paths: a panel can have TWO distinct button instances that must
--- both open the same panel (e.g. a HUD icon + an icon in an already-open
--- submenu) -- both are wired identically.
local function registerPanel(panelId: string, buttonPaths: {string}?, keybindName: string?): ()
	PanelRegistry.Register(panelId, function()
		return (require((script :: any)[panelId].Controller) :: any).new()
	end)

	if not buttonPaths then return end

	local function open(): ()
		if NavigationController.GetActivePanelId() == panelId then
			NavigationController.Pop()
		else
			NavigationController.Push(panelId)
		end
	end

	for _, buttonPath in ipairs(buttonPaths) do
		SafeUIResolver.WaitForPathStringAsync(playerGui, buttonPath, function(openBtn)
			if not openBtn:IsA("GuiButton") then return end
			local button = openBtn :: GuiButton

			-- Hover/press FX: ButtonHoverController (icon grows + tilts, button stays)

			button:SetAttribute("SoundId", "Click")
			if keybindName then
				button:SetAttribute("ActionKeybind", keybindName)
			end

			button.Activated:Connect(open)
			if keybindName then
				Actions.RegisterKeybindHandler(button, open)
			end
		end)
	end
end

--============================================================================--
-- Panels with a HUD button (1 example -- add yours in the same format)
--============================================================================--

registerPanel("DailyRewards", { "MainHUD/LeftHUD/Daily" })
registerPanel("PlaytimeRewards", { "MainHUD/LeftHUD/Gift" })
registerPanel("Trails", { "MainHUD/LeftHUD/Trails" })
registerPanel("Codes", { "MainHUD/RightHUD/Codes" })
registerPanel("Rebirth", { "MainHUD/LeftHUD/Rebirth" })
registerPanel("StarterPack", { "MainHUD/StarterPack" })
-- The old Music slot is now the Shop (red cart) button.
registerPanel("Shop", { "MainHUD/LeftHUD/Shop" })
registerPanel("Settings", { "MainHUD/BottomRightFrame/SettingsBtn" })
-- Prewarmed: its Init() starts the tick that drives the gift button's
-- countdown / "CLAIM!" label, which must run before the panel is ever opened.
NavigationController.Prewarm("PlaytimeRewards")
-- Prewarmed too: their Init() drives the HUD button's notification dot
-- (claimable reward / rebirth available), which must work before first open.
NavigationController.Prewarm("DailyRewards")
NavigationController.Prewarm("Rebirth")
-- Prewarmed: its Init() hides the HUD button once the pack is claimed.
NavigationController.Prewarm("StarterPack")
-- No HUD button: opened when the Roblox menu closes (GuiService), wired in
-- its own Init() -- hence registered here and prewarmed.
registerPanel("LeaveReward", nil)
NavigationController.Prewarm("LeaveReward")
-- Opened by the chest circle (Config/PadConfig, PadController)
registerPanel("GroupReward", nil)

-- `Panels/_Template/` (Fusion-built, see README.md §6) is a copy-this
-- starting point, not live content -- deliberately NOT registered here.
-- Once you've copied it and renamed the panelId, wire it in exactly like
-- Settings above: registerPanel("YourPanelId", { "path/to/your/button" })

--============================================================================--
-- Panels WITHOUT a HUD button: their ONLY opening trigger (pad proximity,
-- server EventBus, global keybind) is wired by the panel itself
-- INSIDE its own Init() -- unlike registerPanel() above, nothing
-- external ever calls Push() a first time to trigger this
-- wiring. Prewarm() therefore forces Resolve+Init NOW (without activating
-- the panel) so this trigger actually exists -- without it, Init() would
-- NEVER run and these panels would stay unreachable.
--
-- Example (uncomment once Panels/Shop/Controller.lua is written -- see
-- Config/PadConfig.lua, which already references the panelId "Shop"):
--
-- PanelRegistry.Register("Shop", function()
-- 	return (require(script.Shop.Controller) :: any).new()
-- end)
-- NavigationController.Prewarm("Shop")
--============================================================================--

return nil
