--!strict
--[[
	@module UITag.Handlers.Presets
	@description Preset tags that apply multiple effect tags at once.

	A preset tag is a shortcut for "apply these effect tags with these
	attributes" — useful for common UI archetypes (epic button, CTA,
	loot drop). Under the hood the preset handler adds the component tags
	via CollectionService and sets default attributes if not already set.

	Presets:
	  - UIPreset_Epic      (Pulse + Glow_Rarity + Shimmer)
	  - UIPreset_CTA       (AttentionPulse + Glow_Gold + Button)
	  - UIPreset_LootDrop  (Entrance Pop + Glow_Rarity + Float)

	Custom presets:
	  Use `UIPreset_Custom` with attribute `Components = "UIEffect_Foo,UIEffect_Bar"`.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger  = require(ReplicatedStorage.Libraries.Logger)
local Utils   = require(script.Parent.Utils)
local Effects = require(script.Parent.Effects)

local log = Logger.new("UITag/Presets")

local Presets = {}

--============================================================================--
-- TAGS
--============================================================================--

local TAGS = {
	EPIC       = "UIPreset_Epic",
	CTA        = "UIPreset_CTA",
	LOOT_DROP  = "UIPreset_LootDrop",
	CUSTOM     = "UIPreset_Custom",
}

Presets.TAGS = TAGS

--============================================================================--
-- PRESET DEFINITIONS
--============================================================================--

export type PresetDefaults = { [string]: Utils.AttributeValue }

export type PresetDefinition = {
	components: { string },
	defaults:   PresetDefaults?,
}

local DEFINITIONS: { [string]: PresetDefinition } = {
	[TAGS.EPIC] = {
		components = { Effects.TAGS.PULSE, Effects.TAGS.GLOW_RARITY, Effects.TAGS.SHIMMER },
		defaults   = {
			scale    = 1.06,
			duration = 0.6,
		} :: PresetDefaults,
	},
	[TAGS.CTA] = {
		-- Note: AttentionPulse animates Size while Button animates UIScale.
		-- Both scale factors compose multiplicatively — this is intentional
		-- for CTAs (slight over-scale on hover on top of the idle pulse).
		components = { Effects.TAGS.ATTENTION_PULSE, Effects.TAGS.GLOW_GOLD, Effects.TAGS.BUTTON },
		defaults   = {
			hoverScale = 1.08,
			pressScale = 0.94,
		} :: PresetDefaults,
	},
	[TAGS.LOOT_DROP] = {
		components = { Effects.TAGS.ENTRANCE, Effects.TAGS.GLOW_RARITY, Effects.TAGS.FLOAT },
		defaults   = {
			mode      = "Pop",
			amplitude = 4,
			frequency = 1.0,
		} :: PresetDefaults,
	},
}

local PRESET_COUNT = (function(): number
	local n = 0
	for _ in pairs(DEFINITIONS) do
		n += 1
	end
	return n
end)()

--============================================================================--
-- PRIVATE HELPERS
--============================================================================--

--- Apply defaults only for attributes not already set by the user.
local function applyDefaults(instance: Instance, defaults: PresetDefaults?)
	if not defaults then return end
	for name, value in pairs(defaults) do
		if instance:GetAttribute(name) == nil then
			instance:SetAttribute(name, value)
		end
	end
end

--- Add a list of CollectionService tags to an instance and return the list of
--- tags that were newly added (so we can remove only those on cleanup).
local function addComponentTags(instance: Instance, components: { string }): { string }
	local added: { string } = {}
	for _, tag in ipairs(components) do
		if not CollectionService:HasTag(instance, tag) then
			CollectionService:AddTag(instance, tag)
			table.insert(added, tag)
		end
	end
	return added
end

--- Parse a comma-separated string into a list, trimming whitespace.
local function splitCsv(value: string): { string }
	local out: { string } = {}
	for part in string.gmatch(value, "([^,]+)") do
		local trimmed = part:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	return out
end

--============================================================================--
-- REGISTRATION
--============================================================================--

local function registerPreset(UITag: any, presetTag: string, def: PresetDefinition)
	UITag.RegisterHandler(presetTag, function(instance: Instance): (() -> ())?
		applyDefaults(instance, def.defaults)
		local added = addComponentTags(instance, def.components)
		return function()
			-- Only strip tags we added ourselves (not tags the user placed manually).
			for _, tag in ipairs(added) do
				if CollectionService:HasTag(instance, tag) then
					CollectionService:RemoveTag(instance, tag)
				end
			end
		end
	end)
end

--- Custom preset: reads `Components` attribute (csv) and applies those tags.
local function registerCustomPreset(UITag: any)
	UITag.RegisterHandler(TAGS.CUSTOM, function(instance: Instance): (() -> ())?
		local components: string = Utils.GetAttr(instance, "Components", "")
		if components == "" then
			log:Warn("UIPreset_Custom missing 'Components' attribute on %s",
				instance:GetFullName())
			return nil
		end
		local list = splitCsv(components)
		if #list == 0 then
			log:Warn("UIPreset_Custom 'Components' parsed to empty list on %s",
				instance:GetFullName())
			return nil
		end
		local added = addComponentTags(instance, list)
		return function()
			for _, tag in ipairs(added) do
				if CollectionService:HasTag(instance, tag) then
					CollectionService:RemoveTag(instance, tag)
				end
			end
		end
	end)
end

--============================================================================--
-- PUBLIC API
--============================================================================--

function Presets.Register(UITag: any)
	for presetTag, def in pairs(DEFINITIONS) do
		registerPreset(UITag, presetTag, def)
	end
	registerCustomPreset(UITag)
	log:Info("Preset handlers registered (%d presets + custom).", PRESET_COUNT)
end

return Presets
