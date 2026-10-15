--!strict
--[[
	@module UIThemeConfig
	@description Theme colors shared across multiple UI domains.

	Only colors that are reused identically across UNRELATED files belong
	here. A color specific to a single screen stays local to that screen;
	UXEffects' internal palettes (Burst/Confetti/Glow) stay where they
	are -- it's a generic library, it doesn't depend on Config.
]]

local UIThemeConfig = {}

--- Gold: Legendary rarity, Gold currency, reward glow.
UIThemeConfig.GOLD = Color3.fromRGB(255, 215, 0)

return table.freeze(UIThemeConfig)
