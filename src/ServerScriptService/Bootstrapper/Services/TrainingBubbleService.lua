--!strict
--[[
	@module TrainingBubbleService
	@description Boost bubbles while training on a fan. While a training
	session runs (player attribute TreadmillConfig.TrainingAttribute = fan Id,
	set by TreadmillService), one bubble appears every
	TreadmillConfig.BubbleInterval seconds and lives BubbleLifetime seconds
	(the client fades it out meanwhile), in the next of the BubbleSlots slots.
	Each bubble carries a random multiplier (BubbleMin..the fan's BubbleMax by
	BubbleStep); popping it (NetworkEvents "PopTrainingBubble", slot) grants
	one fan XP grant (XP/s x the fan's LengthMultiplier) x that multiplier on
	the spot, on top of TreadmillService's regular grants. Leaving the fan
	resets everything.

	Bubbles ride on player attributes (BubbleAttribute .. slot =
	"<serial>:<multiplier>"): the client (TrainingBubbleController) only
	displays them and asks to pop one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local TraversalProgressionService = require(script.Parent.TraversalProgressionService)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)

local log = Logger.new("TrainingBubbleService")
local TrainingBubbleService = {}

local rng = Random.new()
-- One token per training session: a new session swaps it, so a timer from
-- a previous session can never spawn a bubble.
local sessions: { [Player]: {} } = {}
-- The fan each training player is on (pops grant its XP).
local fans: { [Player]: TreadmillConfig.TreadmillDef } = {}
-- Makes every bubble's attribute value unique (see TreadmillConfig.BubbleAttribute).
local serial = 0

local function slotAttribute(slot: number): string
	return TreadmillConfig.BubbleAttribute .. slot
end

local function clearSlots(player: Player): ()
	for slot = 1, TreadmillConfig.BubbleSlots do
		player:SetAttribute(slotAttribute(slot), nil)
	end
end

--- Random multiplier BubbleMin..`max`, on the BubbleStep grid.
local function randomMultiplier(max: number): number
	local steps = math.round((max - TreadmillConfig.BubbleMin) / TreadmillConfig.BubbleStep)
	return math.round(
		(TreadmillConfig.BubbleMin + rng:NextInteger(0, steps) * TreadmillConfig.BubbleStep) * 10
	) / 10
end

--- Spawns one bubble every BubbleInterval while `token`'s session runs, each
--- removed after BubbleLifetime unless popped (or replaced) before.
local function runSession(player: Player, token: {}, max: number): ()
	local slot = 0
	while true do
		task.wait(TreadmillConfig.BubbleInterval)
		if sessions[player] ~= token or not player.Parent then
			return
		end
		slot = slot % TreadmillConfig.BubbleSlots + 1
		serial += 1
		local attribute = slotAttribute(slot)
		local value = ("%d:%s"):format(serial, tostring(randomMultiplier(max)))
		player:SetAttribute(attribute, value)
		task.delay(TreadmillConfig.BubbleLifetime, function()
			if player:GetAttribute(attribute) == value then
				player:SetAttribute(attribute, nil)
			end
		end)
	end
end

local function onTrainingChanged(player: Player): ()
	-- Any change (start, end, other fan) starts over.
	clearSlots(player)
	fans[player] = nil
	local id = player:GetAttribute(TreadmillConfig.TrainingAttribute)
	local def = if type(id) == "string" then TreadmillConfig.Treadmills[id] else nil
	if not def then
		sessions[player] = nil
		return
	end
	local token = {}
	sessions[player] = token
	fans[player] = def
	task.spawn(runSession, player, token, math.min(def.BubbleMax, TreadmillConfig.BubbleMax))
end

local function onPop(player: Player, slot: any): ()
	local fan = fans[player]
	if not (fan and type(slot) == "number" and slot == slot // 1) then
		return
	end
	local value = player:GetAttribute(slotAttribute(slot))
	local multiplier = if type(value) == "string" then tonumber(value:match(":(.+)$")) else nil
	if not multiplier then
		return -- no bubble in that slot: a stale or spoofed click
	end
	player:SetAttribute(slotAttribute(slot), nil)
	local amount = TraversalProgressionService.GetXPPerSecond(player)
		* fan.LengthMultiplier
		* multiplier
	TraversalProgressionService.AddXP(player, amount, "Bubble")
end

function TrainingBubbleService:Init(): ()
	GameEvents.OnPlayerRegistered:Connect(function(player: Player)
		player:GetAttributeChangedSignal(TreadmillConfig.TrainingAttribute):Connect(function()
			onTrainingChanged(player)
		end)
	end)
	GameEvents.OnPlayerUnregistered:Connect(function(player: Player)
		sessions[player] = nil
		fans[player] = nil
	end)
	NetworkEvents.OnServerEvent("PopTrainingBubble", onPop)
	log:Info("Initialized.")
end

function TrainingBubbleService:Start(): () end

return TrainingBubbleService
