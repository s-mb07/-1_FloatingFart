--!strict
--[[
	@module Navigation.PanelTransition
	@description Sequencing of panel transitions for Navigation.Controller.

	Wraps UXEffects.Effects.PanelTransition (blur + zoom, already the
	standard call site for all existing UI) and generalizes
	TradingWindowUIHandler's closeOtherPanelsThen(): close one or more
	panels (animated, popOut) and only call the continuation once ALL are
	closed -- never in parallel/instant, so as not to re-break the timing
	this sequence already protected before the migration (see migration
	plan §9).

	This module ONLY does animation + sequencing: no notion of a stack,
	an "active" panel, or choosing a transition based on Config -- that
	stays with Navigation.Controller (see transitionTypeOf/openPanel/closePanel),
	which reads panel.Config.Transition and decides which primitive to call.
]]

local UXEffects = require(script.Parent.Parent.Libraries.UXEffects)

local PanelTransition = {}

--- Background blur + entrance zoom. `onComplete` called at the end of the zoom.
function PanelTransition.Open(root: GuiObject, onComplete: (() -> ())?): ()
	UXEffects.PanelTransition.open(root, onComplete)
end

--- Background blur + exit zoom. `onComplete` called at the end of the zoom
--- (Visible already reset to false by that point).
function PanelTransition.Close(root: GuiObject, onComplete: (() -> ())?): ()
	UXEffects.PanelTransition.close(root, onComplete)
end

--- Circular entrance reveal (see Config.Transition.Type == "Circular",
--- UXEffects.CircularReveal -- generic disc, content-independent).
--- `UXEffects.CircularReveal.attach` is idempotent: the first call migrates
--- `root`'s content into its Handle, subsequent calls reuse the same one.
--- The Backdrop (background blur) has no dedicated circular equivalent: it
--- stays driven separately by the panel itself (`UXEffects.Backdrop.track`),
--- same as for PlayOpenTransition before this module.
function PanelTransition.OpenCircular(root: GuiObject, onComplete: (() -> ())?): ()
	local handle = UXEffects.CircularReveal.attach(root)
	handle:Open(onComplete)
end

--- Symmetric to OpenCircular on the closing side.
function PanelTransition.CloseCircular(root: GuiObject, onComplete: (() -> ())?): ()
	local handle = UXEffects.CircularReveal.attach(root)
	handle:Close(onComplete)
end

--- Closes each root in `roots` (animated, popOut, in parallel with each
--- other) then calls `onAllClosed` once ALL have finished. This is the
--- A.popOut() -> B.popIn() sequence from TradingWindowUIHandler.closeOtherPanelsThen,
--- generalized to N panels and moved here as a shared primitive.
function PanelTransition.CloseAllThen(roots: { GuiObject }, onAllClosed: () -> ()): ()
	if #roots == 0 then
		onAllClosed()
		return
	end

	local remaining = #roots
	for _, root in ipairs(roots) do
		PanelTransition.Close(root, function()
			remaining -= 1
			if remaining <= 0 then
				onAllClosed()
			end
		end)
	end
end

return PanelTransition
