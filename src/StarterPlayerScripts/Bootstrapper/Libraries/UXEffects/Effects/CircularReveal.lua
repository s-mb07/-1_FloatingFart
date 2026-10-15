--!strict
--[[
	@module UXEffects.Effects.CircularReveal
	@description Generic circular reveal for opening/closing a panel: a disc
	(CanvasGroup + UICorner 0.5 scale) grows from the center of `root` until
	it fully reveals it, then shrinks back on close. Fully agnostic of the
	CONTENT it reveals -- no notion of Skill Tree, inventory, or anything else
	in here, per the request "the animation must be reusable on other panels".

	ROBLOX CONSTRAINT (why this module can't just be a simple overlay layer):
	there is no non-hierarchical masking. `ClipsDescendants` and `CanvasGroup`
	only clip their OWN descendants -- a mask can therefore only "reveal"
	content by becoming its ANCESTOR. This module can't avoid that, but it
	cancels out the side effects: the mask (RevealMask) grows with a size in
	OFFSET that's completely disconnected from `root`, which would shift/resize
	any Scale-positioned child if it lived directly inside it (cf. observed bug:
	InfoPanel shifted, Pattern stretched to the disc's size instead of the
	panel's). The workaround: a `Content` Frame, a child of the mask, whose
	Size in OFFSET is explicitly kept equal to `root.AbsoluteSize` at all times
	(not Scale) -- everything living in Content therefore resolves EXACTLY as
	if it had stayed a direct child of `root`, regardless of the disc's size at
	instant T. `root` itself is never moved (keeps its original Studio
	Parent/Size/Position) -- essential if another system addresses `root` or
	its descendants via an absolute path.

	The visual background (BackgroundColor3/Transparency/Border + decorators
	like UIGradient) belonged to `root` before attaching: it's transferred onto
	`Content` (NOT onto the mask -- an earlier attempt painted the background
	directly on the mask, a giant disc, which tinted the whole revealed surface
	instead of just the panel's rectangle, cf. post-mortem).

	OPTIMIZATION + SHARPNESS: a CanvasGroup composites its children into an
	intermediate texture every frame -- cost proportional to surface area, PLUS
	a slight softening of the rendering (text/images a bit less crisp than
	rendered directly) even once the disc is fully open. Once the opening
	completes, `Content` is therefore pulled OUT of the mask and reparented
	directly under `root` (native rendering, no more CanvasGroup at all while
	the panel stays open) -- the mask, now empty, is detached (`Parent = nil`).
	Closing reinserts Content into the mask and restores its full circular
	shape BEFORE animating.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CircularReveal = {}

--============================================================================--
-- CONSTANTS
--============================================================================--

local MASK_NAME = "RevealMask"
local CONTENT_NAME = "Content"
-- Diameter = Content's diagonal (covers all 4 corners regardless of its
-- ratio) + this margin, otherwise the disc's rounded edges still crop
-- Content on the very last frame of the opening.
local DEFAULT_MARGIN = 1.05
-- Quint/Out: sharp start, soft landing (polished entrance). Quint/In reversed
-- for the exit (fast and crisp) -- standard UX rule. No Back/Out: the
-- overshoot would pull the disc's edges back in after passing them
-- (visible flash on a mask).
local DEFAULT_OPEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DEFAULT_CLOSE_INFO = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

--============================================================================--
-- TYPES
--============================================================================--

export type Options = {
	-- Children of `root` that stay DIRECT children of `root` (persistent
	-- chrome, never moved into the mask/Content) -- e.g. a close button, or
	-- any element another system addresses via an absolute path going
	-- through `root`.
	Exclude: {[string]: boolean}?,
	Margin: number?,
	OpenTweenInfo: TweenInfo?,
	CloseTweenInfo: TweenInfo?,
	-- Among the children listed in `Exclude` (so already placed above the
	-- mask, never moved into it), which ones to hide until the disc has
	-- finished revealing `root`, hidden again as soon as closing starts --
	-- cf. request "the mask must not interfere". Absent here (or false) =
	-- stays visible AT ALL TIMES, including throughout the whole animation --
	-- cf. request "the HUD top bar (the currencies) must stay visible even
	-- during the animation", whereas a simple Exit button can stay hidden
	-- while the panel is being revealed.
	HideWhileClosed: {[string]: boolean}?,
}

export type Handle = {
	Root: GuiObject,
	Mask: CanvasGroup,
	-- Root to use as the parent by any code that builds/reads UI for this
	-- panel (canvas, info panels generated in Lua, Studio path resolution...)
	-- -- NOT `Root` directly, its actual content has been moved here.
	Content: Frame,
	Open: (self: Handle, onComplete: (() -> ())?) -> (),
	Close: (self: Handle, onComplete: (() -> ())?) -> (),
	-- Restores the original hierarchy (debug/tests) -- not used in normal
	-- operation, a migrated panel lives with its Handle for good.
	Detach: (self: Handle) -> (),
}

type Stage = "closed" | "opening" | "open" | "closing"

type HandleInternal = Handle & {
	Corner: UICorner,
	_hideableInstances: {GuiObject},
	_margin: number,
	_openInfo: TweenInfo,
	_closeInfo: TweenInfo,
	_diameter: number,
	_tween: Tween?,
	_stage: Stage,
	_sizeConn: RBXScriptConnection?,
}

--============================================================================--
-- STATE
--============================================================================--

-- A single Handle per root -- re-attaching is a no-op that returns the
-- existing Handle (cf. PanelTransition.OpenCircular, called on every open).
-- Weak key: no leak if `root` is destroyed without going through Detach().
local handles: {[GuiObject]: HandleInternal} = setmetatable({}, { __mode = "k" }) :: any

--============================================================================--
-- PRIVATE
--============================================================================--

local function computeDiameter(size: Vector2, margin: number): number
	if size.X <= 0 or size.Y <= 0 then
		return 0
	end
	return math.ceil(math.sqrt(size.X * size.X + size.Y * size.Y) * margin)
end

--- Keeps Content.Size == Root.AbsoluteSize (cf. module doc) and recomputes
--- the target diameter for the next animation. In the "open" regime, Content
--- isn't even inside the mask anymore (cf. Open below) -- nothing else to
--- do here, the Frame follows its parent (`root`) like any other normal
--- child.
local function applyContentSize(handle: HandleInternal): ()
	local size = handle.Root.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	handle.Content.Size = UDim2.fromOffset(size.X, size.Y)
	handle._diameter = computeDiameter(size, handle._margin)
end

local function cancelTween(handle: HandleInternal): ()
	if handle._tween then
		handle._tween:Cancel()
		handle._tween = nil
	end
end

--- Only affects the instances listed in `options.HideWhileClosed` (already
--- filtered at attach time, cf. `_hideableInstances`) -- a no-op if that list
--- is empty (nothing to hide, cf. Options.HideWhileClosed doc).
local function setHideableVisible(handle: HandleInternal, visible: boolean): ()
	for _, inst in ipairs(handle._hideableInstances) do
		inst.Visible = visible
	end
end

--- Opens the disc: 0 -> diameter. `onComplete` called once the panel is
--- fully revealed (state "open", mask already flattened).
local function open(self: Handle, onComplete: (() -> ())?): ()
	local handle = self :: HandleInternal
	cancelTween(handle)

	handle.Root.Visible = true
	handle._stage = "opening"
	-- Always restarts from a closed AND round disc: after an Open->Close
	-- cycle, the mask may have been flattened (CornerRadius 0) -- without
	-- this reset, reopening would start from a solid rectangle instead of a point.
	handle.Corner.CornerRadius = UDim.new(0.5, 0)
	handle.Mask.Size = UDim2.fromOffset(0, 0)

	task.spawn(function()
		-- Root's AbsoluteSize isn't necessarily up to date the instant
		-- Visible flips (layout recalculated the next frame) -- let the
		-- layout settle before measuring.
		RunService.Heartbeat:Wait()
		if handle._stage ~= "opening" then
			return -- Close() (or a new Open()) has already taken over
		end

		applyContentSize(handle)
		local diameter = handle._diameter
		if diameter <= 0 then
			-- Root still has no usable size (e.g. ScreenGui hidden by
			-- something else) -- no tween possible, jump straight to the
			-- open state rather than blocking indefinitely.
			handle._stage = "open"
			handle.Content.Parent = handle.Root
			handle.Mask.Parent = nil
			setHideableVisible(handle, true)
			if onComplete then
				onComplete()
			end
			return
		end

		local tween = TweenService:Create(handle.Mask, handle._openInfo, {
			Size = UDim2.fromOffset(diameter, diameter),
		})
		handle._tween = tween
		tween:Play()
		tween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Cancelled then
				return
			end
			handle._tween = nil
			handle._stage = "open"

			-- Pulls Content out of the mask -- direct native rendering under
			-- `root`, no more CanvasGroup on the render path while the panel
			-- stays open (cf. module doc, OPTIMIZATION + SHARPNESS section).
			-- The mask, now empty, is detached from the tree (not destroyed --
			-- reused as-is on the next close).
			handle.Content.Parent = handle.Root
			handle.Mask.Parent = nil

			setHideableVisible(handle, true)
			if onComplete then
				onComplete()
			end
		end)
	end)
end

--- Closes the disc: diameter -> 0. `onComplete` called once fully
--- closed (Root.Visible already reset to false).
local function close(self: Handle, onComplete: (() -> ())?): ()
	local handle = self :: HandleInternal
	cancelTween(handle)
	handle._stage = "closing"
	setHideableVisible(handle, false)

	-- Reinserts Content into the mask and the mask into `root` (both were
	-- pulled out at the end of the opening, cf. Open()) then restores the
	-- full circular shape -- BEFORE animating, otherwise we'd be shrinking a
	-- plain rectangle (CornerRadius 0) instead of a disc. An instant jump
	-- from mask->diameter is invisible: the mask stays transparent, Content
	-- (smaller) never overflows the enlarged circle (cf. diagonal margin).
	handle.Mask.Parent = handle.Root
	handle.Content.Parent = handle.Mask

	local size = handle.Root.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		handle._diameter = computeDiameter(size, handle._margin)
	end
	handle.Corner.CornerRadius = UDim.new(0.5, 0)
	local diameter = handle._diameter
	if diameter > 0 then
		handle.Mask.Size = UDim2.fromOffset(diameter, diameter)
	end

	local tween = TweenService:Create(handle.Mask, handle._closeInfo, {
		Size = UDim2.fromOffset(0, 0),
	})
	handle._tween = tween
	tween:Play()
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Cancelled then
			return
		end
		handle._tween = nil
		handle._stage = "closed"
		handle.Root.Visible = false
		if onComplete then
			onComplete()
		end
	end)
end

--- Restores the original hierarchy: reattaches Content's children onto
--- Root, reapplies the background, destroys the mask. Not used in normal
--- operation (cf. Detach field doc).
local function detach(self: Handle): ()
	local handle = self :: HandleInternal
	if handle._sizeConn then
		handle._sizeConn:Disconnect()
		handle._sizeConn = nil
	end
	cancelTween(handle)

	local root = handle.Root
	root.BackgroundColor3 = handle.Content.BackgroundColor3
	root.BackgroundTransparency = handle.Content.BackgroundTransparency
	root.BorderSizePixel = handle.Content.BorderSizePixel
	root.BorderColor3 = handle.Content.BorderColor3

	for _, child in ipairs(handle.Content:GetChildren()) do
		child.Parent = root
	end

	-- Content may be parented directly under `root` ("open" regime, cf.
	-- Open()) or under the mask (any other regime) -- explicitly destroyed
	-- in both cases rather than relying on Mask:Destroy() to take it down
	-- with it.
	handle.Content:Destroy()
	handle.Mask:Destroy()
	handles[root] = nil
end

--============================================================================--
-- PUBLIC
--============================================================================--

--- Attaches the circular reveal to `root` (idempotent -- calling again
--- returns the already-created Handle). Moves all of `root`'s content
--- (except `options.Exclude`) into `Handle.Content` -- use THIS Frame as the
--- parent for everything that should be revealed by the disc, `root` itself
--- stays a pure positioning shell, never moved.
function CircularReveal.attach(root: GuiObject, options: Options?): Handle
	local existing = handles[root]
	if existing then
		return existing
	end

	local opts = options or {}
	local exclude = opts.Exclude or {}
	local margin = opts.Margin or DEFAULT_MARGIN
	local openInfo = opts.OpenTweenInfo or DEFAULT_OPEN_INFO
	local closeInfo = opts.CloseTweenInfo or DEFAULT_CLOSE_INFO
	local hideWhileClosed = opts.HideWhileClosed or {}

	-- The disc always overflows Content (diagonal margin) -- without this
	-- clip, it would also overflow `root`'s own visual rectangle.
	root.ClipsDescendants = true

	local mask = Instance.new("CanvasGroup")
	mask.Name = MASK_NAME
	mask.AnchorPoint = Vector2.new(0.5, 0.5)
	mask.Position = UDim2.fromScale(0.5, 0.5)
	mask.Size = UDim2.fromOffset(0, 0)
	mask.BackgroundTransparency = 1
	mask.BorderSizePixel = 0
	mask.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.Name = "RevealCorner"
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mask

	local content = Instance.new("Frame")
	content.Name = CONTENT_NAME
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(root.AbsoluteSize.X, root.AbsoluteSize.Y)
	-- `root`'s background (+ its UIGradient/UICorner/UIStroke decorators,
	-- moved below along with the rest) IS the panel's visual background --
	-- transferred here, NOT left on the mask (cf. module doc) nor on `root`
	-- (made transparent right after so it's never painted twice).
	content.BackgroundColor3 = root.BackgroundColor3
	content.BackgroundTransparency = root.BackgroundTransparency
	content.BorderSizePixel = root.BorderSizePixel
	content.BorderColor3 = root.BorderColor3

	local hideableInstances: {GuiObject} = {}
	for _, child in ipairs(root:GetChildren()) do
		if exclude[child.Name] then
			if child:IsA("GuiObject") and hideWhileClosed[child.Name] then
				table.insert(hideableInstances, child)
			end
		else
			child.Parent = content
		end
	end
	root.BackgroundTransparency = 1

	content.Parent = mask
	mask.Parent = root

	local handle: HandleInternal = {
		Root = root,
		Mask = mask,
		Content = content,
		Corner = corner,
		Open = open,
		Close = close,
		Detach = detach,
		_hideableInstances = hideableInstances,
		_margin = margin,
		_openInfo = openInfo,
		_closeInfo = closeInfo,
		_diameter = 0,
		_tween = nil,
		_stage = "closed",
		_sizeConn = nil,
	}

	setHideableVisible(handle, false)

	handle._sizeConn = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyContentSize(handle)
	end)
	applyContentSize(handle)

	handles[root] = handle
	return handle
end

return CircularReveal
