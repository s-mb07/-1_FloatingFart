--!strict
--[[
	@module PanelTagsConfig
	@description SINGLE SOURCE of CollectionService tags for full-screen UI panels.

	One panel = one tag, set by its Controller (AddTag) and read as the
	`TargetTag` attribute by Open/Close buttons (see UITag/PanelUI.lua). The tag
	drives mutual exclusion and global close-all WHEN a panel does NOT go
	through Navigation.Controller (Push/CloseAll handles this natively for any
	migrated panel -- see Navigation/Controller.lua): this file therefore only
	serves panels still on the old pure-tag `UITag.PanelUI` system.

	Adding a panel = one entry in `Panels` + `Tags.<NAME>`. Only 2
	examples below (Inventory/Settings) -- replace them with your panels.
]]

local PanelTagsConfig = {}

--- Tags by symbolic name -- use this on the Controller side instead of a literal.
local Tags = {
	INVENTORY = "InventoryPanel",
	SETTINGS  = "SettingsPanel",
}

PanelTagsConfig.Tags = table.freeze(Tags)

export type PanelEntry = {
	tag: string,
	button: string?,           -- HUD button that opens it (nil = opened via a world pad)
	hudMenu: boolean?,         -- false = no HUD hiding or FOV zoom
	mutualExclusion: boolean?, -- false = no mutual exclusion or global close (Shift+P)
	migratedToNavigation: boolean?, -- true = the HUD button is wired by Panels/init.lua to
	                                -- Navigation.Controller.Push -- the old tag system must
	                                -- NOT apply PanelUI.WireOpenButton to it (otherwise a
	                                -- double-open: the old UIAction_Open tag AND the new Push
	                                -- would both trigger on the same click).
}

local Panels: {PanelEntry} = {
	{ tag = Tags.INVENTORY, button = "Inventory", migratedToNavigation = true },
	{ tag = Tags.SETTINGS,  button = "Settings",  migratedToNavigation = true },
}

PanelTagsConfig.Panels = Panels

--- Flat list of tags -- mutual exclusion and global close (Shift+P).
local All: {string} = {}
for _, panel in ipairs(Panels) do
	if panel.mutualExclusion ~= false then
		table.insert(All, panel.tag)
	end
end
PanelTagsConfig.All = table.freeze(All)

--- Panels that hide the HUD and zoom the camera on open.
local HudMenus: {PanelEntry} = {}
for _, panel in ipairs(Panels) do
	if panel.hudMenu ~= false then
		table.insert(HudMenus, panel)
	end
end
PanelTagsConfig.HudMenus = HudMenus

return table.freeze(PanelTagsConfig)
