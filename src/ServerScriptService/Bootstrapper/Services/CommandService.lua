--!strict
--[[
	@module CommandService
	@description Admin/dev command registration and execution. Other services
	register a named handler at `Init()` time (`RegisterCommand`); a chat
	hook, a slash-command parser, or an Admin panel UITag action calls
	`Execute` with the invoking player.

	Security: `player`/`name`/`args` may all originate from client input
	(a chat message, a text box). `Execute` re-checks `AdminConfig.Admins`
	itself -- callers must NOT assume the caller is already authorized.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(script.Parent.Parent.Config.AdminConfig)
local Logger = require(ReplicatedStorage.Libraries.Logger)

export type CommandHandler = (player: Player, args: { string }) -> ()

local CommandService = {}
local log = Logger.new("CommandService")

local commandRegistry: { [string]: CommandHandler } = {}

--- Register an admin/dev command handler under a unique name. Call from a
--- service's `Init()`, before `CommandService:Start()` runs.
--- @param name string -- unique command name, case-sensitive
--- @param handler CommandHandler -- (player, args) -> () invoked on execution
function CommandService.RegisterCommand(name: string, handler: CommandHandler): ()
	commandRegistry[name] = handler
end

--- Execute a registered command for a player. Returns false (and does nothing)
--- if the command doesn't exist OR the player isn't in `AdminConfig.Admins`.
--- @param player Player -- the invoking player, treat as untrusted
--- @param name string -- untrusted command name
--- @param args { string } -- untrusted command arguments
--- @return boolean -- true if the command was found, authorized, and executed
function CommandService.Execute(player: Player, name: string, args: { string }): boolean
	if not AdminConfig.Admins[player.UserId] then
		log:Warn("%s attempted command '%s' without admin rights.", player.Name, name)
		return false
	end

	local handler = commandRegistry[name]
	if not handler then
		return false
	end

	log:Info("%s executed command '%s' %s", player.Name, name, table.concat(args, " "))
	handler(player, args)
	return true
end

function CommandService:Init(): () end

function CommandService:Start(): () end

return CommandService
