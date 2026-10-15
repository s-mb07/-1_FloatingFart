--!strict
--[[
	@module RebirthHudController
	@description Drives the rebirth counter in MainHUD/LeftHUD/RebirthCounter
	(the Frame): `Amount` (+ its `TextStroke` overlay) mirrors `Traversal.Rebirths`
	from the server data snapshot (DataInitialized, then every DataUpdated).
	Same pattern as WinsHudController.

	Named "RebirthCounter", not "Rebirth": LeftHUD/Rebirth is the open-panel
	TextButton, and a shared name made every path lookup land on this Frame.

	A rise in the count (rebirth button or SkipRebirth product) plays
	Assets/VFX/Player/RebirthVFX on the character, held REBIRTH_VFX_SECONDS so
	it is still running once the player closes the Rebirth panel; the first
	value received at load does not.

	MainHUD has ResetOnSpawn = false, so the UI is resolved once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)
local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local PlayerVFX = require(Bootstrapper.Libraries.PlayerVFX)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)

--- How long the rebirth VFX keeps emitting: long enough to close RebirthUI
--- and still see it.
local REBIRTH_VFX_SECONDS = 6

local RebirthHudController = {}

local rebirths: number? = nil
local amountLabels: { TextLabel } = {}

local function render(): ()
	if rebirths == nil then
		return
	end
	local text = NumberUtil.FormatCompact(rebirths)
	for _, label in amountLabels do
		label.Text = text
	end
end

local function absorb(data: any): ()
	local value = data and data.Traversal and data.Traversal.Rebirths
	if type(value) == "number" then
		if rebirths and value > rebirths then
			PlayerVFX.Play("RebirthVFX", REBIRTH_VFX_SECONDS)
		end
		rebirths = value
		render()
	end
end

function RebirthHudController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
end

function RebirthHudController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- SafeUIResolver, not a bare WaitForChild chain: MainHUD only lands after
	-- the loading screen, which tripped WaitForChild's "infinite yield" warning.
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/LeftHUD/RebirthCounter/Amount", function(label: Instance)
		local amount = label :: TextLabel
		amountLabels = { amount }
		local stroke = amount:FindFirstChild("TextStroke")
		if stroke and stroke:IsA("TextLabel") then
			table.insert(amountLabels, stroke)
		end
		render()
	end)
end

return RebirthHudController
