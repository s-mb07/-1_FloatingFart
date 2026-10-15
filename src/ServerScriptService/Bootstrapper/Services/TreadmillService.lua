--!strict
--[[
	@module TreadmillService
	@description Server authority for treadmill training: while a player
	stands in a tagged treadmill Hitbox (TagNames.Treadmill, `Id` attribute
	-> TreadmillConfig.Treadmills) they are granted traversal XP immediately
	on entry and then once per XPInterval (divided by the player's Fast Train
	TreadmillSpeed, see BoostConfig), and the Fly idle pose loops on them. A
	treadmill whose AccessRule isn't met (rebirths / gamepass, see AccessGate)
	grants nothing: the player gets a notification saying what unlocks it
	(or the gamepass prompt once its GamePassConfig id is set). Each grant is the
	player's XP/s x the fan's LengthMultiplier (popped boost bubbles grant
	extra XP on their own: TrainingBubbleService). While a session runs, the
	player attribute TreadmillConfig.TrainingAttribute = the fan Id: the
	client (TreadmillController) shows the training look
	only then -- it never grants nor animates anything.

	Flying into a Hitbox ends the flight on the spot (no End animation, no
	rebound: ForceReset) and training starts right away. Being in a Hitbox
	while the traversal is busy (launch, wall) is remembered: training starts
	the moment the player is back at NORMAL, without having to leave and
	re-enter. Leaving NORMAL (a launch from the fan) ends the session.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessGate = require(script.Parent.Parent.AccessGate)
local CharacterAnimations = require(script.Parent.Parent.Traversal.CharacterAnimations)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NotificationService = require(script.Parent.NotificationService)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TraversalProgressionService = require(script.Parent.TraversalProgressionService)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TraversalStateService = require(script.Parent.TraversalStateService)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)

local log = Logger.new("TreadmillService")
local TreadmillService = {}

-- One token per active session: re-entering swaps the token, so a stale
-- loop from a previous entry can never keep granting.
local sessions: { [Player]: {} } = {}
-- The Fly idle pose started by the session (stopped only if still the
-- player's pose: never over a launch animation).
local idleTracks: { [Player]: AnimationTrack } = {}
type Zone = { Id: string, Def: TreadmillConfig.TreadmillDef }

-- The treadmill each player currently stands in (and may use), session or not.
local zones: { [Player]: Zone } = {}
-- The Hitbox each player stands in, usable or not: a fan unlocked while
-- standing in it (purchase, rebirth) starts training without re-entering.
local inside: { [Player]: BasePart } = {}

--- @return boolean -- true while a training session runs for `player`
function TreadmillService.IsTraining(player: Player): boolean
	return sessions[player] ~= nil
end

local function endSession(player: Player): ()
	sessions[player] = nil
	player:SetAttribute(TreadmillConfig.TrainingAttribute, nil)
	local track = idleTracks[player]
	idleTracks[player] = nil
	CharacterAnimations.StopTrack(player, track)
end

-- After a flight, CharacterLock.Release re-enables the default Animate
-- script; when it restarts on the client it stops EVERY playing track,
-- including a FlyIdle that got there first (the server still thinks it
-- plays). The pose waits this long for that restart to have happened.
-- ponytail: fixed grace, a client stalled longer than this still loses the
-- pose; a client ack of the restart if that ever shows up.
local ANIMATE_RESTART_GRACE = 0.4

--- Runs until the session is ended (left the Hitbox, left NORMAL, gone).
--- Yields: call from a task.
--- @param afterReset boolean? -- the session starts right after a flight (Animate restarting)
local function runSession(player: Player, afterReset: boolean?): ()
	if sessions[player] then
		return
	end
	local zone = zones[player]
	if not zone then
		return
	end
	local token = {}
	sessions[player] = token
	player:SetAttribute(TreadmillConfig.TrainingAttribute, zone.Id)
	GameEvents.OnTreadmillEntered:Fire(player)

	-- After the reset that put the player back at NORMAL (it clears the
	-- poses in the same breath) and, after a flight, the Animate restart.
	task.delay(if afterReset then ANIMATE_RESTART_GRACE else 0, function()
		local character = player.Character
		if sessions[player] == token and character then
			idleTracks[player] = CharacterAnimations.Play(player, character, "FlyIdle")
		end
	end)

	while
		sessions[player] == token
		and player.Parent
		and TraversalStateService.Get(player) == TraversalState.NORMAL
	do
		local amount = TraversalProgressionService.GetXPPerSecond(player)
			* zone.Def.LengthMultiplier
		TraversalProgressionService.AddXP(player, amount, "Treadmill")
		-- Fast Train (BoostConfig) halves the wait; re-read every tick so a
		-- purchase applies mid-session.
		task.wait(TreadmillConfig.XPInterval / DataService:GetTreadmillSpeed(player))
	end
	if sessions[player] == token then
		endSession(player)
	end
end

--- Publishes the fans `player` may use (TreadmillConfig.AccessAttribute).
--- AccessGate may yield (gamepass lookup): call spawned.
local function syncAccess(player: Player): ()
	local ids: { string } = {}
	for id, def in TreadmillConfig.Treadmills do
		if AccessGate.Check(player, def) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	if player.Parent then
		player:SetAttribute(TreadmillConfig.AccessAttribute, table.concat(ids, ","))
	end
end

--- Tells a player what unlocks a fan they cannot use (or prompts the gamepass).
local function explainLocked(player: Player, def: TreadmillConfig.TreadmillDef): ()
	if def.GamePass and GamePassService.Prompt(player, def.GamePass) then
		-- prompt opened (id set, not owned yet)
		return
	end
	local message
	if def.RequiredRebirths and def.PriceRobux then
		message = ("Requires %d Rebirths or %d R$"):format(def.RequiredRebirths, def.PriceRobux)
	elseif def.RequiredRebirths then
		message = ("Requires %d Rebirths"):format(def.RequiredRebirths)
	elseif def.PriceRobux then
		message = ("Unlock this fan for %d R$"):format(def.PriceRobux)
	else
		message = "This fan is locked"
	end
	NotificationService.Send(player, message, "Error")
end

function TreadmillService:Init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		zones[player] = nil
		inside[player] = nil
		sessions[player] = nil
		idleTracks[player] = nil
	end)
	log:Info("Initialized.")
end

--- A player stepped into a treadmill Hitbox (or is re-checked there after an
--- access change: `quiet` skips the "locked" notification/prompt).
local function enter(player: Player, hitbox: BasePart, quiet: boolean?): ()
	local id = hitbox:GetAttribute(TagNames.Attr.Id)
	local def = if type(id) == "string" then TreadmillConfig.Treadmills[id] else nil
	if not def then
		log:Warn("Treadmill '%s' has no valid Id attribute.", hitbox:GetFullName())
		return
	end
	if not AccessGate.Check(player, def) then
		if not quiet then
			explainLocked(player, def)
		end
		return
	end
	if inside[player] ~= hitbox or zones[player] then
		return -- left during the (yielding) access check, or already in
	end
	zones[player] = { Id = id :: string, Def = def }

	local state = TraversalStateService.Get(player)
	if state == TraversalState.ACTIVE or state == TraversalState.ENDING then
		-- Flying (or landing) into a fan: the flight stops right here, no
		-- End animation. The reset lands on NORMAL, which starts the
		-- session (see the state handler below).
		TraversalStateService.ForceReset(player, "Treadmill")
		TraversalStateService.StartCooldown(player)
	elseif state == TraversalState.NORMAL then
		runSession(player)
	end
	-- PRE_LAUNCH / WALL_LOCKED: remembered in `zones`, the session starts at NORMAL.
end

function TreadmillService:Start(): ()
	PadTrigger.Bind(TagNames.Treadmill, {
		Padding = 0, -- strictly inside the Hitbox
		Cooldown = TreadmillConfig.XPInterval, -- no XP farming by hopping in/out
		OnEnter = function(player: Player, hitbox: BasePart): ()
			inside[player] = hitbox
			enter(player, hitbox)
		end,
		OnLeave = function(player: Player): ()
			inside[player] = nil
			zones[player] = nil
			endSession(player)
		end,
	})

	-- Access changes with rebirths (a rebirth resets the level, so the level
	-- signal covers it) and admin edits; checked on load too.
	-- Still standing in a fan that was locked: try it again now.
	local function resync(player: Player)
		task.spawn(function()
			syncAccess(player)
			local hitbox = inside[player]
			if hitbox and not zones[player] then
				enter(player, hitbox, true)
			end
		end)
	end
	GameEvents.OnDataLoaded:Connect(resync)
	GameEvents.OnTraversalLevelChanged:Connect(
		function(player: Player, newLevel: number, previousLevel: number)
			if newLevel <= previousLevel then
				resync(player) -- a level drop (or 1 -> 1, a skipped rebirth) = a rebirth
			end
		end
	)
	GameEvents.OnAdminDataChanged:Connect(resync)
	GameEvents.OnGamePassOwned:Connect(resync)

	GameEvents.OnTraversalStateChanged:Connect(function(player: Player, newState: string)
		if newState ~= TraversalState.NORMAL then
			endSession(player) -- a launch from the fan: its animations take over
		elseif zones[player] then
			task.spawn(runSession, player, true)
		end
	end)
	log:Info("Started.")
end

return TreadmillService
