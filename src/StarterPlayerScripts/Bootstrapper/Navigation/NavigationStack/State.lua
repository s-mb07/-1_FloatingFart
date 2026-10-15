--!strict
--[[
	@module Navigation.NavigationStack.State
	@description Navigation stack: panelId + state snapshot per entry.

	Pure storage, no orchestration here (no Activate/Deactivate/
	Transition calls -- Navigation.Controller decides WHEN, State just
	stores WHAT is stacked below the active panel).

	The active panel itself (the live Controller instance) is NOT stored
	here: only panelId + snapshot are, to stay consistent with the
	"no Instance in a snapshot" rule (see migration plan §8, "Snapshots
	containing Instances"). The live instance of the active panel is kept
	upstream, in Navigation.Controller.
]]

export type StackEntry = {
	panelId: string,
	snapshot: any,
}

local State = {}
State.__index = State

export type NavigationStackState = typeof(setmetatable(
	{} :: { _entries: { StackEntry } },
	State
))

function State.new(): NavigationStackState
	return setmetatable({
		_entries = {},
	}, State) :: any
end

--- Pushes an entry with its snapshot (can be nil for a panel with no state).
function State.Push(self: NavigationStackState, panelId: string, snapshot: any?): ()
	table.insert(self._entries, { panelId = panelId, snapshot = snapshot })
end

--- Removes and returns the top entry (nil if the stack is empty).
function State.Pop(self: NavigationStackState): StackEntry?
	local top = self._entries[#self._entries]
	if top then
		table.remove(self._entries)
	end
	return top
end

--- Returns the top entry without removing it (nil if the stack is empty).
function State.Top(self: NavigationStackState): StackEntry?
	return self._entries[#self._entries]
end

function State.IsEmpty(self: NavigationStackState): boolean
	return #self._entries == 0
end

function State.Size(self: NavigationStackState): number
	return #self._entries
end

--- Updates the top entry's snapshot (called when a panel is moved below
--- another one, without being popped -- it stays "underneath").
function State.UpdateTopSnapshot(self: NavigationStackState, snapshot: any): ()
	local top = self._entries[#self._entries]
	if top then
		top.snapshot = snapshot
	end
end

return State
