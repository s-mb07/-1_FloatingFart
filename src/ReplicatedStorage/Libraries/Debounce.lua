--!strict
--[[
	@module Debounce
	@description Trailing-edge debounce/throttle for UI event handlers (search
	boxes, filters). Coalesces bursts of calls (e.g. one per keystroke) into a
	single call `delaySeconds` after the last one, so expensive rebuild/filter
	work runs once per pause instead of once per event.
]]

local Debounce = {}

export type Debounced<T...> = {
	Call: (self: Debounced<T...>, T...) -> (),
	Cancel: (self: Debounced<T...>) -> (),
	Flush: (self: Debounced<T...>) -> (),
}

--- Wraps `fn` so bursts of `:Call(...)` collapse into one trailing call,
--- `delaySeconds` after the last one. Latest args win.
function Debounce.new<T...>(fn: (T...) -> (), delaySeconds: number): Debounced<T...>
	local pendingArgs: {any}?, pendingCount = nil, 0
	local generation = 0

	local debounced = {} :: Debounced<T...>

	function debounced:Cancel(): ()
		generation += 1
		pendingArgs = nil
	end

	function debounced:Call(...: T...): ()
		generation += 1
		local myGeneration = generation
		pendingArgs = table.pack(...)
		pendingCount = pendingArgs.n

		task.delay(delaySeconds, function()
			if myGeneration ~= generation then
				return -- superseded by a later call
			end
			local args = pendingArgs
			pendingArgs = nil
			if args then
				fn(table.unpack(args, 1, pendingCount))
			end
		end)
	end

	function debounced:Flush(): ()
		if not pendingArgs then
			return
		end
		generation += 1
		local args = pendingArgs
		pendingArgs = nil
		fn(table.unpack(args, 1, pendingCount))
	end

	return debounced
end

--- Convenience one-shot: wraps `fn` directly into a debounced callable
--- (no Cancel/Flush needed by the caller).
function Debounce.wrap<T...>(fn: (T...) -> (), delaySeconds: number): (T...) -> ()
	local debounced = Debounce.new(fn, delaySeconds)
	return function(...: T...)
		debounced:Call(...)
	end
end

return Debounce
