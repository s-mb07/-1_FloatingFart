--!strict
--[[
	@module KeybindsConfig
	@description Default UI and client gameplay keys, consumed by
	StandaloneControllers/KeybindsController.lua.

	Lives under StarterPlayerScripts: it's input, no server consumer.
	A key NEVER authorizes an action -- the server re-validates whatever
	remote it triggers (the client can lie about what it pressed).

	Pure data, no callback here: KeybindsController decides what to do with
	each action name (open a panel via Navigation, fire a
	NetworkEvents, ...).
]]

return {
	--- Navigation panels (toggle Push/Pop, see KeybindsController).
	UI = {
		Inventory = Enum.KeyCode.Q,
		Settings = Enum.KeyCode.P,
	},

	--- Generic gameplay actions -- replace with your own.
	Gameplay = {
		PrimaryAction = Enum.KeyCode.E,
	},

	--- Reserved (read directly by InputRouter-style controllers, not by
	--- KeybindsController's generic dispatch).
	Reserved = {
		CloseUI = Enum.KeyCode.Escape,
		ProbeLaunch = Enum.KeyCode.Space, -- ProbeController: no UI button to hang Actions.RegisterKeybindHandler off, read directly
		ProbeLaunchMouse = Enum.UserInputType.MouseButton1, -- same launch/stop action, read directly like ProbeLaunch
	},

	Gamepad = {
		Inventory = Enum.KeyCode.ButtonY,
	},
}
