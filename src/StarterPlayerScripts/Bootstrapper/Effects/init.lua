--!strict
--[[
	@module Effects
	@description Single entry point for player feedback (sound, visual, camera, haptic).

	Usage: Effects.Play("RewardClaimed", { Position = someWorldPosition })

	The caller only provides context. Cloning and destroying the presented
	model, taking and releasing the camera, handling skip and respawn,
	checking haptic support, reading player settings: all of it is absorbed here.

	No Init/Start: required on demand, not scanned by the bootstrap
	(it's neither a StandaloneController nor a Panel).
]]

local Debris = game:GetService("Debris")

local EffectsConfig = require(script.Parent.Config.EffectsConfig)
local Settings = require(script.Settings)
local SoundChannel = require(script.Channels.Sound)

export type Context = {
	Subject: (string | Model)?,  -- asset name under Assets to clone, or an already-instantiated model
	Position: Vector3?,
	Target: GuiObject?,
	Color: Color3?,
	Text: string?,
	Amount: number?,
}

local Effects = {}

--- An array, not a dictionary: iteration order of a keyed table isn't
--- guaranteed in Luau, and a cinematic with synced sound can't depend on
--- chance. Camera goes first: it's the one that stages the subject, which
--- other channels may depend on.
local CHANNELS = {
	{ Key = "Camera", Module = require(script.Channels.Camera) },
	{ Key = "Sound",  Module = SoundChannel },
	{ Key = "Haptic", Module = require(script.Channels.Haptic) },
	{ Key = "Visual", Module = require(script.Channels.Visual) },
	{ Key = "World",  Module = require(script.Channels.World)  },
}

--- Purchase fanfare (PlayPurchaseFanfare). Sounds by name in ReplicatedStorage/Assets/sfx.
local PURCHASE_COIN_SOUND = "CoinCollect"
local PURCHASE_COIN_HITS = 7
local PURCHASE_COIN_INTERVAL = 0.07
local PURCHASE_XP_SOUND = "XPLand"
local PURCHASE_XP_HITS = 10
local PURCHASE_XP_INTERVAL = 0.06
local PURCHASE_PITCH_STEP = 0.05 -- each hit plays this much faster than the last
--- Gamepass fanfare (PlayPassFanfare): a bigger coin shower, then level-ups.
local PASS_COIN_HITS = 12
local PASS_COIN_INTERVAL = 0.05
local PASS_LEVEL_SOUND = "LevelUp"
local PASS_LEVEL_PITCH_STEP = 0.12

local systemEnabled = true
local lastPlayed: {[string]: number} = {}

--- Plays the feedback recipe associated with `id`, if it exists.
--- @param id string Key in EffectsConfig
--- @param context Context? Contextual data (subject, position, text, UI target...)
function Effects.Play(id: string, context: Context?): ()
	if not systemEnabled then return end

	local recipe = EffectsConfig[id]
	if not recipe then
		warn("[Effects] Unknown recipe: " .. id)
		return
	end

	local cooldown = recipe.Cooldown or 0
	if os.clock() - (lastPlayed[id] or 0) < cooldown then
		return
	end
	lastPlayed[id] = os.clock()

	local resolvedContext: Context = context or {}
	for _, channel in CHANNELS do
		local spec = (recipe :: any)[channel.Key]
		if spec then
			-- A channel that fails must not block the others, but its
			-- error must not silently vanish either.
			local ok, err = pcall(channel.Module.Play, spec, resolvedContext)
			if not ok then
				warn(`[Effects] Channel {channel.Key} failed on "{id}": {err}`)
			end
		end
	end
end

--- Readies every Sound of ReplicatedStorage/Assets/sfx up front (playable
--- copy + downloaded asset), so no sound waits the first time it plays.
--- Yields; call it spawned, once, early (SoundController does).
function Effects.PreloadSounds(): ()
	SoundChannel.Preload()
end

--- The playable copy of the Assets/sfx Sound `name`, for a sound a caller
--- drives itself (e.g. a loop). nil if the folder has no such Sound.
--- @param name string
--- @return Sound?
function Effects.GetSound(name: string): Sound?
	return SoundChannel.Get(name)
end

--- Plays sfx `name` `count` times, `interval` apart, each `pitchStep`
--- faster than the last, starting after `delay`. Each hit is its own clone
--- so they overlap.
local function cascade(
	name: string,
	count: number,
	interval: number,
	delay: number,
	pitchStep: number?
): ()
	local template = SoundChannel.Get(name)
	if not (template and Effects.IsSoundEnabled()) then
		return
	end
	for hit = 0, count - 1 do
		task.delay(delay + hit * interval, function()
			local sound = template:Clone()
			sound.PlaybackSpeed = template.PlaybackSpeed
				* (1 + hit * (pitchStep or PURCHASE_PITCH_STEP))
			sound.Parent = template.Parent
			sound:Play()
			Debris:AddItem(sound, 5)
		end)
	end
end

--- The purchase sound: a shower of coins, then a run of XP ticks, each hit
--- a little higher. Played on a real purchase (PurchasePromptController)
--- and on a free gift worth the same fanfare (Panels/LeaveReward).
function Effects.PlayPurchaseFanfare(): ()
	cascade(PURCHASE_COIN_SOUND, PURCHASE_COIN_HITS, PURCHASE_COIN_INTERVAL, 0)
	local coinsDone = PURCHASE_COIN_HITS * PURCHASE_COIN_INTERVAL
	cascade(PURCHASE_XP_SOUND, PURCHASE_XP_HITS, PURCHASE_XP_INTERVAL, coinsDone)
end

--- Seconds the gamepass coin shower lasts (PlayPassFanfare's first part).
Effects.PassCoinSeconds = PASS_COIN_HITS * PASS_COIN_INTERVAL

--- The gamepass sound: a big shower of coins, then `levels` level-up
--- jingles `levelInterval` apart, each one higher (PurchaseRevealController
--- syncs one benefit line to each level-up).
--- @param levels number
--- @param levelInterval number
function Effects.PlayPassFanfare(levels: number, levelInterval: number): ()
	cascade(PURCHASE_COIN_SOUND, PASS_COIN_HITS, PASS_COIN_INTERVAL, 0)
	cascade(
		PASS_LEVEL_SOUND,
		levels,
		levelInterval,
		Effects.PassCoinSeconds,
		PASS_LEVEL_PITCH_STEP
	)
end

--- True while a sound of `group` (EffectsConfig SoundSpec.Group) is playing.
--- @param group string
--- @return boolean
function Effects.IsSoundGroupPlaying(group: string): boolean
	return SoundChannel.IsGroupPlaying(group)
end

--- True while the player has sound effects on (data.Settings.SfxEnabled).
--- For sounds played outside a recipe (e.g. a loop a controller owns).
--- @return boolean
function Effects.IsSoundEnabled(): boolean
	return systemEnabled and Settings.Get("Sfx")
end

--- Plays Assets/sfx `name` in 3D from `part` (another player's character...).
--- @param name string
--- @param part BasePart
--- @param maxDistance number -- studs beyond which it is silent
function Effects.PlayAt(name: string, part: BasePart, maxDistance: number): ()
	if systemEnabled then
		SoundChannel.PlayAt(name, part, maxDistance)
	end
end

--- Globally enables/disables the system (useful for debugging).
--- @param enabled boolean
function Effects.SetEnabled(enabled: boolean): ()
	systemEnabled = enabled
end

return Effects
