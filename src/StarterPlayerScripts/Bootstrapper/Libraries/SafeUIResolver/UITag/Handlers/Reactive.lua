--!strict
--[[
	@module UITag.Handlers.Reactive
	@description Reactive effect handlers (Axis 3).

	Reactive tags observe UIData updates (via UITag.OnUpdate) and apply an
	effect when the watched value changes. The watched tag is specified by
	the attribute `WatchTag` on the UI instance, or by the shorthand `Watch`
	which prepends the canonical prefix `UIData_`.

	Canonical data-sync convention:
	  - UIData_<Key>  holds the raw numeric value (e.g. 1234).
	  - A formatter RegisterUpdateHandler converts it to a display string
	    (e.g. "1.23K" via NumberUtil.Format) on TextLabels.
	  - Reactive handlers also subscribe to UIData_<Key> to compute deltas.

	Includes:
	  - UIEffect_FlashOnChange    — flash a color when the value changes
	  - UIEffect_CountUp          — interpolate Text from old → new value
	  - UIEffect_ShakeOnDecrease  — shake if the value goes down
	  - UIEffect_BurstOnIncrease  — burst if the value goes up
	  - UIEffect_PulseOnChange    — pulse on any change

	Also exposes Reactive.InstallFormatter(tag) so UITagController can register
	per-currency formatters dynamically, avoiding a hard-coded currency list.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Bootstrapper = script.Parent.Parent.Parent.Parent.Parent

local UXEffects  = require(Bootstrapper.Libraries.UXEffects)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local Logger     = require(ReplicatedStorage.Libraries.Logger)
local Utils      = require(script.Parent.Utils)
local Types      = require(script.Parent.Types)

local log = Logger.new("UITag/Reactive")

local Reactive = {}

--============================================================================--
-- TAGS
--============================================================================--

local TAGS = {
	FLASH_ON_CHANGE    = "UIEffect_FlashOnChange",
	COUNT_UP           = "UIEffect_CountUp",
	SHAKE_ON_DECREASE  = "UIEffect_ShakeOnDecrease",
	BURST_ON_INCREASE  = "UIEffect_BurstOnIncrease",
	PULSE_ON_CHANGE    = "UIEffect_PulseOnChange",
}

Reactive.TAGS = TAGS

-- Canonical prefix for data tags pushed by UITagController.
local DATA_TAG_PREFIX = "UIData_"

--============================================================================--
-- MODULE STATE
--============================================================================--

--- Track installed formatter tags to avoid double-registration when
--- UITagController installs formatters dynamically per currency.
local installedFormatters: { [string]: true } = {}

--- Active CountUp threads by instance so the handler cleanup can cancel them.
local activeCountUps: { [Instance]: thread? } = {}

--============================================================================--
-- PRIVATE HELPERS
--============================================================================--

--- Subscribe to a specific watched tag on UITag.OnUpdate. The callback receives
--- (newValue, oldValue). Returns a cleanup function that disconnects the signal.
local function subscribeTag(
	UITag: any,
	watchTag: string,
	callback: (newValue: any, oldValue: any) -> ()
): () -> ()
	local lastValue: any = UITag.GetLastValue(watchTag)

	local conn: RBXScriptConnection = UITag.OnUpdate:Connect(function(tagName: string, value: any)
		if tagName ~= watchTag then return end
		local old = lastValue
		lastValue = value
		local ok, err: any = pcall(callback, value, old)
		if not ok then
			log:Warn("Reactive callback error on '%s': %s", watchTag, tostring(err))
		end
	end)

	return function()
		conn:Disconnect()
	end
end

--- Resolve the watched tag name from an instance's attributes.
--- Priority:
---   1. `WatchTag` attribute (full tag name, used verbatim)
---   2. `Watch` attribute (key only; prefixed with `UIData_`)
---   3. nil (no watch)
local function resolveWatchTag(instance: Instance): string?
	local explicit = instance:GetAttribute("WatchTag")
	if type(explicit) == "string" and explicit ~= "" then
		return explicit
	end
	local watch = instance:GetAttribute("Watch")
	if type(watch) == "string" and watch ~= "" then
		return DATA_TAG_PREFIX .. watch
	end
	return nil
end

--- Emit a standard warning when a reactive tag is applied without a watch target.
local function warnMissingWatch(tagName: string, instance: Instance)
	log:Warn(
		"%s on %s has no 'WatchTag' or 'Watch' attribute — effect will not fire.",
		tagName, instance:GetFullName()
	)
end

--============================================================================--
-- FLASH ON CHANGE
--============================================================================--

local function registerFlashOnChange(UITag: any)
	UITag.RegisterHandler(TAGS.FLASH_ON_CHANGE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then return nil end
		local watchTag = resolveWatchTag(instance)
		if not watchTag then
			warnMissingWatch(TAGS.FLASH_ON_CHANGE, instance)
			return nil
		end

		local flashColor: Color3 = Utils.ToColor3(
			instance:GetAttribute("FlashColor"),
			Color3.fromRGB(255, 235, 120)
		)
		local duration: number = Utils.GetAttr(instance, "duration", 0.3)

		return subscribeTag(UITag, watchTag, function(newValue, oldValue)
			-- Skip redundant updates that don't actually change the value.
			if newValue == oldValue then return end

			local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

			if instance:IsA("TextLabel") then
				local original = instance.TextColor3
				instance.TextColor3 = flashColor
				TweenService:Create(instance, tweenInfo, { TextColor3 = original }):Play()
			end
			if instance:IsA("TextButton") then
				local original = instance.TextColor3
				instance.TextColor3 = flashColor
				TweenService:Create(instance, tweenInfo, { TextColor3 = original }):Play()
			end
			if instance:IsA("ImageLabel") then
				local original = instance.ImageColor3
				instance.ImageColor3 = flashColor
				TweenService:Create(instance, tweenInfo, { ImageColor3 = original }):Play()
			end
			if instance:IsA("ImageButton") then
				local original = instance.ImageColor3
				instance.ImageColor3 = flashColor
				TweenService:Create(instance, tweenInfo, { ImageColor3 = original }):Play()
			end
			if not (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
				local original = instance.BackgroundColor3
				instance.BackgroundColor3 = flashColor
				TweenService:Create(instance, tweenInfo, { BackgroundColor3 = original }):Play()
			end
		end)
	end)
end

--============================================================================--
-- COUNT UP (numeric interpolation on Text)
--============================================================================--

local function cancelCountUpThread(instance: Instance)
	local thread = activeCountUps[instance]
	if thread then
		task.cancel(thread)
		activeCountUps[instance] = nil
	end
end

local function registerCountUp(UITag: any)
	UITag.RegisterHandler(TAGS.COUNT_UP, function(instance: Instance): (() -> ())?
		if not (instance:IsA("TextLabel") or instance:IsA("TextButton")) then
			return nil
		end
		local text = instance :: any
		local watchTag = resolveWatchTag(instance)
		if not watchTag then
			warnMissingWatch(TAGS.COUNT_UP, instance)
			return nil
		end

		local duration: number = Utils.GetAttr(instance, "duration", 0.6)
		local formatted: boolean = Utils.GetAttr(instance, "formatted", true)

		local function interp(from: number, to: number)
			cancelCountUpThread(instance)
			activeCountUps[instance] = task.spawn(function()
				local elapsed = 0
				while elapsed < duration do
					local dt = task.wait(1 / 30)
					elapsed += (dt or 0)
					local t = math.clamp(elapsed / duration, 0, 1)
					local eased = 1 - (1 - t) ^ 3 -- easeOutCubic
					local current = from + (to - from) * eased
					if not text.Parent then break end
					if formatted then
						text.Text = NumberUtil.Format(current)
					else
						text.Text = tostring(math.floor(current))
					end
				end
				if text.Parent then
					if formatted then
						text.Text = NumberUtil.Format(to)
					else
						text.Text = tostring(math.floor(to))
					end
				end
				activeCountUps[instance] = nil
			end)
		end

		local unsubscribe = subscribeTag(UITag, watchTag, function(newValue, oldValue)
			local from = Utils.ToNumber(oldValue, 0) or 0
			local to   = Utils.ToNumber(newValue, 0) or 0
			if from == to then return end
			interp(from, to)
		end)

		return function()
			unsubscribe()
			cancelCountUpThread(instance)
		end
	end)
end

--============================================================================--
-- SHAKE ON DECREASE
--============================================================================--

local function registerShakeOnDecrease(UITag: any)
	UITag.RegisterHandler(TAGS.SHAKE_ON_DECREASE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then return nil end
		local watchTag = resolveWatchTag(instance)
		if not watchTag then
			warnMissingWatch(TAGS.SHAKE_ON_DECREASE, instance)
			return nil
		end

		local style = Utils.GetAttr(instance, "ShakeStyle", "impact") :: Types.ShakeStyle

		return subscribeTag(UITag, watchTag, function(newValue, oldValue)
			local newN = Utils.ToNumber(newValue)
			local oldN = Utils.ToNumber(oldValue)
			if not newN or not oldN then return end
			if newN >= oldN then return end

			if style == "error" then
				UXEffects.Shake.error(instance)
			else
				local intensity: number = Utils.GetAttr(instance, "intensity", 12)
				UXEffects.Shake.impact(instance, intensity)
			end
		end)
	end)
end

--============================================================================--
-- BURST ON INCREASE
--============================================================================--

local function registerBurstOnIncrease(UITag: any)
	UITag.RegisterHandler(TAGS.BURST_ON_INCREASE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then return nil end
		local watchTag = resolveWatchTag(instance)
		if not watchTag then
			warnMissingWatch(TAGS.BURST_ON_INCREASE, instance)
			return nil
		end

		local style = Utils.GetAttr(instance, "BurstStyle", "gold") :: Types.BurstStyle

		return subscribeTag(UITag, watchTag, function(newValue, oldValue)
			local newN = Utils.ToNumber(newValue)
			local oldN = Utils.ToNumber(oldValue)
			if not newN or not oldN then return end
			if newN <= oldN then return end

			local pos = Utils.GetCenterPosition(instance)
			if style == "rainbow" then
				UXEffects.Burst.rainbow(pos)
			elseif style == "custom" then
				local colorAttr = instance:GetAttribute("BurstColor")
				local cfg: { particleCount: number, colors: { Color3 }? } = {
					particleCount = Utils.GetAttr(instance, "particleCount", 15),
				}
				if colorAttr ~= nil then
					cfg.colors = { Utils.ToColor3(colorAttr) }
				end
				UXEffects.Burst.play(pos, cfg :: any)
			else
				UXEffects.Burst.gold(pos)
			end
		end)
	end)
end

--============================================================================--
-- PULSE ON CHANGE
--============================================================================--

local function registerPulseOnChange(UITag: any)
	UITag.RegisterHandler(TAGS.PULSE_ON_CHANGE, function(instance: Instance): (() -> ())?
		if not instance:IsA("GuiObject") then return nil end
		local watchTag = resolveWatchTag(instance)
		if not watchTag then
			warnMissingWatch(TAGS.PULSE_ON_CHANGE, instance)
			return nil
		end

		local config = {
			scale       = Utils.GetAttr(instance, "scale",       1.12),
			duration    = Utils.GetAttr(instance, "duration",    0.18),
			repeatCount = 1,
		}

		return subscribeTag(UITag, watchTag, function(newValue, oldValue)
			if newValue == oldValue then return end
			UXEffects.Pulse.play(instance, config)
		end)
	end)
end

--============================================================================--
-- UIDATA_* AUTOMATIC TEXT FORMATTING
--============================================================================--

--- Install a default Text-syncing UpdateHandler for a `UIData_*` tag that
--- formats numeric values with NumberUtil.Format. Idempotent: calling this
--- repeatedly for the same tag is a no-op after the first call.
---
--- Skips instances that also carry `UIEffect_CountUp` so the interpolation
--- handler keeps control of the Text property without being stomped on.
function Reactive.InstallFormatter(UITag: any, tagName: string)
	if installedFormatters[tagName] then
		return
	end
	installedFormatters[tagName] = true

	UITag.RegisterUpdateHandler(tagName, function(instance: Instance, value: any)
		if not (instance:IsA("TextLabel") or instance:IsA("TextButton")) then
			return
		end
		if CollectionService:HasTag(instance, TAGS.COUNT_UP) then
			-- CountUp owns the Text interpolation; let it run.
			return
		end
		local text = instance :: any
		if type(value) == "number" then
			text.Text = NumberUtil.Format(value)
		else
			text.Text = tostring(value)
		end
	end)
end

--============================================================================--
-- PUBLIC API
--============================================================================--

function Reactive.Register(UITag: any)
	registerFlashOnChange(UITag)
	registerCountUp(UITag)
	registerShakeOnDecrease(UITag)
	registerBurstOnIncrease(UITag)
	registerPulseOnChange(UITag)
	log:Info("Reactive handlers registered (%d tags).", 5)
end

return Reactive
