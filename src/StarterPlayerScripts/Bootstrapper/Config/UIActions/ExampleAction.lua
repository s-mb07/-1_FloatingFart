--!strict
--[[
	@module ExampleAction (UIActionMethod)
	@description Example UI action method: sends ActionRequest to the
	server with the clicked button's name, waits for ActionResult, logs the result.

	Studio-side wiring: "UI_BUTTON_ACTION" tag on the button + attribute
	Method = "Example" (see UIActions/init.lua, UITag/Handlers/Actions.lua).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)

local log = Logger.new("ExampleAction")

type Context = {
	player: Player,
	button: Instance,
}

local ExampleAction = {
	Name = "Example",
}

function ExampleAction.Run(context: Context): ()
	NetworkEvents.FireServer("ActionRequest", { Kind = "Example", Button = context.button.Name })
	log:Info("ActionRequest sent from '%s'.", context.button.Name)
end

return ExampleAction
