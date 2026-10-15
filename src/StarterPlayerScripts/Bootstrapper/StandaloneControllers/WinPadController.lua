--!strict
--[[
	@module WinPadController
	@description Writes each win pad's "+N Wins" label (Studio-authored
	`GUI/WinAmount` under the pad Part) from TrophyPadConfig: the stage's
	trophies, x X2Multiplier on a blue x2 pad. Display only -- the payout
	itself is TrophyPadService's, from the same config, so the label can
	never disagree with what the pad gives.

	The Studio texts are kept in sync too (edit-time view); with streaming, a
	label that arrives after its pad is written as soon as it lands.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstanceUtil = require(ReplicatedStorage.Libraries.Utils.Instance)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)
local TrophyPadConfig = require(ReplicatedStorage.Config.TrophyPadConfig)

local WinPadController = {}

local LABEL_NAME = "WinAmount"

local function label(pad: Instance): ()
	local stage = pad:GetAttribute(TagNames.Attr.Stage)
	local entry = if type(stage) == "number" then TrophyPadConfig.Stages[stage] else nil
	if not entry then
		return
	end
	local text = pad:FindFirstChild(LABEL_NAME, true)
	if not text then
		-- Streaming: the GUI may land after the pad itself
		InstanceUtil.OnDescendantNamed(pad, LABEL_NAME, function()
			label(pad)
		end)
		return
	end
	if not text:IsA("TextLabel") then
		return
	end
	local x2 = pad:GetAttribute(TagNames.Attr.X2) == true
	local amount = entry.Trophies * (if x2 then TrophyPadConfig.X2Multiplier else 1)
	text.Text = ("+%s %s"):format(
		NumberUtil.FormatCompact(amount),
		if amount == 1 then "Win" else "Wins"
	)
end

function WinPadController:Init(): () end

function WinPadController:Start(): ()
	for _, pad in CollectionService:GetTagged(TagNames.WinPad) do
		label(pad)
	end
	-- Pads streamed in later
	CollectionService:GetInstanceAddedSignal(TagNames.WinPad):Connect(label)
end

return WinPadController
