--!strict
--[[
	@module AntiCheatService
	@description Detects abnormal movement (speedhack/teleportation),
	SERVER side only -- the client can never clear itself.

	Deliberately simple skeleton: one position/time pair per player, a
	Scheduler task that recomputes the implicit speed on every tick and
	accumulates "flags" when it exceeds the cap. This is NOT a replacement
	for server-side validation of every remote (cf. CLAUDE.md: "the client
	can lie", every value-affecting action must be revalidated at its own
	source, not just here) -- this service catches MOVEMENT cheating, not
	LOGIC cheating (e.g. falsifying an amount sent by a remote, which must
	be re-checked in the relevant Service).

	`MAX_STUDS_PER_SECOND` must cover a wide range: sprint, dash, knockback,
	legitimate IN-GAME teleportation (that one must go through
	ResetTracking, not get flagged as cheating).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local TraversalState = require(ReplicatedStorage.Config.TraversalState)
local TraversalStateService = require(script.Parent.TraversalStateService)

local AntiCheatService = {}
local log = Logger.new("AntiCheatService")

-- Deliberately generous (see doc above): this catches blatant speedhacking,
-- not a subtle movement exploit (poorly implemented dash, etc.).
local MAX_STUDS_PER_SECOND = 80
-- Number of consecutive overages before taking action -- absorbs an isolated
-- false positive (lag spike, legitimate knockback) without ever punishing on a single sample.
local FLAG_THRESHOLD = 5

-- Velocity caps (studs/s, rad/s) outside the flight mechanic. A free fall
-- tops out near 200 studs/s; a normal character never spins anywhere near this.
local MAX_LINEAR_VELOCITY = 300
local MAX_ANGULAR_VELOCITY = 50

type Tracked = {
	LastPosition: Vector3,
	LastClock: number,
	Flags: number,
}

local tracked: { [Player]: Tracked } = {}

--- Resets a player's tracking -- must be called by ANY system that
--- legitimately teleports a player (spawn, portal, TeleportService...),
--- otherwise that instant displacement gets counted as an overage.
--- @param player Player
function AntiCheatService.ResetTracking(player: Player): ()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	tracked[player] = {
		LastPosition = root.Position,
		LastClock = os.clock(),
		Flags = 0,
	}
end

--- True while this player is sitting at the escalation threshold above.
--- Read-only accessor so another service can ASK this layer rather than
--- reach into its tracking table (README §9.7) -- it adds no new policy and
--- changes nothing this service already does.
--- @param player Player
--- @return boolean
function AntiCheatService.IsFlagged(player: Player): boolean
	local state = tracked[player]
	return state ~= nil and state.Flags >= FLAG_THRESHOLD
end

-- Rule violations reported by other services (see Report). Kept apart from
-- the movement flags: those decay by the second and are wiped by every
-- ResetTracking (each legitimate teleport), which would erase these.
local VIOLATION_THRESHOLD = 3
local violations: { [Player]: number } = {}

--- Records a server-rule violation (a skipped checkpoint, impossible timing,
--- ...) on the same warn -> escalation path as movement cheating. The caller
--- has already refused the action; this only tracks repeat offenders.
--- Legitimate server teleports are NOT violations: callers must check
--- PlayerTeleportService.IsProtected first.
--- @param player Player
--- @param reason string
function AntiCheatService.Report(player: Player, reason: string): ()
	local count = (violations[player] or 0) + 1
	violations[player] = count
	log:Warn("%s: rule violation (%s) -- %d/%d.", player.Name, reason, count, VIOLATION_THRESHOLD)

	if count >= VIOLATION_THRESHOLD then
		-- Same deliberate non-action as onFlagged below: visible first, then
		-- hook up ModerationService (warn/kick/ban) here.
		log:Error(
			"%s: violation threshold exceeded, moderation action to hook up here.",
			player.Name
		)
		violations[player] = 0
	end
end

local function onFlagged(player: Player, studsPerSecond: number): ()
	log:Warn(
		"%s: implicit speed %.0f studs/s (threshold %d) -- flag %d/%d.",
		player.Name,
		studsPerSecond,
		MAX_STUDS_PER_SECOND,
		tracked[player].Flags,
		FLAG_THRESHOLD
	)

	if tracked[player].Flags >= FLAG_THRESHOLD then
		-- Example action: replace with your own escalation (report to
		-- ModerationService, catch-up teleport to the last known-good
		-- position, kick...). Deliberately NOT a direct kick here -- a
		-- repeated false positive must be visible (warn/analytics)
		-- before cutting off a legitimate player's session.
		log:Error("%s: flag threshold exceeded, moderation action to hook up here.", player.Name)
		tracked[player].Flags = 0
	end
end

local function checkPlayer(player: Player): ()
	local state = tracked[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if not state then
		AntiCheatService.ResetTracking(player)
		return
	end

	-- A player in the flight mechanic (lift, flight, rebound, free fall of the
	-- ending, wall lock) is judged by ProbeService itself (windowed speed
	-- check + obstacle sweep), whose motion legitimately exceeds the cap.
	if TraversalStateService.Get(player) ~= TraversalState.NORMAL then
		AntiCheatService.ResetTracking(player)
		return
	end

	-- Fling / velocity exploit: a character spun or launched by manipulating its
	-- own physics. Collisions between players are already disabled
	-- (PlayerCollisionService), so this catches the self-inflicted remainder.
	-- Spin and velocity are neutralised on the spot, then reported.
	if
		root.AssemblyAngularVelocity.Magnitude > MAX_ANGULAR_VELOCITY
		or root.AssemblyLinearVelocity.Magnitude > MAX_LINEAR_VELOCITY
	then
		root.AssemblyAngularVelocity = Vector3.zero
		root.AssemblyLinearVelocity = Vector3.zero
		AntiCheatService.Report(player, "abnormal velocity")
	end

	local now = os.clock()
	local dt = now - state.LastClock
	if dt <= 0 then
		return
	end

	-- Downward motion is not judged: a long fall legitimately exceeds the cap.
	local moved = root.Position - state.LastPosition
	local distance = Vector3.new(moved.X, math.max(moved.Y, 0), moved.Z).Magnitude
	local studsPerSecond = distance / dt

	state.LastPosition = root.Position
	state.LastClock = now

	if studsPerSecond > MAX_STUDS_PER_SECOND then
		state.Flags += 1
		onFlagged(player, studsPerSecond)
	elseif state.Flags > 0 then
		state.Flags -= 1 -- decay: an isolated flag fades away over time
	end
end

function AntiCheatService:Init(): ()
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(AntiCheatService.ResetTracking, player) -- let the Character finish populating
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		tracked[player] = nil
		violations[player] = nil
	end)

	Scheduler.Every("AntiCheatService_MovementCheck", 4, function()
		for _, player in Players:GetPlayers() do
			checkPlayer(player)
		end
	end)
end

return AntiCheatService
