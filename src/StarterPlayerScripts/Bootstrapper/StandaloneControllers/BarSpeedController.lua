--!strict
--[[
	@module BarSpeedController
	@description Drives the Studio-authored traversal bar in
	MainHUD/StaminaBar + MainHUD/BottomHUD/LevelBar. Display only, same numbers TraversalHudController
	shows:
	- `StaminaBar/Progress` width + `StaminaBar/TextProgres` ("N/100") from
	  EventBus.Traversal.StaminaChanged. The server only pushes while a probe
	  flies (and once on stop, to refill), so the bar starts full.
	  The whole `StaminaBar` is only visible while the LOCAL player's probe
	  flies: popped in on EventBus.Traversal.Started, popped out on Stopped
	  (out of stamina or any other stop, as the walk to the probe begins).
	  The server pushes stamina in steps; the fill and the "N/100" text
	  glide toward the latest value every frame (exponential smoothing)
	  instead of jumping. The fill keeps its Studio color at every level.
	  Within a flight stamina only ever goes DOWN: the refill the server
	  pushes when the flight stops is ignored, so the bar never climbs back
	  while it pops out (the next take-off restarts it full). The per-frame
	  loop only runs while the bar is shown or still
	  catching up.
	- `TextLevel` ("Level N"), `TextProges` ("got/cost" XP inside the current
	  level, "MAX" at the cap) + `FrameProgres` width (got / cost), from
	  EventBus.Traversal.LevelChanged / XPChanged.
	- `TextTotalLength` ("Total Length : N") = total traversal XP earned
	  (the "fake length"), compact-formatted (2.50M).

	Level and XP honor XPHold/XPFlush (driven by XPGainController): they only
	change when a flying "+N exp" lands in the bar, and always travel
	together. A landed gain animates the bar: the fill tweens to its new
	width (on a level up it fills to the end, then restarts from 0), the
	"got/cost" and "Total Length" numbers count up (GAIN_COUNT_TIME), the
	bar punches (GAIN_PUNCH_SCALE) and the fill flashes white.

	Every label is paired with a `TextStroke` overlay child carrying the same
	text. MainHUD has ResetOnSpawn = false: resolved once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)
local TraversalProgressionConfig = require(ReplicatedStorage.Config.TraversalProgressionConfig)
local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

--- Display scale, matches TraversalHudController's "N / 100".
local NORMALIZED_MAX = 100
--- Stamina smoothing speed (1/s): higher = the fill catches up faster.
local STAMINA_SMOOTHING = 10

local BarSpeedController = {}

local staminaFraction = 1 -- latest server value
local shownStamina = 1 -- what the bar currently draws (glides toward staminaFraction)
local staminaLoop: RBXScriptConnection? = nil
local level: number? = nil
local xp: number? = nil
local threshold: number? = nil -- nil = max level (no next threshold)
local pendingLevel: number? = nil
local pendingXp: { xp: number, threshold: number? }? = nil
local holding = false

local probeActive = false
local staminaBar: GuiObject? = nil
local staminaFill: GuiObject? = nil
local xpFill: GuiObject? = nil
local staminaLabels: { TextLabel } = {}
local levelLabels: { TextLabel } = {}
local xpLabels: { TextLabel } = {}
local lengthLabels: { TextLabel } = {}
local rebirthLabels: { TextLabel } = {}
local rebirthBonusPercent = 0

local function setText(labels: { TextLabel }, text: string): ()
	for _, label in labels do
		label.Text = text
	end
end

--- XP gain feedback (see header).
local GAIN_COUNT_TIME = 0.35
local GAIN_PUNCH_SCALE = 1.05
local GAIN_PUNCH_IN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GAIN_PUNCH_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local GAIN_FLASH = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GAIN_FLASH_TRANSPARENCY = 0.35

local levelBarScale: UIScale? = nil
local fillFlash: Frame? = nil
--- Numbers the labels currently show (the count-up starts from them).
local shownGot = 0
local shownTotal = 0
local countAlpha: NumberValue = Instance.new("NumberValue")
local countTween: Tween? = nil

local FILL_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FILL_TO_FULL_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local fillTweens: { [GuiObject]: Tween } = {}

--- Sets `fill`'s width to `fraction`. `animate` tweens it; `wrap` (a level
--- up) first fills the bar to the end, then restarts it from 0.
local function setFill(fill: GuiObject?, fraction: number, animate: boolean?, wrap: boolean?): ()
	if not fill then
		return
	end
	local size = fill.Size
	local goal = UDim2.new(fraction, 0, size.Y.Scale, size.Y.Offset)
	local running = fillTweens[fill]
	if running then
		running:Cancel()
		fillTweens[fill] = nil
	end
	if not animate then
		fill.Size = goal
		return
	end
	if wrap then
		local toFull = TweenService:Create(fill, FILL_TO_FULL_TWEEN, {
			Size = UDim2.new(1, 0, size.Y.Scale, size.Y.Offset),
		})
		fillTweens[fill] = toFull
		toFull.Completed:Once(function(state: Enum.PlaybackState)
			if state ~= Enum.PlaybackState.Completed then
				return
			end
			fill.Size = UDim2.new(0, 0, size.Y.Scale, size.Y.Offset)
			local regrow = TweenService:Create(fill, FILL_TWEEN, { Size = goal })
			fillTweens[fill] = regrow
			regrow:Play()
		end)
		toFull:Play()
		return
	end
	local tween = TweenService:Create(fill, FILL_TWEEN, { Size = goal })
	fillTweens[fill] = tween
	tween:Play()
end

local function withStroke(label: TextLabel): { TextLabel }
	return { label, label:WaitForChild("TextStroke") :: TextLabel }
end

--- Draws `shownStamina` (fill width + "N/100").
local function drawStamina(): ()
	setFill(staminaFill, shownStamina)
	setText(
		staminaLabels,
		("%d/%d"):format(math.floor(shownStamina * NORMALIZED_MAX + 0.5), NORMALIZED_MAX)
	)
end

--- Per-frame glide of the stamina fill toward the server value. Stops
--- itself once the bar is hidden and caught up.
local function ensureStaminaLoop(): ()
	if staminaLoop then
		return
	end
	staminaLoop = RunService.RenderStepped:Connect(function(deltaTime: number)
		local alpha = 1 - math.exp(-STAMINA_SMOOTHING * deltaTime)
		shownStamina += (staminaFraction - shownStamina) * alpha
		local settled = math.abs(staminaFraction - shownStamina) < 0.001
		if settled then
			shownStamina = staminaFraction
		end
		drawStamina()
		if settled and not probeActive and staminaLoop then
			staminaLoop:Disconnect()
			staminaLoop = nil
		end
	end)
end

local function setStaminaBarShown(shown: boolean): ()
	local bar = staminaBar
	if not bar then
		return
	end
	if shown then
		UXEffects.Scale.popIn(bar, { fromScale = 0.6, duration = 0.3 })
	elseif bar.Visible then
		UXEffects.Scale.popOut(bar, { toScale = 0.6, duration = 0.2, easingStyle = "Quad" })
	end
end

--- "got/cost" + "Total Length" texts for the given values.
local function writeXpTexts(got: number, cost: number, total: number): ()
	setText(xpLabels, ("%d/%d"):format(math.floor(got + 0.5), cost))
	setText(lengthLabels, "Total Length : " .. NumberUtil.FormatCompact(math.floor(total + 0.5)))
end

--- Bar punch + white flash on the fill: the "XP landed" hit.
local function playGainHit(): ()
	local scale = levelBarScale
	if scale then
		local punch = TweenService:Create(scale, GAIN_PUNCH_IN, { Scale = GAIN_PUNCH_SCALE })
		punch.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				TweenService:Create(scale, GAIN_PUNCH_OUT, { Scale = 1 }):Play()
			end
		end)
		punch:Play()
	end
	local flash = fillFlash
	if flash then
		flash.BackgroundTransparency = GAIN_FLASH_TRANSPARENCY
		TweenService:Create(flash, GAIN_FLASH, { BackgroundTransparency = 1 }):Play()
	end
end

local function render(): ()
	setText(rebirthLabels, ("Rebirth: +%d%%"):format(rebirthBonusPercent))
	if level then
		setText(levelLabels, ("Level %d"):format(level))
	end
end

--- XP texts + fill. `gained`: a landed gain (animated); `wrap`: it crossed a level.
local function renderXp(gained: boolean, wrap: boolean): ()
	if not (level and xp) then
		return
	end
	local total = xp :: number
	-- XP inside the current level: level start = next threshold - this level's cost.
	local cost = TraversalProgressionConfig.GetLevelCost(level)
	if not cost or not threshold then
		setText(xpLabels, "MAX")
		setText(lengthLabels, "Total Length : " .. NumberUtil.FormatCompact(total))
		setFill(xpFill, 1, gained)
		return
	end
	local got = math.clamp(math.floor(total) - (threshold - cost), 0, cost)
	setFill(xpFill, got / cost, gained, wrap)

	if countTween then
		countTween:Cancel()
		countTween = nil
	end
	if not gained then
		shownGot, shownTotal = got, total
		writeXpTexts(got, cost, total)
		return
	end
	-- Count up from what is on screen (from 0 inside a new level)
	local fromGot = if wrap then 0 else shownGot
	local fromTotal = shownTotal
	shownGot, shownTotal = got, total
	countAlpha.Value = 0
	local tween = TweenService:Create(
		countAlpha,
		TweenInfo.new(GAIN_COUNT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	local connection = countAlpha.Changed:Connect(function(alpha: number)
		writeXpTexts(fromGot + (got - fromGot) * alpha, cost, fromTotal + (total - fromTotal) * alpha)
	end)
	tween.Completed:Once(function()
		connection:Disconnect()
	end)
	countTween = tween
	tween:Play()
	playGainHit()
end

local function flush(): ()
	local gained = false
	if pendingXp then
		gained = xp ~= nil and pendingXp.xp > (xp :: number)
		xp = pendingXp.xp
		threshold = pendingXp.threshold
		pendingXp = nil
	end
	local leveledUp = false
	if pendingLevel then
		leveledUp = level ~= nil and pendingLevel > level
		level = pendingLevel
		pendingLevel = nil
		if leveledUp and levelLabels[1] then
			-- The stroke overlay is a child of the label: one UIScale bounces both
			UXEffects.Scale.bounce(levelLabels[1], { fromScale = 0.7, duration = 0.5 })
		end
	end
	render()
	renderXp(gained, leveledUp)
end

--- Rebirth multiplier x(R) shown as "+(x - 1) * 100 %" from the `Traversal` snapshot.
local function absorbRebirths(data: any): ()
	local traversal = data and data.Traversal
	if type(traversal) ~= "table" then
		return
	end
	local multiplier = RebirthConfig.GetMultiplier(tonumber(traversal.Rebirths) or 0)
	rebirthBonusPercent = math.round((multiplier - 1) * 100)
	render()
end

function BarSpeedController:Init(): ()
	PlayerDataFetcher.OnReady(absorbRebirths)
	EventBus.Data.Updated:Connect(absorbRebirths)
	EventBus.Traversal.StaminaChanged:Connect(function(current: number, max: number)
		local fraction = if max > 0 then math.clamp(current / max, 0, 1) else 0
		-- Only down: the stop-time refill must not show (Started resets to full)
		if fraction < staminaFraction then
			staminaFraction = fraction
			ensureStaminaLoop()
		end
	end)
	EventBus.Traversal.Started:Connect(function(player: Player)
		if player == Players.LocalPlayer then
			probeActive = true
			-- a fresh launch always starts with the full length
			staminaFraction = 1
			shownStamina = 1
			drawStamina()
			setStaminaBarShown(true)
			ensureStaminaLoop()
		end
	end)
	EventBus.Traversal.Stopped:Connect(function(player: Player)
		if player == Players.LocalPlayer then
			probeActive = false
			setStaminaBarShown(false)
		end
	end)

	EventBus.Traversal.LevelChanged:Connect(function(newLevel: number)
		pendingLevel = newLevel
		if not holding then
			flush()
		end
	end)
	EventBus.Traversal.XPChanged:Connect(function(newXp: number, newThreshold: number?)
		pendingXp = { xp = newXp, threshold = newThreshold }
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

function BarSpeedController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	SafeUIResolver.WaitForPathStringAsync(
		playerGui,
		"MainHUD/StaminaBar",
		function(stamina: Instance)
			local bar = stamina :: GuiObject
			staminaBar = bar
			staminaFill = stamina:WaitForChild("Progress") :: GuiObject
			staminaLabels = withStroke(stamina:WaitForChild("TextProgres") :: TextLabel)
			bar.Visible = probeActive
			drawStamina()
		end
	)
	SafeUIResolver.WaitForPathStringAsync(
		playerGui,
		"MainHUD/BottomHUD/LevelBar",
		function(bar: Instance)
			local barObject = bar :: GuiObject
			local scale = Instance.new("UIScale")
			scale.Name = "GainPunchScale"
			scale.Parent = barObject
			levelBarScale = scale
			local fill = bar:WaitForChild("FrameProgres") :: GuiObject
			xpFill = fill
			-- White layer over the fill, flashed on each gain
			local flash = Instance.new("Frame")
			flash.Name = "GainFlash"
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundColor3 = Color3.new(1, 1, 1)
			flash.BackgroundTransparency = 1
			flash.BorderSizePixel = 0
			flash.ZIndex = fill.ZIndex + 1
			local corner = fill:FindFirstChildOfClass("UICorner")
			if corner then
				corner:Clone().Parent = flash
			end
			flash.Parent = fill
			fillFlash = flash
			rebirthLabels = withStroke(bar:WaitForChild("RebirthAdd") :: TextLabel)
			levelLabels = withStroke(bar:WaitForChild("TextLevel") :: TextLabel)
			xpLabels = withStroke(bar:WaitForChild("TextProges") :: TextLabel)
			lengthLabels = withStroke(bar:WaitForChild("TextTotalLength") :: TextLabel)
			render()
			renderXp(false, false)
		end
	)
end

return BarSpeedController
