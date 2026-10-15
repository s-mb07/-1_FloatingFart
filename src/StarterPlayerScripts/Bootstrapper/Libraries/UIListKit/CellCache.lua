--!strict
--[[
	@module UIListKit.CellCache
	@description Keyed cache of live UI "cells" (a cloned template + the
	connections/tooltips/etc wired onto it once) for list/grid renderers.

	Replaces the "destroy everything, clone everything" pattern:
	- A cell for a given key (ItemType, GUID, ...) is created ONCE -- all
	  Instance.new/:Clone(), :Connect(), Tooltip.AttachToButton, ButtonFX
	  wiring happens a single time in `createCell`.
	- On every sync (search/filter/sort/data change), a key that's still
	  present just gets `SetData(newData)` called on its existing cell --
	  the Frame and its connections are untouched, only the displayed fields
	  change.
	- A key that disappears (filtered out / item removed) has its cell
	  parked (Parent = nil, hidden) in a per-`poolKey` free list instead of
	  being destroyed -- future keys sharing the same poolKey (e.g. same
	  slot Size, so same template shape) reuse that instance instead of
	  cloning a new one.

	Usage pattern per populate call:
		cache:BeginSync()
		for i, key in order do
			local cell = cache:AcquireOrUpdate(key, poolKeyFor(key), dataFor(key))
			cell.Frame.Parent = targetSection
			cell.Frame.LayoutOrder = i
		end
		cache:EndSync() -- parks (not destroys) anything not touched this pass
]]

local CellCache = {}
CellCache.__index = CellCache

export type Cell<D, F> = {
	Frame: F,
	SetData: (D) -> (),
	Destroy: (() -> ())?,
}

type ActiveEntry<D, F> = {
	cell: Cell<D, F>,
	poolKey: string,
}

export type CellCache<D, F> = typeof(setmetatable(
	{} :: {
		_createCell: (poolKey: string, data: D) -> Cell<D, F>,
		_active: { [string]: ActiveEntry<D, F> },
		_pool: { [string]: { Cell<D, F> } },
		_touched: { [string]: boolean },
		_maxPoolPerKey: number,
		_parkedLastSync: { F },
	},
	CellCache
))

--- @param createCell Builds a brand-new cell for `poolKey` (clones the right
--- template for that pool, wires all connections ONCE). Called only on true
--- cache misses (no active or pooled cell available).
--- @param maxPoolPerKey Caps how many parked cells are kept per poolKey
--- before excess ones are hard-destroyed (default 200).
function CellCache.new<D, F>(createCell: (poolKey: string, data: D) -> Cell<D, F>, maxPoolPerKey: number?): CellCache<D, F>
	local self = setmetatable({
		_createCell = createCell,
		_active = {},
		_pool = {},
		_touched = {},
		_maxPoolPerKey = maxPoolPerKey or 200,
		_parkedLastSync = {},
	}, CellCache)
	return self :: any
end

--- Call before iterating the new order for this populate pass.
function CellCache.BeginSync<D, F>(self: CellCache<D, F>): ()
	table.clear(self._touched)
	table.clear(self._parkedLastSync)
end

--- Returns the cell for `key`, creating or reusing (from the `poolKey` free
--- list) one if needed, and always refreshes it with `data` via `SetData`.
--- Does NOT set Parent/LayoutOrder -- caller places the returned Frame.
function CellCache.AcquireOrUpdate<D, F>(self: CellCache<D, F>, key: string, poolKey: string, data: D): Cell<D, F>
	self._touched[key] = true

	local entry = self._active[key]
	if entry then
		entry.cell.SetData(data)
		return entry.cell
	end

	local pool = self._pool[poolKey]
	local cell: Cell<D, F>?
	if pool and #pool > 0 then
		cell = table.remove(pool)
	end
	if not cell then
		cell = self._createCell(poolKey, data)
	end

	-- Symmetric to EndSync (which sets Visible=false when parking): a cell
	-- returned here -- fresh or reused from the pool -- must always come back
	-- visible, otherwise a parked-then-reacquired slot stays invisible forever
	-- (Parent reassigned by the caller, but Visible never restored).
	local frame = (cell :: Cell<D, F>).Frame :: any
	if frame.Visible ~= nil then
		frame.Visible = true
	end

	(cell :: Cell<D, F>).SetData(data)
	self._active[key] = { cell = cell :: Cell<D, F>, poolKey = poolKey }
	return cell :: Cell<D, F>
end

--- Call after the populate pass: any active cell whose key wasn't touched
--- this sync gets parked into its poolKey free list (Parent cleared,
--- Visible=false) for reuse instead of being destroyed.
function CellCache.EndSync<D, F>(self: CellCache<D, F>): ()
	for key, entry in self._active do
		if not self._touched[key] then
			self._active[key] = nil
			table.insert(self._parkedLastSync, entry.cell.Frame)

			local frame = entry.cell.Frame :: any
			frame.Parent = nil
			if frame.Visible ~= nil then
				frame.Visible = false
			end

			local pool = self._pool[entry.poolKey]
			if not pool then
				pool = {}
				self._pool[entry.poolKey] = pool
			end

			if #pool >= self._maxPoolPerKey then
				if entry.cell.Destroy then
					entry.cell.Destroy()
				else
					frame:Destroy()
				end
			else
				table.insert(pool, entry.cell)
			end
		end
	end
end

--- Returns the Frame of every currently active (visible, in-order) cell.
--- Snapshot array, safe to iterate while mutating the cache afterwards.
function CellCache.GetActiveFrames<D, F>(self: CellCache<D, F>): { F }
	local frames = {}
	for _, entry in self._active do
		table.insert(frames, entry.cell.Frame)
	end
	return frames
end

--- Returns the Frame of every cell parked (recycled to the pool, or hard-
--- destroyed if the pool was full) by the MOST RECENT EndSync() call --
--- lets a caller detect which keys actually dropped out of the active set
--- THIS pass specifically (as opposed to GetActiveFrames, which only
--- reflects what's currently shown). Cleared again at the next BeginSync.
function CellCache.GetFramesParkedLastSync<D, F>(self: CellCache<D, F>): { F }
	return self._parkedLastSync
end

--- Hard-destroys every active and pooled cell. Use when the whole list is
--- torn down (e.g. panel closing for good), not on routine repopulate.
function CellCache.DestroyAll<D, F>(self: CellCache<D, F>): ()
	for _, entry in self._active do
		if entry.cell.Destroy then
			entry.cell.Destroy()
		else
			(entry.cell.Frame :: any):Destroy()
		end
	end
	table.clear(self._active)

	for _, pool in self._pool do
		for _, cell in pool do
			if cell.Destroy then
				cell.Destroy()
			else
				(cell.Frame :: any):Destroy()
			end
		end
	end
	table.clear(self._pool)
end

return CellCache
