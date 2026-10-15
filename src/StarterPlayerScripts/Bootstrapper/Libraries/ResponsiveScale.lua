--!strict
--[[
	@module ResponsiveScale
	@description Adapts a GuiObject designed for a reference resolution (1920x1080
	by default) to the player's actual screen size, via a UIScale recalculated on every
	ViewportSize change (window resize, mobile rotation, etc.).
]]

local Workspace = game:GetService("Workspace")

local ResponsiveScale = {}

local DEFAULT_REF_RESOLUTION = Vector2.new(1920, 1080)
local DEFAULT_MIN_SCALE = 0.5
local DEFAULT_MAX_SCALE = 1.5

-- Instances already attached -> existing cleanup. Weak key (auto GC if the
-- object is destroyed): avoids stacking multiple ViewportSize listeners on
-- the same instance if Attach gets called again (e.g. re-caching refs on an
-- already-open panel).
local attachedCleanups: {[GuiObject]: () -> ()} = setmetatable({}, { __mode = "k" }) :: any

--- Computes the current scale factor for a given reference resolution.
function ResponsiveScale.ComputeScale(refResolution: Vector2?, minScale: number?, maxScale: number?): number
	local camera = Workspace.CurrentCamera
	local vp = camera and camera.ViewportSize
	if not vp or vp.X < 1 or vp.Y < 1 then
		return 1
	end

	local ref = refResolution or DEFAULT_REF_RESOLUTION
	local s = math.min(vp.X / ref.X, vp.Y / ref.Y)
	return math.clamp(s, minScale or DEFAULT_MIN_SCALE, maxScale or DEFAULT_MAX_SCALE)
end

--- Attaches (or reuses) a UIScale on `guiObject` and keeps it up to date live.
--- @return cleanup function to call if `guiObject` is recycled/destroyed manually.
function ResponsiveScale.Attach(guiObject: GuiObject, refResolution: Vector2?, minScale: number?, maxScale: number?): () -> ()
	local existing = attachedCleanups[guiObject]
	if existing then return existing end

	local uiScale = guiObject:FindFirstChildOfClass("UIScale") :: UIScale?
	if not uiScale then
		local created = Instance.new("UIScale")
		created.Parent = guiObject
		uiScale = created
	end

	local function apply()
		(uiScale :: UIScale).Scale = ResponsiveScale.ComputeScale(refResolution, minScale, maxScale)
	end
	apply()

	local camera = Workspace.CurrentCamera
	local vpConn: RBXScriptConnection? = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)

	local camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if vpConn then
			vpConn:Disconnect()
		end
		camera = Workspace.CurrentCamera
		vpConn = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		apply()
	end)

	local function cleanup()
		if vpConn then
			vpConn:Disconnect()
		end
		camConn:Disconnect()
		attachedCleanups[guiObject] = nil
	end
	attachedCleanups[guiObject] = cleanup

	return cleanup
end

-- Frames already handled by AttachCompactSize -> cleanup.
local compactCleanups: {[GuiObject]: () -> ()} = setmetatable({}, { __mode = "k" }) :: any

--- Viewport height (px) under which a screen counts as "compact" (phones in
--- landscape are ~360-430 px tall).
local COMPACT_HEIGHT = 600

--- Swaps `guiObject.Size` to `compactSize` while the viewport is shorter than
--- COMPACT_HEIGHT, and back to its Studio size otherwise. For panels laid
--- out in screen scale (MainFrame at 50% of the screen is fine on a monitor,
--- unreadable on a phone). Touches Size only -- not UIScale, which the panel
--- open/close transitions own.
--- @return cleanup function
function ResponsiveScale.AttachCompactSize(guiObject: GuiObject, compactSize: UDim2): () -> ()
	local existing = compactCleanups[guiObject]
	if existing then return existing end

	local baseSize = guiObject.Size

	local function apply()
		local camera = Workspace.CurrentCamera
		local vp = camera and camera.ViewportSize
		local compact = vp ~= nil and vp.Y >= 1 and vp.Y < COMPACT_HEIGHT
		guiObject.Size = if compact then compactSize else baseSize
	end
	apply()

	local camera = Workspace.CurrentCamera
	local vpConn: RBXScriptConnection? = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)

	local camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if vpConn then
			vpConn:Disconnect()
		end
		camera = Workspace.CurrentCamera
		vpConn = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		apply()
	end)

	local function cleanup()
		if vpConn then
			vpConn:Disconnect()
		end
		camConn:Disconnect()
		guiObject.Size = baseSize
		compactCleanups[guiObject] = nil
	end
	compactCleanups[guiObject] = cleanup

	return cleanup
end

-- Registry separate from Attach() (attachedCleanups): AttachScrollBar does
-- NOT put a UIScale in place (that would rescale the entire ScrollingFrame's
-- content, not just the bar -- cf. incident: applying Attach() directly on
-- the inventory/settings/etc ScrollingFrames broke their layout). We scale
-- ONLY ScrollBarThickness (a pixel property, never affected by children's
-- UDim Scale) relative to the original thickness set in Studio.
local scrollBarCleanups: {[ScrollingFrame]: () -> ()} = setmetatable({}, { __mode = "k" }) :: any

--- Scales ONLY a ScrollingFrame's ScrollBarThickness according to resolution
--- (same formula as ComputeScale/Attach), without touching the frame's
--- Size/Position or its children -- unlike Attach(), which puts a UIScale in place.
--- @return cleanup function
function ResponsiveScale.AttachScrollBar(scrollingFrame: ScrollingFrame, refResolution: Vector2?, minScale: number?, maxScale: number?): () -> ()
	local existing = scrollBarCleanups[scrollingFrame]
	if existing then return existing end

	local baseThickness = scrollingFrame.ScrollBarThickness

	local function apply()
		local scale = ResponsiveScale.ComputeScale(refResolution, minScale, maxScale)
		-- Luau has no math.round (only math.floor/math.ceil): manual
		-- rounding to the nearest integer.
		scrollingFrame.ScrollBarThickness = math.max(1, math.floor(baseThickness * scale + 0.5))
	end
	apply()

	local camera = Workspace.CurrentCamera
	local vpConn: RBXScriptConnection? = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)

	local camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if vpConn then
			vpConn:Disconnect()
		end
		camera = Workspace.CurrentCamera
		vpConn = camera and camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		apply()
	end)

	local function cleanup()
		if vpConn then
			vpConn:Disconnect()
		end
		camConn:Disconnect()
		scrollBarCleanups[scrollingFrame] = nil
	end
	scrollBarCleanups[scrollingFrame] = cleanup

	return cleanup
end

return ResponsiveScale
