--!strict
--[[
	@module UITag.Handlers.Actions
	@description Trigger / one-shot action handlers (Axis 2).

	Action tags bind a click (or input) on a GuiButton to a one-shot effect
	or network call. Config is read from attributes at click time so it stays
	data-driven from Studio.

	Includes:
	  - Legacy        : UIAction_Button, UIAction_Open
	  - Close         : UIAction_Close
	  - FX triggers   : UIAction_Burst, _Confetti, _Shake, _Toast
	  - Media / I/O   : UIAction_Sound, _FlyToUI, _Counter
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")

local Bootstrapper = script.Parent.Parent.Parent.Parent.Parent

local UXEffects        = require(Bootstrapper.Libraries.UXEffects)
local NetworkEvents    = require(ReplicatedStorage.Libraries.NetworkEvents)
local Logger           = require(ReplicatedStorage.Libraries.Logger)
local UIActionRegistry = require(Bootstrapper.Config.UIActions)
local Utils            = require(script.Parent.Utils)
local Types            = require(script.Parent.Types)

local log = Logger.new("UITag/Actions")

local Actions = {}

local globalLastToggle = 0
local GLOBAL_COOLDOWN = 0.3

local keybindRegistry: {
	[Instance]: {
		actionKeybinds: {string},
		handler: () -> ()
	}
} = setmetatable({}, { __mode = "k" }) :: any

--============================================================================--
-- TAGS
--============================================================================--

local TAGS = {
	-- Legacy
	BUTTON    = "UIAction_Button",
	OPEN      = "UIAction_Open",

	-- Action methods (registry CFG, "Method" attribute)
	ACTION    = "UI_BUTTON_ACTION",

	-- New
	CLOSE     = "UIAction_Close",
	BURST     = "UIAction_Burst",
	CONFETTI  = "UIAction_Confetti",
	SHAKE     = "UIAction_Shake",
	TOAST     = "UIAction_Toast",
	SOUND     = "UIAction_Sound",
	FLY_TO_UI = "UIAction_FlyToUI",
	COUNTER   = "UIAction_Counter",
}

Actions.TAGS = TAGS

-- Default animation directive for the HowToOpen / HowToClose attributes.
-- Wiring done in code (UIHandlers, Controllers) must set THIS constant
-- rather than the literal, to stay aligned with the default read here.
local HOW_TO_DEFAULT = "Scale"

Actions.HOW_TO_OPEN_DEFAULT = HOW_TO_DEFAULT
Actions.HOW_TO_CLOSE_DEFAULT = HOW_TO_DEFAULT

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

--- Connect a GuiButton.Activated callback and return a cleanup closure.
local function bindClick(instance: Instance, handler: () -> ()): (() -> ())?
	if not instance:IsA("GuiButton") then
		return nil
	end
	
	local clickConn = instance.Activated:Connect(function()
		local ok, err: any = pcall(handler)
		if not ok then
			log:Warn("Action handler error on %s: %s", instance:GetFullName(), tostring(err))
		end
	end)
	
	local function updateKeybind()
		local actionKeybind = instance:GetAttribute("ActionKeybind")
		if actionKeybind and type(actionKeybind) == "string" then
			local keys: { string } = {}
			for keyName in string.gmatch(actionKeybind, "([^,]+)") do
				table.insert(keys, keyName:match("^%s*(.-)%s*$") :: string)
			end
			keybindRegistry[instance] = {
				actionKeybinds = keys,
				handler = handler
			}
		else
			keybindRegistry[instance] = nil
		end
	end

	updateKeybind()
	local attrConn = instance:GetAttributeChangedSignal("ActionKeybind"):Connect(updateKeybind)
	
	return function()
		clickConn:Disconnect()
		attrConn:Disconnect()
		keybindRegistry[instance] = nil
	end
end

--- Pick the "anchor" GuiObject for an effect that needs a screen position.
--- Uses TargetTag's first match if provided, else falls back to the instance.
local function resolveAnchor(instance: Instance): GuiObject?
	local targets = Utils.ResolveTargets(instance)
	for _, t in ipairs(targets) do
		if t:IsA("GuiObject") then
			return t
		end
	end
	if instance:IsA("GuiObject") then
		return instance
	end
	return nil
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player and player:FindFirstChildOfClass("PlayerGui")

local function isValidClientTarget(instance: Instance): boolean
	if not playerGui then
		playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	end
	if not playerGui then 

		return false 
	end
	local result = instance:IsDescendantOf(playerGui)

	return result
end

-- Attribute used to cache a slide panel's rest position.
-- slideOut moves the Position off-screen; without this cache, slideIn would
-- read that off-screen position back as the new "rest position" and the panel
-- would never come back on screen (the "opens once then never reopens" bug).
local SLIDE_REST_ATTR = "_UISlideRestPosition"

--- Returns a slide panel's rest position, caching it on first call
--- (as long as the current Position is still the right one, i.e. at open time).
local function resolveRestPosition(target: GuiObject): UDim2
	local stored = target:GetAttribute(SLIDE_REST_ATTR)
	if typeof(stored) == "UDim2" then
		return stored
	end
	
	-- Detects an invalid (off-screen) rest position during automatic init
	local pos = target.Position
	if pos.Y.Scale < -0.9 or pos.Y.Scale > 0.9 or pos.X.Scale < -0.9 or pos.X.Scale > 0.9 then
		-- Fall back to the center position if the current position is clearly off-screen
		warn("[UITag/Actions] Off-screen current position detected while resolving for " .. target.Name .. ". Falling back to {0.5, 0, 0.5, 0}")
		pos = UDim2.fromScale(0.5, 0.5)
	end

	target:SetAttribute(SLIDE_REST_ATTR, pos)

	return pos
end

--- Animate a target in according to a HowToOpen directive.
local function animateOpen(target: GuiObject, howToOpen: Types.HowToOpen | string)
	if howToOpen == "Scale" then
		-- Standard background blur + zoom (constants in Config.UIAnimationConfig).
		UXEffects.PanelTransition.open(target)
	elseif howToOpen == "Bounce" then
		UXEffects.Backdrop.track(target)
		UXEffects.Scale.bounce(target)
	else
		-- Background blur driven by the panel's actual visibility.
		UXEffects.Backdrop.track(target)
		local direction = Types.ParseSlideShorthand(howToOpen :: string)
		if direction then
			UXEffects.SlidePanel.slideIn(target, {
				direction = direction,
				targetPosition = resolveRestPosition(target),
			} :: any)
		else
			target.Visible = true
		end
	end
end

--- Animate a target out according to a HowToClose directive (or HowToOpen reversed).
local function animateClose(target: GuiObject, howToClose: Types.HowToClose | string)
	-- A focused TextBox (search, amount, code...) keeps the keyboard/scroll wheel
	-- captured by Roblox even after the panel closes, blocking the camera zoom
	-- until a click elsewhere (e.g. opening another UI) releases the focus.
	local focusedBox = UserInputService:GetFocusedTextBox()
	if focusedBox and focusedBox:IsDescendantOf(target) then
		focusedBox:ReleaseFocus()
	end

	if howToClose == "Scale" or howToClose == "Bounce" then
		-- Standard background blur + zoom (constants in Config.UIAnimationConfig).
		UXEffects.PanelTransition.close(target)
	elseif howToClose == "Fade" then
		UXEffects.Backdrop.track(target)
		UXEffects.Scale.fadeOut(target)
	elseif howToClose == "Instant" then
		UXEffects.Backdrop.track(target)
		target.Visible = false
	else
		-- Keeps tracking: the blur will clear once the panel becomes invisible.
		UXEffects.Backdrop.track(target)
		local direction = Types.ParseSlideShorthand(howToClose :: string)
		if direction then
			UXEffects.SlidePanel.slideOut(target, {
				direction = direction,
				targetPosition = resolveRestPosition(target),
			} :: any)
		else
			target.Visible = false
		end
	end
end

--============================================================================--
-- LEGACY
--============================================================================--

local function registerLegacy(UITag: any)
	-- Button: network-bound click (fires ActionRequest to server)
	UITag.RegisterHandler(TAGS.BUTTON, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local actionName = instance:GetAttribute("ActionName")
			if type(actionName) ~= "string" or actionName == "" then
				return
			end
			local actionData = instance:GetAttribute("ActionData")
			NetworkEvents.FireServer("ActionRequest", {
				Action = actionName,
				Data   = actionData,
			})
			log:Debug("ActionRequest sent: %s (Data: %s) from %s",
				actionName, tostring(actionData), instance.Name)
		end)
	end)

	-- Open: toggles visibility of target frames with animated modes
	UITag.RegisterHandler(TAGS.OPEN, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local now = os.clock()
			if now - globalLastToggle < GLOBAL_COOLDOWN then return end

			local targetTag = instance:GetAttribute("TargetTag")
			if type(targetTag) ~= "string" or targetTag == "" then
				return
			end
			local howToOpen: string = Utils.GetAttr(instance, "HowToOpen", HOW_TO_DEFAULT)

			local targets = CollectionService:GetTagged(targetTag)
			if #targets > 0 then
				globalLastToggle = now
			end

			for _, target in ipairs(targets) do
				if not target:IsA("GuiObject") then continue end
				if not isValidClientTarget(target) then continue end
				
				local isOpening = not target.Visible
				if isOpening then
					animateOpen(target, howToOpen)
				else
					-- Close using the matching close animation (Slide* reverses, others use popOut)
					animateClose(target, howToOpen)
				end
			end
		end)
	end)
end

--============================================================================--
-- CLOSE (pure close, no toggle)
--============================================================================--

local function registerClose(UITag: any)
	UITag.RegisterHandler(TAGS.CLOSE, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local now = os.clock()
			if now - globalLastToggle < GLOBAL_COOLDOWN then return end

			local targetTag = instance:GetAttribute("TargetTag")
			if type(targetTag) ~= "string" or targetTag == "" then
				return
			end
			local howToClose: string = Utils.GetAttr(instance, "HowToClose", HOW_TO_DEFAULT)

			local targets = CollectionService:GetTagged(targetTag)
			if #targets > 0 then
				globalLastToggle = now
			end

			for _, target in ipairs(targets) do
				if not target:IsA("GuiObject") then continue end
				if not isValidClientTarget(target) then continue end
				
				animateClose(target, howToClose)
			end
		end)
	end)
end

--============================================================================--
-- BURST / CONFETTI / SHAKE
--============================================================================--

local function registerBurst(UITag: any)
	UITag.RegisterHandler(TAGS.BURST, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local style = Utils.GetAttr(instance, "BurstStyle", "default") :: Types.BurstStyle
			local anchor = resolveAnchor(instance)
			if not anchor then return end
			local pos = Utils.GetCenterPosition(anchor)

			if style == "gold" then
				UXEffects.Burst.gold(pos)
			elseif style == "rainbow" then
				UXEffects.Burst.rainbow(pos)
			else
				local colorAttr = instance:GetAttribute("BurstColor")
				local config: { particleCount: number, lifetime: number, spread: number, colors: { Color3 }? } = {
					particleCount = Utils.GetAttr(instance, "particleCount", 20),
					lifetime      = Utils.GetAttr(instance, "lifetime",      1.0),
					spread        = Utils.GetAttr(instance, "spread",        360),
				}
				if colorAttr ~= nil then
					config.colors = { Utils.ToColor3(colorAttr) }
				end
				UXEffects.Burst.play(pos, config :: any)
			end
		end)
	end)
end

local function registerConfetti(UITag: any)
	UITag.RegisterHandler(TAGS.CONFETTI, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local style = Utils.GetAttr(instance, "ConfettiStyle", "default") :: Types.ConfettiStyle
			if style == "gold" then
				UXEffects.Confetti.gold()
			elseif style == "rainbow" then
				UXEffects.Confetti.rainbow()
			elseif style == "light" then
				UXEffects.Confetti.light()
			else
				UXEffects.Confetti.play()
			end
		end)
	end)
end

local function registerShake(UITag: any)
	UITag.RegisterHandler(TAGS.SHAKE, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local style = Utils.GetAttr(instance, "ShakeStyle", "default") :: Types.ShakeStyle
			for _, target in ipairs(Utils.ResolveTargets(instance)) do
				if not target:IsA("GuiObject") then continue end
				if style == "error" then
					UXEffects.Shake.error(target)
				elseif style == "impact" then
					local intensity: number = Utils.GetAttr(instance, "intensity", 15)
					UXEffects.Shake.impact(target, intensity)
				else
					local config = Utils.GetAttributes(instance, {
						"intensity", "duration", "frequency", "decay", "axis",
					})
					UXEffects.Shake.play(target, config :: any)
				end
			end
		end)
	end)
end

--============================================================================--
-- TOAST / SOUND
--============================================================================--

local function registerToast(UITag: any)
	UITag.RegisterHandler(TAGS.TOAST, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local message: string = Utils.GetAttr(instance, "ToastMessage", "")
			if message == "" then
				log:Warn("UIAction_Toast missing 'ToastMessage' on %s", instance:GetFullName())
				return
			end
			local toastType = Utils.GetAttr(instance, "ToastType", "Info") :: Types.ToastType
			local duration: number = Utils.GetAttr(instance, "ToastDuration", 3)

			if toastType == "Success" then
				UXEffects.Toast.success(message, duration)
			elseif toastType == "Warning" then
				UXEffects.Toast.warning(message, duration)
			elseif toastType == "Error" then
				UXEffects.Toast.error(message, duration)
			else
				UXEffects.Toast.info(message, duration)
			end
		end)
	end)
end

local function registerSound(UITag: any)
	UITag.RegisterHandler(TAGS.SOUND, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local soundId: string = Utils.GetAttr(instance, "SoundId", "")
			if soundId == "" then
				log:Warn("UIAction_Sound missing 'SoundId' on %s", instance:GetFullName())
				return
			end

			-- One-shot sound through SoundService for reliable playback even if
			-- the triggering UI is destroyed mid-playback.
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			sound.Volume  = Utils.GetAttr(instance, "Volume", 0.5)
			sound.Parent  = SoundService
			sound:Play()
			sound.Ended:Connect(function()
				sound:Destroy()
			end)
			-- Safety timeout: destroy the sound object even if Ended never fires.
			task.delay(10, function()
				if sound and sound.Parent then
					sound:Destroy()
				end
			end)
		end)
	end)
end

--============================================================================--
-- FLY TO UI / COUNTER
--============================================================================--

local function registerFlyToUI(UITag: any)
	UITag.RegisterHandler(TAGS.FLY_TO_UI, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local iconId: string = Utils.GetAttr(instance, "IconId", "")
			if iconId == "" then
				log:Warn("UIAction_FlyToUI missing 'IconId' on %s", instance:GetFullName())
				return
			end

			-- Target UI: first GuiObject matching TargetTag.
			local targetUI: GuiObject? = nil
			local targetTag = instance:GetAttribute("TargetTag")
			if type(targetTag) == "string" and targetTag ~= "" then
				for _, t in ipairs(CollectionService:GetTagged(targetTag)) do
					if t:IsA("GuiObject") then
						targetUI = t
						break
					end
				end
			end
			if not targetUI then
				log:Warn("UIAction_FlyToUI: no target resolved on %s", instance:GetFullName())
				return
			end

			local config = {
				iconId   = iconId,
				count    = Utils.GetAttr(instance, "Count",    3),
				iconSize = Utils.GetAttr(instance, "IconSize", 40),
				duration = Utils.GetAttr(instance, "Duration", 0.6),
				spread   = Utils.GetAttr(instance, "Spread",   60),
			}
			if instance:IsA("GuiObject") then
				local startPos = Utils.GetCenterPosition(instance)
				UXEffects.FlyToUI.play(startPos, targetUI, config)
			else
				UXEffects.FlyToUI.playFromCenter(targetUI, config)
			end
		end)
	end)
end

local function registerCounter(UITag: any)
	UITag.RegisterHandler(TAGS.COUNTER, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local value: number = Utils.ToNumber(instance:GetAttribute("Value"), 0) or 0
			local mode = Utils.GetAttr(instance, "Mode", "gain") :: Types.CounterMode
			local suffix: string = Utils.GetAttr(instance, "Suffix", "")

			local anchor = resolveAnchor(instance)
			if not anchor then return end
			local pos = Utils.GetCenterPosition(anchor)

			local suffixArg: string? = if suffix ~= "" then suffix else nil
			if mode == "loss" then
				UXEffects.Counter.loss(pos, value, suffixArg)
			else
				UXEffects.Counter.gain(pos, value, suffixArg)
			end
		end)
	end)
end

--============================================================================--
-- ACTION METHODS (registry CFG, data-driven as code)
--============================================================================--

local function registerAction(UITag: any)
	UITag.RegisterHandler(TAGS.ACTION, function(instance: Instance): (() -> ())?
		return bindClick(instance, function()
			local methodName = instance:GetAttribute("Method")
			if type(methodName) ~= "string" or methodName == "" then
				log:Warn("UI_BUTTON_ACTION missing a valid 'Method' attribute on %s", instance:GetFullName())
				return
			end

			local method = UIActionRegistry.Get(methodName)
			if not method then
				log:Warn("Unknown UI action method '%s' (on %s)", methodName, instance:GetFullName())
				return
			end

			method.Run({ player = player, button = instance })
		end)
	end)
end

--============================================================================--
-- PUBLIC API
--============================================================================--

function Actions.TriggerKeybind(keyName: string)
	if not playerGui then
		playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	end
	
	for instance, data in pairs(keybindRegistry) do
		local matched = false
		for _, k in ipairs(data.actionKeybinds) do
			if k == keyName then
				matched = true
				break
			end
		end
		
		if matched then
			if playerGui and instance:IsDescendantOf(playerGui) and (not instance:IsA("GuiButton") or instance.Active) then
				local isVisible = true
				local curr: Instance? = instance
				while curr and curr:IsA("GuiObject") do
					if not curr.Visible then
						isVisible = false
						break
					end
					curr = curr.Parent
				end
				
				-- Bypass visibility check for global HUD menus
				if instance:GetAttribute("GlobalKeybind") then
					isVisible = true
				end

				-- A Container.Visible=true left over on a disabled ScreenGui (leftover
				-- Studio state) must not trigger the action -- same check as
				-- UITagController.onPanelVisibleChanged / HudMenuController.isMenuOpen.
				if isVisible then
					local screenGui = instance:FindFirstAncestorWhichIsA("ScreenGui")
					if screenGui and not screenGui.Enabled then
						isVisible = false
					end
				end

				if isVisible then
					local ok, err: any = pcall(data.handler)
					if not ok then
						log:Warn("Action keybind handler error on %s: %s", instance:GetFullName(), tostring(err))
					end
				end
			end
		end
	end
end

function Actions.RegisterKeybindHandler(instance: Instance, handler: () -> ())
	local actionKeybind = instance:GetAttribute("ActionKeybind")
	if actionKeybind and type(actionKeybind) == "string" then
		local keys: { string } = {}
		for keyName in string.gmatch(actionKeybind, "([^,]+)") do
			table.insert(keys, keyName:match("^%s*(.-)%s*$") :: string)
		end
		keybindRegistry[instance] = {
			actionKeybinds = keys,
			handler = handler
		}
	end
end

function Actions.Register(UITag: any)
	registerLegacy(UITag)
	registerAction(UITag)
	registerClose(UITag)
	registerBurst(UITag)
	registerConfetti(UITag)
	registerShake(UITag)
	registerToast(UITag)
	registerSound(UITag)
	registerFlyToUI(UITag)
	registerCounter(UITag)
	log:Info("Actions handlers registered (%d tags).", TAG_COUNT)
end

return Actions
