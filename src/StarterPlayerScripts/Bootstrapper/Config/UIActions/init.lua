--!strict
--[[
	@module UIActions (Registry)
	@description Registry of UI action "methods" (data-driven as code).

	Each child ModuleScript exports a UIActionMethod (standalone logic).
	A button tagged "UI_BUTTON_ACTION" with a "Method" = <Name> attribute
	triggers the corresponding method (see UITag/Handlers/Actions).

	Adding an action = dropping a file here. No other step.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Libraries.Logger)

local log = Logger.new("UIActionRegistry")

local Registry = {}

-- Context passed to each method at click time.
export type Context = {
	player: Player,
	button: Instance,
}

-- Contract for a UI action method.
export type UIActionMethod = {
	Name: string,
	Run: (context: Context) -> (),
}

-- Name -> method index, populated at load time.
local methods: { [string]: UIActionMethod } = {}

--- Validates a method definition.
local function isValid(def: any, sourceName: string): boolean
	if type(def) ~= "table" then
		log:Warn("'%s' doesn't export a table -- ignored.", sourceName)
		return false
	end
	if type(def.Name) ~= "string" or def.Name == "" then
		log:Warn("'%s' has no valid Name -- ignored.", sourceName)
		return false
	end
	if type(def.Run) ~= "function" then
		log:Warn("Method '%s' must define Run -- ignored.", def.Name)
		return false
	end
	return true
end

--- Loads every child method. Called once at require time.
local function loadMethods(): ()
	for _, child in ipairs(script:GetChildren()) do
		if not child:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, child)
		if not ok then
			log:Warn("Failed to require method '%s': %s", child.Name, tostring(result))
			continue
		end

		if not isValid(result, child.Name) then
			continue
		end

		local def = result :: UIActionMethod
		if methods[def.Name] then
			log:Warn("Duplicate method '%s' (file '%s') -- keeping the first one.", def.Name, child.Name)
			continue
		end

		methods[def.Name] = def
	end
end

--- Retrieves a method by its Name.
function Registry.Get(name: string): UIActionMethod?
	return methods[name]
end

--- Reports whether a method exists.
function Registry.Has(name: string): boolean
	return methods[name] ~= nil
end

loadMethods()
local count = 0
for _ in pairs(methods) do
	count += 1
end
log:Info("%d UI action method(s) loaded.", count)

return Registry
