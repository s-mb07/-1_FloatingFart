--!strict
--[[
	@module TrainingBubbleController
	@description Shows the fan boost bubbles (round pink bubble with a
	brick-stud texture, paper airplane, "x1.1"), each bobbing at a random
	spot of the screen that no shown UI (nor another bubble) covers, while the
	server has them waiting (player attributes TreadmillConfig.BubbleAttribute
	.. slot, set by TrainingBubbleService). The lower the multiplier, the
	bigger the bubble. Right after popping in, a bubble starts shrinking and
	is down to nothing at the end of TreadmillConfig.BubbleLifetime, when the
	server removes it. Clicking one bursts it (sound, swells then pops: flash,
	shockwave ring, 2D particle explosion) and asks the server to pop it (NetworkEvents "PopTrainingBubble", slot). A bubble the
	server removes early (the session ended) shrinks away quickly.
	Purely cosmetic: the server decides when a bubble exists and what it grants.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)
local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)

local Attribute = Fusion.Attribute
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local TrainingBubbleController = {}

local LocalPlayer = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
--- Same paper airplane as the XP gain icon (MainHUD/XpGainFrame/IconTemplate).
local ICON = "rbxassetid://82109037700647"
local COLORS = {
	Outline = Color3.fromRGB(20, 22, 40),
	Top = Color3.fromRGB(255, 120, 230),
	Bottom = Color3.fromRGB(220, 40, 190),
	--- Thin lines between the brick squares.
	Seam = Color3.fromRGB(150, 20, 130),
}
--- Bubble diameter (fraction of the screen height, below the top bar): the
--- BubbleMin multiplier gets SIZE_MAX, the BubbleMax one SIZE_MIN.
local SIZE_MAX = 0.24
local SIZE_MIN = 0.12
--- Brick texture: GRID x GRID small squares, each a random shade up to
--- SHADE_JITTER lighter or darker than its row's colour.
local GRID = 8
local SHADE_JITTER = 0.12
--- Candidate spots are a grid over the screen, this fraction of the bubble
--- radius apart; gap (px) kept from the screen edges and every shown UI.
local GRID_STEP = 0.5
local GAP = 12
--- A UI covering more than this share of the screen is a backdrop/overlay
--- (vignette, full-screen container), not something the bubble must avoid.
local MAX_OBSTACLE_SHARE = 0.5
local BOB_HEIGHT = 0.015
local BOB_SECONDS = 1.2
local APPEAR_SECONDS = 0.35
--- Burst: swells to BURST_SWELL x over BURST_SWELL_SECONDS, then pops: the
--- bubble collapses over BURST_COLLAPSE_SECONDS while a white flash, a pink
--- shockwave ring and two particle layers (bubble chunks, white sparks) fly
--- out. BURST_SCALE sizes the whole explosion (the particle ranges below are
--- already at that scale).
local BURST_SWELL = 1.35
local BURST_SWELL_SECONDS = 0.1
local BURST_COLLAPSE_SECONDS = 0.12
local BURST_SCALE = 0.8
--- Flash: a white disc from FLASH_FROM to FLASH_TO x the bubble, fading out.
local FLASH_FROM = 0.6
local FLASH_TO = 1.3
local FLASH_SECONDS = 0.18
--- Shockwave: a ring from the bubble's size to RING_GROWTH x, fading out.
local RING_GROWTH = 2.2
local RING_THICKNESS = 0.08
local RING_SECONDS = 0.4
--- Removed before its lifetime ended (session over): quick shrink.
local CANCEL_SECONDS = 0.25

type Bubble = {
	--- The slot attribute value it shows ("<serial>:<multiplier>").
	Key: string,
	Button: TextButton,
	--- Pop-in, lifetime shrink and burst all tween this.
	Scale: UIScale,
	Scope: Fusion.Scope<typeof(Fusion)>,
}

-- The bubbles on screen, by server slot.
local bubbles: { [number]: Bubble } = {}

--- A round frame `diameter` px wide centred on the bubble, in its ScreenGui
--- (destroyed with it).
local function disc(bubble: Bubble, diameter: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = bubble.Button.Position
	frame.Size = UDim2.fromOffset(diameter, diameter)
	frame.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	frame.Parent = bubble.Button.Parent
	return frame
end

--- The explosion itself: flash, shockwave ring, particles, collapse. The
--- bubble is cleaned up once the ring (the longest part) is gone.
local function pop(bubble: Bubble): ()
	local button = bubble.Button
	local diameter = button.AbsoluteSize.X * BURST_SCALE
	-- The bubble ScreenGui keeps the top-bar inset, the burst layer ignores it.
	local centre = button.AbsolutePosition
		+ button.AbsoluteSize / 2
		+ Vector2.new(0, GuiService:GetGuiInset().Y)
	local out = TweenInfo.new(RING_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	local flash = disc(bubble, diameter * FLASH_FROM)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0.1
	flash.ZIndex = 2
	local flashSize = UDim2.fromOffset(diameter * FLASH_TO, diameter * FLASH_TO)
	local flashInfo = TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(flash, flashInfo, { Size = flashSize, BackgroundTransparency = 1 }):Play()

	local ring = disc(bubble, diameter)
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Top
	stroke.Thickness = diameter * RING_THICKNESS
	stroke.Parent = ring
	local ringSize = UDim2.fromOffset(diameter * RING_GROWTH, diameter * RING_GROWTH)
	TweenService:Create(ring, out, { Size = ringSize }):Play()
	local fade = TweenService:Create(stroke, out, { Transparency = 1, Thickness = 0 })
	fade.Completed:Once(function()
		bubble.Scope:doCleanup()
	end)
	fade:Play()

	-- Chunks: 80% of the old burst (size 18-42, speed 450-1050), fewer pieces.
	UXEffects.Burst.play(centre, {
		colors = { COLORS.Top, COLORS.Bottom, COLORS.Seam },
		particleCount = 18,
		lifetime = 0.55,
		size = NumberRange.new(14, 34),
		speed = NumberRange.new(360, 840),
	})
	-- Sparks: small, quick, white.
	UXEffects.Burst.play(centre, {
		colors = { Color3.new(1, 1, 1), Color3.fromRGB(255, 220, 250) },
		particleCount = 14,
		lifetime = 0.35,
		size = NumberRange.new(5, 10),
		speed = NumberRange.new(560, 1040),
	})

	TweenService:Create(
		bubble.Scale,
		TweenInfo.new(BURST_COLLAPSE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Scale = 0 }
	):Play()
end

--- Burst animation then cleanup; the server is told right away.
local function burst(slot: number): ()
	local bubble = bubbles[slot]
	if not bubble then
		return
	end
	bubbles[slot] = nil
	Effects.Play("BubblePop")
	NetworkEvents.FireServer("PopTrainingBubble", slot)
	bubble.Button.Active = false
	local swell = TweenService:Create(
		bubble.Scale,
		TweenInfo.new(BURST_SWELL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = bubble.Scale.Scale * BURST_SWELL }
	)
	swell.Completed:Once(function()
		pop(bubble)
	end)
	swell:Play()
end

--- Shrinks the bubble down to nothing over `info`.
local function shrink(bubble: Bubble, info: TweenInfo): Tween
	local tween = TweenService:Create(bubble.Scale, info, { Scale = 0 })
	tween:Play()
	return tween
end

--- Unpopped bubble removed by the server: already shrunk to nothing at the
--- end of its lifetime, otherwise (session over) a quick shrink first.
local function expire(bubble: Bubble): ()
	bubble.Button.Active = false
	shrink(bubble, TweenInfo.new(CANCEL_SECONDS)).Completed:Once(function()
		bubble.Scope:doCleanup()
	end)
end

--- Diameter (fraction of the screen height) for a multiplier: bigger when lower.
local function sizeFor(multiplier: number): number
	local span = TreadmillConfig.BubbleMax - TreadmillConfig.BubbleMin
	local t = math.clamp((multiplier - TreadmillConfig.BubbleMin) / span, 0, 1)
	return SIZE_MAX + (SIZE_MIN - SIZE_MAX) * t
end

--- The GRID x GRID brick squares, shaded top to bottom, each a random shade.
local function bricks(scope: Fusion.Scope<typeof(Fusion)>): { Instance }
	local cells: { Instance } = {
		scope:New("UIGridLayout")({
			CellSize = UDim2.fromScale(1 / GRID, 1 / GRID),
			CellPadding = UDim2.new(),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index = 0, GRID * GRID - 1 do
		local row = index // GRID
		local jitter = (math.random() * 2 - 1) * SHADE_JITTER
		local color = COLORS.Top:Lerp(COLORS.Bottom, row / (GRID - 1)):Lerp(
			if jitter > 0 then Color3.new(1, 1, 1) else Color3.new(),
			math.abs(jitter)
		)
		table.insert(
			cells,
			scope:New("Frame")({
				LayoutOrder = index,
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				[Children] = scope:New("UIStroke")({
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = COLORS.Seam,
					Thickness = 1,
				}),
			})
		)
	end
	return cells
end

--- True when `object` and every GuiObject above it are Visible.
local function isShown(object: GuiObject): boolean
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

--- True when `object` actually draws something (or can be clicked).
local function draws(object: GuiObject): boolean
	if object:IsA("GuiButton") or object.BackgroundTransparency < 1 then
		return true
	end
	if object:IsA("ImageLabel") then
		return object.Image ~= "" and object.ImageTransparency < 1
	end
	if object:IsA("TextLabel") then
		return object.Text ~= "" and object.TextTransparency < 1
	end
	return false
end

--- Screen rects (min, max) of every shown UI in the enabled ScreenGuis.
local function obstacles(playerGui: PlayerGui, screenArea: number): { { Vector2 } }
	local rects = {}
	for _, gui in playerGui:GetChildren() do
		-- (the other bubbles count too: they never overlap each other)
		if not (gui:IsA("ScreenGui") and gui.Enabled) then
			continue
		end
		for _, object in gui:GetDescendants() do
			if not object:IsA("GuiObject") then
				continue
			end
			local size = object.AbsoluteSize
			if
				size.X * size.Y > screenArea * MAX_OBSTACLE_SHARE
				or not draws(object)
				or not isShown(object)
			then
				continue
			end
			table.insert(rects, { object.AbsolutePosition, object.AbsolutePosition + size })
		end
	end
	return rects
end

--- A bubble centre picked uniformly among ALL the screen spots no shown UI
--- overlaps (a grid scan, so a free spot is found whenever one exists), in
--- the bubble ScreenGui's space (IgnoreGuiInset off: same space as every
--- AbsolutePosition). Screen too crowded: the least-covered spot, random
--- among equals -- never a fixed fallback (that made every hard case land
--- on the same side).
local function freeSpot(playerGui: PlayerGui, size: number): UDim2
	local area = workspace.CurrentCamera.ViewportSize - Vector2.new(0, GuiService:GetGuiInset().Y)
	local radius = size * area.Y / 2
	-- Room for the bob (BOB_HEIGHT, downward) and the gap.
	local reach = Vector2.new(radius + GAP, radius + GAP + BOB_HEIGHT * area.Y)
	local rects = obstacles(playerGui, area.X * area.Y)
	local step = math.max(radius * GRID_STEP, 8)

	local free: { Vector2 } = {}
	local leastCovered: { Vector2 } = {}
	local leastArea = math.huge
	for x = reach.X, math.max(area.X - reach.X, reach.X), step do
		for y = reach.X, math.max(area.Y - reach.Y, reach.X), step do
			local centre = Vector2.new(x, y)
			local low, high = centre - Vector2.new(reach.X, reach.X), centre + reach
			local covered = 0
			for _, rect in rects do
				local w = math.min(high.X, rect[2].X) - math.max(low.X, rect[1].X)
				local h = math.min(high.Y, rect[2].Y) - math.max(low.Y, rect[1].Y)
				if w > 0 and h > 0 then
					covered += w * h
				end
			end
			if covered == 0 then
				table.insert(free, centre)
			elseif #free == 0 then
				if covered < leastArea then
					leastArea = covered
					leastCovered = { centre }
				elseif covered == leastArea then
					table.insert(leastCovered, centre)
				end
			end
		end
	end
	local pool = if #free > 0 then free else leastCovered
	local centre = pool[math.random(1, math.max(#pool, 1))] or area / 2
	-- Jitter so spots don't look aligned on the grid; at most GAP each way,
	-- so a free spot stays free (the gap absorbs it), and kept on screen.
	local jitter = math.min(step / 2, GAP)
	centre += Vector2.new((math.random() * 2 - 1) * jitter, (math.random() * 2 - 1) * jitter)
	centre = Vector2.new(
		math.clamp(centre.X, reach.X, math.max(area.X - reach.X, reach.X)),
		math.clamp(centre.Y, reach.X, math.max(area.Y - reach.Y, reach.X))
	)
	return UDim2.fromOffset(centre.X, centre.Y)
end

local function show(slot: number, key: string, value: string): ()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local size = sizeFor(tonumber(value) or TreadmillConfig.BubbleMin)
	local position = freeSpot(playerGui, size)
	local scope = Fusion.scoped(Fusion)
	local scale = scope:New("UIScale")({ Scale = 0 }) :: UIScale
	-- A CanvasGroup: its UICorner clips the bricks round.
	local body = scope:New("CanvasGroup")({
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			scope:New("Frame")({
				Name = "Bricks",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				[Children] = bricks(scope),
			}),
			scope:New("ImageLabel")({
				Name = "Icon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.4),
				Size = UDim2.fromScale(0.8, 0.8),
				BackgroundTransparency = 1,
				Image = ICON,
				ZIndex = 2,
			}),
			scope:New("TextLabel")({
				Name = "Value",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.78),
				Size = UDim2.fromScale(0.8, 0.3),
				BackgroundTransparency = 1,
				FontFace = FONT,
				Text = "x" .. value,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = 3,
				[Children] = scope:New("UIStroke")({ Color = COLORS.Outline, Thickness = 2.5 }),
			}),
		},
	}) :: CanvasGroup
	local button = scope:New("TextButton")({
		Name = "Bubble",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromScale(size, size),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		-- ButtonHoverController would read the pop-in UIScale (0) as the rest
		-- scale and shrink the bubble away on hover; it has its own burst.
		[Attribute("NoHoverFX")] = true,
		[OnEvent("Activated")] = function()
			burst(slot)
		end,
		[Children] = {
			scale,
			scope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			scope:New("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = COLORS.Outline,
				Thickness = 4,
			}),
			body,
		},
	}) :: TextButton
	scope:New("ScreenGui")({
		Name = "TrainingBubble",
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = playerGui,
		[Children] = button,
	})
	local bubble: Bubble = { Key = key, Button = button, Scale = scale, Scope = scope }
	bubbles[slot] = bubble

	-- Pops in, then starts shrinking right away; down to nothing when the
	-- server removes it. (Started on Completed: a delayed tween on the same
	-- UIScale would cancel the pop-in as soon as it is played.)
	local popIn = TweenService:Create(
		scale,
		TweenInfo.new(APPEAR_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	popIn.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and bubbles[slot] == bubble then
			shrink(
				bubble,
				TweenInfo.new(
					TreadmillConfig.BubbleLifetime - APPEAR_SECONDS,
					Enum.EasingStyle.Linear
				)
			)
		end
	end)
	popIn:Play()
	TweenService:Create(
		button,
		TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = position + UDim2.fromScale(0, BOB_HEIGHT) }
	):Play()
end

local function refresh(slot: number): ()
	local key = LocalPlayer:GetAttribute(TreadmillConfig.BubbleAttribute .. slot)
	local shown = bubbles[slot]
	if shown and shown.Key ~= key then
		-- Not popped here (a popped one already left `bubbles`): expired.
		bubbles[slot] = nil
		expire(shown)
	end
	local value = if type(key) == "string" then key:match(":(.+)$") else nil
	if value and not bubbles[slot] then
		show(slot, key :: string, value)
	end
end

function TrainingBubbleController:Init(): () end

function TrainingBubbleController:Start(): ()
	for slot = 1, TreadmillConfig.BubbleSlots do
		LocalPlayer:GetAttributeChangedSignal(TreadmillConfig.BubbleAttribute .. slot)
			:Connect(function()
				refresh(slot)
			end)
		refresh(slot)
	end
end

return TrainingBubbleController
