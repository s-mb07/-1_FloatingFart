--!strict
--[[
	@module UIListKit.Diff
	@description Keyed diff between an old rendered order and a new desired
	order. Used by list/grid renderers to figure out which UI cells can be
	kept in place (just refreshed), which are newly needed (create/acquire),
	and which are no longer needed (release/pool) -- instead of destroying and
	recreating everything on every search/filter/sort change.

	O(n) via set membership, no nested loops over the full collections.
]]

local Diff = {}

export type DiffResult = {
	Added: { string },   -- keys present in new, absent in old
	Removed: { string }, -- keys present in old, absent in new
	Kept: { string },    -- keys present in both (order follows `newOrder`)
}

--- Computes added/removed/kept keys between `oldOrder` and `newOrder`.
--- Both arrays are assumed to contain unique keys (as in this codebase:
--- ItemType, GUID, category id, etc).
function Diff.compute(oldOrder: { string }, newOrder: { string }): DiffResult
	local oldSet: { [string]: boolean } = {}
	for _, key in oldOrder do
		oldSet[key] = true
	end

	local newSet: { [string]: boolean } = {}
	local added: { string } = {}
	local kept: { string } = {}
	for _, key in newOrder do
		newSet[key] = true
		if oldSet[key] then
			table.insert(kept, key)
		else
			table.insert(added, key)
		end
	end

	local removed: { string } = {}
	for _, key in oldOrder do
		if not newSet[key] then
			table.insert(removed, key)
		end
	end

	return { Added = added, Removed = removed, Kept = kept }
end

return Diff
