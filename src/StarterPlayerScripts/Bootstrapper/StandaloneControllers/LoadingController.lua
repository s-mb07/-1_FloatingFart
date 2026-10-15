--!strict
--[[
	@module LoadingController
	@description Plays the paper plane loading screen
	(`Libraries/PaperPlaneLoadingScreen`) while
	`ReplicatedFirst/LoadingManager.lua` preloads assets, then tears both
	down. NOT auto-invoked by the Init/Start scan -- boot order across
	`StandaloneControllers/` is undefined (see README.md §9.8) and a loading
	screen needs to run before (or ahead of) everything else. Call
	`LoadingController.RunPreload(...)` explicitly and early -- top of
	`init.client.lua`, or before a zone teleport that needs its own assets
	ready first.

	The screen is plain `Instance`-based, not Fusion (see README.md §6): its
	frames are driven per Heartbeat from baked Blender data.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AnimationIds = require(ReplicatedStorage.Config.AssetIds.AnimationIds)
local AssetManifest = require(ReplicatedFirst.AssetManifest)
local Effects = require(script.Parent.Parent.Effects)
local LoadingManager = require(ReplicatedFirst.LoadingManager)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local PaperPlaneLoadingScreen = require(script.Parent.Parent.Libraries.PaperPlaneLoadingScreen)

local LoadingController = {}

-- Minimum time (s) granted to the Animation preload phase.
local ANIMATION_PHASE_MIN_SECONDS = 15
-- Progress at which the plane leaves its twirl loop for the finale dive, so
-- the dive lands as loading wraps up rather than after it.
local FINALE_AT_RATIO = 0.9
-- Looping high-altitude wind under the whole screen (Assets/sfx/Loading).
local WIND_SOUND = "LoadingWind"
local WIND_FADE_SECONDS = 0.6
-- Screen cue (PaperPlaneLoadingScreen) -> EffectsConfig recipe.
local CUE_RECIPES: { [string]: string } = {
	Swoop = "LoadingSwoop",
	Roll = "LoadingSwoop",
	Turn = "LoadingSwoop",
	Dive = "LoadingDive",
	Through = "LoadingThrough",
}
local log = Logger.new("LoadingController")

local INPUT_SINK_ACTION = "LoadingControllerInputSink"

-- Every input family a player can act with. `UserInputType.Keyboard` (and the
-- gamepad/touch equivalents) bind the whole device, so no per-key list to keep
-- in sync.
local SUNK_INPUTS: { Enum.UserInputType } = {
	Enum.UserInputType.Keyboard,
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.MouseButton3,
	Enum.UserInputType.MouseWheel,
	Enum.UserInputType.Touch,
	Enum.UserInputType.Gamepad1,
}

local function sinkInput(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

--- Preload every asset collected from `CollectAssets` (Studio-parented
--- instances under whitelisted containers) plus `AssetManifest.Entries`
--- (raw ids with no Studio instance), behind the paper plane loading screen.
--- Yields until every phase completes, is cancelled, or times out, and the
--- plane has finished its dive -- or until the player presses Skip, which
--- cancels the remaining preload (assets still stream in on demand) and
--- fades straight to the reveal.
--- @param config LoadingManager.LoadingManagerConfig? -- forwarded to LoadingManager.new
function LoadingController.RunPreload(config: LoadingManager.LoadingManagerConfig?): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = PaperPlaneLoadingScreen.new(playerGui)
	screen:OnCue(function(cue: string)
		local recipe = CUE_RECIPES[cue]
		if recipe then
			Effects.Play(recipe)
		end
	end)

	-- Wind loop: owned here, not a one-shot recipe (fades out under the
	-- whiteout instead of cutting).
	local wind = if Effects.IsSoundEnabled() then Effects.GetSound(WIND_SOUND) else nil
	local windVolume = if wind then wind.Volume else 0
	if wind then
		wind.Volume = windVolume -- restored: the fade below leaves the reusable copy at 0
		wind:Play()
	end

	-- Above every default binding (movement, camera, jump, ProbeController's
	-- launch), which all skip an input that arrives already sunk -- both
	-- ContextAction handlers and UserInputService listeners that honor
	-- `gameProcessed`. Released at the very end, alongside the screen itself.
	ContextActionService:BindActionAtPriority(
		INPUT_SINK_ACTION,
		sinkInput,
		false,
		Enum.ContextActionPriority.High.Value,
		unpack(SUNK_INPUTS)
	)

	local loader = LoadingManager.new(config)
	loader:OnProgress(function(state: LoadingManager.ProgressState)
		screen:SetProgress(state.ratio)
		if state.ratio >= FINALE_AT_RATIO then
			screen:RequestFinale()
		end
	end)

	-- Every registered animation, straight from the AssetIds registry: the
	-- server plays these on characters, so each client must have them loaded
	-- BEFORE the first FlyIdle/WallIdle or the pose pops in late. Read from the
	-- registry (not duplicated into AssetManifest) so a new id is one edit.
	local manifestEntries: { AssetManifest.ManifestEntry } = table.clone(AssetManifest.Entries)
	for _, id in AnimationIds do
		table.insert(manifestEntries, { id = id, category = "Animation" })
	end

	local assets = loader:CollectAssets()
	for _, manifestAsset in loader:CollectManifestAssets(manifestEntries) do
		table.insert(assets, manifestAsset)
	end
	loader:CalculateWeight(assets)

	-- Preload runs on its own thread so Skip can end the wait at once instead
	-- of sitting out the current phase's timeout (up to 15 s for animations).
	local finished = Instance.new("BindableEvent")
	local isFinished = false
	local function finish()
		if not isFinished then
			isFinished = true
			finished:Fire()
		end
	end
	screen:OnSkip(function()
		Effects.Play("UIClick")
		loader:Cancel()
		screen:Skip()
		finish()
	end)

	task.spawn(function()
		for _, phase in loader:CategorizeAssets(assets) do
			if #phase.assets == 0 or loader:IsCancelled() then
				continue
			end

			-- Animations are few but critical (the flight sequence): never given up
			-- on after the short generic ceiling.
			local timeoutSeconds = loader:GetDynamicCeiling(0.05, 3)
			if phase.category == "Animation" then
				timeoutSeconds = math.max(timeoutSeconds, ANIMATION_PHASE_MIN_SECONDS)
			end
			local completed = loader:HandleTimeout(function()
				loader:PreloadBatch(phase.assets, phase.category)
			end, timeoutSeconds)

			if not completed then
				log:Warn(
					"Phase '%s' timed out after %ds, continuing.",
					phase.category,
					timeoutSeconds
				)
			end
		end
		finish()
	end)
	if not isFinished then
		finished.Event:Wait()
	end
	finished:Destroy()

	loader:Cleanup()
	screen:SetProgress(1)
	screen:RequestFinale()
	screen:WaitForWhiteout()
	if wind then
		local fade = TweenService:Create(wind, TweenInfo.new(WIND_FADE_SECONDS), { Volume = 0 })
		fade.Completed:Once(function()
			wind:Stop()
		end)
		fade:Play()
	end
	ContextActionService:UnbindAction(INPUT_SINK_ACTION)
	screen:Reveal()
end

function LoadingController:Init(): ()
	log:Info("Initialized.")
end

function LoadingController:Start(): () end

return LoadingController
