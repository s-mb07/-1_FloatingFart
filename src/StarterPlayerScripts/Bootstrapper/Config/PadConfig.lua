--!strict
--[[
	@module PadConfig
	@description Declarative table of world pads that open a Navigation
	panel, consumed by StandaloneControllers/PadController via the
	PadTrigger primitive (ReplicatedStorage/Libraries/PadTrigger.lua).

	Lives under StarterPlayerScripts: opening a panel is a UI decision,
	no server consumer. A pad with real logic (reward, sale, machine)
	keeps its own service/controller and calls PadTrigger.Bind itself --
	this registry ONLY covers the "pad -> Navigation panel" case.

	Adding a panel-opening pad = placing the tag on the level design side +
	ONE line here. No detection code to write, and no distance to choose:
	PadTrigger derives the entry/exit margin from the actual size of the
	hitbox placed in Studio (see the header of PadTrigger.lua) -- a pad
	placed larger in Studio opens/closes further away, with no magic number
	hand-picked per pad.
]]

export type PadPanelEntry = {
	--- CollectionService tag of the hitbox (Hitbox_OpenWorld_<Name> convention).
	Tag: string,
	--- panelId registered in Navigation.PanelRegistry.
	Panel: string,
	--- Optional PadTrigger `Reach` (studs per local axis) instead of the
	--- geometry-derived padding (half the diagonal: far too wide on big hitboxes).
	Reach: Vector3?,
	--- Optional boolean key of the player data snapshot: once true, the pad
	--- no longer opens the panel (e.g. a one-time reward already claimed).
	HideWhen: string?,
}

local panels: { PadPanelEntry } = {
	-- Examples -- replace with your own pads.
	{ Tag = "Hitbox_OpenWorld_Shop", Panel = "Shop" },
	{ Tag = "Hitbox_OpenWorld_Info", Panel = "Info" },
	-- The circle around the big chest next to the trainers
	{ Tag = "Hitbox_OpenWorld_GroupReward", Panel = "GroupReward", Reach = Vector3.new(0, 4.5, 0), HideWhen = "GroupRewardClaimed" },
}

local PadConfig = {
	Panels = panels,
}

return PadConfig
