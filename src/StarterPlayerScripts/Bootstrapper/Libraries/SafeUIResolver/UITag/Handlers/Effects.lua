--!strict
--[[
	@module UITag.Handlers.Effects
	@description Continuous / static UI effect handlers (Axis 1).

	Effects registered here apply as long as the instance exists and the tag
	is attached. Each handler returns a cleanup function that stops the effect
	and releases resources; UITag calls this cleanup on Destroying or tag removal.

	Includes:
	  - Legacy bridges  : UIEffect_Button, _Shimmer, _Glow, _Ripple
	  - Button variant  : UIEffect_ButtonPush  (push-in layout via parent frame)
	  - Glow presets    : UIEffect_Glow_Gold / _Legendary / _Rare / _Rarity
	  - Idle shake      : UIEffect_Shake_Idle
	  - Rainbow cycle   : UIEffect_Rainbow     (Text / UIStroke / UIGradient)
	  - Float           : UIEffect_Float
	  - Tilt3D          : UIEffect_Tilt3D
	  - Entrance        : UIEffect_Entrance    (one-shot on mount)

	Note: UIEffect_Pulse and UIEffect_AttentionPulse tag strings still exist
	(Effects.TAGS, referenced by UITag/Handlers/Presets.lua composites) but no
	longer have a handler — tagging an element with them does nothing now.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local Bootstrapper = script.Parent.Parent.Parent.Parent.Parent

local UXEffects          = require(Bootstrapper.Libraries.UXEffects)
local RarityVisualConfig = require(Bootstrapper.Config.RarityVisualConfig)
local Logger             = require(ReplicatedStorage.Libraries.Logger)
local Utils              = require(script.Parent.Utils)
local Types              = require(script.Parent.Types)

local log = Logger.new("UITag/Effects")

local Effects = {}

--============================================================================--
-- TAGS
--============================================================================--

local TAGS = {
	-- Legacy (migrated from StandardHandlers)
	BUTTON          = "UIEffect_Button",
	PULSE           = "UIEffect_Pulse",
	SHIMMER         = "UIEffect_Shimmer",
	GLOW            = "UIEffect_Glow",
	RIPPLE          = "UIEffect_Ripple",

	-- Button variant
	BUTTON_PUSH     = "UIEffect_ButtonPush",

	-- Glow variants
	GLOW_GOLD       = "UIEffect_Glow_Gold",
	GLOW_LEGENDARY  = "UIEffect_Glow_Legendary",
	GLOW_RARE       = "UIEffect_Glow_Rare",
	GLOW_RARITY     = "UIEffect_Glow_Rarity",

	-- Idle / ambient
	SHAKE_IDLE      = "UIEffect_Shake_Idle",
	RAINBOW         = "UIEffect_Rainbow",
	FLOAT           = "UIEffect_Float",
	TILT_3D         = "UIEffect_Tilt3D",
	ATTENTION_PULSE = "UIEffect_AttentionPulse",

	-- Entrance (one-shot on mount)
	ENTRANCE        = "UIEffect_Entrance",

	-- Continuous rotation
	ROTATE          = "UIEffect_Rotate",

	-- Scale on interaction
	HOVER           = "UIEffect_Hover",
	PRESS           = "UIEffect_Press",

	-- Rich animated gradient stroke
	STROKE_AURA     = "UIEffect_StrokeAura",
}

Effects.TAGS = TAGS

local TAG_COUNT = (function(): number
	local n = 0
	for _ in pairs(TAGS) do
		n += 1
	end
	return n
end)()

--============================================================================--
-- PRIVATE HELPERS
--============================================================================--

--- Returns (UIScale, created?) on the instance. Creates the UIScale if absent.
local function getOrCreateUIScale(instance: GuiObject): (UIScale, boolean)
	local existing = instance:FindFirstChildOfClass("UIScale")
	if existing then
		return existing, false
	end
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = instance
	return uiScale, true
end

local DEFAULT_RARITY_FALLBACK = "Common"

local function resolveRarityColor(rarity: string): Color3
	local visual = RarityVisualConfig[rarity] or RarityVisualConfig[DEFAULT_RARITY_FALLBACK]
	if visual and visual.StrokeInColors and visual.StrokeInColors[1] then
		return visual.StrokeInColors[1]
	end
	return Color3.fromRGB(255, 255, 255)
end

--- Wrap a list of RBXScriptConnection (returned by UXEffects.ButtonFX.attach)
--- into a single cleanup closure.
local function wrapConnections(conns: {RBXScriptConnection}): () -> ()
	return function()
		for _, c in ipairs(conns) do
			if c and c.Connected then
				c:Disconnect()
			end
		end
	end
end

--============================================================================--
-- LEGACY EFFECT HANDLERS
--============================================================================--

local function registerLegacy(UITag: any)
	-- Button: hover/press FX on ImageButton or TextButton
	UITag.RegisterHandler(TAGS.BUTTON, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiButton") then
			return nil
		end
		local config = Utils.GetAttributes(instance, {
			"hoverScale", "pressScale", "hoverDuration",
			"pressDuration", "normalScale", "resetDuration",
		})
		local conns = UXEffects.ButtonFX.attach(instance, config :: any)
		return wrapConnections(conns)
	end)

	-- Shimmer: animate a UIGradient child
	UITag.RegisterHandler(TAGS.SHIMMER, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local existing = instance:FindFirstChildOfClass("UIGradient")
		local ownedGradient = existing == nil
		local gradient: UIGradient = existing or Instance.new("UIGradient")
		if ownedGradient then
			gradient.Parent = instance
		end
		local config = Utils.GetAttributes(instance, { "animationSpeed", "rotationSpeed", "animationType" })
		UXEffects.Shimmer.play(gradient, config :: any)
		return function()
			if gradient then
				UXEffects.Shimmer.stop(gradient)
				if ownedGradient and gradient.Parent then
					gradient:Destroy()
				end
			end
		end
	end)

	-- Glow: apply halo; cleanup removes it
	UITag.RegisterHandler(TAGS.GLOW, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local config = Utils.GetAttributes(instance, { "color", "intensity", "pulses", "pulseSpeed" })
		UXEffects.Glow.apply(instance, config :: any)
		return function()
			UXEffects.Glow.remove(instance)
		end
	end)

	-- Ripple: click ripple on GuiButton
	UITag.RegisterHandler(TAGS.RIPPLE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiButton") then
			return nil
		end
		local conn = UXEffects.Ripple.attachToButton(instance)
		return function()
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
	end)
end

--============================================================================--
-- BUTTON PUSH (attachWithPush)
--============================================================================--

local function registerButtonPush(UITag: any)
	UITag.RegisterHandler(TAGS.BUTTON_PUSH, function(instance: Instance): (() -> ())?
		if not instance:IsA("ImageButton") then
			return nil
		end
		local parent = instance.Parent
		if not parent or not parent:IsA("GuiObject") then
			return nil
		end
		local config = Utils.GetAttributes(instance, {
			"hoverScale", "pressScale", "hoverDuration",
			"pressDuration", "resetDuration",
		})
		local conns = UXEffects.ButtonFX.attachWithPush(parent, instance, config :: any)
		return wrapConnections(conns)
	end)
end

--============================================================================--
-- GLOW PRESETS (auto-color)
--============================================================================--

local function registerGlowPresets(UITag: any)
	local function applyGlowPreset(preset: Types.GlowPreset)
		return function(instance: Instance): (() -> ())?
			if not instance:IsA("GuiObject") then
				return nil
			end
			if preset == "Gold" then
				UXEffects.Glow.gold(instance)
			elseif preset == "Legendary" then
				UXEffects.Glow.legendary(instance)
			else -- "Rare"
				UXEffects.Glow.rare(instance)
			end
			return function()
				UXEffects.Glow.remove(instance)
			end
		end
	end

	UITag.RegisterHandler(TAGS.GLOW_GOLD,      applyGlowPreset("Gold"))
	UITag.RegisterHandler(TAGS.GLOW_LEGENDARY, applyGlowPreset("Legendary"))
	UITag.RegisterHandler(TAGS.GLOW_RARE,      applyGlowPreset("Rare"))

	-- Rarity-driven glow: reads `Rarity` attribute and picks color from RarityVisualConfig
	UITag.RegisterHandler(TAGS.GLOW_RARITY, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local rarity: string = Utils.GetAttr(instance, "Rarity", DEFAULT_RARITY_FALLBACK)
		local color  = resolveRarityColor(rarity)
		local config = {
			color      = color,
			intensity  = Utils.GetAttr(instance, "intensity",  1.0),
			pulses     = Utils.GetAttr(instance, "pulses",     true),
			pulseSpeed = Utils.GetAttr(instance, "pulseSpeed", 1.5),
		}
		UXEffects.Glow.apply(instance, config)

		-- React to live rarity changes without re-tagging
		local conn = instance:GetAttributeChangedSignal("Rarity"):Connect(function()
			local newRarity: string = Utils.GetAttr(instance, "Rarity", DEFAULT_RARITY_FALLBACK)
			UXEffects.Glow.setColor(instance, resolveRarityColor(newRarity), 0.3)
		end)

		return function()
			conn:Disconnect()
			UXEffects.Glow.remove(instance)
		end
	end)
end

--============================================================================--
-- SHAKE IDLE
--============================================================================--

local function registerShakeIdle(UITag: any)
	UITag.RegisterHandler(TAGS.SHAKE_IDLE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local intensity: number = Utils.GetAttr(instance, "intensity", 4)
		UXEffects.Shake.vibrate(instance, intensity)
		return function()
			UXEffects.Shake.stop(instance)
		end
	end)
end

--============================================================================--
-- RAINBOW CYCLE
--============================================================================--

--- Cycles color through the rainbow on:
---   * TextLabel / TextButton → TextColor3
---   * ImageLabel / ImageButton → ImageColor3
---   * A child UIStroke if any → Color
---   * A child UIGradient if any → 3-keypoint sequence slid over the cycle
local function registerRainbow(UITag: any)
	UITag.RegisterHandler(TAGS.RAINBOW, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local speed: number = Utils.GetAttr(instance, "speed", 0.25) -- cycles per second
		local stroke   = instance:FindFirstChildOfClass("UIStroke")
		local gradient = instance:FindFirstChildOfClass("UIGradient")

		local phase = 0
		local conn = RunService.Heartbeat:Connect(function(dt: number)
			phase = (phase + speed * dt) % 1
			local c = Utils.RainbowColor(phase)
			if instance:IsA("TextLabel") then
				instance.TextColor3 = c
			end
			if instance:IsA("TextButton") then
				instance.TextColor3 = c
			end
			if instance:IsA("ImageLabel") then
				instance.ImageColor3 = c
			end
			if instance:IsA("ImageButton") then
				instance.ImageColor3 = c
			end
			if stroke then
				stroke.Color = c
			end
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0,   c),
					ColorSequenceKeypoint.new(0.5, Utils.RainbowColor(phase + 0.33)),
					ColorSequenceKeypoint.new(1,   Utils.RainbowColor(phase + 0.66)),
				})
			end
		end)
		return function()
			conn:Disconnect()
		end
	end)
end

--============================================================================--
-- FLOAT (vertical bobbing via UDim2 offset)
--============================================================================--

local function registerFloat(UITag: any)
	UITag.RegisterHandler(TAGS.FLOAT, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local amplitude: number = Utils.GetAttr(instance, "amplitude", 6)   -- px
		local frequency: number = Utils.GetAttr(instance, "frequency", 1.2) -- Hz
		local basePos = instance.Position
		local t = 0

		local conn = RunService.Heartbeat:Connect(function(dt: number)
			t += dt
			local offset = math.sin(t * math.pi * 2 * frequency) * amplitude
			instance.Position = UDim2.new(
				basePos.X.Scale, basePos.X.Offset,
				basePos.Y.Scale, basePos.Y.Offset + offset
			)
		end)
		return function()
			conn:Disconnect()
			if instance.Parent then
				instance.Position = basePos
			end
		end
	end)
end

--============================================================================--
-- TILT 3D (mouse/touch parallax using rotation)
--============================================================================--

local function registerTilt3D(UITag: any)
	UITag.RegisterHandler(TAGS.TILT_3D, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local maxRotation: number = Utils.GetAttr(instance, "maxRotation", 8) -- degrees
		local smoothing: number   = Utils.GetAttr(instance, "smoothing",   8) -- higher = snappier

		local baseRotation = instance.Rotation
		local targetRotation = 0
		local currentRotation = 0

		local conn = RunService.Heartbeat:Connect(function(dt: number)
			local mouse = UserInputService:GetMouseLocation()
			local center = Utils.GetCenterPosition(instance)
			local size = instance.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then
				return
			end
			local dx = math.clamp((mouse.X - center.X) / (size.X * 0.5), -1, 1)
			targetRotation = dx * maxRotation
			currentRotation += (targetRotation - currentRotation) * math.min(smoothing * dt, 1)
			instance.Rotation = baseRotation + currentRotation
		end)
		return function()
			conn:Disconnect()
			if instance.Parent then
				instance.Rotation = baseRotation
			end
		end
	end)
end

--============================================================================--
-- STROKE AURA — presets & builder (module-level, shared)
--============================================================================--

local STROKE_PRESETS: {[string]: {Color3}} = {
	Rainbow = {
		Color3.fromHSV(0/6, 1, 1),
		Color3.fromHSV(1/6, 1, 1),
		Color3.fromHSV(2/6, 1, 1),
		Color3.fromHSV(3/6, 1, 1),
		Color3.fromHSV(4/6, 1, 1),
		Color3.fromHSV(5/6, 1, 1),
		Color3.fromHSV(6/6, 1, 1),
	},
	Gold = {
		Color3.fromRGB(255, 180,  30),
		Color3.fromRGB(255, 240, 150),
		Color3.fromRGB(255, 200,  60),
		Color3.fromRGB(255, 255, 200),
		Color3.fromRGB(255, 180,  30),
	},
	Neon = {
		Color3.fromRGB(  0, 255, 255),
		Color3.fromRGB(180,   0, 255),
		Color3.fromRGB(255,   0, 180),
		Color3.fromRGB(  0, 255, 255),
	},
	Fire = {
		Color3.fromRGB(255,  40,   0),
		Color3.fromRGB(255, 140,   0),
		Color3.fromRGB(255, 230,  80),
		Color3.fromRGB(255, 140,   0),
		Color3.fromRGB(255,  40,   0),
	},
	Ice = {
		Color3.fromRGB( 80, 200, 255),
		Color3.fromRGB(200, 240, 255),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(120, 180, 255),
		Color3.fromRGB( 80, 200, 255),
	},
}

local function buildStrokeColorSequence(baseColors: {Color3}, hueShift: number): ColorSequence
	local n = #baseColors
	if n == 0 then
		return ColorSequence.new(Color3.fromRGB(255, 255, 255))
	end
	if n == 1 then
		local h, s, v = Color3.toHSV(baseColors[1])
		return ColorSequence.new(Color3.fromHSV((h + hueShift) % 1, s, v))
	end
	local keypoints = table.create(n)
	for i, color in ipairs(baseColors) do
		local h, s, v = Color3.toHSV(color)
		local shifted = Color3.fromHSV((h + hueShift) % 1, s, v)
		keypoints[i] = ColorSequenceKeypoint.new((i - 1) / (n - 1), shifted)
	end
	return ColorSequence.new(keypoints)
end

--============================================================================--
-- STROKE AURA (rich gradient + animation on UIStroke)
--============================================================================--

local function registerStrokeAura(UITag: any)
	UITag.RegisterHandler(TAGS.STROKE_AURA, function(instance: Instance): (() -> ())?
		if not instance:IsA("UIStroke") then
			return nil
		end
		local stroke = instance :: UIStroke

		-- Attributes
		local preset         = Utils.GetAttr(instance, "preset",         "Rainbow")
		local thickness      = Utils.GetAttr(instance, "thickness",      3)
		local transparency   = Utils.GetAttr(instance, "transparency",   0)
		local strokeMode     = Utils.GetAttr(instance, "strokeMode",     "Border")
		local rotateGradient = Utils.GetAttr(instance, "rotateGradient", true)
		local rotateSpeed    = Utils.GetAttr(instance, "rotateSpeed",    45)
		local cycleColors    = Utils.GetAttr(instance, "cycleColors",    false)
		local cycleSpeed     = Utils.GetAttr(instance, "cycleSpeed",     3)
		local pulseGlow      = Utils.GetAttr(instance, "pulseGlow",      false)
		local pulseMin       = Utils.GetAttr(instance, "pulseMin",       0)
		local pulseMax       = Utils.GetAttr(instance, "pulseMax",       0.5)
		local pulseSpeed     = Utils.GetAttr(instance, "pulseSpeed",     1)

		-- Save original values
		local origColor        = stroke.Color
		local origThickness    = stroke.Thickness
		local origTransparency = stroke.Transparency
		local origStrokeMode   = stroke.ApplyStrokeMode

		-- Apply base settings
		stroke.Color           = Color3.fromRGB(255, 255, 255)
		stroke.Thickness       = thickness
		stroke.Transparency    = transparency
		stroke.ApplyStrokeMode = if strokeMode == "Contextual"
			then Enum.ApplyStrokeMode.Contextual
			else Enum.ApplyStrokeMode.Border

		-- Color palette
		local baseColors = STROKE_PRESETS[preset] or STROKE_PRESETS.Rainbow

		-- Child UIGradient
		local gradient = Instance.new("UIGradient")
		gradient.Color  = buildStrokeColorSequence(baseColors, 0)
		gradient.Parent = stroke

		-- Animated state
		local rotation  = 0
		local hueOffset = 0
		local pulseTime = 0

		local conn = RunService.Heartbeat:Connect(function(dt: number)
			-- Gradient rotation
			if rotateGradient then
				rotation = (rotation + rotateSpeed * dt) % 360
				gradient.Rotation = math.floor(rotation)
			end
			-- Hue cycle
			if cycleColors and cycleSpeed > 0 then
				hueOffset = (hueOffset + dt / cycleSpeed) % 1
				gradient.Color = buildStrokeColorSequence(baseColors, hueOffset)
			end
			-- Transparency pulse
			if pulseGlow then
				pulseTime += dt * pulseSpeed
				local t = (math.sin(pulseTime * math.pi * 2) + 1) / 2
				stroke.Transparency = pulseMin + (pulseMax - pulseMin) * t
			end
		end)

		return function()
			conn:Disconnect()
			if gradient.Parent then
				gradient:Destroy()
			end
			if instance.Parent then
				stroke.Color           = origColor
				stroke.Thickness       = origThickness
				stroke.Transparency    = origTransparency
				stroke.ApplyStrokeMode = origStrokeMode
			end
		end
	end)
end

--============================================================================--
-- HOVER (scale up on mouse enter)
--============================================================================--

local function registerHover(UITag: any)
	UITag.RegisterHandler(TAGS.HOVER, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local targetScale: number = Utils.GetAttr(instance, "scale",    1.05)
		local duration: number    = Utils.GetAttr(instance, "duration", 0.10)

		local uiScale, created = getOrCreateUIScale(instance :: GuiObject)
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local currentTween: Tween? = nil

		local function tweenTo(scale: number)
			if currentTween then
				currentTween:Cancel()
			end
			local newTween = TweenService:Create(uiScale, tweenInfo, { Scale = scale })
			currentTween = newTween
			newTween:Play()
		end

		local enterConn = (instance :: GuiObject).MouseEnter:Connect(function()
			tweenTo(targetScale)
		end)
		local leaveConn = (instance :: GuiObject).MouseLeave:Connect(function()
			tweenTo(1)
		end)

		return function()
			enterConn:Disconnect()
			leaveConn:Disconnect()
			if currentTween then
				currentTween:Cancel()
			end
			if instance.Parent then
				if created then
					uiScale:Destroy()
				else
					uiScale.Scale = 1
				end
			end
		end
	end)
end

--============================================================================--
-- PRESS (scale down on mouse button down)
--============================================================================--

local function registerPress(UITag: any)
	UITag.RegisterHandler(TAGS.PRESS, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiButton") then
			return nil
		end
		local targetScale: number = Utils.GetAttr(instance, "scale",    0.95)
		local duration: number    = Utils.GetAttr(instance, "duration", 0.07)

		local uiScale, created = getOrCreateUIScale(instance :: GuiObject)
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local currentTween: Tween? = nil

		local function tweenTo(scale: number)
			if currentTween then
				currentTween:Cancel()
			end
			local newTween = TweenService:Create(uiScale, tweenInfo, { Scale = scale })
			currentTween = newTween
			newTween:Play()
		end

		local downConn  = (instance :: GuiButton).MouseButton1Down:Connect(function()
			tweenTo(targetScale)
		end)
		local upConn    = (instance :: GuiButton).MouseButton1Up:Connect(function()
			tweenTo(1)
		end)
		local leaveConn = (instance :: GuiObject).MouseLeave:Connect(function()
			tweenTo(1)
		end)

		return function()
			downConn:Disconnect()
			upConn:Disconnect()
			leaveConn:Disconnect()
			if currentTween then
				currentTween:Cancel()
			end
			if instance.Parent then
				if created then
					uiScale:Destroy()
				else
					uiScale.Scale = 1
				end
			end
		end
	end)
end

--============================================================================--
-- ROTATE (continuous spin)
--============================================================================--

local function registerRotate(UITag: any)
	UITag.RegisterHandler(TAGS.ROTATE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local speed: number    = Utils.GetAttr(instance, "speed",    90)   -- degrees/second
		local reverse: boolean = Utils.GetAttr(instance, "reverse", false) -- counterclockwise
		local baseRotation     = instance.Rotation
		local accumulated      = 0

		local conn = RunService.Heartbeat:Connect(function(dt: number)
			accumulated += speed * dt * (if reverse then -1 else 1)
			instance.Rotation = baseRotation + accumulated
		end)
		return function()
			conn:Disconnect()
			if instance.Parent then
				instance.Rotation = baseRotation
			end
		end
	end)
end

--============================================================================--
-- ENTRANCE (one-shot mount animation)
--============================================================================--

--- mode: "Pop" | "Bounce" | "Fade" | "Slide" (+ attribute `direction` for Slide)
local function registerEntrance(UITag: any)
	UITag.RegisterHandler(TAGS.ENTRANCE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then
			return nil
		end
		local rawMode = instance:GetAttribute("mode")
		local mode: Types.EntranceMode = Types.ToEntranceMode(rawMode, "Pop")

		if mode == "Pop" then
			UXEffects.Scale.popIn(instance)
		elseif mode == "Bounce" then
			UXEffects.Scale.bounce(instance)
		elseif mode == "Fade" then
			UXEffects.Scale.fadeIn(instance)
		else -- "Slide"
			local rawDirection = instance:GetAttribute("direction")
			local direction: Types.SlideDirection = Types.ToSlideDirection(rawDirection, "Top")
			UXEffects.SlidePanel.slideIn(instance, { direction = direction })
		end

		-- Entrance is fire-and-forget; no per-instance cleanup needed here.
		return nil
	end)
end

--============================================================================--
-- PUBLIC API
--============================================================================--

function Effects.Register(UITag: any)
	registerLegacy(UITag)
	registerButtonPush(UITag)
	registerGlowPresets(UITag)
	registerShakeIdle(UITag)
	registerRainbow(UITag)
	registerFloat(UITag)
	registerTilt3D(UITag)
	registerRotate(UITag)
	registerStrokeAura(UITag)
	registerHover(UITag)
	registerPress(UITag)
	registerEntrance(UITag)
	log:Info("Effects handlers registered (%d tags).", TAG_COUNT)
end

return Effects
