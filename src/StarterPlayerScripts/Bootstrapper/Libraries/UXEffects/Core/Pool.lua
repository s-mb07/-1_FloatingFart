--!strict
--[[
	@module UXEffects.Core.Pool
	@description Object pooling system to optimize performance.

	Pooling avoids frequent allocations/deallocations that cause
	latency spikes from the garbage collector. Essential for visual
	effects that create many temporary instances.
]]

local Pool = {}
Pool.__index = Pool

--============================================================================--
-- TYPES
--============================================================================--

type PooledItem<T> = {
	instance: T,
	inUse: boolean,
}

type PoolImpl<T> = {
	_items: {PooledItem<T>},
	_factory: () -> T,
	_reset: (T) -> (),
	_maxSize: number,
	_activeCount: number,
}

export type Pool<T> = typeof(setmetatable({} :: PoolImpl<T>, Pool))

--============================================================================--
-- CONSTRUCTOR
--============================================================================--

--- Creates a new object pool.
--- @param factory any Function to create a new object
--- @param reset any Function to reset an object
--- @param initialSize number? Initial pool size (default: 10)
--- @param maxSize number? Maximum pool size (default: 100)
--- @return any
function Pool.new<T>(
	factory: () -> T,
	reset: (T) -> (),
	initialSize: number?,
	maxSize: number?
): Pool<T>
	local self = setmetatable({} :: PoolImpl<T>, Pool)
	
	self._factory = factory
	self._reset = reset
	self._maxSize = maxSize or 100
	self._activeCount = 0
	self._items = {}
	
	-- Pre-allocates the initial objects
	local initSize = initialSize or 10
	for _ = 1, initSize do
		table.insert(self._items, {
			instance = factory(),
			inUse = false,
		})
	end
	
	return self
end

--============================================================================--
-- PUBLIC METHODS
--============================================================================--

--- Retrieves an object from the pool (or creates a new one if necessary).
--- @return any The retrieved object, or nil if the pool is full
function Pool.acquire<T>(self: Pool<T>): T?
	-- Looks for an available object
	for _, item in self._items do
		if not item.inUse then
			item.inUse = true
			self._activeCount += 1
			return item.instance
		end
	end

	-- None available, create a new one if possible
	if #self._items < self._maxSize then
		local newItem: PooledItem<T> = {
			instance = self._factory(),
			inUse = true,
		}
		table.insert(self._items, newItem)
		self._activeCount += 1
		return newItem.instance
	end
	
	-- Pool full
	return nil
end

--- Releases an object back into the pool.
--- @param instance any The object to release
function Pool.release<T>(self: Pool<T>, instance: T): ()
	for _, item in self._items do
		if item.instance == instance and item.inUse then
			item.inUse = false
			self._activeCount -= 1
			self._reset(instance)
			return
		end
	end
end

--- Returns the number of objects currently in use.
--- @return number
function Pool.getActiveCount<T>(self: Pool<T>): number
	return self._activeCount
end

--- Returns the total size of the pool.
--- @return number
function Pool.getSize<T>(self: Pool<T>): number
	return #self._items
end

--- Returns the number of available objects.
--- @return number
function Pool.getAvailableCount<T>(self: Pool<T>): number
	return #self._items - self._activeCount
end

--- Clears the pool and destroys all objects.
--- @param destroy any Optional destruction function
function Pool.clear<T>(self: Pool<T>, destroy: ((T) -> ())?): ()
	for _, item in self._items do
		if destroy then
			destroy(item.instance)
		end
	end
	
	table.clear(self._items)
	self._activeCount = 0
end

--- Shrinks the pool by removing unused objects.
--- @param targetSize number? Target size (default: number of active objects)
--- @param destroy any Optional destruction function
function Pool.shrink<T>(self: Pool<T>, targetSize: number?, destroy: ((T) -> ())?): ()
	local target = targetSize or self._activeCount
	target = math.max(target, self._activeCount)
	
	local i = #self._items
	while i > 0 and #self._items > target do
		local item = self._items[i]
		if not item.inUse then
			if destroy then
				destroy(item.instance)
			end
			table.remove(self._items, i)
		end
		i -= 1
	end
end

return Pool
