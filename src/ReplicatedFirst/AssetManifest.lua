--!strict
--[[
	@module AssetManifest
	@description Single source of assets referenced dynamically by ID (never placed
	             as a property of an existing instance in Studio/Rojo), and therefore
	             invisible to an instance-based preloader's scan. Each group corresponds
	             to one consumer file; a LoadingManager (not provided here) preloads
	             AssetManifest.Entries by creating a disposable instance per ID.

	ONLY list real IDs. A placeholder ID "rbxassetid://0" (feature not yet
	designed) stays hardcoded in its Config as long as it points to nothing real --
	centralizing it here would bring no preloading benefit. Migrate an entry
	here as soon as a real asset replaces it.

	A single example group (Toast) -- add your own in the same format.
]]

local AssetManifest = {}

export type AssetCategory = "Texture" | "Sound" | "Animation"

export type ManifestEntry = {
	id: string,
	category: AssetCategory,
}

-- Toast notification icons (UXEffects/Effects/Toast.lua)
AssetManifest.Toast = {
	Info = "rbxassetid://6031076099",
	Success = "rbxassetid://6031071058",
	Warning = "rbxassetid://6031071053",
	Error = "rbxassetid://6031071048",
}

-- Flat, categorized list, consumed by a LoadingManager.CollectManifestAssets().
-- Built by referencing the tables above: a single place to edit per ID,
-- no risk of drift between named access and the preload list.
AssetManifest.Entries = {} :: { ManifestEntry }

local function registerGroup(group: { [string]: string }, category: AssetCategory): ()
	for _, id in group do
		table.insert(AssetManifest.Entries, { id = id, category = category })
	end
end

registerGroup(AssetManifest.Toast, "Texture")

return AssetManifest
