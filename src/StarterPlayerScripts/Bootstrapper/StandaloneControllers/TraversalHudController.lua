--!strict
--[[
	@module TraversalHudController
	@description The minimal always-on gameplay HUD for the traversal
	systems: stamina, traversal level, traversal XP. Nothing else -- no
	shop, rebirth, wins or revive surface is built here.

	A StandaloneController rather than a Navigation Panel, deliberately.
	Navigation owns a STACK of panels that open, close and can be popped;
	this is a permanent overlay with no open/close semantics, so pushing it
	through PanelRegistry would mean registering something that must never
	be popped. It still uses the project's Fusion architecture exactly as
	Panels/_Template demonstrates: one `Fusion.scoped` scope, `scope:Value`
	for state, `scope:Computed` for anything derived, `[Children]` for the
	tree.

	Data flow, all one-way: the server pushes authoritative values over
	NetworkEvents, NetworkBridgeController turns those into EventBus
	signals, and this controller writes them into Fusion Values. The HUD
	never computes a gameplay number and never sends anything.

	THEME SEPARATION (§12): this reads EventBus.Traversal, which names no
	visual. Whatever ends up rendering the mechanic -- tongue, hook and
	rope, stretching hand, tentacle, chain, vine, magic tether -- is a
	separate listener on the same signals and requires no change here.

	XP DENOMINATOR: `nextThreshold` is the total XP needed to leave the
	current level (config: level * XPPerLevel). It is still handled as
	optional -- if the curve ever reports no next threshold, the XP line
	shows the raw total with no "/ N" rather than inventing a target.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Events.EventBus)
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local TraversalProgressionConfig = require(ReplicatedStorage.Config.TraversalProgressionConfig)

local Children = Fusion.Children

local log = Logger.new("TraversalHudController")
local TraversalHudController = {}

local LocalPlayer = Players.LocalPlayer

--- The bar is a 0-100 % of the real length still available while a probe is
--- active (full otherwise). Display only -- it is not a gameplay resource.
local NORMALIZED_MAX = 100

local COLORS = {
	Panel = Color3.fromRGB(18, 20, 26),
	Text = Color3.fromRGB(235, 238, 245),
	Muted = Color3.fromRGB(150, 158, 175),
	StaminaFull = Color3.fromRGB(90, 200, 120),
	StaminaLow = Color3.fromRGB(225, 90, 80),
	Blocked = Color3.fromRGB(240, 170, 60),
	XpFill = Color3.fromRGB(90, 160, 235),
}

--- Below this fraction the bar turns red -- purely visual, no gameplay
--- meaning attached.
local LOW_FRACTION = 0.25

local scope: Fusion.Scope<typeof(Fusion)>? = nil

function TraversalHudController:Init(): ()
	log:Info("Initialized.")
end

function TraversalHudController:Start(): ()
	local hudScope = Fusion.scoped(Fusion)
	scope = hudScope

	local stamina = hudScope:Value(1)
	local staminaMax = hudScope:Value(1)
	local level = hudScope:Value(1)
	local xp = hudScope:Value(0)
	local nextThreshold: Fusion.Value<number?, number?> = hudScope:Value(nil :: number?)
	local aimBlocked = hudScope:Value(false)

	--- Fraction of the pool remaining, clamped -- the single derivation both
	--- the bar width and the bar color read, so they can never disagree.
	local staminaFraction = hudScope:Computed(function(use)
		local max = use(staminaMax)
		if max <= 0 then
			return 0
		end
		return math.clamp(use(stamina) / max, 0, 1)
	end)

	local staminaText = hudScope:Computed(function(use)
		-- Normalized to 0-100 for display, as the reference HUD shows it.
		return string.format(
			"STAMINA  %d / %d",
			math.floor(use(staminaFraction) * NORMALIZED_MAX + 0.5),
			NORMALIZED_MAX
		)
	end)

	-- Everything earned since level 1 (the "fake length").
	local totalXpText = hudScope:Computed(function(use)
		return string.format("TOTAL XP  %d", math.floor(use(xp)))
	end)

	-- XP inside the current level: restarts at 0 after each level-up.
	-- Level start = next threshold - this level's cost; nil at the max level.
	local levelCost = hudScope:Computed(function(use)
		return TraversalProgressionConfig.GetLevelCost(use(level))
	end)

	local levelXp = hudScope:Computed(function(use)
		local threshold = use(nextThreshold)
		local cost = use(levelCost)
		if not threshold or not cost then
			return nil
		end
		return math.clamp(math.floor(use(xp)) - (threshold - cost), 0, cost)
	end)

	local levelXpText = hudScope:Computed(function(use)
		local got = use(levelXp)
		if not got then
			return "LEVEL MAX"
		end
		return string.format("LEVEL XP  %d / %d", got, use(levelCost) :: number)
	end)

	local levelXpFraction = hudScope:Computed(function(use)
		local got, cost = use(levelXp), use(levelCost)
		if not got or not cost then
			return 1
		end
		return got / cost
	end)

	local levelText = hudScope:Computed(function(use)
		return string.format("LEVEL %d", use(level))
	end)

	-- Real length (max reach when launching) for the current level.
	local lengthText = hudScope:Computed(function(use)
		return string.format("LENGTH %d studs", TraversalProgressionConfig.GetMaxLength(use(level)))
	end)

	local statusText = hudScope:Computed(function(use)
		if use(aimBlocked) then
			return "Aim away from the wall to launch"
		end
		return ""
	end)

	local function label(
		name: string,
		order: number,
		text: any,
		color: Color3,
		size: number
	): Instance
		return hudScope:New("TextLabel")({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, size),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = size - 4,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Text = text,
		})
	end

	hudScope:New("ScreenGui")({
		Enabled = false,
		Name = "TraversalHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = hudScope:New("Frame")({
			Name = "Root",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.fromOffset(260, 190),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.25,
			[Children] = {
				hudScope:New("UICorner")({ CornerRadius = UDim.new(0, 8) }),
				hudScope:New("UIPadding")({
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
				}),
				hudScope:New("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),

				label("StaminaLabel", 1, staminaText, COLORS.Text, 18),

				hudScope:New("Frame")({
					Name = "StaminaBar",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 10),
					BackgroundColor3 = Color3.fromRGB(45, 48, 58),
					[Children] = {
						hudScope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
						hudScope:New("Frame")({
							Name = "Fill",
							Size = hudScope:Computed(function(use)
								return UDim2.fromScale(use(staminaFraction), 1)
							end),
							BackgroundColor3 = hudScope:Computed(function(use)
								return if use(staminaFraction) <= LOW_FRACTION
									then COLORS.StaminaLow
									else COLORS.StaminaFull
							end),
							BorderSizePixel = 0,
							[Children] = hudScope:New("UICorner")({
								CornerRadius = UDim.new(1, 0),
							}),
						}),
					},
				}),

				label("LevelLabel", 3, levelText, COLORS.Text, 18),
				label("LengthLabel", 4, lengthText, COLORS.Text, 18),
				label("LevelXpLabel", 5, levelXpText, COLORS.Muted, 16),

				hudScope:New("Frame")({
					Name = "LevelXpBar",
					LayoutOrder = 6,
					Size = UDim2.new(1, 0, 0, 10),
					BackgroundColor3 = Color3.fromRGB(45, 48, 58),
					[Children] = {
						hudScope:New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
						hudScope:New("Frame")({
							Name = "Fill",
							Size = hudScope:Computed(function(use)
								return UDim2.fromScale(use(levelXpFraction), 1)
							end),
							BackgroundColor3 = COLORS.XpFill,
							BorderSizePixel = 0,
							[Children] = hudScope:New("UICorner")({
								CornerRadius = UDim.new(1, 0),
							}),
						}),
					},
				}),

				label("TotalXpLabel", 7, totalXpText, COLORS.Muted, 16),
				label("StatusLabel", 8, statusText, COLORS.Blocked, 16),
			},
		}),
	})

	--== Authoritative values in, nothing out ================================--
	EventBus.Traversal.StaminaChanged:Connect(function(current: number, max: number)
		stamina:set(current)
		staminaMax:set(max)
	end)

	-- Treadmill: the server grants XP instantly, but the player should see it
	-- land when the treadmill part hits its target. Buffer, reveal on flush.
	local holding = false
	local pending: { xp: number, threshold: number? }? = nil
	local pendingLevel: number? = nil
	local function flushXp(): ()
		if pending then
			xp:set(pending.xp)
			nextThreshold:set(pending.threshold)
			pending = nil
		end
		-- Level travels with its XP so the level bar never mixes the two.
		if pendingLevel then
			level:set(pendingLevel)
			pendingLevel = nil
		end
	end

	EventBus.Traversal.XPChanged:Connect(function(newXp: number, threshold: number?)
		pending = { xp = newXp, threshold = threshold }
		if not holding then
			flushXp()
		end
	end)

	EventBus.Traversal.LevelChanged:Connect(function(newLevel: number)
		pendingLevel = newLevel
		if not holding then
			flushXp()
		end
	end)

	EventBus.Traversal.XPHold:Connect(function(hold: boolean)
		holding = hold
		if not hold then
			flushXp()
		end
	end)

	EventBus.Traversal.XPFlush:Connect(flushXp)

	EventBus.Traversal.AimBlocked:Connect(function(blocked: boolean)
		aimBlocked:set(blocked)
	end)

	log:Info("Started.")
end

--- Not part of the Init/Start contract -- present so the HUD can be torn
--- down deliberately (a cutscene, a test) without leaking its Fusion scope.
function TraversalHudController.Destroy(): ()
	if scope then
		scope:doCleanup()
		scope = nil
	end
end

return TraversalHudController
