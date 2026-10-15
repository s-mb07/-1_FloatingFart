--!strict
--[[
	Hand-rolled test runner for `Libraries/Utils/` -- run via Lune
	(`lune run scripts/test-utils`). No TestEZ, no Roblox place needed: every
	function under test is pure Luau with zero Instance/Roblox-datatype
	dependency, so it can be required and exercised directly outside Studio.

	NOT covered here (need a real Roblox place or @lune/roblox datatype
	emulation this kit doesn't pull in): `Vector.lua`, `Color.lua`
	(Vector3/Color3), `Instance.lua` (a real Instance tree), `Spawn.lua`
	(task scheduling semantics). Exercise those manually in Studio.
	`Guard.lua` is covered only for its non-Instance branches, same reason.

	Requires modules by filesystem path (Lune has no `script` global --
	that's Rojo/Roblox-only), not through the `Utils/init.lua` barrel (which
	does `require(script.X)` and would error outside Rojo).
]]

local process = require("@lune/process")

local Array = require("../src/ReplicatedStorage/Libraries/Utils/Array")
local Dict = require("../src/ReplicatedStorage/Libraries/Utils/Dict")
local Table = require("../src/ReplicatedStorage/Libraries/Utils/Table")
local String = require("../src/ReplicatedStorage/Libraries/Utils/String")
local Math = require("../src/ReplicatedStorage/Libraries/Utils/Math")
local Format = require("../src/ReplicatedStorage/Libraries/Utils/Format")
local Guard = require("../src/ReplicatedStorage/Libraries/Utils/Guard")
local Random = require("../src/ReplicatedStorage/Libraries/Utils/Random")
local RateLimiter = require("../src/ReplicatedStorage/Libraries/Utils/RateLimiter")
local Throttle = require("../src/ReplicatedStorage/Libraries/Utils/Throttle")
local Time = require("../src/ReplicatedStorage/Libraries/Utils/Time")

local failures: { string } = {}
local passCount = 0

local function check(name: string, condition: boolean): ()
	if condition then
		passCount += 1
	else
		table.insert(failures, name)
	end
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Array
check("Array.Find finds a match", Array.Find({ 1, 2, 3 }, function(v) return v == 2 end) == 2)
check("Array.Find returns nil on no match", Array.Find({ 1, 2, 3 }, function(v) return v == 9 end) == nil)
check(
	"Array.Filter keeps only matches",
	deepEqual(Array.Filter({ 1, 2, 3, 4 }, function(v) return v % 2 == 0 end), { 2, 4 })
)

-- Dict
check("Dict.Keys returns all keys", #Dict.Keys({ a = 1, b = 2 }) == 2)
check("Dict.Values returns all values", #Dict.Values({ a = 1, b = 2 }) == 2)

-- Table
check("Table.Merge overrides base with overrides", deepEqual(Table.Merge({ a = 1, b = 2 }, { b = 3 }), { a = 1, b = 3 }))
check("Table.Merge does not mutate base", (function()
	local base = { a = 1 }
	Table.Merge(base, { a = 2 })
	return base.a == 1
end)())
check("Table.DeepCopy copies nested tables", (function()
	local source = { a = { b = 1 } }
	local copy = Table.DeepCopy(source)
	copy.a.b = 2
	return source.a.b == 1 and copy.a.b == 2
end)())

-- String
check("String.Split splits on separator", deepEqual(String.Split("a,b,c", ","), { "a", "b", "c" }))
check("String.Split handles no separator match", deepEqual(String.Split("abc", ","), { "abc" }))
check("String.Trim removes leading/trailing whitespace", String.Trim("  hi  ") == "hi")

-- Math
check("Math.Lerp at alpha=0 returns from", Math.Lerp(0, 10, 0) == 0)
check("Math.Lerp at alpha=1 returns to", Math.Lerp(0, 10, 1) == 10)
check("Math.Lerp at alpha=0.5 returns midpoint", Math.Lerp(0, 10, 0.5) == 5)
check("Math.Round rounds to nearest step", Math.Round(7, 5) == 5)

-- Format
check("Format.Commas adds thousands separators", Format.Commas(1234567) == "1,234,567")
check("Format.Commas handles negatives", Format.Commas(-1234) == "-1,234")
check("Format.Commas handles small numbers", Format.Commas(42) == "42")

-- Guard (non-Instance branches only, see module doc above)
check("Guard.IsPlayer rejects non-Instance values", Guard.IsPlayer(42) == false)
check("Guard.IsPlayer rejects nil", Guard.IsPlayer(nil) == false)
check("Guard.IsFiniteNumber accepts a normal number", Guard.IsFiniteNumber(1.5) == true)
check("Guard.IsFiniteNumber rejects a string", Guard.IsFiniteNumber("1.5") == false)
check("Guard.IsFiniteNumber rejects infinity", Guard.IsFiniteNumber(math.huge) == false)
check("Guard.IsFiniteNumber rejects NaN", Guard.IsFiniteNumber(0 / 0) == false)

-- Random (range/membership checks, not exact values)
check("Random.Range stays within bounds", (function()
	for _ = 1, 20 do
		local n = Random.Range(1, 5)
		if n < 1 or n > 5 then
			return false
		end
	end
	return true
end)())
check("Random.Choice returns a member of the array", (function()
	local array = { "a", "b", "c" }
	local choice = Random.Choice(array)
	return table.find(array, choice) ~= nil
end)())

-- RateLimiter
check("RateLimiter allows up to the limit", (function()
	local limiter = RateLimiter.new(2, 60)
	return limiter:TryConsume() and limiter:TryConsume()
end)())
check("RateLimiter rejects beyond the limit", (function()
	local limiter = RateLimiter.new(1, 60)
	limiter:TryConsume()
	return limiter:TryConsume() == false
end)())

-- Throttle
check("Throttle allows the first call", (function()
	local calls = 0
	local wrapped = Throttle.Wrap(function() calls += 1 end, 60)
	wrapped()
	return calls == 1
end)())
check("Throttle drops calls inside the cooldown window", (function()
	local calls = 0
	local wrapped = Throttle.Wrap(function() calls += 1 end, 60)
	wrapped()
	wrapped()
	return calls == 1
end)())

-- Time
check("Time.FormatSeconds formats under an hour as M:SS", Time.FormatSeconds(65) == "1:05")
check("Time.FormatSeconds formats an hour+ as H:MM:SS", Time.FormatSeconds(3661) == "1:01:01")
check("Time.FormatSeconds clamps negative durations to 0", Time.FormatSeconds(-5) == "0:00")

if #failures > 0 then
	print(`Utils tests FAILED ({#failures}/{passCount + #failures}):`)
	for _, name in failures do
		print("  - " .. name)
	end
	process.exit(1)
end

print(`Utils tests passed ({passCount}/{passCount}).`)
