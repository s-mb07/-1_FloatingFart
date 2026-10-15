--!strict
--[[
	@module TraversalProgressionService
	@description Traversal XP and level: accumulation, threshold crossing
	(including several level-ups from one grant), and the recalculation that
	a level-up triggers downstream.

	SPLIT OF RESPONSIBILITY with DataService, per README §5's own warning
	against letting DataService become a god-service:
	  - DataService owns the typed, persisted MUTATORS (AddTraversalXP,
	    SetTraversalLevel, ...) and the replication of the saved values.
	  - This service owns the LOGIC -- when a threshold is crossed, how many
	    levels that is worth, what has to be recomputed afterwards.
	Profile data is never touched directly from here or from ProbeService;
	every write goes through a DataService mutator.

	THE XP CURVE lives entirely in TraversalProgressionConfig (tiers with
	interpolation). Nothing in this file encodes it: the loop below only ever
	asks the config "what total does this level need next", so rebalancing
	touches config only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)
local SkinService = require(script.Parent.SkinService)
local TrailConfig = require(ReplicatedStorage.Config.TrailConfig)
local TraversalProgressionConfig = require(ReplicatedStorage.Config.TraversalProgressionConfig)

local log = Logger.new("TraversalProgressionService")
local TraversalProgressionService = {}

--============================================================================--
-- READS
--============================================================================--

--- @param player Player
--- @return number -- 1 when no profile is loaded yet
function TraversalProgressionService.GetLevel(player: Player): number
	-- Clamped: a stored level above the cap (older data, a bad write) must
	-- never size the reach or the HUD beyond the config.
	return math.min(DataService:GetTraversalLevel(player), TraversalProgressionConfig.MaxLevel)
end

--- @param player Player
--- @return number
function TraversalProgressionService.GetXP(player: Player): number
	return DataService:GetTraversalXP(player)
end

--- XP earned per second of active probe / treadmill training.
--- The equipped skin sets the base rate. The rebirth and the equipped trail
--- are ADDITIVE bonuses in % of that base (a "x1.5" entry = +50% of the base),
--- summed together, then the Length boost (BoostConfig) multiplies the total.
---   total = base * (1 + (rebirth - 1) + (trail - 1)) * lengthBoost
--- The single seam every per-second grant goes through (ProbeService, TreadmillService).
--- Example: skin 2 (2/s), rebirth x1.5 (+1), Yellow trail x1.5 (+1), no Length boost
---   -> 2 + 1 + 1 = 4/s.
--- @param player Player
--- @return number
function TraversalProgressionService.GetXPPerSecond(player: Player): number
	local base = SkinService.GetXPPerSecond(player)
	local rebirthBonus = RebirthConfig.GetMultiplier(DataService:GetRebirths(player)) - 1
	local trailBonus = TrailConfig.GetXPMultiplier(DataService:GetEquippedTrail(player)) - 1
	return base * (1 + rebirthBonus + trailBonus) * DataService:GetLengthMultiplier(player)
end

--- Total XP needed to leave the player's current level, or nil if the curve
--- ever reports no next threshold (e.g. a future max level).
--- @param player Player
--- @return number?
function TraversalProgressionService.GetNextThreshold(player: Player): number?
	return TraversalProgressionConfig.GetNextThreshold(TraversalProgressionService.GetLevel(player))
end

--============================================================================--
-- REPLICATION
--============================================================================--

--- Pushes the authoritative triple to the owner's HUD. Sent as its own event
--- rather than leaving the HUD to read the "DataUpdated" patch, so the HUD
--- never has to know the profile's shape -- and so `nextThreshold`, which is
--- config-derived and not stored in the profile at all, arrives with it.
--- @param player Player
function TraversalProgressionService.Publish(player: Player): ()
	NetworkEvents.FireClient(
		"TraversalProgressChanged",
		player,
		TraversalProgressionService.GetLevel(player),
		TraversalProgressionService.GetXP(player),
		TraversalProgressionService.GetNextThreshold(player)
	)
end

--============================================================================--
-- WRITES
--============================================================================--

--- Applies as many level-ups as the new XP total earns, one threshold at a
--- time. A single large grant crossing three thresholds produces three
--- level-ups and three signals, in order -- never one jump to the end.
local function applyLevelUps(player: Player): number
	local levelsGained = 0

	while true do
		local level = TraversalProgressionService.GetLevel(player)
		local threshold = TraversalProgressionConfig.GetNextThreshold(level)
		if not threshold then
			break -- unknown curve, or genuine max level
		end
		if TraversalProgressionService.GetXP(player) < threshold then
			break
		end

		local ok, reason = DataService:SetTraversalLevel(player, level + 1)
		if not ok then
			log:Warn("%s: level-up write refused (%s).", player.Name, tostring(reason))
			break
		end

		levelsGained += 1
		log:Info("%s: traversal level %d -> %d.", player.Name, level, level + 1)
		-- Fired per level so a listener that reacts to a level-up (the
		-- stamina pool resize, a future effect) sees each one.
		GameEvents.OnTraversalLevelChanged:Fire(player, level + 1, level)
	end

	return levelsGained
end

--- Grants XP and resolves any level-ups it earns.
--- @param player Player
--- @param amount number -- must be finite and > 0
--- @param source string -- logged only, for telling grant paths apart
--- @return boolean, string? -- ok, DataService error code on failure
function TraversalProgressionService.AddXP(
	player: Player,
	amount: number,
	source: string
): (boolean, string?)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false, "InvalidAmount"
	end
	-- At the level cap there is nothing to earn: XP must not pile up past it.
	if TraversalProgressionService.GetNextThreshold(player) == nil then
		return true
	end

	local ok, reason = DataService:AddTraversalXP(player, amount)
	if not ok then
		return false, reason
	end

	log:Debug("%s: +%.1f traversal XP (%s).", player.Name, amount, source)
	applyLevelUps(player)

	GameEvents.OnTraversalXPChanged:Fire(player, TraversalProgressionService.GetXP(player))
	TraversalProgressionService.Publish(player)
	return true
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

function TraversalProgressionService:Init(): ()
	local ok, reason = TraversalProgressionConfig.Validate()
	if not ok then
		log:Error(
			"Progression curve is malformed (%s) -- level-ups disabled until it is fixed.",
			tostring(reason)
		)
	elseif not TraversalProgressionConfig.HasThresholds() then
		log:Warn("No next threshold is configured -- XP accumulates but no level-up can occur.")
	else
		log:Info(
			"Progression: %d tiers, max level %d.",
			#TraversalProgressionConfig.Tiers,
			TraversalProgressionConfig.MaxLevel
		)
	end

	log:Info("Initialized.")
end

function TraversalProgressionService:Start(): ()
	-- Profile-dependent: the first push has to wait for the profile, or it
	-- would replicate the template defaults over the player's real values.
	GameEvents.OnDataLoaded:Connect(function(player: Player)
		TraversalProgressionService.Publish(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			-- Re-push on respawn: a fresh HUD (ResetOnSpawn) has nothing to
			-- show otherwise.
			TraversalProgressionService.Publish(player)
		end)
	end)

	log:Info("Started.")
end

return TraversalProgressionService
