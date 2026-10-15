--!strict
--[[
	@module Navigation.Controller
	@description Orchestrates the navigation stack + transitions, the single
	abstraction for opening/closing a migrated panel.

	Model:
	  Push(id) -> Resolve/Init (1st time) -> closes+(destroys) the active
	  panel if CanStack ~= true, WITHOUT remembering it -> Activate+opens the
	  incoming one.
	  PushChild(id) -> same thing but snapshots+stacks the active panel
	  underneath instead of discarding it -- reserved for panels opening
	  ANOTHER panel from their own interior (e.g. panel A opening Settings).
	  Pop()  -> closes+(destroys) the active panel -> pops the entry below it
	  -> reveals it (Resolve/Init if destroyed, RestoreState, Activate, opens).
	  Nothing stacked (Push() case) => Pop() returns to the bare HUD.

	Only this live "active" instance (a Lua table, never a stack of strings)
	is kept upstream, in `activePanel` -- the NavigationStack only stores
	panelId+snapshot for what's BELOW it.

	KeepAlive: the panel is never destroyed, only Deactivate()'d --
	CaptureState/RestoreState aren't called in that case, the state already
	survives as-is in the instance kept by PanelRegistry.

	CanStack: by default (absent or false), opening a panel closes the
	active panel before activating. CanStack = true is an explicit opt-in
	for a panel that must stay visible/active underneath another one (e.g. a
	panel that opens on top without closing what's beneath it).

	CanGoBack = false: Pop() is refused while this panel is active.

	Signals: EventBus.Navigation.PanelOpened / PanelClosed (panelId) fire
	when a transition STARTS, for feedback that must line up with it.
]]

local EventBus = require(script.Parent.Parent.Events.EventBus)
local PanelRegistry = require(script.Parent.PanelRegistry)
local PanelTransition = require(script.Parent.PanelTransition)
local NavigationStackState = require(script.Parent.NavigationStack.State)

local NavigationController = {}

local stack = NavigationStackState.new()

-- Live Controller instance of the panel currently active (logical top of
-- the stack). nil when no migrated panel is open.
local activePanel: any = nil

-- Panels already Init()'d -- weak-keyed so a destroyed (non-KeepAlive)
-- panel isn't retained after it's been garbage-collected.
local initializedPanels: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function buildDependencies(): { EventBus: any, Navigation: any }
	return {
		EventBus = EventBus,
		Navigation = NavigationController,
	}
end

local function ensureInitialized(panel: any): ()
	if not initializedPanels[panel] then
		panel:Init(buildDependencies())
		initializedPanels[panel] = true
	end
end

local function navConfigOf(panel: any): { CanStack: boolean?, CanGoBack: boolean?, KeepAlive: boolean? }?
	local config = panel.Config
	return config and config.Navigation
end

local function resolveRoot(panelId: string, panel: any): GuiObject
	return assert(
		panel.Root,
		("Navigation.Controller: panel '%s' has no Root after Init()"):format(panelId)
	) :: GuiObject
end

--- Destroys `panel` unless it's KeepAlive (only Deactivate() in that case).
local function finalizeDeactivated(panel: any): ()
	local navConfig = navConfigOf(panel)
	local keepAlive = navConfig ~= nil and navConfig.KeepAlive == true
	if not keepAlive then
		panel:Destroy()
		initializedPanels[panel] = nil
	end
end

--- Resolves, (re)initializes, restores state, and activates the entry below
--- the top of the stack after a Pop() has closed the panel that was above it.
--- Does nothing if the stack is empty (return to the bare HUD, no active panel).
local function revealPreviousFromStack(): ()
	local entry = stack:Pop()
	if not entry then
		activePanel = nil
		return
	end

	local panel = PanelRegistry.Resolve(entry.panelId)
	ensureInitialized(panel)
	if entry.snapshot ~= nil and panel.RestoreState then
		panel:RestoreState(entry.snapshot)
	end

	activePanel = panel
	panel:Activate()
	EventBus.Navigation.PanelOpened:Fire(entry.panelId)
	PanelTransition.Open(resolveRoot(entry.panelId, panel))
end

--- Common core of Push/PushChild. `remember` distinguishes the two: see
--- their respective docs for which to pick at a given call site.
local function performPush(panelId: string, remember: boolean): ()
	if activePanel and activePanel._panelId == panelId then
		return -- already active, no-op
	end

	local incoming = PanelRegistry.Resolve(panelId)
	incoming._panelId = panelId
	ensureInitialized(incoming)

	local incomingNav = navConfigOf(incoming)
	local canStack = incomingNav ~= nil and incomingNav.CanStack == true

	local function activateIncoming()
		-- Root first: a panel whose UI never resolved must not become the
		-- active panel, or every later Push dies trying to close it.
		local root = resolveRoot(panelId, incoming)
		activePanel = incoming
		incoming:Activate()
		EventBus.Navigation.PanelOpened:Fire(panelId)
		PanelTransition.Open(root)
	end

	local previous = activePanel
	if previous and not canStack then
		if remember then
			local snapshot = if previous.CaptureState then previous:CaptureState() else nil
			stack:Push(previous._panelId, snapshot)
		else
			-- Top-level opening (HUD button, proximity, global keybind,
			-- server event...): NOT a panel-to-panel navigation, so nothing
			-- gets remembered -- and whatever was already stacked below also
			-- gets discarded. Without this reset, a top-level Push done
			-- AFTER a PushChild would leave the old parent's stack lingering
			-- beneath the new top-level panel.
			stack = NavigationStackState.new()
		end

		previous:Deactivate()
		EventBus.Navigation.PanelClosed:Fire(previous._panelId)
		PanelTransition.CloseAllThen({ resolveRoot(previous._panelId, previous) }, function()
			finalizeDeactivated(previous)
			activateIncoming()
		end)
	else
		activateIncoming()
	end
end

--- Opens `panelId` as a NEW top-level entry point (HUD button, proximity,
--- global keybind, server event...). Closes the active panel WITHOUT
--- remembering it: Pop() on `panelId` therefore reveals nothing, direct
--- return to the bare HUD -- intended behavior for a HUD switch (no
--- stacking when switching panels from the outside). Use for any caller
--- that is NOT itself an already-open panel.
function NavigationController.Push(panelId: string): ()
	performPush(panelId, false)
end

--- Opens `panelId` as a CHILD panel of the active panel (e.g. a panel A
--- opening Settings from its own "settings" button): remembers the active
--- panel so Pop() returns to it afterward. Reserve for openings triggered
--- from INSIDE an already-open panel -- any external opening (HUD,
--- proximity, keybind, server event) must go through Push(), not PushChild().
function NavigationController.PushChild(panelId: string): ()
	performPush(panelId, true)
end

--- Closes the active panel and reveals the one below it (if any).
--- No-op if no panel is active, or if the active panel has
--- Config.Navigation.CanGoBack = false.
function NavigationController.Pop(): ()
	local current = activePanel
	if not current then
		return
	end

	local currentNav = navConfigOf(current)
	if currentNav ~= nil and currentNav.CanGoBack == false then
		warn(("Navigation.Controller: Pop() refused, '%s' has CanGoBack = false"):format(current._panelId))
		return
	end

	current:Deactivate()
	EventBus.Navigation.PanelClosed:Fire(current._panelId)
	PanelTransition.CloseAllThen({ resolveRoot(current._panelId, current) }, function()
		finalizeDeactivated(current)
		revealPreviousFromStack()
	end)
end

--- Immediately closes ALL navigation (active panel + the entire stack
--- below it), without reactivating anything -- unlike Pop(), which always
--- reveals what's below. Useful for a Shift+P / FreeCam-style shortcut
--- that needs to clear the UI all at once, not navigate back one step at a
--- time. Entries BELOW the active panel need no Deactivate/Destroy: they
--- were already deactivated/destroyed at the moment Push() stacked them
--- (cf. finalizeDeactivated above) -- only the storage needs clearing.
--- No-op (with warn) if the active panel has Config.Navigation.CanGoBack =
--- false, same refusal semantics as Pop().
function NavigationController.CloseAll(): ()
	local current = activePanel
	if current then
		local currentNav = navConfigOf(current)
		if currentNav ~= nil and currentNav.CanGoBack == false then
			warn(("Navigation.Controller: CloseAll() could not close '%s' (CanGoBack = false)."):format(current._panelId))
			return
		end

		activePanel = nil
		current:Deactivate()
		EventBus.Navigation.PanelClosed:Fire(current._panelId)
		PanelTransition.CloseAllThen({ resolveRoot(current._panelId, current) }, function()
			finalizeDeactivated(current)
		end)
	end

	stack = NavigationStackState.new()
end

--- panelId of the currently active panel, or nil if no migrated panel is
--- open. Read-only: debug/diagnostics, and ProbeController refuses a launch
--- while any panel is open.
function NavigationController.GetActivePanelId(): string?
	return activePanel and activePanel._panelId
end

--- Forces Resolve+Init of `panelId` NOW, without activating it. Necessary
--- for any panel whose FIRST Push() doesn't come from an independently
--- wired HUD button (cf. Panels/init.lua's registerPanel) but from a
--- trigger the panel sets up itself INSIDE its own Init() (pad/zone
--- proximity detection, EventBus listener for a server event, global
--- keybind): without this call, Init() would NEVER run -- Push() is only
--- called from THAT trigger, itself set up BY Init().
--- Goes through the same path (ensureInitialized) as Push()/revealPreviousFromStack
--- so `initializedPanels` tracking stays consistent -- a later Push()
--- therefore does NOT reinitialize a second time.
function NavigationController.Prewarm(panelId: string): ()
	local panel = PanelRegistry.Resolve(panelId)
	panel._panelId = panelId
	ensureInitialized(panel)
end

return NavigationController
