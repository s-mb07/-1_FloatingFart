--!strict
--[[
	@module UXEffects.Effects.TabRevealSelect
	@description Entrance of a tab's selection background (e.g. container_Selected
	on the Inventory tabs): horizontal reveal, anchored left, Size.X.Scale from 0 to
	1. Animates ONLY Size -- never Position. The target clips itself
	(ClipsDescendants = true, forced once): its content (icon/text/badge)
	is therefore masked progressively at the same rate as the background, not just the
	background alone.

	In the real Inventory tree, `container` and `container_Selected` are two
	SIBLINGS (not parent/child) under the category frame -- `container_Selected`
	therefore cannot be clipped by `container`. The clip happens on the target
	itself, which visually produces the same result (nothing ever exceeds
	the rectangle currently being revealed).

	@usage
	```lua
	local UXEffects = require(Bootstrapper.Libraries.UXEffects)

	UXEffects.TabRevealSelect.play(containerSelected)
	UXEffects.TabRevealSelect.cancel(containerSelected) -- cuts an animation in progress
	```
]]

local TweenService = game:GetService("TweenService")

local TabRevealSelect = {}

--============================================================================--
-- TYPES
--============================================================================--

export type TabRevealSelectConfig = {
	--- Reveal duration, in seconds (default: 0.13 -- snappy, per design request)
	duration: number?,
	--- Called ONLY if the reveal runs to completion (never if interrupted by a
	--- cancel/restart) -- used e.g. to hide the old background only once
	--- the new one is fully revealed, never before.
	onComplete: (() -> ())?,
}

--============================================================================--
-- STATE
--============================================================================--

-- Active tween per target, for clean cancellation before restarting (fast click) --
-- avoids multiple concurrent tweens on the same GuiObject.
local activeTweens: {[GuiObject]: Tween} = {}
-- Rest Size/Position (state "100% revealed"), captured once per
-- target, BEFORE any animation -- serves both as the tween's end value
-- and as a reference to reconstruct the "width 0" state.
local nativeSizes: {[GuiObject]: UDim2} = {}

--============================================================================--
-- PRIVATE
--============================================================================--

local function cancelActive(target: GuiObject): ()
	if activeTweens[target] then
		activeTweens[target]:Cancel()
		activeTweens[target] = nil
	end
end

--- Prepares `target` for a left-anchored reveal: forces ClipsDescendants
--- (masks content during the reveal) and AnchorPoint.X to 0 (the reveal must
--- start from the left edge, never the center/right), correcting Position.X
--- along the way so the visual left edge doesn't move if the original
--- AnchorPoint wasn't already 0. Idempotent, does nothing after the 1st call.
local function ensurePrepared(target: GuiObject): UDim2
	local native = nativeSizes[target]
	if native then
		return native
	end

	target.ClipsDescendants = true

	local anchor = target.AnchorPoint
	if anchor.X ~= 0 then
		local pos = target.Position
		local size = target.Size
		local leftScale = pos.X.Scale - anchor.X * size.X.Scale
		local leftOffset = pos.X.Offset - anchor.X * size.X.Offset
		target.Position = UDim2.new(leftScale, leftOffset, pos.Y.Scale, pos.Y.Offset)
		target.AnchorPoint = Vector2.new(0, anchor.Y)
	end

	nativeSizes[target] = target.Size
	return nativeSizes[target]
end

--============================================================================--
-- PUBLIC
--============================================================================--

--- Plays the reveal: width 0 -> 100% (Size.X only), anchored left.
--- @param target GuiObject  The actual selection background (e.g. container_Selected)
--- @param config TabRevealSelectConfig?
function TabRevealSelect.play(target: GuiObject, config: TabRevealSelectConfig?): ()
	local cfg: TabRevealSelectConfig = config or {}
	local duration = cfg.duration or 0.13

	local nativeSize = ensurePrepared(target)
	cancelActive(target)

	-- Starting state set instantly (outside the tween): width 0, native height.
	target.Size = UDim2.new(0, 0, nativeSize.Y.Scale, nativeSize.Y.Offset)

	local tween = TweenService:Create(
		target,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = nativeSize }
	)
	activeTweens[target] = tween
	tween:Play()
	tween.Completed:Once(function(state: Enum.PlaybackState)
		activeTweens[target] = nil
		-- Fires onComplete ONLY if the tween ran to completion (not on a
		-- Cancel caused by a fast click restarting a new reveal) -- otherwise
		-- the old background would be hidden before the new one is actually at 100%.
		if state == Enum.PlaybackState.Completed and cfg.onComplete then
			cfg.onComplete()
		end
	end)
end

--- Cuts the animation in progress on the target and resets it to its rest state
--- (native Size, 100% revealed). Safe to call even if no animation is in progress.
--- @param target GuiObject
function TabRevealSelect.cancel(target: GuiObject): ()
	cancelActive(target)
	local nativeSize = nativeSizes[target]
	if nativeSize then
		target.Size = nativeSize
	end
end

--- Global cleanup of all animations in progress.
function TabRevealSelect.cleanup(): ()
	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

return TabRevealSelect
