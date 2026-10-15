--!strict
--[[
	@module Traversal.CharacterAnimations
	@description Server-only playback of the two looping poses the traversal
	mechanic puts a character in: FlyIdle (towed back along the trail) and
	WallIdle (suspended against a wall).

	Played from the SERVER on the character's Animator, so the pose replicates
	to every client watching that character and stays in lockstep with the
	state machine that decides it -- no client can hold or skip it.

	Why this needs no fight with the default Animate script: CharacterLock
	disables Animate (and stops its tracks) for exactly the window these
	poses play in, so nothing else drives the rig. The explicit Action
	priority is belt-and-braces for the one case that could still race in --
	a track Animate started in the frame before it was disabled -- and makes
	the pose win over any Core/Idle/Movement track regardless of the priority
	the asset was published with.

	Not a Service: no Init/Start. Per-player state is only "which track is
	playing right now", so it lives beside CharacterLock in Traversal/.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationIds = require(ReplicatedStorage.Config.AssetIds.AnimationIds)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local TraversalConfig = require(ReplicatedStorage.Config.TraversalConfig)

local log = Logger.new("CharacterAnimations")

local CharacterAnimations = {}

--- Names accepted by Play / PlayOnce -- each must be a key of AnimationIds.
export type PoseName = "FlyStart" | "FlyIdle" | "FlyEnd" | "WallIdle"

--- Longest wait (s) for a freshly loaded track to report its Length.
local LENGTH_TIMEOUT = 2
--- Grace (s) after a one-shot's length before it is force-stopped.
local SAFETY_MARGIN = 0.5

-- The ONE pose of a player: every pose goes through here, so a character can
-- never have two of ours playing at once (the server is the only author --
-- no client plays any of these any more).
local playing: { [Player]: AnimationTrack } = {}
-- One track per (Animator, pose), loaded once and reused: no pile of
-- orphan tracks (one per launch) that nothing would ever stop again.
local tracks: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
-- Id of the latest play of a track: a delayed callback (safety stop) only
-- acts on the play that scheduled it, never on a later one of the same track.
local playIds: { [AnimationTrack]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextPlayId = 0

local function getTrack(animator: Animator, pose: PoseName): AnimationTrack
	local byPose = tracks[animator]
	if not byPose then
		byPose = {}
		tracks[animator] = byPose
	end
	local track = byPose[pose]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = AnimationIds[pose]
		track = animator:LoadAnimation(animation)
		byPose[pose] = track
	end
	return track
end

local function ownIds(): { [string]: boolean }
	local ours: { [string]: boolean } = {}
	for _, pose in { "FlyStart", "FlyIdle", "FlyEnd", "WallIdle" } do
		ours[AnimationIds[pose]] = true
	end
	return ours
end

--- Stops whatever pose is playing for `player`. Safe when nothing is: called
--- from every unlock path (CharacterLock.Lock/Release), which must never have
--- to know whether a pose was active.
--- @param player Player
--- @param fadeTime number? -- defaults to TraversalConfig.Animation.PoseFade
function CharacterAnimations.Stop(player: Player, fadeTime: number?): ()
	local track = playing[player]
	playing[player] = nil
	if track then
		track:Stop(fadeTime or TraversalConfig.Animation.PoseFade)
	end
end

--- Stops `track` only if it is still THE pose of `player` -- for a caller that
--- started a pose long ago (treadmill) and must not clobber a newer one.
function CharacterAnimations.StopTrack(player: Player, track: AnimationTrack?): ()
	if track and playing[player] == track then
		CharacterAnimations.Stop(player)
	end
end

--- Cross-fades to `pose`: the previous pose fades out while the new one fades
--- in (no dip through the bind pose), then it is THE pose of the player.
local function start(
	player: Player,
	character: Model,
	pose: PoseName,
	looped: boolean
): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		log:Warn("%s: no Animator on character -- cannot play %s.", player.Name, pose)
		return nil
	end

	local track = getTrack(animator, pose)
	local previous = playing[player]
	if previous == track then
		track:Stop(0) -- same pose again: restart it, never stack on itself
	elseif previous then
		previous:Stop(TraversalConfig.Animation.PoseFade)
	end
	-- Whatever else of ours still plays on this Animator (a track whose
	-- record was lost, e.g. across a respawn) goes too: one pose, ever.
	local ours = ownIds()
	for _, other in animator:GetPlayingAnimationTracks() do
		local animation = other.Animation
		if other ~= track and animation and ours[animation.AnimationId] then
			other:Stop(TraversalConfig.Animation.PoseFade)
		end
	end

	track.Priority = TraversalConfig.Animation.PosePriority
	track.Looped = looped
	nextPlayId += 1
	playIds[track] = nextPlayId
	track:Play(TraversalConfig.Animation.PoseFade)
	playing[player] = track
	return track
end

--- Starts looping `pose` on `character`, replacing any pose already playing
--- for `player` (FlyIdle -> WallIdle at the end of a walk-back is one call).
--- Failure (no Animator yet, asset not loadable) is logged and swallowed:
--- the pose is cosmetic and must never interrupt the mechanic.
--- @param player Player
--- @param character Model
--- @param pose PoseName
--- @return AnimationTrack? -- the track, to hand to StopTrack later
function CharacterAnimations.Play(player: Player, character: Model, pose: PoseName): AnimationTrack?
	return start(player, character, pose, true)
end

--- Plays `pose` ONCE (no loop) and returns its track and length in seconds,
--- so the caller can sequence on it (Start -> flight, End -> controls back).
--- Replaces any pose playing for `player`. Yields briefly until the engine
--- reports the track's Length (0 until the asset has loaded).
--- @return AnimationTrack?, number -- nil track (and 0) when it cannot play
function CharacterAnimations.PlayOnce(
	player: Player,
	character: Model,
	pose: PoseName
): (AnimationTrack?, number)
	local track = start(player, character, pose, false)
	if not track then
		return nil, 0
	end
	local id = playIds[track]

	local waited = 0
	while track.Length <= 0 and waited < LENGTH_TIMEOUT do
		waited += task.wait()
	end

	-- Safety net: whatever happens to the sequencing around it, a one-shot
	-- can never keep playing (and replaying for the other players) past its
	-- own length.
	local lifetime = if track.Length > 0 then track.Length else LENGTH_TIMEOUT
	task.delay(lifetime + SAFETY_MARGIN, function()
		-- A one-shot never loops: force it off even if Looped got flipped.
		if playIds[track] == id and track.IsPlaying then
			track.Looped = false
			track:Stop(TraversalConfig.Animation.PoseFade)
		end
	end)
	return track, track.Length
end

--- Preloads every registered animation on the server (yields). Without it
--- the first LoadAnimation of a launch fetches the asset on the spot: the
--- track reports no Length for a moment and the Start animation starts late.
function CharacterAnimations.Preload(): ()
	local carriers: { Instance } = {}
	for _, id in AnimationIds do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		table.insert(carriers, animation)
	end
	ContentProvider:PreloadAsync(carriers)
	for _, carrier in carriers do
		carrier:Destroy()
	end
end

--- Loads (without playing) every registered animation on `character`'s
--- Animator, so its first real play finds them ready. Call on spawn.
--- @param character Model
function CharacterAnimations.Warm(character: Model): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	local animator = humanoid and humanoid:WaitForChild("Animator", 5)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	for pose in AnimationIds do
		if ownIds()[AnimationIds[pose]] then
			getTrack(animator, pose :: PoseName)
		end
	end
end

--- Stops every track of the flight (Start / Idle / End / WallIdle) still
--- playing on `character`, whoever started it. The sweep used by every exit
--- path so nothing of the mechanic can keep looping on a character.
--- @param character Model?
function CharacterAnimations.StopAll(character: Model?): ()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local ours = ownIds()
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and ours[animation.AnimationId] then
			track:Stop(TraversalConfig.Animation.PoseFade)
		end
	end
end

--- Watchdog step: stops any of our poses playing on `character` that is NOT
--- the registered pose of `player` (an orphan nothing would ever stop), and
--- with `idle` also the registered one -- for a player who should be playing
--- nothing at all (back to NORMAL, not training).
--- @param player Player
--- @param idle boolean
function CharacterAnimations.Sweep(player: Player, idle: boolean): ()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local keep = if idle then nil else playing[player]
	local ours = ownIds()
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and ours[animation.AnimationId] then
			-- A one-shot kept as the pose that already ran its whole length
			-- is a stuck replay: stop it too.
			local spent = not track.Looped and track.Length > 0 and track.TimePosition >= track.Length
			if track ~= keep or spent then
				track:Stop(TraversalConfig.Animation.PoseFade)
			end
		end
	end
	if idle then
		playing[player] = nil
	end
end

--- Drops the record without touching the track -- for a player who has left,
--- where the Animator is already gone.
--- @param player Player
function CharacterAnimations.Forget(player: Player): ()
	playing[player] = nil
end

return CharacterAnimations
