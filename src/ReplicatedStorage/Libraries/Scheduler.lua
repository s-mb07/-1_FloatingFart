--!strict
--[[
	@module Scheduler
	@description A SINGLE Heartbeat connection for all periodic tasks. Each
	task declares its frequency; the scheduler automatically spreads the
	phases so that two tasks never fall on the same frame.

	Why: the `if now - last >= INTERVAL then` idiom copy-pasted into every
	controller that needs to run at a regular interval (proximity,
	collection, decorative effects, PadTrigger...) has two flaws.
	1. Each copy keeps its own Heartbeat connection, so the engine pays for
	   N signal dispatches per frame to do nothing most of the time.
	2. All copies start at boot with `last = 0`, so all tasks of the same
	   frequency fire ON THE SAME FRAME, over and over -- which is exactly
	   what produces a periodic spike instead of a smoothed-out cost.

	Here: one connection, and the starting phase is drawn from a golden-ratio
	sequence (low discrepancy) to spread tasks as evenly as possible within
	their interval.

	Usage:
		local handle = Scheduler.Every("MyController_ZoneScan", 10, updateZoneScan)
		handle:Disconnect()

	`Scheduler.Report()` prints the real cost per task (callable from the
	Studio console) -- use it to find a culprit instead of guessing.
]]

local RunService = game:GetService("RunService")

local Scheduler = {}

--============================================================================--
-- TYPES
--============================================================================--

export type Handle = {
	Disconnect: (Handle) -> (),
}

type Task = {
	Name: string,
	-- Cadence requested by the caller. `Interval` is derived from it via the
	-- global quality multiplier (cf. SetCosmeticRateScale).
	BaseInterval: number,
	Cosmetic: boolean,
	Interval: number,
	NextRun: number,
	Fn: (number) -> (),
	LastRan: number,
	Alive: boolean,
	Enabled: boolean,
	Calls: number,
	TotalTime: number,
	MaxTime: number,
}

--============================================================================--
-- CONSTANTS
--============================================================================--

-- Golden ratio conjugate: the sequence (i * GOLDEN) % 1 fills [0,1[ more
-- evenly than any rational step, regardless of how many tasks are
-- registered (no need to know N in advance).
local GOLDEN = 0.6180339887498949

--============================================================================--
-- STATE
--============================================================================--

local tasks: { Task } = {}
local connection: RBXScriptConnection? = nil
local phaseIndex = 0
-- Rate multiplier for COSMETIC tasks only, driven by QualityController.
-- 1 = requested cadence. Gameplay tasks (proximity, harvesting, countdown)
-- ignore it: lowering graphics quality must never make the game feel less
-- responsive.
local cosmeticRateScale = 1

--============================================================================--
-- PRIVATE
--============================================================================--

local function step(): ()
	local now = os.clock()

	for i = #tasks, 1, -1 do
		local task_ = tasks[i]

		if not task_.Alive then
			local last = #tasks
			tasks[i] = tasks[last]
			tasks[last] = nil
			continue
		end

		if not task_.Enabled or now < task_.NextRun then
			continue
		end

		local dt = now - task_.LastRan
		task_.LastRan = now
		-- Rescheduled from NOW, not from NextRun: a long frame must not
		-- produce a burst catch-up (spiral of death).
		task_.NextRun = now + task_.Interval

		debug.profilebegin(task_.Name)
		local ok, err = pcall(task_.Fn, dt)
		debug.profileend()

		local elapsed = os.clock() - now
		task_.Calls += 1
		task_.TotalTime += elapsed
		if elapsed > task_.MaxTime then
			task_.MaxTime = elapsed
		end

		if not ok then
			warn(string.format("[Scheduler] ❌ Task '%s': %s", task_.Name, tostring(err)))
			task_.Alive = false
		end
	end
end

local function ensureRunning(): ()
	if connection then return end
	connection = RunService.Heartbeat:Connect(step)
end

--============================================================================--
-- PUBLIC API
--============================================================================--

--- Registers `fn` to run `hz` times per second.
--- @param name string Readable name (used as MicroProfiler label + in Report)
--- @param hz number Frequency in Hz (10 = 10 calls/second)
--- @param fn function Receives the actual delta elapsed since its last call
--- @param cosmetic boolean? `true` = purely visual, so subject to the
---   graphics quality multiplier. Defaults to `false` (gameplay, guaranteed
---   cadence).
--- @return Handle
function Scheduler.Every(name: string, hz: number, fn: (number) -> (), cosmetic: boolean?): Handle
	assert(hz > 0, "[Scheduler] hz must be > 0")

	local baseInterval = 1 / hz
	local isCosmetic = cosmetic == true
	local interval = isCosmetic and (baseInterval / cosmeticRateScale) or baseInterval
	local now = os.clock()

	-- Phase offset: the task doesn't start right away but somewhere within
	-- its first interval, so it doesn't align with the others.
	local offset = ((phaseIndex * GOLDEN) % 1) * interval
	phaseIndex += 1

	local task_: Task = {
		Name = name,
		BaseInterval = baseInterval,
		Cosmetic = isCosmetic,
		Interval = interval,
		NextRun = now + offset,
		Fn = fn,
		LastRan = now,
		Alive = true,
		Enabled = true,
		Calls = 0,
		TotalTime = 0,
		MaxTime = 0,
	}

	table.insert(tasks, task_)
	ensureRunning()

	local handle = {}
	function handle:Disconnect(): ()
		task_.Alive = false
	end
	return (handle :: any) :: Handle
end

export type Stat = {
	Name: string,
	Hz: number,
	Calls: number,
	AvgMs: number,
	MaxMs: number,
	TotalMs: number,
}

--- Snapshot of live tasks, sorted by descending total time.
--- Used by `Report()` (console) and by the Admin Panel's Perf tab
--- (in-game display) -- a single source so the sort/format never gets duplicated.
function Scheduler.GetStats(): { Stat }
	local sorted = table.clone(tasks)
	table.sort(sorted, function(a, b)
		return a.TotalTime > b.TotalTime
	end)

	local stats = {}
	for _, task_ in ipairs(sorted) do
		local avg = task_.Calls > 0 and (task_.TotalTime / task_.Calls) or 0
		table.insert(stats, {
			Name = task_.Name,
			Hz = 1 / task_.Interval,
			Calls = task_.Calls,
			AvgMs = avg * 1000,
			MaxMs = task_.MaxTime * 1000,
			TotalMs = task_.TotalTime * 1000,
		})
	end
	return stats
end

--- Prints the measured cost of each task, sorted by total time.
--- Call from the Studio console to identify a culprit.
function Scheduler.Report(): ()
	print("[Scheduler] ---- cost per task ----")
	for _, stat in ipairs(Scheduler.GetStats()) do
		print(string.format(
			"  %-40s %5.1f Hz | %6d calls | avg %6.3f ms | max %6.3f ms | total %7.1f ms",
			stat.Name,
			stat.Hz,
			stat.Calls,
			stat.AvgMs,
			stat.MaxMs,
			stat.TotalMs
		))
	end
end

--- Applies a global rate multiplier to already-registered cosmetic tasks
--- AND to ones registered afterward. `1` = nominal cadence,
--- `0.5` = half as often.
--- @param scale number
function Scheduler.SetCosmeticRateScale(scale: number): ()
	assert(scale > 0, "[Scheduler] scale must be > 0")
	if scale == cosmeticRateScale then return end
	cosmeticRateScale = scale

	local now = os.clock()
	for _, task_ in ipairs(tasks) do
		if not task_.Cosmetic then continue end
		task_.Interval = task_.BaseInterval / scale
		-- Reschedules from now: lengthening the interval must not make the
		-- task wait for the old NextRun AND THEN the new one.
		task_.NextRun = now + task_.Interval
	end
end

--- Resets Report()'s counters to zero (to measure a specific window).
function Scheduler.ResetStats(): ()
	for _, task_ in ipairs(tasks) do
		task_.Calls = 0
		task_.TotalTime = 0
		task_.MaxTime = 0
	end
end

--- Enables/disables a task by name -- a live A/B bisection tool.
--- @return boolean true if the task was found
function Scheduler.SetEnabled(name: string, enabled: boolean): boolean
	for _, task_ in ipairs(tasks) do
		if task_.Name == name then
			task_.Enabled = enabled
			return true
		end
	end
	return false
end

return Scheduler
