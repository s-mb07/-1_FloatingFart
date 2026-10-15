--!strict
--[[
	@module Logger
	@description Unified logging system for granular or global debug control.
]]

local Logger = {}
Logger.__index = Logger

-- Global log state (shared through the module)
local activeLogs: {[string]: boolean} = {
	["Global"] = false -- Global debug mode disabled by default
}

--============================================================================--
-- CONFIGURATION
--============================================================================--

--- Enables or disables debug mode for a specific module.
--- @param moduleName string Module name or "Global"
--- @param enabled boolean
function Logger.SetDebugMode(moduleName: string, enabled: boolean): ()
	activeLogs[moduleName] = enabled
	local status = enabled and "ENABLED" or "DISABLED"
	print(string.format("\u{1F527} [LOGGER] Debug mode for '%s' is now %s", moduleName, status))
end

--- Checks whether debug mode is active for a module.
--- @param moduleName string
--- @return boolean
function Logger.IsDebugEnabled(moduleName: string): boolean
	return activeLogs["Global"] == true or activeLogs[moduleName] == true
end

--============================================================================--
-- INSTANTIATION
--============================================================================--

--- Creates a new logger instance for a script.
--- @param moduleName string Name displayed in the logs
--- @return any
function Logger.new(moduleName: string): any
	local self = setmetatable({}, Logger)
	self.moduleName = moduleName
	return self
end

--============================================================================--
-- LOG METHODS
--============================================================================--

--- Standard informational log (always shown).
--- @param message string
function Logger:Info(message: string, ...: any): ()
	print(string.format("[%s] %s", self.moduleName, string.format(message, ...)))
end

--- Warning log (always shown).
--- @param message string
function Logger:Warn(message: string, ...: any): ()
	warn(string.format("[%s][WARN] %s", self.moduleName, string.format(message, ...)))
end

--- Error log (always shown).
--- @param message string
function Logger:Error(message: string, ...: any): ()
	local formatted = string.format("[%s][ERROR] %s", self.moduleName, string.format(message, ...))
	warn(formatted) -- We use warn to avoid stopping the thread while still flagging the error
end

--- Debug log (encapsulated). Gated by configuration.
--- @param message string
function Logger:Debug(message: string, ...: any): ()
	if Logger.IsDebugEnabled(self.moduleName) then
		print(string.format("[DEBUG][%s] %s", self.moduleName, string.format(message, ...)))
	end
end

--- Shorthand function requested by the user (alias of Debug).
function Logger:DebugLog(message: string, ...: any): ()
	self:Debug(message, ...)
end

return Logger
