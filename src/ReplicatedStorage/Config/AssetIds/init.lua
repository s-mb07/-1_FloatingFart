--!strict
--[[
	@class AssetIds
	Barrel module re-exporting every typed asset id registry under a single
	`AssetIds` namespace, e.g. `AssetIds.SoundIds.HitImpact`. Keeps every raw
	asset id string in one place instead of scattered across whatever module
	happens to play a sound/spawn a particle -- see README.md §9.9 (registry
	pattern).
]]

local AnimationIds = require(script.AnimationIds)
local ImageIds = require(script.ImageIds)
local MeshIds = require(script.MeshIds)
local ParticleIds = require(script.ParticleIds)
local SoundIds = require(script.SoundIds)
local TagNames = require(script.TagNames)

--- Shape of the aggregated asset id table.
export type AssetIdsType = {
	AnimationIds: typeof(AnimationIds),
	ImageIds: typeof(ImageIds),
	MeshIds: typeof(MeshIds),
	ParticleIds: typeof(ParticleIds),
	SoundIds: typeof(SoundIds),
	TagNames: typeof(TagNames),
}

local AssetIds: AssetIdsType = table.freeze({
	AnimationIds = AnimationIds,
	ImageIds = ImageIds,
	MeshIds = MeshIds,
	ParticleIds = ParticleIds,
	SoundIds = SoundIds,
	TagNames = TagNames,
}) :: AssetIdsType

return AssetIds
