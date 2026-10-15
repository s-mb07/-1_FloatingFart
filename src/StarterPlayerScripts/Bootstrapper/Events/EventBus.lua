--!strict
--[[
	@module EventBus
	@description Client-side inter-controller event bus.

	Client-side mirror of GameEvents.lua (server). Lets controllers
	communicate without require()-ing each other directly, and fully
	isolates the network layer inside NetworkBridgeController.

	Convention:
	  - Events are fired by NetworkBridgeController (coming from the network)
	    OR directly by a Controller for a 100% local action (no server
	    round-trip needed).

	One file per domain under Events/ (see the `Events` folder) rather than
	a single big table, so adding a new system doesn't require touching a
	file already loaded with every other domain.
]]

return {
	Data = require(script.Parent.Events.Data),
	Action = require(script.Parent.Events.Action),
	Settings = require(script.Parent.Events.Settings),
	Notification = require(script.Parent.Events.Notification),
	Gameplay = require(script.Parent.Events.Gameplay),
	Traversal = require(script.Parent.Events.Traversal),
	Purchase = require(script.Parent.Events.Purchase),
	Navigation = require(script.Parent.Events.Navigation),
}
