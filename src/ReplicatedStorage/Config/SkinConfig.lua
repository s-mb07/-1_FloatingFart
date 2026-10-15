--!strict
--[[
	@class SkinConfig
	Skin catalogue (shared: the server enforces price and XP, the client only
	displays). A skin is only the look of the `Fly` model on the character's
	back (FlyModelService): ADDING A SKIN = one entry below + its assets/pad:

	  - Assets:  ReplicatedStorage/Assets/Skins/<Id>/SurfaceAppearance
	             (no SurfaceAppearance = the base look of the model)
	  - Pad:     a Part tagged TagNames.SkinPad with an `Id` attribute = "<Id>"
	  - Entry:   Skins["<Id>"] = { Price = <wins>, XPPerSecond = <xp> }
	             or, for a Robux skin, { GamePass = "<GamePassConfig key>", ... } (paid only)

	Ids are STRINGS and match the asset folder name and the pad `Id` attribute.
]]

export type SkinDef = {
	--- Wins (trophies) needed to unlock (0 = free).
	Price: number,
	--- Base XP ("Length") granted per second (flight + treadmill) while
	--- equipped -- the "+N Length" shown on its pad.
	XPPerSecond: number,
	--- Robux skin: unlocked ONLY through this GamePassConfig pass (bought or
	--- gifted, see AccessGate), never with wins. Nil = wins only.
	GamePass: string?,
	--- Robux skin: price shown on its pad (the real price is the gamepass's).
	--- Nil on a Robux skin = its pad reads "VIP" (granted by the VIP pass).
	PriceRobux: number?,
}

local SkinConfig = {
	--- Unlocked by every player from the start; equipped on a new profile.
	Default = "1",
	--- Player attribute (replicated) holding the equipped skin id, read by
	--- FlyModelService (the model's look) and the pad colours.
	EquippedAttribute = "EquippedSkin",
	--- Player attribute (replicated) listing the owned skin ids, "1,2,5":
	--- lets every client colour the pads without a data round trip.
	OwnedAttribute = "OwnedSkins",
	--- Enter reach of a skin pad (PadTrigger Reach): over the plate's
	--- footprint, up to 4.5 studs above it (the HRP floats ~3.4 studs over a
	--- thin plate), nothing sideways. A sideways padding made neighbouring pads
	--- (3-4 studs apart) overlap: walking back onto a pad never left its zone,
	--- so it never re-entered and the skin could not be equipped.
	PadReach = Vector3.new(0, 4.5, 0),

	Skins = {
		["1"] = { Price = 0, XPPerSecond = 1 }, -- starter, equipped on a new profile
		["2"] = { Price = 1, XPPerSecond = 3 },
		["3"] = { Price = 5, XPPerSecond = 4 },
		["4"] = { Price = 10, XPPerSecond = 6 },
		["5"] = { Price = 25, XPPerSecond = 7 },
		["6"] = { Price = 50, XPPerSecond = 8 },
		["7"] = { Price = 100, XPPerSecond = 11 },
		["8"] = { Price = 250, XPPerSecond = 13 },
		["9"] = { Price = 600, XPPerSecond = 19 },
		["10"] = { Price = 1200, XPPerSecond = 23 },
		["11"] = { Price = 0, XPPerSecond = 30, GamePass = "VIP" }, -- Golden Plane: VIP only
		["12"] = { Price = 5000, XPPerSecond = 37 },
		["13"] = { Price = 10000, XPPerSecond = 51 },
		Robux = { Price = 0, XPPerSecond = 100, GamePass = "RobuxSkin", PriceRobux = 399 },
	} :: { [string]: SkinDef },
}

--- Wins skins in purchase order (Robux skins are outside the order: they can
--- be bought at any time). Numeric ids ascending.
local order: { string } = {}
for id, def in SkinConfig.Skins do
	if not def.GamePass then
		table.insert(order, id)
	end
end
table.sort(order, function(a: string, b: string): boolean
	return (tonumber(a) or 0) < (tonumber(b) or 0)
end)

--- The wins skin that has to be owned before `id` can be bought (nil for the
--- first one and for Robux skins).
function SkinConfig.PreviousOf(id: string): string?
	local index = table.find(order, id)
	return if index and index > 1 then order[index - 1] else nil
end

--- The next wins skin to buy given the owned set: the first of the order not
--- owned yet (nil when all are).
function SkinConfig.NextToBuy(owned: { [string]: boolean }): string?
	for _, id in order do
		if not owned[id] then
			return id
		end
	end
	return nil
end

function SkinConfig.EncodeOwned(owned: { [string]: boolean }): string
	local ids: { string } = {}
	for id in owned do
		table.insert(ids, id)
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function SkinConfig.DecodeOwned(encoded: any): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	if type(encoded) == "string" then
		for id in string.gmatch(encoded, "[^,]+") do
			owned[id] = true
		end
	end
	return owned
end

return SkinConfig
