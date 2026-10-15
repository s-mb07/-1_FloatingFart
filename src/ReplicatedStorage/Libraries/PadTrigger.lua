--!strict
--[[
	@module PadTrigger
	@description The single "player is standing on a pad" detection primitive
	for the WHOLE project (client AND server): a CollectionService tag ->
	OnEnter/OnLeave callbacks. Replaces N copy-pasted `.Touched` wirings from
	one pad to the next (proximity-opened menus client-side, rewards/machines
	server-side), each diverging with its own bugs over successive copies.

	Why NOT `.Touched`:
	  - `.Touched` regularly misses when walking flat onto a pad;
	  - it NEVER guarantees an exit (death, teleport, streaming out): the
	    panel stayed open;
	  - it forces a manual debounce against physics jitter, and the copied
	    versions did that debounce PER PAD instead of PER PLAYER;
	  - `.Touched` closures captured the `Character` at contact time ->
	    stale after respawn, pad permanently dead (same bug family as
	    handlers not re-resolved after CharacterAdded).

	Here: ONE Scheduler task (POLL_INTERVAL, see `Scheduler.lua`) walks every
	registered pad and maintains an enter/exit state machine per (pad,
	player). `Character` is re-read on every tick -> respawn-safe by
	construction, no CharacterAdded re-hook needed. N pads = 1 shared task,
	cheaper than N `.Touched` connections.

	Distance is measured against the pad's box SURFACE, not its center: on a
	large pad, the center can be dozens of studs away even while standing on
	it (the classic immediate-close/flicker bug on any pad whose hitbox is
	bigger than average).

	The enter/exit padding is NOT a value chosen in code: it's computed from
	EACH PadHitbox's own geometry (half its diagonal, see `padFor` below) --
	a pad placed larger in Studio opens/closes farther away, without a dev
	having to guess a magic number per pad. Same value for enter and exit:
	no oscillation regardless, the enter (<=) and exit (>) comparison stays
	consistent around a single threshold. That's also why a tag like
	MachineTrigger (4 pads of different sizes) computes its padding PER PAD
	instead of once for the whole binding.

	Usage:
		local unbind = PadTrigger.Bind("Hitbox_OpenWorld_Index", {
			OnEnter = function(player, pad, source) ... end,
			OnLeave = function(player, pad, source) ... end,
		})

	`OnEnter` may yield (it runs inside a task.spawn). `OnLeave` MUST NOT
	yield: it's called inline in the loop, and its return value is used --
	returning `false` means "refuse to exit right now", the state stays
	"inside" and OnLeave will be called again on the next tick (used by
	SpinWheel, which refuses to close while a spin is in progress).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Scheduler = require(script.Parent.Scheduler)

local PadTrigger = {}

export type PadCallback = (player: Player, pad: BasePart, source: Instance) -> ()
--- Returning `false` = exit refused, retried on the next tick.
export type PadLeaveCallback = (player: Player, pad: BasePart, source: Instance) -> boolean?

export type PadOptions = {
	--- Minimum delay (s) between two OnEnters of the SAME player on the SAME
	--- pad. The state machine already handles spam; this cooldown only
	--- limits deliberate back-and-forth on a pad that grants a reward.
	--- Default: 0 (none).
	Cooldown: number?,
	--- Name of the descendant used as the hitbox when the tagged instance
	--- isn't itself a BasePart. Default: "PadHitbox".
	HitboxName: string?,
	--- Generates a hitbox from the bounding box if none is found (a station
	--- should never depend on manual placement to work -- original
	--- WorldRewardService behavior). Server-only: a part created client-side
	--- would only be visible to that client. Default: false.
	GenerateHitbox: boolean?,
	--- Fixed enter/exit padding (studs) instead of the geometry-derived one.
	--- 0 = strictly inside the box.
	Padding: number?,
	--- Per-axis enter/exit reach (studs) in the hitbox's LOCAL space, used
	--- instead of `Padding`: the pad counts as touched when the root is inside
	--- the box expanded by this much on each axis (e.g. (0, 4.5, 0) = over the
	--- footprint and within 4.5 studs of it vertically, nothing sideways).
	Reach: Vector3?,
	OnEnter: PadCallback?,
	OnLeave: PadLeaveCallback?,
}

local DEFAULT_HITBOX_NAME = "PadHitbox"
-- Floor (studs) for the computed padding: a safety net if a PadHitbox is
-- placed near-pointlike in Studio (Size close to zero) -- also covers the
-- case of a thin, flat pad whose box would never contain the center of the
-- HumanoidRootPart (which floats ~3 studs above the ground).
local MIN_PADDING = 4
-- 10 Hz: reactive enough for on-foot proximity, and negligible even with
-- dozens of pads (cost is O(pads x players) per tick).
local POLL_INTERVAL = 0.1
-- Height (studs) of the fallback-generated hitbox, and horizontal margin.
local GENERATED_HITBOX_HEIGHT = 4
local GENERATED_HITBOX_MARGIN = 2

local isServer = RunService:IsServer()

--- Client-side, a pad only ever concerns the LOCAL player (other players
--- obviously shouldn't have a panel opened for them); server-side, everyone.
local function observedPlayers(): { Player }
	if isServer then
		return Players:GetPlayers()
	end
	local localPlayer = Players.LocalPlayer
	return localPlayer and { localPlayer } or {}
end

type PadState = {
	Hitbox: BasePart,
	Source: Instance,
	-- Enter padding = exit padding, computed from THIS PAD'S GEOMETRY (see
	-- padFor) -- not a Binding-level value, two pads sharing a tag (e.g.
	-- MachineTrigger) can have different sizes.
	Padding: number,
	Reach: Vector3?,
	Inside: { [Player]: boolean },
	LastEnter: { [Player]: number },
}

type Binding = {
	Tag: string,
	Options: PadOptions,
	Cooldown: number,
	Pads: { [Instance]: PadState },
	Connections: { RBXScriptConnection },
	Alive: boolean,
}

local bindings: { [Binding]: boolean } = {}
local pollHandle: Scheduler.Handle? = nil

--============================================================================--
-- GEOMETRY
--============================================================================--

--- Distance between a point and the pad box's SURFACE (0 = inside).
local function distanceToBox(position: Vector3, box: BasePart): number
	local rel = box.CFrame:PointToObjectSpace(position)
	local half = box.Size * 0.5
	local dx = math.max(math.abs(rel.X) - half.X, 0)
	local dy = math.max(math.abs(rel.Y) - half.Y, 0)
	local dz = math.max(math.abs(rel.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- True when `position` counts as on the pad: within `Reach` per axis (local
--- space) if the pad sets one, else within the euclidean `Padding`.
local function isNear(state: PadState, position: Vector3): boolean
	local reach = state.Reach
	if reach then
		local rel = state.Hitbox.CFrame:PointToObjectSpace(position)
		local half = state.Hitbox.Size * 0.5
		return math.abs(rel.X) - half.X <= reach.X
			and math.abs(rel.Y) - half.Y <= reach.Y
			and math.abs(rel.Z) - half.Z <= reach.Z
	end
	return distanceToBox(position, state.Hitbox) <= state.Padding
end

--- Enter/exit padding derived from the pad's OWN GEOMETRY (half its
--- diagonal): a level designer resizing a PadHitbox in Studio widens its
--- trigger zone without touching code. `Size.Magnitude` is independent of
--- the part's orientation (unlike Size.X/Z), so it holds even for rotated
--- hitboxes.
local function padFor(hitbox: BasePart, options: PadOptions): number
	return options.Padding or math.max(hitbox.Size.Magnitude / 2, MIN_PADDING)
end

--============================================================================--
-- HITBOX RESOLUTION
--============================================================================--

--- Fallback for when no hitbox was placed by hand. `source` is guaranteed
--- to be a Model here: resolveHitbox already returns the BasePart itself
--- before reaching this point.
local function generateHitbox(source: Instance, name: string): BasePart?
	if not source:IsA("Model") then
		return nil
	end

	local cframe, size = (source :: Model):GetBoundingBox()

	local hitbox = Instance.new("Part")
	hitbox.Name = name
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = false
	hitbox.Transparency = 1
	hitbox.Size = Vector3.new(size.X + GENERATED_HITBOX_MARGIN, GENERATED_HITBOX_HEIGHT, size.Z + GENERATED_HITBOX_MARGIN)
	hitbox.CFrame = cframe * CFrame.new(0, -size.Y / 2 + GENERATED_HITBOX_HEIGHT / 2, 0)
	hitbox.Parent = source
	return hitbox
end

--- The tagged instance can BE the hitbox (Hitbox_OpenWorld_* convention) or
--- CONTAIN it (PadHitbox under an Interactive/Animated model convention).
local function resolveHitbox(source: Instance, options: PadOptions): BasePart?
	if source:IsA("BasePart") then
		return source
	end

	local name = options.HitboxName or DEFAULT_HITBOX_NAME
	local existing = source:FindFirstChild(name, true)
	if existing and existing:IsA("BasePart") then
		return existing
	end

	if options.GenerateHitbox then
		return generateHitbox(source, name)
	end

	return nil
end

--============================================================================--
-- STATE MACHINE
--============================================================================--

local function fireLeave(binding: Binding, state: PadState, player: Player): boolean
	local callback = binding.Options.OnLeave
	if not callback then
		return true
	end

	local ok, result = pcall(callback, player, state.Hitbox, state.Source)
	if not ok then
		warn(("PadTrigger: OnLeave failed for tag '%s': %s"):format(binding.Tag, tostring(result)))
		return true
	end

	return result ~= false
end

--- Forces every player still "inside" to exit (pad destroyed, tag removed,
--- player left) -- ignoring any refusal, there's nothing left to stay
--- attached to.
local function flushLeaves(binding: Binding, state: PadState): ()
	for player in state.Inside do
		state.Inside[player] = nil
		fireLeave(binding, state, player)
	end
end

local function updatePad(binding: Binding, source: Instance, state: PadState): ()
	local hitbox = state.Hitbox
	-- Streaming out / removal: forced exit, otherwise a panel opened by
	-- this pad would never close.
	if not hitbox.Parent or not hitbox:IsDescendantOf(workspace) then
		flushLeaves(binding, state)
		-- A Model source still here whose hitbox part streamed out: pick up
		-- the new instance once it streams back in (the old one is dead).
		if source ~= hitbox and source:IsDescendantOf(workspace) then
			local fresh = resolveHitbox(source, binding.Options)
			if fresh and fresh ~= hitbox then
				state.Hitbox = fresh
				state.Padding = padFor(fresh, binding.Options)
			end
		end
		return
	end

	for _, player in observedPlayers() do
		-- Character re-read on every tick: nothing captured, so respawn-safe.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if not root or not humanoid or humanoid.Health <= 0 then
			if state.Inside[player] then
				state.Inside[player] = nil
				fireLeave(binding, state, player)
			end
			continue
		end

		local near = isNear(state, root.Position)

		if state.Inside[player] then
			if not near and fireLeave(binding, state, player) then
				state.Inside[player] = nil
			end
		elseif near then
			local now = os.clock()
			if binding.Cooldown > 0 and now - (state.LastEnter[player] or -math.huge) < binding.Cooldown then
				continue
			end
			state.Inside[player] = true
			state.LastEnter[player] = now

			local callback = binding.Options.OnEnter
			if callback then
				-- task.spawn: OnEnter is allowed to yield (panel transition,
				-- loading screen, server round-trip) without blocking the
				-- other pads in the loop.
				-- An error inside a task.spawn thread is already surfaced by
				-- the engine with its full traceback -- no pcall here, which
				-- would reduce it to a stackless warn.
				task.spawn(callback, player, hitbox, source)
			end
		end
	end
end

--- Cost: O(pads x observed players) per tick, pure arithmetic, no
--- allocation. At the current scale (~10 pads, 1 observed player
--- client-side) this is negligible and comfortably beats a spatial query,
--- which walks the engine's broadphase AND allocates a results table on
--- every call.
---
--- ponytail: if the pad count grew into the several-HUNDREDS, invert the
--- loop: a single `workspace:GetPartBoundsInRadius` around each player per
--- tick, then only test the hitboxes it returns (O(players) instead of
--- O(pads x players)). REPLACE, don't add behind a flag -- two detection
--- paths where one is never exercised is exactly what made the 6
--- `.Touched` copies this module replaces diverge in the first place.
local function poll(): ()
	for binding in bindings do
		for source, state in binding.Pads do
			updatePad(binding, source, state)
		end
	end
end

local function ensurePolling(): ()
	if pollHandle then
		return
	end
	pollHandle = Scheduler.Every("PadTrigger_Poll", 1 / POLL_INTERVAL, poll)
end

local function stopPollingIfIdle(): ()
	if next(bindings) ~= nil then
		return
	end
	if pollHandle then
		pollHandle:Disconnect()
		pollHandle = nil
	end
end

--============================================================================--
-- PAD REGISTRATION
--============================================================================--

local function addPad(binding: Binding, source: Instance): ()
	if binding.Pads[source] then
		return
	end

	local hitbox = resolveHitbox(source, binding.Options)
	if hitbox then
		binding.Pads[source] = {
			Hitbox = hitbox,
			Source = source,
			Padding = padFor(hitbox, binding.Options),
			Reach = binding.Options.Reach,
			Inside = {},
			LastEnter = {},
		}
		return
	end

	-- These models live far from spawn: with StreamingEnabled, the hitbox
	-- often arrives AFTER the tag itself. DescendantAdded catches that late
	-- arrival without a dedicated poll.
	local name = binding.Options.HitboxName or DEFAULT_HITBOX_NAME
	local connection: RBXScriptConnection
	connection = source.DescendantAdded:Connect(function(descendant: Instance)
		if not binding.Alive then
			connection:Disconnect()
			return
		end
		if descendant.Name ~= name or not descendant:IsA("BasePart") then
			return
		end
		connection:Disconnect()
		if not binding.Pads[source] then
			local lateHitbox = descendant :: BasePart
			binding.Pads[source] = {
				Hitbox = lateHitbox,
				Source = source,
				Padding = padFor(lateHitbox, binding.Options),
				Reach = binding.Options.Reach,
				Inside = {},
				LastEnter = {},
			}
		end
	end)
	table.insert(binding.Connections, connection)
end

local function removePad(binding: Binding, source: Instance): ()
	local state = binding.Pads[source]
	if not state then
		return
	end
	binding.Pads[source] = nil
	flushLeaves(binding, state)
end

--============================================================================--
-- PUBLIC API
--============================================================================--

local function newBinding(tag: string, options: PadOptions): Binding
	return {
		Tag = tag,
		Options = options,
		Cooldown = options.Cooldown or 0,
		Pads = {},
		Connections = {},
		Alive = true,
	}
end

local function activate(binding: Binding): () -> ()
	bindings[binding] = true
	ensurePolling()

	return function(): ()
		if not binding.Alive then
			return
		end
		binding.Alive = false
		bindings[binding] = nil
		for _, connection in binding.Connections do
			connection:Disconnect()
		end
		table.clear(binding.Connections)
		for source in binding.Pads do
			removePad(binding, source)
		end
		stopPollingIfIdle()
	end
end

--- Wires every object tagged `tag` (present AND future) to the given
--- callbacks. Returns an unbind function.
function PadTrigger.Bind(tag: string, options: PadOptions): () -> ()
	local binding = newBinding(tag, options)

	for _, source in CollectionService:GetTagged(tag) do
		addPad(binding, source)
	end

	table.insert(binding.Connections, CollectionService:GetInstanceAddedSignal(tag):Connect(function(source: Instance)
		addPad(binding, source)
	end))
	table.insert(binding.Connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(source: Instance)
		removePad(binding, source)
	end))

	return activate(binding)
end

--- Variant for a hitbox the CALLER has already resolved (a station still
--- located via a hardcoded Workspace path instead of a tag -- see
--- SellService). Avoid for any new pad: go through a tag and PadTrigger.Bind.
function PadTrigger.BindPart(hitbox: BasePart, options: PadOptions): () -> ()
	local binding = newBinding(hitbox:GetFullName(), options)
	binding.Pads[hitbox] = {
		Hitbox = hitbox,
		Source = hitbox,
		Padding = padFor(hitbox, binding.Options),
		Reach = options.Reach,
		Inside = {},
		LastEnter = {},
	}
	return activate(binding)
end

if isServer then
	Players.PlayerRemoving:Connect(function(player: Player)
		for binding in bindings do
			for _, state in binding.Pads do
				state.Inside[player] = nil
				state.LastEnter[player] = nil
			end
		end
	end)
end

return PadTrigger
