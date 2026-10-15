--!strict
--[[
	@module FanSignConfig
	@description Colors of the "xN LENGTH" sign floating above each training
	fan (FanSignController), keyed by the fan Hitbox `Id` attribute
	(TreadmillConfig.Treadmills): top / bottom of the title gradient, top
	also outlines the requirement pill. Purely cosmetic, client only.
]]

export type Sign = {
	Top: Color3,
	Bottom: Color3,
}

return {
	["1"] = { Top = Color3.fromRGB(235, 240, 250), Bottom = Color3.fromRGB(160, 170, 190) }, -- classic (grey)
	["2"] = { Top = Color3.fromRGB(255, 200, 90), Bottom = Color3.fromRGB(230, 95, 40) }, -- autumn leaves
	["3"] = { Top = Color3.fromRGB(255, 200, 230), Bottom = Color3.fromRGB(255, 95, 170) }, -- pink (sakura)
	["4"] = { Top = Color3.fromRGB(255, 240, 140), Bottom = Color3.fromRGB(235, 160, 20) }, -- golden
	["5"] = { Top = Color3.fromRGB(200, 245, 255), Bottom = Color3.fromRGB(70, 160, 255) }, -- diamond (blue)
	["6"] = { Top = Color3.fromRGB(235, 180, 255), Bottom = Color3.fromRGB(150, 70, 255) }, -- amethyst (violet)
} :: { [string]: Sign }
