--!strict
--[[
	@module TrailConfig
	@description Character trail catalogue. Shared: TrailService builds the
	Trail instances and enforces prices/bonuses from it, the Trails panel
	labels its cards from it. ADDING A TRAIL = one entry below + a card Frame
	named `Card` under TrailsUI/MainFrame/ScrollingFrame (cards not listed
	here are hidden).

	THE RULES (server-enforced, see TrailService)
	  - Buy with Wins (trophies, PriceWins) or Robux: each trail is its own
	    gamepass (GamePass = GamePassConfig key); buying it unlocks the trail.
	  - The VIP trail has no PriceWins/PriceRobux: only the VIP gamepass
	    unlocks it (its card's Robux button opens the VIP prompt).
	  - Owned trails are saved; one can be equipped at a time (or none).
	  - The equipped trail adds to per-second XP (hook + treadmill):
	    XPMultiplier as an ADDITIVE % (x1.5 = +50% of the skin base XP/s), in
	    TraversalProgressionService.GetXPPerSecond.
	  - Visual: a Trail between two Attachments on the HumanoidRootPart,
	    created server-side so every client sees it.
]]

export type TrailDef = {
	DisplayName: string,
	--- Card Frame name in the Trails panel.
	Card: string,
	--- Nil = cannot be bought with Wins (the card hides its Win button).
	PriceWins: number?,
	--- Shown on the card's Robux button (the real price is the gamepass's).
	--- Nil = the button reads "VIP" (a VIP-only trail).
	PriceRobux: number?,
	--- GamePassConfig key sold by the card's Robux button.
	GamePass: string,
	XPMultiplier: number,
	--- Trail color from origin to tail, spread evenly (2+ colors).
	Colors: { Color3 },
	--- WidthScale at the tail (1.0 at the origin).
	TailWidth: number,
}

local TrailConfig = {
	--- Folder the server generates the Trail templates into.
	TemplateFolderPath = { "Cosmetics", "Trails" },
	Lifetime = 0.6,
	MinLength = 0.1,
	Attachment0Position = Vector3.new(0, 1, 0),
	Attachment1Position = Vector3.new(0, -1, 0),

	--- The "flashy" look shared by EVERY trail: a glowing, slightly
	--- see-through ribbon plus sparkles (stars + small dots) in the trail's
	--- own colors. The sparkles only emit while the player moves
	--- (TrailEffectsController, client). Built-in texture: no upload needed.
	Effect = {
		LightEmission = 0.6, -- partly additive glow (1 = full glow, too bright)
		Brightness = 1.4,
		HeadTransparency = 0.25, -- ribbon transparency at the origin (fades to 1 at the tail)
		SparkleTexture = "rbxasset://textures/particles/sparkles_main.dds",
		SparkleRate = 35, -- particles / second while moving
		SparkleLifetime = NumberRange.new(0.6, 1.1),
		SparkleSize = NumberRange.new(0.4, 1.8), -- small = dots, big = stars
		SparkleSpeed = NumberRange.new(0.5, 2),
		SparkleSpread = Vector2.new(180, 180),
		SparkleRotSpeed = NumberRange.new(-180, 180),
		--- HumanoidRootPart speed (studs/s) above which sparkles emit.
		MovingSpeed = 2,
	},

	--- Display/card order.
	Order = { "Orange", "Blue", "Green", "Purple", "Rainbow", "Vip" },

	Trails = {
		Orange = {
			DisplayName = "Orange Trail",
			Card = "OrangeTrail",
			GamePass = "TrailOrange",
			PriceWins = 25,
			PriceRobux = 19,
			XPMultiplier = 1.25,
			Colors = { Color3.fromRGB(255, 167, 15), Color3.fromRGB(255, 85, 0) },
			TailWidth = 0.1,
		},
		Blue = {
			DisplayName = "Blue Trail",
			Card = "BlueTrail",
			GamePass = "TrailBlue",
			PriceWins = 50,
			PriceRobux = 29,
			XPMultiplier = 1.5,
			Colors = { Color3.fromRGB(0, 220, 255), Color3.fromRGB(0, 50, 255) },
			TailWidth = 0.1,
		},
		Green = {
			DisplayName = "Green Trail",
			Card = "GreenTrail",
			GamePass = "TrailGreen",
			PriceWins = 75,
			PriceRobux = 39,
			XPMultiplier = 1.75,
			Colors = { Color3.fromRGB(110, 235, 110), Color3.fromRGB(30, 165, 55) },
			TailWidth = 0.1,
		},
		Purple = {
			DisplayName = "Purple Trail",
			Card = "PurpleTrail",
			GamePass = "TrailPurple",
			PriceWins = 100,
			PriceRobux = 49,
			XPMultiplier = 2,
			Colors = { Color3.fromRGB(190, 80, 255), Color3.fromRGB(110, 20, 200) },
			TailWidth = 0.1,
		},
		Rainbow = {
			DisplayName = "Rainbow Trail",
			Card = "RainbowTrail",
			GamePass = "TrailRainbow",
			PriceWins = 125,
			PriceRobux = 59,
			XPMultiplier = 2.5,
			-- Same stops as the Studio RainbowTrail card gradient.
			Colors = {
				Color3.fromRGB(255, 21, 25),
				Color3.fromRGB(249, 248, 70),
				Color3.fromRGB(90, 255, 59),
				Color3.fromRGB(87, 251, 255),
				Color3.fromRGB(70, 57, 255),
				Color3.fromRGB(255, 103, 227),
			},
			TailWidth = 0.1,
		},
		-- VIP only, the top tier: best bonus, wider ribbon, shimmering gold.
		-- Uses the Studio YellowTrail card.
		Vip = {
			DisplayName = "VIP Trail",
			Card = "YellowTrail",
			GamePass = "VIP",
			XPMultiplier = 3,
			Colors = {
				Color3.fromRGB(255, 255, 230),
				Color3.fromRGB(255, 220, 70),
				Color3.fromRGB(255, 245, 170),
				Color3.fromRGB(255, 185, 20),
				Color3.fromRGB(220, 130, 0),
			},
			TailWidth = 0.4,
		},
	} :: { [string]: TrailDef },
}

--- The trail's Colors spread evenly into a ColorSequence (the Trail itself
--- and its purchase reveal).
function TrailConfig.ColorSequenceOf(def: TrailDef): ColorSequence
	local keypoints = {}
	for i, color in def.Colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#def.Colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

--- XP multiplier of trail `id` (x1 for none / unknown).
function TrailConfig.GetXPMultiplier(id: string?): number
	local def = if id then TrailConfig.Trails[id] else nil
	return if def then def.XPMultiplier else 1
end

return TrailConfig
