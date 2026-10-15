--!strict
--[[
	@module UIRegistry
	@description Client-side Controller availability registry (future-proof
	             infra). Bootstrapper calls MarkReady(name) after a successful
	             Init(); any module can then WaitFor(name) instead of an ad hoc
	             WaitForChild/retry.

	Not consumed by default -- Controllers can keep their current
	WaitForChild/retry. Migrate case by case, no big-bang.

	WaitFor() has no timeout: if `name` is never MarkReady'd (Init failed or
	never called), the caller stays blocked indefinitely. Acceptable as long as
	nothing uses it yet -- revisit on first real usage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

local UIRegistry = {}

local readySignals: { [string]: any } = {}
local readyState: { [string]: boolean } = {}

local function getSignal(name: string): any
	local signal = readySignals[name]
	if not signal then
		signal = Signal.new()
		readySignals[name] = signal
	end
	return signal
end

--- Marks `name` as ready and unblocks any pending WaitFor(name).
--- Idempotent: a second call for the same name is a no-op.
function UIRegistry.MarkReady(name: string): ()
	if readyState[name] then
		return
	end
	readyState[name] = true
	getSignal(name):Fire()
end

function UIRegistry.IsReady(name: string): boolean
	return readyState[name] == true
end

--- Yields until `name` is MarkReady, or returns immediately if it already is.
function UIRegistry.WaitFor(name: string): ()
	if readyState[name] then
		return
	end
	getSignal(name):Wait()
end

return UIRegistry
