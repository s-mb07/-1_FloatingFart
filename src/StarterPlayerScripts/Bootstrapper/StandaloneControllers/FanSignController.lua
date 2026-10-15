--!strict
--[[
	@module FanSignController
	@description A floating sign above each training fan (treadmill Hitbox,
	TagNames.Treadmill), built with Fusion, client only:

	      x30            <- the fan's LengthMultiplier, big, in the fan's
	     LENGTH             colors (FanSignConfig gradient)
	  [ 🔒 3 REBIRTHS ]  <- what it takes, or its state for THIS player

	The pill reads, from TreadmillConfig + the player attribute
	TreadmillConfig.AccessAttribute (fans this player may use, kept by
	TreadmillService through AccessGate -- rebirths, gamepass, FreeMode):
	  - free fan                       "FREE"            (green)
	  - usable, earned with rebirths   "✓ UNLOCKED"      (green)
	  - usable, Robux fan              "✓ OWNED"         (green)
	  - locked, rebirths               "🔒 3 REBIRTHS"   (white)
	  - locked, Robux                  "<robux>299"      (gold)
	The sign bobs gently. Display only: access is decided by the server.

	StreamingEnabled: each sign lives in its own Fusion scope, cleaned up
	(billboard, bob tween, connections) when its hitbox streams out, and built
	again when it streams back in -- nothing piles up on low-memory devices.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)
local Bootstrapper = script.Parent.Parent
local FanSignConfig = require(Bootstrapper.Config.FanSignConfig)

local Children = Fusion.Children

local FanSignController = {}

local LocalPlayer = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
--- Roblox's built-in Robux glyph (private-use character of the engine fonts).
local ROBUX = utf8.char(0xE002)
local COLORS = {
	Outline = Color3.fromRGB(20, 22, 40),
	Ok = Color3.fromRGB(120, 255, 140),
	Locked = Color3.fromRGB(255, 255, 255),
	Robux = Color3.fromRGB(255, 220, 90),
}
--- Sign size (studs) relative to the fan: width = hitbox width x this, clamped.
local WIDTH_SCALE, MIN_WIDTH, MAX_WIDTH = 1, 8, 16
--- Height above the top of the fan model (studs), and the bob amplitude / period.
local LIFT = 2.2
local BOB_HEIGHT = 0.6
local BOB_SECONDS = 1.6
local MAX_DISTANCE = 150

-- Created in Init (modules stay side-effect-free at require, README §9.8);
-- lives as long as the client.
local scope: Fusion.Scope<typeof(Fusion)>
local access: Fusion.Value<{ [string]: boolean }, { [string]: boolean }>
--- One inner scope per sign, by hitbox (cleaned up when it streams out).
local signs: { [Instance]: Fusion.Scope<typeof(Fusion)> } = {}

local function readAccess(): ()
	local ids: { [string]: boolean } = {}
	local raw = LocalPlayer:GetAttribute(TreadmillConfig.AccessAttribute)
	if type(raw) == "string" then
		for id in raw:gmatch("[^,]+") do
			ids[id] = true
		end
	end
	access:set(ids)
end

--- Text + color of the requirement pill of a fan.
local function status(def: TreadmillConfig.TreadmillDef, usable: boolean): (string, Color3)
	local free = def.RequiredRebirths == nil and def.GamePass == nil
	if free then
		return "FREE", COLORS.Ok
	elseif usable then
		return if def.PriceRobux and not def.RequiredRebirths then "✓ OWNED" else "✓ UNLOCKED",
			COLORS.Ok
	elseif def.RequiredRebirths then
		local rebirths = def.RequiredRebirths :: number
		return ("🔒 %d %s"):format(rebirths, if rebirths == 1 then "REBIRTH" else "REBIRTHS"),
			COLORS.Locked
	end
	return ("%s%d"):format(ROBUX, def.PriceRobux or 0), COLORS.Robux
end

local function textLabel(signScope: Fusion.Scope<typeof(Fusion)>, props: { [any]: any }): TextLabel
	local base: { [any]: any } = {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}
	for key, value in props do
		base[key] = value
	end
	return signScope:New("TextLabel")(base) :: TextLabel
end

local function build(hitbox: Instance): ()
	if signs[hitbox] or not hitbox:IsA("BasePart") then
		return
	end
	local id = hitbox:GetAttribute(TagNames.Attr.Id)
	local def = if type(id) == "string" then TreadmillConfig.Treadmills[id] else nil
	local colors = if type(id) == "string" then FanSignConfig[id] else nil
	if not (def and colors and type(id) == "string") then
		return
	end
	local signScope = scope:innerScope()
	signs[hitbox] = signScope

	local width = math.clamp(hitbox.Size.X * WIDTH_SCALE, MIN_WIDTH, MAX_WIDTH)
	local height = width * 0.62
	local fan = hitbox.Parent or hitbox

	-- Above the whole fan model (ring, crystals...), over its head at the +Z
	-- end, never below the hitbox top. Streaming sends the fan's parts one by
	-- one, so this is re-run as they arrive (computed once, the sign stayed
	-- at the height of whatever had streamed in first -- often the base).
	local function restOffset(): Vector3
		local top = hitbox.Position.Y + hitbox.Size.Y / 2
		for _, part in fan:GetDescendants() do
			if part:IsA("BasePart") and part ~= hitbox and part.Transparency < 1 then
				-- Vertical half-extent of the (rotated) part
				local cf, size = part.CFrame, part.Size
				local halfHeight = 0.5
					* (
						math.abs(cf.RightVector.Y) * size.X
						+ math.abs(cf.UpVector.Y) * size.Y
						+ math.abs(cf.LookVector.Y) * size.Z
					)
				top = math.max(top, part.Position.Y + halfHeight)
			end
		end
		return Vector3.new(0, top - hitbox.Position.Y + LIFT + height / 2, hitbox.Size.Z / 2 - 1)
	end
	local rest = restOffset()

	local pillText = signScope:Computed(function(use)
		local text = status(def, use(access)[id] == true)
		return text
	end)
	local pillColor = signScope:Computed(function(use)
		local _, color = status(def, use(access)[id] == true)
		return color
	end)

	local sign = signScope:New("BillboardGui")({
		Name = "FanSign_" .. id,
		Adornee = hitbox,
		StudsOffsetWorldSpace = rest,
		Size = UDim2.fromScale(width, height),
		LightInfluence = 0,
		MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = {
			signScope:New("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			-- "x30": the multiplier, big, in the fan's colors
			textLabel(signScope, {
				Name = "Multiplier",
				LayoutOrder = 1,
				Size = UDim2.fromScale(1, 0.46),
				Text = ("x%d"):format(def.LengthMultiplier),
				TextColor3 = Color3.new(1, 1, 1),
				[Children] = {
					signScope:New("UIGradient")({
						Rotation = 90,
						Color = ColorSequence.new(colors.Top, colors.Bottom),
					}),
					signScope:New("UIStroke")({ Color = COLORS.Outline, Thickness = 4 }),
				},
			}),
			textLabel(signScope, {
				Name = "Unit",
				LayoutOrder = 2,
				Size = UDim2.fromScale(1, 0.2),
				Text = "LENGTH",
				TextColor3 = Color3.new(1, 1, 1),
				[Children] = signScope:New("UIStroke")({ Color = COLORS.Outline, Thickness = 2.5 }),
			}),
			-- Requirement / state pill
			signScope:New("Frame")({
				Name = "Pill",
				LayoutOrder = 3,
				Size = UDim2.fromScale(0.82, 0.26),
				BackgroundColor3 = COLORS.Outline,
				BackgroundTransparency = 0.25,
				[Children] = {
					signScope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
					signScope:New("UIStroke")({
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = colors.Top,
						Thickness = 2,
						Transparency = 0.2,
					}),
					signScope:New("UIPadding")({
						PaddingTop = UDim.new(0.16, 0),
						PaddingBottom = UDim.new(0.16, 0),
						PaddingLeft = UDim.new(0.08, 0),
						PaddingRight = UDim.new(0.08, 0),
					}),
					textLabel(signScope, {
						Name = "Status",
						Text = pillText,
						TextColor3 = pillColor,
						[Children] = signScope:New("UIStroke")({
							Color = COLORS.Outline,
							Thickness = 1.5,
						}),
					}),
				},
			}),
		},
	}) :: BillboardGui

	-- Gentle bob, looping both ways; restarted from the new height whenever
	-- a streamed-in part raises the fan's top.
	local bob: Tween? = nil
	local function place(): ()
		if bob then
			bob:Cancel()
		end
		sign.StudsOffsetWorldSpace = rest
		bob = TweenService:Create(
			sign,
			TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ StudsOffsetWorldSpace = rest + Vector3.new(0, BOB_HEIGHT, 0) }
		);
		(bob :: Tween):Play()
	end
	place()
	table.insert(signScope, function()
		if bob then
			bob:Cancel()
		end
	end)

	local pending = false
	table.insert(
		signScope,
		fan.DescendantAdded:Connect(function(part: Instance)
			if pending or not part:IsA("BasePart") then
				return
			end
			pending = true
			task.defer(function() -- one recompute per burst of streamed parts
				pending = false
				local newRest = restOffset()
				if newRest.Y > rest.Y + 0.05 then
					rest = newRest
					place()
				end
			end)
		end)
	)
end

--- Hitbox streamed out (or untagged): its sign and everything it holds go.
local function unbuild(hitbox: Instance): ()
	local signScope = signs[hitbox]
	if signScope then
		signs[hitbox] = nil
		signScope:doCleanup()
	end
end

function FanSignController:Init(): ()
	scope = Fusion.scoped(Fusion)
	access = scope:Value({})
end

function FanSignController:Start(): ()
	readAccess()
	LocalPlayer:GetAttributeChangedSignal(TreadmillConfig.AccessAttribute):Connect(readAccess)
	for _, hitbox in CollectionService:GetTagged(TagNames.Treadmill) do
		build(hitbox)
	end
	CollectionService:GetInstanceAddedSignal(TagNames.Treadmill):Connect(build)
	CollectionService:GetInstanceRemovedSignal(TagNames.Treadmill):Connect(unbuild)
end

return FanSignController
