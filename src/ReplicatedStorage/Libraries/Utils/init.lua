--!strict
--[[
	@module Utils
	Barrel module re-exporting every generic, pure-function helper under
	`Libraries/Utils`. Sibling top-level `Libraries/` modules (NumberUtil,
	Debounce, Signal, Scheduler...) stay where they are and are NOT
	re-exported here -- this barrel is scoped to the small stateless helpers
	that don't warrant their own top-level require path.

	Usage:
	  local Utils = require(ReplicatedStorage.Libraries.Utils)
	  Utils.Table.Merge(a, b)
	  Utils.Array.Find(items, predicate)
]]

local Utils = {
	Array = require(script.Array),
	Dict = require(script.Dict),
	Table = require(script.Table),
	String = require(script.String),
	Math = require(script.Math),
	Vector = require(script.Vector),
	Color = require(script.Color),
	Format = require(script.Format),
	Guard = require(script.Guard),
	Random = require(script.Random),
	RateLimiter = require(script.RateLimiter),
	Spawn = require(script.Spawn),
	Throttle = require(script.Throttle),
	Instance = require(script.Instance),
	Time = require(script.Time),
}

return Utils
