--!strict
--[[
	@module Effects.Channels.Sound
	@description Effects' sound channel.

	Every sound is an authored Sound instance in ReplicatedStorage/Assets/sfx
	(any subfolder), picked by NAME: its SoundId, Volume, PlaybackSpeed,
	Looped are tuned there in Studio, never in code. A Sound under
	ReplicatedStorage cannot play, so each one is cloned ONCE into
	SoundService/EffectsSounds and that copy is reused (a replay restarts
	it). `Preload` (Effects.PreloadSounds) clones and downloads the whole
	folder up front, so no play waits for its asset.

	`Group`: sounds sharing a group form a sequence -- playing one stops the
	others of the group still ringing (a panel's close cuts its open, a
	flight stop cuts the take-off). `Stops`: groups a sound silences when it
	starts (a celebration cuts the notification chime of the same event).
	`IsGroupPlaying` lets a caller skip a minor sound while a bigger one of a
	group is still on.

	Gated by the player's SFX setting (data.Settings.SfxEnabled).
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local EffectsConfig = require(script.Parent.Parent.Parent.Config.EffectsConfig)
local Settings = require(script.Parent.Parent.Settings)

local Sound = {}

local PLAYBACK_FOLDER_NAME = "EffectsSounds"

local playbackFolder: Folder? = nil
local copies: { [string]: Sound } = {}
local groups: { [string]: { Sound } } = {}
local warned: { [string]: boolean } = {}

--- ReplicatedStorage/Assets/sfx, or nil if it is not there.
local function getLibrary(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("sfx")
end

local function getPlaybackFolder(): Folder
	local existing = playbackFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = PLAYBACK_FOLDER_NAME
	created.Parent = SoundService
	playbackFolder = created
	return created
end

--- The playable copy of the sfx Sound named `name` (nil + one warning if absent).
--- @param name string
--- @return Sound?
function Sound.Get(name: string): Sound?
	local copy = copies[name]
	if copy and copy.Parent then
		return copy
	end
	local library = getLibrary()
	local template = library and library:FindFirstChild(name, true)
	if not (template and template:IsA("Sound")) then
		if not warned[name] then
			warned[name] = true
			warn(("[Effects] No Sound named '%s' in ReplicatedStorage/Assets/sfx"):format(name))
		end
		return nil
	end
	local created = template:Clone()
	created.Parent = getPlaybackFolder()
	copies[name] = created
	return created
end

--- Stops every playing sound of `group` but `except`.
local function stopGroup(group: string, except: Sound?): ()
	for _, other in groups[group] or {} do
		if other ~= except and other.IsPlaying then
			other:Stop()
		end
	end
end

function Sound.Play(spec: EffectsConfig.SoundSpec, _context: any): ()
	if not Settings.Get("Sfx") then
		return -- player turned SFX off (Settings panel, data.Settings.SfxEnabled)
	end
	local sound = Sound.Get(spec.Name)
	if not sound then
		return
	end
	if spec.Group then
		local members = groups[spec.Group] or {}
		groups[spec.Group] = members
		if not table.find(members, sound) then
			table.insert(members, sound)
		end
		stopGroup(spec.Group, sound)
	end
	for _, group in spec.Stops or {} do
		stopGroup(group)
	end
	sound.TimePosition = 0
	sound:Play()
end

--- Plays sfx `name` in 3D from `part` (a Sound inside a BasePart is positional):
--- a one-off clone, so it overlaps freely and never cuts the 2D copy or a group.
--- @param name string -- Sound in Assets/sfx
--- @param part BasePart -- where it is heard from (follows the part)
--- @param maxDistance number -- studs beyond which it is silent
function Sound.PlayAt(name: string, part: BasePart, maxDistance: number): ()
	if not Settings.Get("Sfx") then
		return
	end
	local template = Sound.Get(name)
	if not template then
		return
	end
	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = part
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

--- Clones every Sound of Assets/sfx and downloads their assets. Yields.
function Sound.Preload(): ()
	local library = getLibrary()
	if not library then
		warn("[Effects] ReplicatedStorage/Assets/sfx is missing: no sound will play")
		return
	end
	local sounds: { Instance } = {}
	for _, descendant in library:GetDescendants() do
		if descendant:IsA("Sound") then
			local copy = Sound.Get(descendant.Name)
			if copy then
				table.insert(sounds, copy)
			end
		end
	end
	ContentProvider:PreloadAsync(sounds)
end

--- True while any sound of `group` is playing.
--- @param group string
--- @return boolean
function Sound.IsGroupPlaying(group: string): boolean
	for _, sound in groups[group] or {} do
		if sound.IsPlaying then
			return true
		end
	end
	return false
end

return Sound
