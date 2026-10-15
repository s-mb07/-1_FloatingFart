--!strict
--[[
	@module AccessGate
	@description The single "may this player use this element" check for every
	pad that can be free, earned or bought (win pads, treadmills, skins).
	Server-only; lives beside Services/ so the bootstrapper doesn't Init it.

	An element carries an `AccessRule`. It is usable when ANY path is open:
	  - no path declared at all    -> free, always usable;
	  - `RequiredRebirths` reached -> earned;
	  - `GamePass` owned           -> bought or gifted (GamePassService.HasPass;
	                                  every pass counts as owned while
	                                  MonetizationConfig.FreeMode is on).
	So "rebirth 2 OR Robux" = both fields set; "Robux only" = just GamePass.
	Never yields (ownership is cached).
]]

local DataService = require(script.Parent.Services.DataService)
local GamePassService = require(script.Parent.Services.GamePassService)

export type AccessRule = {
	--- Rebirths needed to use the element without paying.
	RequiredRebirths: number?,
	--- GamePassConfig key that unlocks the element.
	GamePass: string?,
}

local AccessGate = {}

--- True when `player` owns pass `passKey` (always, in FreeMode).
function AccessGate.OwnsPaid(player: Player, passKey: string): boolean
	return GamePassService.HasPass(player, passKey)
end

--- True when `player` may use an element governed by `rule`.
function AccessGate.Check(player: Player, rule: AccessRule): boolean
	local required, pass = rule.RequiredRebirths, rule.GamePass
	if required == nil and pass == nil then
		return true
	end
	if required ~= nil and DataService:GetRebirths(player) >= required then
		return true
	end
	return pass ~= nil and AccessGate.OwnsPaid(player, pass)
end

return AccessGate
