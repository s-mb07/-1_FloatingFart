--!strict
--[[
	@module AnimationWarmController
	@description Primes the flight animations on every character this client
	sees, so the FIRST launch of a session does not play oddly.

	The server plays the poses (Traversal/CharacterAnimations); a client that
	has downloaded the asset (LoadingController preload) still has to build the
	track on that character's Animator the first time it is asked to play it,
	which shows as a late / glitchy first Start animation. Here each registered
	animation is loaded on the Animator and played for one frame at weight 0
	(invisible), then stopped: the first real play finds everything ready.
	Client-created tracks are local only and never touch what the server plays.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationIds = require(ReplicatedStorage.Config.AssetIds.AnimationIds)
local Logger = require(ReplicatedStorage.Libraries.Logger)

local log = Logger.new("AnimationWarmController")
local AnimationWarmController = {}

local ANIMATOR_TIMEOUT = 10

local function warm(character: Model): ()
	local humanoid = character:WaitForChild("Humanoid", ANIMATOR_TIMEOUT)
	local animator = humanoid and humanoid:WaitForChild("Animator", ANIMATOR_TIMEOUT)
	if not (animator and animator:IsA("Animator")) then
		return
	end
	local tracks: { AnimationTrack } = {}
	for _, id in AnimationIds do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track:Play(0, 0, 1) -- weight 0: nothing visible
		table.insert(tracks, track)
		animation:Destroy()
	end
	task.wait()
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
end

local function watch(player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(warm, character)
	end)
	if player.Character then
		task.spawn(warm, player.Character)
	end
end

function AnimationWarmController:Init(): ()
	log:Info("Initialized.")
end

function AnimationWarmController:Start(): ()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return AnimationWarmController
