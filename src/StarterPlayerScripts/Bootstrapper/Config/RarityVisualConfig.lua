--!strict
--[[
	@module RarityVisualConfig
	@description Visual slot configuration per rarity (gradient/stroke),
	consumed by UITag.Handlers.Effects (`Rarity` attribute -> glow/gradient).

	5 example tiers -- extend with your own, the rest of the code only
	reads the keys present here (no hardcoded rarity list elsewhere).
]]

local UIThemeConfig = require(script.Parent.UIThemeConfig)

export type RarityVisual = {
	GradientColors: {Color3},
	StrokeInColors: {Color3},
	StrokeInRotation: number,
	StrokeOutColor: Color3,
}

local RarityVisualConfig: {[string]: RarityVisual} = {
	Common = {
		GradientColors = {
			Color3.fromRGB(220, 215, 200),
			Color3.fromRGB(180, 175, 160),
		},
		StrokeInColors = {
			Color3.fromRGB(200, 195, 180),
			Color3.fromRGB(160, 155, 140),
		},
		StrokeInRotation = 90,
		StrokeOutColor = Color3.fromRGB(60, 55, 50),
	},

	Rare = {
		GradientColors = {
			Color3.fromRGB(100, 180, 255),
			Color3.fromRGB(50, 130, 210),
		},
		StrokeInColors = {
			Color3.fromRGB(140, 200, 255),
			Color3.fromRGB(80, 160, 230),
		},
		StrokeInRotation = 45,
		StrokeOutColor = Color3.fromRGB(20, 50, 80),
	},

	Epic = {
		GradientColors = {
			Color3.fromRGB(255, 100, 150),
			Color3.fromRGB(200, 50, 100),
		},
		StrokeInColors = {
			Color3.fromRGB(255, 140, 180),
			Color3.fromRGB(230, 80, 130),
		},
		StrokeInRotation = 45,
		StrokeOutColor = Color3.fromRGB(80, 20, 40),
	},

	Legendary = {
		GradientColors = {
			UIThemeConfig.GOLD,
			Color3.fromRGB(255, 165, 0),
		},
		StrokeInColors = {
			Color3.fromRGB(255, 235, 100),
			Color3.fromRGB(255, 200, 50),
		},
		StrokeInRotation = 90,
		StrokeOutColor = Color3.fromRGB(100, 70, 0),
	},

	Mythic = {
		GradientColors = {
			Color3.fromRGB(255, 50, 100),
			Color3.fromRGB(100, 50, 255),
		},
		StrokeInColors = {
			Color3.fromRGB(255, 100, 150),
			Color3.fromRGB(150, 100, 255),
		},
		StrokeInRotation = 135,
		StrokeOutColor = Color3.fromRGB(50, 0, 50),
	},
}

return RarityVisualConfig
