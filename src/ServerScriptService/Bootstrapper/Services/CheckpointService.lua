--!strict
--[[
	@module CheckpointService
	@description Per-run checkpoint progress (runtime, never persisted) with
	the anti-cheat rules:
	  - checkpoint N needs N-1 first (skipping is reported);
	  - a minimum time between two checkpoints: reaching checkpoint N starts a
	    one-shot timer (distance to N+1 / (probe speed / SpeedDivisor)). When
	    it elapses it flips `NextReady` to true -- nothing runs in between and
	    nothing runs after. The anti-cheat reads that boolean when N+1 is
	    entered; if it is still false the move is reported (too fast).
	Reaching checkpoint 1 is not timed (nothing precedes it).
	Violations go to AntiCheatService.Report (the existing flag/escalation
	path); the checkpoint is simply not validated. Players being moved by the
	server (PlayerTeleportService.IsProtected) are never judged.

	Checkpoint Hitboxes: Parts tagged TagNames.CheckpointHitbox with a
	`Stage` attribute (Workspace._WORLD.MAP.CHECKPOINTS/<n>/Hitbox).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AntiCheatService = require(script.Parent.AntiCheatService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local PlayerTeleportService = require(script.Parent.PlayerTeleportService)
local ProbeConfig = require(ReplicatedStorage.Config.ProbeConfig)
local RespawnConfig = require(script.Parent.Parent.Config.RespawnConfig)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)

local log = Logger.new("CheckpointService")
local CheckpointService = {}

type Progress = {
	Stage: number, -- highest checkpoint reached (0 = none)
	--- False from the moment `Stage` is reached until the minimum travel time
	--- to the next checkpoint has elapsed (flipped by a one-shot timer).
	NextReady: boolean,
}

local progress: { [Player]: Progress } = {}

local function findHitbox(stage: number): BasePart?
	for _, part in CollectionService:GetTagged(TagNames.CheckpointHitbox) do
		if part:IsA("BasePart") and part:GetAttribute(TagNames.Attr.Stage) == stage then
			return part
		end
	end
	return nil
end

--- Progress for having just reached `stage` (0 = run start: nothing to time).
--- Starts the one-shot timer towards the next checkpoint, if there is one.
local function startProgress(player: Player, stage: number): Progress
	local p: Progress = { Stage = stage, NextReady = true }
	progress[player] = p

	local here = findHitbox(stage)
	local nextHitbox = findHitbox(stage + 1)
	if here and nextHitbox then
		local gap = (nextHitbox.Position - here.Position).Magnitude
			- here.Size.Magnitude / 2
			- nextHitbox.Size.Magnitude / 2
		local minSeconds = math.max(gap, 0) / (ProbeConfig.Speed / RespawnConfig.SpeedDivisor)
		if minSeconds > 0 then
			p.NextReady = false
			task.delay(minSeconds, function()
				p.NextReady = true -- p is stale (and harmless) if the run was reset meanwhile
			end)
		end
	end
	return p
end

local function getProgress(player: Player): Progress
	return progress[player] or startProgress(player, 0)
end

--- Highest checkpoint reached this run (0 = none).
function CheckpointService.GetStage(player: Player): number
	return getProgress(player).Stage
end

--- New run: back to the lobby, no checkpoint.
function CheckpointService.Reset(player: Player): ()
	startProgress(player, 0)
end

--- After a revive: the run resumes AT `stage`, timer restarted from there.
function CheckpointService.RestoreTo(player: Player, stage: number): ()
	if findHitbox(stage) then
		startProgress(player, stage)
	end
end

--- Where a player is put back inside checkpoint `stage`: the bottom centre of
--- the Hitbox part (computed from its size, not its pivot), lifted a little
--- so the character never lands in the floor. nil if there is no such stage.
function CheckpointService.GetSpawnCFrame(stage: number): CFrame?
	local hitbox = findHitbox(stage)
	if not hitbox then
		return nil
	end
	local bottom = hitbox.CFrame * Vector3.new(0, -hitbox.Size.Y / 2, 0)
	return CFrame.new(bottom + Vector3.new(0, RespawnConfig.LobbyLift, 0))
end

local function onEntered(player: Player, hitbox: BasePart): ()
	if PlayerTeleportService.IsProtected(player) then
		return -- moved by the server: never a violation, never progress
	end
	local stage = hitbox:GetAttribute(TagNames.Attr.Stage)
	if type(stage) ~= "number" then
		log:Warn("Checkpoint '%s' has no numeric Stage.", hitbox:GetFullName())
		return
	end

	local p = getProgress(player)
	if stage <= p.Stage then
		return -- already reached
	end
	if stage > p.Stage + 1 then
		AntiCheatService.Report(
			player,
			("checkpoint %d reached without %d"):format(stage, p.Stage + 1)
		)
		return
	end
	if not p.NextReady then
		AntiCheatService.Report(player, ("checkpoint %d reached too fast"):format(stage))
		return
	end

	startProgress(player, stage)
	log:Info("%s reached checkpoint %d.", player.Name, stage)
	GameEvents.OnCheckpointReached:Fire(player, stage)
end

function CheckpointService:Init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		progress[player] = nil
	end)
	log:Info("Initialized.")
end

function CheckpointService:Start(): ()
	PadTrigger.Bind(TagNames.CheckpointHitbox, {
		Padding = 0, -- strictly inside the volume
		OnEnter = onEntered,
	})
	log:Info("Started.")
end

return CheckpointService
