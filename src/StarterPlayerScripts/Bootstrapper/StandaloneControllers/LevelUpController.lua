--!strict
--[[
	@module LevelUpController
	@description Level-up banner (MainHUD/LevelUpFrame). On a level-up it
	pops in (UXEffects.Scale), two confetti cannons fire from the bottom
	corners (UXEffects.Confetti.cannons), it stays HOLD_SECONDS with the new
	values, then pops out.

	  - Level : "Level <old> > Level <new>"
	  - Lengh : "Lengh <old> studs > <new> studs" (real reach,
	            TraversalProgressionConfig.GetMaxLength)

	Honors XPHold/XPFlush like BarSpeedController, so the banner only shows
	when the treadmill part lands and the HUD level actually changes.
	Drops (rebirth resets to level 1) and the very first level received at
	load are not level-ups and show nothing. A new level-up while the banner
	is up refreshes the texts, bounces it and restarts the hold timer.

	Every label is paired with a `TextStroke` overlay child carrying the same
	text. MainHUD has ResetOnSpawn = false: resolved once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TraversalProgressionConfig = require(ReplicatedStorage.Config.TraversalProgressionConfig)
local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local Effects = require(Bootstrapper.Effects)
local PlayerVFX = require(Bootstrapper.Libraries.PlayerVFX)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local HOLD_SECONDS = 3
local POP_IN_SECONDS = 0.45
local POP_OUT_SECONDS = 0.25
--- Vertical position (screen scale) of the banner: upper middle, clear of the
--- tutorial banner at the top.
local BANNER_Y_SCALE = 0.3
--- Banner height (screen scale): big, like the reference level-up text.
local BANNER_HEIGHT_SCALE = 0.17
--- Paper-plane palette: paper white, sky blues, sunny gold, pink.
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(120, 205, 255),
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(255, 215, 70),
	Color3.fromRGB(255, 120, 200),
}

local LevelUpController = {}

local frame: Frame? = nil
local levelLabels: { TextLabel } = {}
local lengthLabels: { TextLabel } = {}

local currentLevel: number? = nil
local pendingLevel: number? = nil
local holding = false
local showToken = 0

local function withStroke(label: TextLabel): { TextLabel }
	return { label, label:WaitForChild("TextStroke") :: TextLabel }
end

local function setText(labels: { TextLabel }, text: string): ()
	for _, label in labels do
		label.Text = text
	end
end

local function show(oldLevel: number, newLevel: number): ()
	local banner = frame
	if not banner then
		return
	end
	setText(levelLabels, ("Level %d > Level %d"):format(oldLevel, newLevel))
	setText(
		lengthLabels,
		("Lengh %d studs > %d studs"):format(
			TraversalProgressionConfig.GetMaxLength(oldLevel),
			TraversalProgressionConfig.GetMaxLength(newLevel)
		)
	)

	showToken += 1
	local token = showToken
	if banner.Visible then
		UXEffects.Scale.bounce(banner, { fromScale = 0.85 })
	else
		UXEffects.Scale.popIn(banner, { fromScale = 0, duration = POP_IN_SECONDS })
	end
	UXEffects.Confetti.cannons(CONFETTI_COLORS)
	Effects.Play("LevelUp")
	PlayerVFX.Play("LevelUpVFX")

	task.delay(POP_IN_SECONDS + HOLD_SECONDS, function()
		if token == showToken then
			-- popOut hides the banner itself; a newer level-up cancels it
			UXEffects.Scale.popOut(banner, { duration = POP_OUT_SECONDS })
		end
	end)
end

local function flush(): ()
	local newLevel = pendingLevel
	if not newLevel then
		return
	end
	pendingLevel = nil
	local previous = currentLevel
	currentLevel = newLevel
	if previous and newLevel > previous then
		show(previous, newLevel)
	end
end

function LevelUpController:Init(): ()
	EventBus.Traversal.LevelChanged:Connect(function(newLevel: number)
		pendingLevel = newLevel
		if not holding then
			flush()
		end
	end)
	EventBus.Traversal.XPHold:Connect(function(hold: boolean)
		holding = hold
		if not hold then
			flush()
		end
	end)
	EventBus.Traversal.XPFlush:Connect(flush)
end

function LevelUpController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/LevelUpFrame", function(instance: Instance)
		local banner = instance :: Frame
		frame = banner
		banner.Position = UDim2.new(banner.Position.X, UDim.new(BANNER_Y_SCALE, 0))
		banner.Size = UDim2.new(banner.Size.X, UDim.new(BANNER_HEIGHT_SCALE, 0))
		banner.BackgroundTransparency = 1 -- floating text over the world, no dark band
		levelLabels = withStroke(banner:WaitForChild("Level") :: TextLabel)
		lengthLabels = withStroke(banner:WaitForChild("Lengh") :: TextLabel)
		banner.Visible = false
	end)
end

return LevelUpController
