--!strict
--[[
	@module ButtonHoverController
	@description Hover/press feedback for every GuiButton in PlayerGui,
	picked up as soon as it appears (cloned list cards included):

	  - a button WITH an icon (a descendant ImageLabel named "Icon" or
	    "Image", like the HUD and shop buttons): on hover the ICON grows
	    (ICON_HOVER_SCALE) and tilts right (ICON_TILT degrees) -- the button
	    itself keeps its size, only its press squash remains;
	  - any other button grows a bit (HOVER_FACTOR), via UXEffects.ButtonFX;
	  - every button plays "UIClick" when activated and "UIHover" when the
	    mouse enters it (no hover sound on a touch-only device: a tap would
	    play both).

	Buttons a panel/controller already wired with its own ButtonFX call keep
	that effect: the pick-up is deferred one step and ButtonFX.attach is
	idempotent, so nothing stacks (the icon effect is added on top). Opt a
	button out with the boolean attribute `NoHoverFX` = true (set in Studio);
	set at runtime (ButtonFX.setPressed, an owned shop pass), it mutes the
	icon hover and hover sound from then on.

	The rest scale is the button's own UIScale (if the designer set one), so
	a button authored at 0.9 grows from 0.9, not from 1. The icon's rest
	rotation is the one authored in Studio.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

--- Hover / press size relative to the button's rest scale.
local HOVER_FACTOR = 1.08
local PRESS_FACTOR = 0.95
--- Icon hover: grows to this scale and tilts this many degrees to the right.
local ICON_HOVER_SCALE = 1.15
local ICON_TILT = 12
local ICON_IN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ICON_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ICON_NAMES = { Icon = true, Image = true }
local OPT_OUT_ATTRIBUTE = "NoHoverFX"

local ButtonHoverController = {}

--- First descendant ImageLabel named like an icon, nearest first.
local function findIcon(button: GuiButton): ImageLabel?
	for _, descendant in button:GetDescendants() do
		if descendant:IsA("ImageLabel") and ICON_NAMES[descendant.Name] then
			return descendant
		end
	end
	return nil
end

--- Grow + tilt `icon` while `button` is hovered.
local function attachIconFX(button: GuiButton, icon: ImageLabel): ()
	local uiScale = icon:FindFirstChildOfClass("UIScale")
	if not uiScale then
		local created = Instance.new("UIScale")
		created.Parent = icon
		uiScale = created
	end
	local scale = uiScale :: UIScale
	local restScale = scale.Scale
	local restRotation = icon.Rotation

	button.MouseEnter:Connect(function()
		if button:GetAttribute(OPT_OUT_ATTRIBUTE) == true then
			return
		end
		TweenService:Create(scale, ICON_IN, { Scale = restScale * ICON_HOVER_SCALE }):Play()
		TweenService:Create(icon, ICON_IN, { Rotation = restRotation + ICON_TILT }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, ICON_OUT, { Scale = restScale }):Play()
		TweenService:Create(icon, ICON_OUT, { Rotation = restRotation }):Play()
	end)
end

local function track(instance: Instance): ()
	if not instance:IsA("GuiButton") then
		return
	end
	-- Deferred: let the owning panel attach its own ButtonFX first.
	task.defer(function()
		if not instance.Parent or instance:GetAttribute(OPT_OUT_ATTRIBUTE) == true then
			return
		end
		local uiScale = instance:FindFirstChildOfClass("UIScale")
		local rest = if uiScale then uiScale.Scale else 1
		local icon = findIcon(instance)
		if icon then
			attachIconFX(instance, icon)
		end
		instance.Activated:Connect(function()
			Effects.Play("UIClick")
		end)
		instance.MouseEnter:Connect(function()
			if
				UserInputService.MouseEnabled
				and instance:GetAttribute(OPT_OUT_ATTRIBUTE) ~= true
			then
				Effects.Play("UIHover")
			end
		end)
		UXEffects.ButtonFX.attach(instance, {
			normalScale = rest,
			-- With an icon, the icon carries the hover: the button stays put
			hoverScale = if icon then rest else rest * HOVER_FACTOR,
			pressScale = rest * PRESS_FACTOR,
		})
	end)
end

function ButtonHoverController:Init(): () end

function ButtonHoverController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, descendant in playerGui:GetDescendants() do
		track(descendant)
	end
	playerGui.DescendantAdded:Connect(track)
end

return ButtonHoverController
