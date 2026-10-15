--!strict
--[[
	@module TrophyPadService
	@description Walking onto a win pad (TagNames.WinPad) claims its trophies
	(amount per `Stage`, see Config/TrophyPadConfig) and sends the player back
	to the lobby through PlayerTeleportService. A blue x2 pad (attribute
	TagNames.Attr.X2) pays TrophyPadConfig.X2Multiplier times more and needs
	the X2Wins gamepass (AccessGate); stepping on one without it opens the
	X2Wins purchase prompt.
	Claiming ends the run: checkpoint progress and any open
	revive offer are cleared, the next run starts from zero. Trophies pay for
	skins (SkinService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AccessGate = require(script.Parent.Parent.AccessGate)
local CheckpointService = require(script.Parent.CheckpointService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassService = require(script.Parent.GamePassService)
local LifeService = require(script.Parent.LifeService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NotificationService = require(script.Parent.NotificationService)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local PlayerTeleportService = require(script.Parent.PlayerTeleportService)
local RewardGrant = require(script.Parent.Parent.RewardGrant)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TrophyPadConfig = require(ReplicatedStorage.Config.TrophyPadConfig)

local log = Logger.new("TrophyPadService")
local TrophyPadService = {}

--- Stage and x2 flag of a pad, or nil when the Stage attribute is missing
--- or has no `Stages` entry.
local function readPad(pad: Instance): (number?, boolean)
	local stage = pad:GetAttribute(TagNames.Attr.Stage)
	local x2 = pad:GetAttribute(TagNames.Attr.X2) == true
	if type(stage) ~= "number" or not TrophyPadConfig.Stages[stage] then
		return nil, x2
	end
	return stage, x2
end

local function hasAccess(player: Player, x2: boolean): boolean
	return not x2 or AccessGate.Check(player, { GamePass = TrophyPadConfig.X2GamePass })
end

local function onPadEntered(player: Player, pad: BasePart): ()
	local stage, x2 = readPad(pad)
	if not stage then
		log:Warn("Win pad '%s' has no valid Stage attribute.", pad:GetFullName())
		return
	end

	-- x2 pad without the X2Wins pass: offer the pass instead of claiming.
	if not hasAccess(player, x2) then
		GamePassService.Prompt(player, TrophyPadConfig.X2GamePass)
		return
	end

	-- A pad is only claimable once the matching checkpoint has been reached
	-- this run (pad Stage N <-> checkpoint Stage N). Not a violation: just
	-- standing on it early does nothing.
	if CheckpointService.GetStage(player) < stage then
		return
	end

	local lobby = PlayerTeleportService.GetLobbyCFrame()
	if not lobby then
		return
	end
	-- Teleport first: no claim unless the player was actually sent back (the
	-- module waits for traversal control and refuses a dead/absent character).
	if not PlayerTeleportService.TeleportTo(player, lobby, "TrophyClaim") then
		return
	end

	local amount = TrophyPadConfig.Stages[stage].Trophies
		* (if x2 then TrophyPadConfig.X2Multiplier else 1)
	local message = RewardGrant.Grant(player, { Kind = "Trophies", Amount = amount }, "TrophyPad")
	if not message then
		return
	end
	log:Info(
		"%s claimed stage %d %spad (%s).",
		player.Name,
		stage,
		if x2 then "x2 " else "",
		message
	)
	GameEvents.OnTrophyPadClaimed:Fire(player, stage)
	NotificationService.Send(player, message, "Success")

	-- Run over: life reset, back to zero.
	CheckpointService.Reset(player)
	LifeService.ClearOffer(player)
end

--- True when `player` could claim this pad right now (valid Stage, checkpoint
--- reached, X2Wins owned for an x2 pad). Same rule as walking onto it.
function TrophyPadService.CanClaim(player: Player, pad: Instance): boolean
	local stage, x2 = readPad(pad)
	return stage ~= nil and CheckpointService.GetStage(player) >= stage and hasAccess(player, x2)
end

--- Claims `pad` for `player` exactly as if they had walked onto it (used when
--- their probe stopped against it). May yield.
function TrophyPadService.Claim(player: Player, pad: BasePart): ()
	onPadEntered(player, pad)
end

function TrophyPadService:Init(): ()
	log:Info("Initialized.")
end

function TrophyPadService:Start(): ()
	PadTrigger.Bind(TagNames.WinPad, {
		Padding = TrophyPadConfig.Padding,
		OnEnter = onPadEntered,
	})
	log:Info("Started.")
end

return TrophyPadService
