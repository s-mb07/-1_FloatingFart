--!strict
--[[
	@module CodeService
	@description Server authority for redeem codes (Config/CodeConfig).

	NetworkEvents "RedeemCode" (RemoteFunction, rate-limited): the client
	sends the raw text it typed and gets back
	{ Success, Error?, Message? } -- Message is the reward text to show on
	success. Each code can be redeemed once per player, recorded in the
	profile's RedeemedCodes through DataService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodeConfig = require(script.Parent.Parent.Config.CodeConfig)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local RewardGrant = require(script.Parent.Parent.RewardGrant)

local log = Logger.new("CodeService")
local CodeService = {}

--- Longest input accepted before even looking it up.
local MAX_CODE_LENGTH = 50

type RedeemResult = { Success: boolean, Error: string?, Message: string? }

--- Redeems `input` for `player`.
--- @param input any -- raw client text, validated here
--- @return RedeemResult -- Error: "InvalidCode" | "AlreadyRedeemed" | "GrantFailed"
function CodeService.Redeem(player: Player, input: any): RedeemResult
	if type(input) ~= "string" or #input > MAX_CODE_LENGTH then
		return { Success = false, Error = "InvalidCode" }
	end
	local code = string.lower((input:gsub("^%s+", ""):gsub("%s+$", "")))
	local def = CodeConfig.Codes[code]
	if not def then
		return { Success = false, Error = "InvalidCode" }
	end
	if DataService:HasRedeemedCode(player, code) then
		return { Success = false, Error = "AlreadyRedeemed" }
	end

	local message = RewardGrant.Grant(player, def.Reward, "Code")
	if not message then
		log:Warn("%s: code '%s' grant failed.", player.Name, code)
		return { Success = false, Error = "GrantFailed" }
	end

	DataService:MarkCodeRedeemed(player, code)
	GameEvents.OnCodeRedeemed:Fire(player, code)
	log:Info("%s redeemed code '%s'.", player.Name, code)
	return { Success = true, Message = message }
end

function CodeService:Init(): ()
	NetworkEvents.OnServerInvoke("RedeemCode", CodeService.Redeem, true)
end

function CodeService:Start(): () end

return CodeService
