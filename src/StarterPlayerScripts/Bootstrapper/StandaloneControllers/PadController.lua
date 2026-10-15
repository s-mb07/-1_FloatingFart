--!strict
--[[
	@module PadController
	@description Wires up every world pad "get close = open the panel"
	declared in Config/PadConfig.lua, via the PadTrigger primitive.

	The wiring lives HERE rather than in the panel's Controller, for the
	same reason the HUD button lives in Panels/init.lua: the pad is a
	permanent world Instance, independent of the lifecycle of a
	non-KeepAlive panel that can be destroyed/recreated on every Push.

	Intended side effect: the pad no longer requires the panel to have been
	Prewarm()'d to work -- Push() resolves and Init()s the panel on its own.

	Exit: Pop() ONLY if the relevant panel is still the active one (the
	player may have navigated elsewhere in the meantime) -- same guard as
	each panel's Controller.Close().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventBus = require(script.Parent.Parent.Events.EventBus)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local PadConfig = require(script.Parent.Parent.Config.PadConfig)
local PadTrigger = require(ReplicatedStorage.Libraries.PadTrigger)
local PlayerDataFetcher = require(script.Parent.Parent.Events.PlayerDataFetcher)

-- WaitForChild: this controller is required during the scan of
-- StandaloneControllers/, so BEFORE Panels/ -- nothing guarantees the
-- Navigation/ folder is already replicated at this point.
local NavigationFolder = script.Parent.Parent:WaitForChild("Navigation")
local NavigationController = require(NavigationFolder:WaitForChild("Controller"))

local PadController = {}
local log = Logger.new("PadController")

-- Panels that temporarily refuse auto-close on walking away (e.g. a panel
-- mid-action that must not be interrupted). Closing stays refused as long
-- as the flag is set, and the exit is retried on every tick by
-- PadTrigger -- no permanent disabling of auto-close.
local busyPanels: { [string]: boolean? } = {}

local unbinders: { () -> () } = {}

-- Latest value of each PadConfig `HideWhen` data key (patches only carry
-- the keys that changed, so absent keys keep their last value).
local hideFlags: { [string]: boolean } = {}

local function absorb(data: any): ()
	if type(data) ~= "table" then
		return
	end
	for _, entry in PadConfig.Panels do
		local key = entry.HideWhen
		if key and data[key] ~= nil then
			hideFlags[key] = data[key] == true
		end
	end
end

--- Marks `panelId` as non-closable by walking away as long as `busy` is
--- true. ONLY affects closing by pad: close button, keybind and
--- Navigation remain free to close it.
function PadController.SetPanelBusy(panelId: string, busy: boolean): ()
	busyPanels[panelId] = busy or nil
end

local function bindEntry(entry: PadConfig.PadPanelEntry): ()
	local unbind = PadTrigger.Bind(entry.Tag, {
		Reach = entry.Reach,
		OnEnter = function(): ()
			if NavigationController.GetActivePanelId() == entry.Panel then
				return
			end
			if entry.HideWhen and hideFlags[entry.HideWhen] then
				return
			end
			NavigationController.Push(entry.Panel)
		end,
		OnLeave = function(): boolean
			if NavigationController.GetActivePanelId() ~= entry.Panel then
				return true
			end
			if busyPanels[entry.Panel] then
				return false -- retried on the next tick
			end
			NavigationController.Pop()
			return true
		end,
	})
	table.insert(unbinders, unbind)
end

function PadController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
end

function PadController:Start(): ()
	for _, entry in PadConfig.Panels do
		bindEntry(entry)
	end
	log:Info("Ready (%d panel pad(s) declared).", #PadConfig.Panels)
end

function PadController:Destroy(): ()
	for _, unbind in unbinders do
		unbind()
	end
	table.clear(unbinders)
end

return PadController
