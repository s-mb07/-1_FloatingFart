--!strict
--[[
	@class TagNames
	Registry of CollectionService tags and the attribute names read off them.

	ONE tag per element TYPE; what distinguishes two elements of the same type
	is an attribute on the tagged Part. Per-element rules (price, rebirths,
	Robux product, ...) live in code registries keyed by that attribute, never
	in Studio.

	  Tag                | Part                | Attributes
	  -------------------+---------------------+---------------------------
	  Pad_Win            | win pad (orange, or blue x2 = Vip true) | Stage:number, Vip:boolean
	  Pad_Treadmill      | treadmill Hitbox    | Id:string  (TreadmillConfig.Treadmills)
	  Pad_Skin           | skin pad            | Id:string  (SkinConfig.Skins)
	  Hitbox_Checkpoint  | checkpoint volume   | Stage:number
	  Kill_Part          | any killing Part    | -
	  Vertical           | wall-lockable Part (Honey) | -
	  Deco_Fan           | Fan model (cosmetic spin) | -
	  Deco_SkinShow      | skin showcase Part (cosmetic spin) | -
	  Trap_Train         | stage 6 train trap Folder (Traps/Train) | -
	  Trap_Drone         | stage 8 ZoneSpawnDrone Part (Traps/Drone) | -
]]

export type TagNamesType = {
	WinPad: string,
	Treadmill: string,
	SkinPad: string,
	CheckpointHitbox: string,
	KillPart: string,
	Vertical: string,
	Fan: string,
	SkinShow: string,
	TrainTrap: string,
	DroneTrap: string,
	--- Attribute names read off tagged Parts.
	Attr: { Stage: string, X2: string, Id: string },
}

local TagNames: TagNamesType = table.freeze({
	WinPad = "Pad_Win",
	Treadmill = "Pad_Treadmill",
	SkinPad = "Pad_Skin",
	CheckpointHitbox = "Hitbox_Checkpoint",
	KillPart = "Kill_Part",
	Vertical = "Vertical",
	Fan = "Deco_Fan",
	SkinShow = "Deco_SkinShow",
	TrainTrap = "Trap_Train",
	DroneTrap = "Trap_Drone",
	Attr = table.freeze({
		Stage = "Stage",
		-- Blue x2 win pad flag. The Studio attribute keeps its old name "Vip"
		-- (the pads are unlocked by the X2Wins pass, not VIP).
		X2 = "Vip",
		Id = "Id",
	}),
})

return TagNames
