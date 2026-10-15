--!strict

--- @module LoadingManager
--- @description Weighted, phased preloading system with real progress tracking,
---              controlled yielding and a safety timeout. Meant to be placed as a
---              ModuleScript (e.g. in ReplicatedFirst) and used by the client loading script.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")

local LoadingManager = {}
LoadingManager.__index = LoadingManager

--============================================================
-- TYPES
--============================================================

export type AssetCategory = "UI" | "Texture" | "Sound" | "Animation" | "Model"

export type WeightedAsset = {
	instance: Instance,
	category: AssetCategory,
	weight: number,
}

export type ProgressState = {
	ratio: number, -- 0..1, real weighted progress
	phase: string, -- name of the current phase
	loadedWeight: number,
	totalWeight: number,
}

export type ProgressCallback = (ProgressState) -> ()

export type LoadingManagerConfig = {
	batchSize: number?, -- number of instances sent to PreloadAsync per call (default: 15)
	batchYield: number?, -- pause in seconds between each batch (default: 0.03)
	phaseTimeout: number?, -- safety timeout per phase in seconds (default: 12)
	batchTimeout: number?, -- max bound in seconds per PreloadAsync call (default: 5)
	extraContainers: { Instance }?, -- additional folders to scan (e.g. workspace.SpawnCritical)
	extraTags: { string }?, -- CollectionService tags whose tagged instances get scanned
	-- (e.g. "Seeds_Container_Icons" -> registries built dynamically in Studio,
	-- whose actual position in the hierarchy isn't fixed/known ahead of time).
}

type Self = {
	_config: LoadingManagerConfig,
	_onProgress: ProgressCallback?,
	_totalWeight: number,
	_loadedWeight: number,
	_cancelled: boolean,
	_lastProgressClock: number,
}

export type LoadingManagerType = typeof(setmetatable({} :: Self, LoadingManager))

--============================================================
-- CONSTANTS
--============================================================

-- Relative weight of each category: a sound or a model "costs" more than a
-- UI image, so it carries more weight in the progress calculation.
local CATEGORY_WEIGHTS: { [AssetCategory]: number } = {
	UI = 1,
	Texture = 1,
	Sound = 2,
	Animation = 1,
	Model = 3,
}

-- Phase priority order: load what's immediately visible first (loading
-- screen, UI), then the rest.
-- Animations come second: tiny, and the flight cannot look right without them.
local PHASE_ORDER: { AssetCategory } = { "UI", "Animation", "Texture", "Sound", "Model" }

--============================================================
-- CONSTRUCTOR
--============================================================

function LoadingManager.new(config: LoadingManagerConfig?): LoadingManagerType
	local self = (setmetatable({}, LoadingManager) :: any) :: Self
	self._config = config or {}
	self._onProgress = nil
	self._totalWeight = 0
	self._loadedWeight = 0
	self._cancelled = false
	self._lastProgressClock = os.clock()
	return (self :: any) :: LoadingManagerType
end

function LoadingManager.OnProgress(self: LoadingManagerType, callback: ProgressCallback): ()
	(self :: any)._onProgress = callback
end

--- Allows a preload in progress to be cleanly interrupted (e.g. player clicks "Skip").
function LoadingManager.Cancel(self: LoadingManagerType): ()
	(self :: any)._cancelled = true
end

function LoadingManager.IsCancelled(self: LoadingManagerType): boolean
	return (self :: any)._cancelled
end

--============================================================
-- ASSET COLLECTION
--============================================================

--- @function CollectAssets
--- @description Scans only whitelisted containers (NOT the whole Workspace,
---              NOT StarterPlayerScripts, NOT Lighting) to avoid preloading
---              irrelevant instances (scripts, values, config folders, etc.)
function LoadingManager.CollectAssets(self: LoadingManagerType): { WeightedAsset }
	local results: { WeightedAsset } = {}
	local seen: { [Instance]: boolean } = {}

	local containers: { Instance } = {}

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		table.insert(containers, assetsFolder)
	end

	local uiFolder = ReplicatedStorage:FindFirstChild("UI")
	if uiFolder then
		table.insert(containers, uiFolder)
	end

	local loadingScreenSource = ReplicatedFirst:FindFirstChild("LoadingScreen")
	if loadingScreenSource then
		table.insert(containers, loadingScreenSource)
	end

	-- StarterGui: the ScreenGuis that will be cloned into PlayerGui (menus, HUD, etc.)
	table.insert(containers, StarterGui)

	-- Additional containers explicitly supplied by the developer
	-- (e.g. workspace.SpawnCritical -> only the models near the spawn,
	-- never the whole Workspace).
	local extra = (self :: any)._config.extraContainers
	if extra then
		for _, container in extra do
			table.insert(containers, container)
		end
	end

	-- Containers found by CollectionService tag rather than by fixed path: used
	-- for registries built dynamically in Studio (e.g. SeedConfig scans
	-- "Seeds_Container_Icons" for its icon registry), whose position in the
	-- hierarchy isn't predictable/scannable by path. GetTagged() can return
	-- several instances for the same tag; all of them get scanned.
	local tags = (self :: any)._config.extraTags
	if tags then
		for _, tag in tags do
			for _, container in CollectionService:GetTagged(tag) do
				table.insert(containers, container)
			end
		end
	end

	for _, container in containers do
		self:_scanContainer(container, results, seen)
	end

	return results
end

function LoadingManager._scanContainer(
	self: LoadingManagerType,
	container: Instance,
	results: { WeightedAsset },
	seen: { [Instance]: boolean }
): ()
	for _, descendant in container:GetDescendants() do
		if seen[descendant] then
			continue
		end

		local category = self:_categorize(descendant)
		if category then
			local cat: AssetCategory = (category :: any) :: AssetCategory
			seen[descendant] = true
			local asset = ({
				instance = descendant,
				category = cat,
				weight = CATEGORY_WEIGHTS[cat],
			} :: any) :: WeightedAsset
			table.insert(results, asset)
		end
	end
end

function LoadingManager._categorize(_self: LoadingManagerType, inst: Instance): AssetCategory?
	-- IMPORTANT: per ContentProvider's official documentation, SurfaceAppearance
	-- and MaterialVariant are NOT supported by PreloadAsync (the call does nothing).
	-- Their associated textures get streamed automatically at runtime anyway.
	-- We explicitly exclude them to avoid wasting useless calls.
	if inst:IsA("SurfaceAppearance") or inst:IsA("MaterialVariant") then
		return nil
	end

	-- ParticleEmitter/Beam: the skins' VFX (Assets.Skins), whose textures
	-- otherwise load the first time a skin is equipped (lag spike).
	if
		inst:IsA("ImageLabel")
		or inst:IsA("ImageButton")
		or inst:IsA("Decal")
		or inst:IsA("Texture")
		or inst:IsA("ParticleEmitter")
		or inst:IsA("Beam")
	then
		return "Texture"
	elseif inst:IsA("Sound") then
		return "Sound"
	elseif inst:IsA("Animation") then
		return "Animation"
	elseif inst:IsA("MeshPart") then
		return "Model"
	elseif inst:IsA("GuiObject") then
		return "UI"
	end

	return nil
end

--============================================================
-- MANIFEST ASSETS (raw IDs, without an existing instance)
--============================================================

-- Convention used across the project's Config files for a not-yet-designed icon
-- (any content Config with a not-yet-designed icon): never an actual
-- asset to preload.
local PLACEHOLDER_ID = "rbxassetid://0"

--- @function CollectManifestAssets
--- @description Preloads raw IDs referenced dynamically (e.g. an icon assigned
---              at runtime from a Config, never placed on an existing instance
---              in a container scanned by CollectAssets). For each ID, creates a
---              throwaway instance (Decal/Sound/Animation, never parented) that
---              serves purely as a carrier for PreloadAsync -- the standard
---              technique for preloading an ID without a pre-existing Studio instance.
function LoadingManager.CollectManifestAssets(
	self: LoadingManagerType,
	entries: { { id: string, category: AssetCategory } }
): { WeightedAsset }
	local results: { WeightedAsset } = {}
	local seen: { [string]: boolean } = {}

	for _, entry in entries do
		if entry.id == "" or entry.id == PLACEHOLDER_ID or seen[entry.id] then
			continue
		end
		seen[entry.id] = true

		local instance = self:_createThrowawayInstance(entry.id, entry.category)
		if instance then
			table.insert(results, {
				instance = instance,
				category = entry.category,
				weight = CATEGORY_WEIGHTS[entry.category],
			})
		end
	end

	return results
end

function LoadingManager._createThrowawayInstance(_self: LoadingManagerType, id: string, category: AssetCategory): Instance?
	if category == "Texture" then
		local decal = Instance.new("Decal")
		decal.Texture = id
		return decal
	elseif category == "Sound" then
		local sound = Instance.new("Sound")
		sound.SoundId = id
		return sound
	elseif category == "Animation" then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		return animation
	end
	return nil
end

--============================================================
-- PHASE CATEGORIZATION
--============================================================

--- @function CategorizeAssets
--- @description Groups the collected assets by category, in PHASE_ORDER order.
function LoadingManager.CategorizeAssets(
	_self: LoadingManagerType,
	assets: { WeightedAsset }
): { { category: AssetCategory, assets: { WeightedAsset } } }
	local buckets: { [AssetCategory]: { WeightedAsset } } = {}
	for _, category: AssetCategory in PHASE_ORDER do
		buckets[category] = {}
	end

	for _, asset in assets do
		table.insert(buckets[asset.category], asset)
	end

	local ordered: { { category: AssetCategory, assets: { WeightedAsset } } } = {}
	for _, category: AssetCategory in PHASE_ORDER do
		table.insert(ordered, { category = category, assets = buckets[category] })
	end

	return ordered
end

--============================================================
-- WEIGHT / PROGRESS
--============================================================

--- @function CalculateWeight
--- @description Computes the total weighted weight of the asset list and stores
---              it as the denominator for real progress tracking.
function LoadingManager.CalculateWeight(self: LoadingManagerType, assets: { WeightedAsset }): number
	local total = 0
	for _, asset in assets do
		total += asset.weight
	end
	;(self :: any)._totalWeight = total
	return total
end

function LoadingManager._reportProgress(self: LoadingManagerType, phase: string): ()
	local selfAny = self :: any
	local callback = selfAny._onProgress :: ProgressCallback?
	if not callback then
		return
	end

	local total = math.max(selfAny._totalWeight, 1)
	local ratio = math.clamp(selfAny._loadedWeight / total, 0, 1)

	callback({
		ratio = ratio,
		phase = phase,
		loadedWeight = selfAny._loadedWeight,
		totalWeight = selfAny._totalWeight,
	})
end

--============================================================
-- BATCH PRELOADING
--============================================================

--- @function PreloadBatch
--- @description Preloads a list of assets in small batches, with a controlled
---              yield (task.wait) between each batch so the client thread never
---              freezes, even with a very large number of assets.
function LoadingManager.PreloadBatch(self: LoadingManagerType, assets: { WeightedAsset }, phaseName: string): ()
	local selfAny = self :: any
	local batchSize = selfAny._config.batchSize or 15
	local batchYield = selfAny._config.batchYield or 0.03
	local batchTimeout = selfAny._config.batchTimeout -- nil = no HandleTimeout wrapping, original behavior
	local total = #assets

	if total == 0 then
		return
	end

	local i = 1
	while i <= total do
		if selfAny._cancelled then
			return
		end

		local batch: { Instance } = {}
		local batchWeight = 0
		local j = i
		while j <= math.min(i + batchSize - 1, total) do
			table.insert(batch, assets[j].instance)
			batchWeight += assets[j].weight
			j += 1
		end

		-- batchTimeout absent (default): original behavior, direct pcall with no
		-- time bound. batchTimeout explicitly supplied by the caller (prototype,
		-- cf. UI loading audit): bounded by HandleTimeout -- a single asset rejected
		-- by Roblox permission inside the batch can otherwise block PreloadAsync for
		-- several dozen seconds (observed in practice: went from 5-15s to 155s).
		if batchTimeout then
			local completed = self:HandleTimeout(function()
				local ok, err = pcall(function()
					ContentProvider:PreloadAsync(batch)
				end)
				if not ok then
					warn(string.format("[LoadingManager] Preload failed (%s): %s", phaseName, tostring(err)))
				end
			end, batchTimeout)
			if not completed then
				warn(string.format(
					"[LoadingManager] Preload batch (%s, %d assets) exceeded %ds, abandoned -- probably an asset rejected by Roblox permission.",
					phaseName, #batch, batchTimeout
				))
			end
		else
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			if not ok then
				warn(string.format("[LoadingManager] Preload failed (%s): %s", phaseName, tostring(err)))
			end
		end

		selfAny._loadedWeight += batchWeight
		selfAny._lastProgressClock = os.clock()
		self:_reportProgress(phaseName)

		i = j

		-- Controlled yield: hands control back to the scheduler between two batches.
		-- PreloadAsync already yields natively, but this extra task.wait smooths out
		-- the visual progress and avoids bursts of network requests.
		task.wait(batchYield)
	end
end

--============================================================
-- STALL DETECTION / DYNAMIC CEILING
--============================================================

--- @function HasStalled
--- @description True if no progress has been recorded since `stallSeconds`.
---              Main safety net: independent of the total asset count,
---              triggers at a constant rate on an actual stall (a moderated/
---              deleted asset, a fetch that never completes), whether the
---              project has 10 or 1000 assets to preload.
function LoadingManager.HasStalled(self: LoadingManagerType, stallSeconds: number): boolean
	local selfAny = self :: any
	return (os.clock() - selfAny._lastProgressClock) >= stallSeconds
end

--- @function GetDynamicCeiling
--- @description Total time ceiling, proportional to the actual weight to
---              preload (already computed by CalculateWeight) -- not to an
---              asset count nor to a fetch parallelism we don't control
---              (Roblox doesn't expose it). Acts as a safety net for the
---              "never stalled but abnormally slow" case; HasStalled remains
---              the primary trigger for an actual stall.
function LoadingManager.GetDynamicCeiling(self: LoadingManagerType, secondsPerWeightUnit: number, minSeconds: number): number
	local selfAny = self :: any
	return math.max(minSeconds, selfAny._totalWeight * secondsPerWeightUnit)
end

--============================================================
-- SAFETY TIMEOUT
--============================================================

--- @function HandleTimeout
--- @description Runs a potentially long/blocking function on a separate thread
---              and cleanly gives up if it exceeds timeoutSeconds, so the loading
---              screen never blocks indefinitely (e.g. a WaitForChild that never
---              resolves, an asset whose fetch never completes).
function LoadingManager.HandleTimeout(_self: LoadingManagerType, fn: () -> (), timeoutSeconds: number): boolean
	local done = false
	local thread = task.spawn(function()
		fn()
		done = true
	end)

	local elapsed = 0
	while not done and elapsed < timeoutSeconds do
		elapsed += task.wait(0.1)
	end

	if not done then
		task.cancel(thread)
		warn(string.format("[LoadingManager] %ds timeout exceeded, continuing without blocking.", timeoutSeconds))
		return false
	end

	return true
end

--============================================================
-- CLEANUP
--============================================================

function LoadingManager.Cleanup(self: LoadingManagerType): ()
	local selfAny = self :: any
	selfAny._onProgress = nil
	selfAny._cancelled = true
end

return LoadingManager
