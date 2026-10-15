--!strict
--[[
	@module UXEffects.Effects.ButtonFX
	@description Standardized hover/press effects for ImageButtons.

	Attaches the MouseEnter, MouseLeave, MouseButton1Down, MouseButton1Up
	connections onto any ImageButton in a single line.

	Automatically creates a child UIScale if absent.

	@usage
	```lua
	local UXEffects = require(Bootstrapper.Libraries.UXEffects)

	-- Attach the hover/press effects with default values
	UXEffects.ButtonFX.attach(myButton)

	-- With custom config
	UXEffects.ButtonFX.attach(myButton, {
		hoverScale = 1.08,
		pressScale = 0.92,
	})
	```
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ButtonFX = {}

--============================================================================--
-- TYPES
--============================================================================--

export type ButtonFXConfig = {
	--- Scale applied on hover   (default: 1.08)
	hoverScale: number?,
	--- Scale applied on press   (default: 0.95)
	pressScale: number?,
	--- Rest scale                (default: 1.00)
	normalScale: number?,
	--- Hover tween duration (s)  (default: 0.10)
	hoverDuration: number?,
	--- Press tween duration (s)  (default: 0.07)
	pressDuration: number?,
	--- Reset tween duration (s)  (default: 0.13)
	resetDuration: number?,
}

--============================================================================--
-- DEFAULTS
--============================================================================--

local DEFAULTS: ButtonFXConfig = {
	hoverScale    = 1.08,
	pressScale    = 0.95,
	normalScale   = 1.00,
	hoverDuration = 0.10,
	pressDuration = 0.07,
	resetDuration = 0.13,
}

--- Set while a button is held pressed (setPressed): its hover/press FX
--- stop reacting. Same name as ButtonHoverController's opt-out attribute.
local PRESSED_ATTRIBUTE = "NoHoverFX"

--============================================================================--
-- PRIVATE
--============================================================================--

-- Buttons that already have hover/press FX -> their connections. Makes
-- attach() idempotent, so the global ButtonHoverController and per-panel
-- attach() calls never stack. Strong keys (a weak Instance key can vanish
-- while the Instance lives); entries go when the button is destroyed.
local attached: {[GuiButton]: {RBXScriptConnection}} = {}

local function register(button: GuiButton, conns: {RBXScriptConnection}): ()
	if attached[button] == nil then
		button.Destroying:Once(function()
			attached[button] = nil
		end)
	end
	attached[button] = conns
end

--- Drops an earlier attach() on `button` (attachGroup/attachWithPush scale
--- another target and must not stack with a scale on the button itself).
local function release(button: GuiButton): ()
	local previous = attached[button]
	if previous then
		for _, conn in previous do
			conn:Disconnect()
		end
		local uiScale = button:FindFirstChildOfClass("UIScale")
		if uiScale then
			uiScale.Scale = 1
		end
	end
end

local function getOrCreateUIScale(target: GuiObject): UIScale
	return target:FindFirstChildOfClass("UIScale")
		or (function()
			local s = Instance.new("UIScale")
			s.Parent = target
			return s
		end)()
end

--- True when `target` sits in a flex UIListLayout: such items ignore their
--- own UIScale (e.g. MainHUD/LeftHUD, HorizontalFlex = SpaceEvenly).
local function isFlexItem(target: GuiObject): boolean
	local parent = target.Parent
	local layout = parent and parent:FindFirstChildOfClass("UIListLayout")
	return layout ~= nil
		and (layout.HorizontalFlex ~= Enum.UIFlexAlignment.None
			or layout.VerticalFlex ~= Enum.UIFlexAlignment.None)
end

-- Rest Position/Size of each content child scaled by scaleContents.
-- Strong keys, same reason as `attached`; cleared when the child is destroyed.
local restLayouts: {[GuiObject]: {Position: UDim2, Size: UDim2}} = {}

local function scaleUDim(value: UDim, scale: number, pivot: number): UDim
	return UDim.new(pivot + (value.Scale - pivot) * scale, value.Offset * scale)
end

--- Same look as a UIScale on `target`, for flex items: every direct
--- GuiObject child is resized and moved away from the button centre.
local function scaleContents(target: GuiObject, scale: number, duration: number): ()
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, child in target:GetChildren() do
		if not child:IsA("GuiObject") then
			continue
		end
		local rest = restLayouts[child]
		if not rest then
			rest = { Position = child.Position, Size = child.Size }
			restLayouts[child] = rest
			child.Destroying:Once(function()
				restLayouts[child] = nil
			end)
		end
		local position, size = rest.Position, rest.Size
		TweenService:Create(child, info, {
			Position = UDim2.new(scaleUDim(position.X, scale, 0.5), scaleUDim(position.Y, scale, 0.5)),
			Size = UDim2.new(scaleUDim(size.X, scale, 0), scaleUDim(size.Y, scale, 0)),
		}):Play()
	end
end

--- A flex item scales through its content children -- an ImageButton that is
--- only its own image has none, so it would never react. It gets one: an
--- ImageLabel copy of its image (the button itself turns transparent), which
--- is what scaleContents then grows around the button's centre.
local function ensureVisualChild(target: GuiObject): ()
	if not target:IsA("ImageButton") then
		return
	end
	for _, child in target:GetChildren() do
		if child:IsA("GuiObject") then
			return
		end
	end
	local visual = Instance.new("ImageLabel")
	visual.Name = "FXVisual"
	visual.BackgroundTransparency = 1
	visual.AnchorPoint = Vector2.new(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Size = UDim2.fromScale(1, 1)
	visual.Image = target.Image
	visual.ImageColor3 = target.ImageColor3
	visual.ImageTransparency = target.ImageTransparency
	visual.ScaleType = target.ScaleType
	visual.SliceCenter = target.SliceCenter
	visual.SliceScale = target.SliceScale
	visual.ZIndex = target.ZIndex
	visual.Active = false
	visual.Parent = target
	target.ImageTransparency = 1
end

local function tweenScale(target: GuiObject, scale: number, duration: number): ()
	if isFlexItem(target) then
		ensureVisualChild(target)
		scaleContents(target, scale, duration)
		return
	end
	local uiScale = getOrCreateUIScale(target)
	TweenService:Create(
		uiScale,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = scale }
	):Play()
end

--============================================================================--
-- PUBLIC
--============================================================================--

--- Attaches the hover/press effects on an ImageButton or TextButton.
--- Returns an array of RBXScriptConnection so callers can disconnect if needed.
--- Idempotent: a button that already has FX is left as is (returns {}).
--- @param button  GuiButton      Target button
--- @param config  ButtonFXConfig? Optional configuration
--- @return {RBXScriptConnection}
function ButtonFX.attach(button: GuiButton, config: ButtonFXConfig?): {RBXScriptConnection}
	if attached[button] then
		return {} -- already has FX (first attach wins)
	end
	local cfg: ButtonFXConfig = config or {}

	local hoverScale    = cfg.hoverScale    or DEFAULTS.hoverScale    :: number
	local pressScale    = cfg.pressScale    or DEFAULTS.pressScale    :: number
	local normalScale   = cfg.normalScale   or DEFAULTS.normalScale   :: number
	local hoverDuration = cfg.hoverDuration or DEFAULTS.hoverDuration :: number
	local pressDuration = cfg.pressDuration or DEFAULTS.pressDuration :: number
	local resetDuration = cfg.resetDuration or DEFAULTS.resetDuration :: number

	local conns: {RBXScriptConnection} = {}
	local isPressed = false
	local isHovered = false

	conns[1] = button.MouseEnter:Connect(function()
		if button:GetAttribute(PRESSED_ATTRIBUTE) == true then
			return
		end
		isHovered = true
		tweenScale(button, hoverScale, hoverDuration)
	end)

	conns[2] = button.MouseLeave:Connect(function()
		if button:GetAttribute(PRESSED_ATTRIBUTE) == true then
			return
		end
		isHovered = false
		if not isPressed then
			tweenScale(button, normalScale, resetDuration)
		end
	end)

	conns[3] = button.MouseButton1Down:Connect(function()
		if button:GetAttribute(PRESSED_ATTRIBUTE) == true then
			return
		end
		isPressed = true
		tweenScale(button, pressScale, pressDuration)
	end)

	conns[4] = button.MouseButton1Up:Connect(function()
		if button:GetAttribute(PRESSED_ATTRIBUTE) == true then
			return
		end
		isPressed = false
		tweenScale(button, isHovered and hoverScale or normalScale, resetDuration)
	end)

	-- Catches the finger being released outside the button (mobile: MouseLeave + MouseButton1Up don't fire)
	conns[5] = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if isPressed and button:GetAttribute(PRESSED_ATTRIBUTE) ~= true then
				isPressed = false
				isHovered = false
				tweenScale(button, normalScale, resetDuration)
			end
		end
	end)

	register(button, conns)
	return conns
end

--- Attaches the hover/press effects (UIScale, like attach()) on a parent
--- frame, triggered by SEVERAL child buttons (e.g. container +
--- container_Selected stacked, where only one is visible/active at a time --
--- the hover must apply to the frame no matter which of the two receives
--- the mouse).
--- @param frame          GuiObject       Frame that receives the UIScale
--- @param buttons        {GuiButton}     Buttons whose events trigger the scale (hover + press)
--- @param config         ButtonFXConfig?
--- @param hoverTargets   {GuiObject}?    Additional (non-clickable) surfaces that trigger hover
---                        only -- useful when the clickable button doesn't cover the whole
---                        visual area (e.g. a slot whose button only occupies part of the frame).
--- @return {RBXScriptConnection}
function ButtonFX.attachGroup(frame: GuiObject, buttons: {GuiButton}, config: ButtonFXConfig?, hoverTargets: {GuiObject}?): {RBXScriptConnection}
	local cfg: ButtonFXConfig = config or {}

	local hoverScale    = cfg.hoverScale    or DEFAULTS.hoverScale    :: number
	local pressScale    = cfg.pressScale    or DEFAULTS.pressScale    :: number
	local normalScale   = cfg.normalScale   or DEFAULTS.normalScale   :: number
	local hoverDuration = cfg.hoverDuration or DEFAULTS.hoverDuration :: number
	local pressDuration = cfg.pressDuration or DEFAULTS.pressDuration :: number
	local resetDuration = cfg.resetDuration or DEFAULTS.resetDuration :: number

	local conns: {RBXScriptConnection} = {}
	local isPressed = false
	local isHovered = false

	local scaleTarget = frame :: any

	for _, button in buttons do
		release(button)
		register(button, conns)
		table.insert(conns, button.MouseEnter:Connect(function()
			isHovered = true
			tweenScale(scaleTarget, hoverScale, hoverDuration)
		end))

		table.insert(conns, button.MouseLeave:Connect(function()
			isHovered = false
			if not isPressed then
				tweenScale(scaleTarget, normalScale, resetDuration)
			end
		end))

		table.insert(conns, button.MouseButton1Down:Connect(function()
			isPressed = true
			tweenScale(scaleTarget, pressScale, pressDuration)
		end))

		table.insert(conns, button.MouseButton1Up:Connect(function()
			isPressed = false
			tweenScale(scaleTarget, isHovered and hoverScale or normalScale, resetDuration)
		end))
	end

	for _, target in hoverTargets or {} do
		table.insert(conns, target.MouseEnter:Connect(function()
			isHovered = true
			tweenScale(scaleTarget, hoverScale, hoverDuration)
		end))

		table.insert(conns, target.MouseLeave:Connect(function()
			isHovered = false
			if not isPressed then
				tweenScale(scaleTarget, normalScale, resetDuration)
			end
		end))
	end

	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if isPressed then
				isPressed = false
				isHovered = false
				tweenScale(scaleTarget, normalScale, resetDuration)
			end
		end
	end))

	return conns
end

--- Holds `button` in its clicked look (pressed scale, no AutoButtonColor
--- tint, hover/press FX off) or releases it to rest. No-op when already in
--- that state, so it is safe to call on every render.
--- @param button  GuiButton  Button wired with attach()
--- @param pressed boolean    true = hold pressed, false = back to rest
function ButtonFX.setPressed(button: GuiButton, pressed: boolean): ()
	if (button:GetAttribute(PRESSED_ATTRIBUTE) == true) == pressed then
		return
	end
	button:SetAttribute(PRESSED_ATTRIBUTE, if pressed then true else nil)
	button.AutoButtonColor = not pressed
	tweenScale(
		button,
		if pressed then DEFAULTS.pressScale :: number else DEFAULTS.normalScale :: number,
		DEFAULTS.pressDuration :: number
	)
end

--- Detaches all connections returned by attach().
--- @param conns {RBXScriptConnection}
function ButtonFX.detach(conns: {RBXScriptConnection}): ()
	for _, conn in conns do
		conn:Disconnect()
	end
	for button, owned in attached do
		if owned == conns then
			attached[button] = nil
		end
	end
	table.clear(conns)
end

--- Global cleanup (no-op, connections are managed by the caller).
function ButtonFX.cleanup(): ()
end

--============================================================================--
-- attachWithPush: tweens Size on the parent frame (pushes UIListLayout siblings)
--============================================================================--

local originalSizes: {[GuiObject]: UDim2} = {}
local activePushTweens: {[GuiObject]: Tween} = {}

--- Saves a frame's original size if not already done.
local function ensureOriginalSize(frame: GuiObject): UDim2
	if not originalSizes[frame] then
		originalSizes[frame] = frame.Size
	end
	return originalSizes[frame]
end

--- Tweens a frame's Size by a multiplicative factor.
local function tweenFrameSize(frame: GuiObject, factor: number, duration: number): ()
	local orig = ensureOriginalSize(frame)
	local target = UDim2.new(
		orig.X.Scale  * factor, orig.X.Offset * factor,
		orig.Y.Scale  * factor, orig.Y.Offset * factor
	)
	if activePushTweens[frame] then
		activePushTweens[frame]:Cancel()
	end
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = target }
	)
	activePushTweens[frame] = tween
	tween:Play()
	tween.Completed:Once(function()
		activePushTweens[frame] = nil
	end)
end

--- Attaches the hover/press effects by tweening the parent frame's **Size**.
--- This forces UIListLayout to recompute and pushes neighboring siblings.
--- @param frame   GuiObject      Parent frame (the direct child of the UIListLayout)
--- @param button  GuiButton      Button that receives mouse events (ImageButton or TextButton)
--- @param config  ButtonFXConfig? Optional configuration
--- @return {RBXScriptConnection}
function ButtonFX.attachWithPush(frame: GuiObject, button: GuiButton, config: ButtonFXConfig?): {RBXScriptConnection}
	local cfg: ButtonFXConfig = config or {}

	local hoverScale    = cfg.hoverScale    or 1.05
	local pressScale    = cfg.pressScale    or 0.93
	local hoverDuration = cfg.hoverDuration or DEFAULTS.hoverDuration :: number
	local pressDuration = cfg.pressDuration or DEFAULTS.pressDuration :: number
	local resetDuration = cfg.resetDuration or DEFAULTS.resetDuration :: number

	-- Records the original size at attach time, not on the first hover
	ensureOriginalSize(frame)

	release(button)
	local conns: {RBXScriptConnection} = {}
	register(button, conns)
	local isPressed = false
	local isHovered = false

	conns[1] = button.MouseEnter:Connect(function()
		isHovered = true
		tweenFrameSize(frame, hoverScale, hoverDuration)
	end)

	conns[2] = button.MouseLeave:Connect(function()
		isHovered = false
		if not isPressed then
			tweenFrameSize(frame, 1.0, resetDuration)
		end
	end)

	conns[3] = button.MouseButton1Down:Connect(function()
		isPressed = true
		tweenFrameSize(frame, pressScale, pressDuration)
	end)

	conns[4] = button.MouseButton1Up:Connect(function()
		isPressed = false
		tweenFrameSize(frame, isHovered and hoverScale or 1.0, resetDuration)
	end)

	-- Catches the finger being released outside the button (mobile)
	conns[5] = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if isPressed then
				isPressed = false
				isHovered = false
				tweenFrameSize(frame, 1.0, resetDuration)
			end
		end
	end)

	return conns
end

return ButtonFX
