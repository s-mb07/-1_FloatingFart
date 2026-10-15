--!strict
--!derogation: pcall each pcall isolates one tagged-instance handler/updateHandler call so one bad handler can't break tag dispatch for every other instance (see README.md §9.3)
--[[
	@module UITag
	@version 1.0.0
	@description UI framework driven by tags (CollectionService) and signals.

	Centralizes effect handling, actions, and data synchronization simply by
	adding tags to UI elements.

	Features:
	  - RegisterHandler / UnregisterHandler: lifecycle management for tagged instances
	  - RegisterUpdateHandler: syncing data to the UI
	  - Automatic connection tracking with cleanup on destruction
	  - Listening for attribute changes (RegisterAttributeHandler)
	  - Update / UpdateBatch: data updates
	  - GetTagged / Has: query utilities
	  - Destroy: full framework cleanup
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Libraries.Signal)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local log = Logger.new("UITag")

local UITag = {}

--============================================================================--
-- TYPES
--============================================================================--

type Handler = (Instance) -> (() -> ())?
type UpdateHandler = (Instance, any) -> ()
type AttributeHandler = (Instance, string, any) -> ()
type CleanupFn = () -> ()

--============================================================================--
-- STATE
--============================================================================--

local handlers: {[string]: Handler} = {}
local updateHandlers: {[string]: UpdateHandler} = {}
local attributeHandlers: {[string]: AttributeHandler} = {}
local registeredTags: {[string]: boolean} = {}

-- Connections owned by the framework itself (GetInstanceAddedSignal, etc.)
local frameworkConnections: {RBXScriptConnection} = {}

-- Connections and cleanups tracked per instance  {[Instance] = {RBXScriptConnection | CleanupFn}}
local instanceConnections: {[Instance]: {any}} = {}

-- Last values sent via Update (to give new elements their initial value)
local lastValues: {[string]: any} = {}

-- Guard against double init / use after destroy
local initialized = false
local destroyed = false

-- Global signal for updates (key, value)
UITag.OnUpdate = Signal.new()

--============================================================================--
-- PRIVATE : INSTANCE TRACKING
--============================================================================--

--- Registers a connection or cleanup function for an instance.
local function trackConnection(instance: Instance, conn: any)
	if not instanceConnections[instance] then
		instanceConnections[instance] = {}
	end
	table.insert(instanceConnections[instance], conn)
end

--- Cleans up every connection/resource attached to an instance.
local function cleanupInstance(instance: Instance)
	local conns = instanceConnections[instance]
	if not conns then return end

	for _, item in ipairs(conns) do
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif type(item) == "function" then
			local ok, err = pcall(item)
			if not ok then
				log:Warn("Cleanup error for %s: %s", instance.Name, tostring(err))
			end
		end
	end

	instanceConnections[instance] = nil
end

--- Runs a handler under protection and tracks any cleanup it returns.
local function safeRunHandler(tagName: string, handler: Handler, instance: Instance)
	local ok, result = pcall(handler, instance)
	if not ok then
		log:Warn("Handler error for tag '%s' on %s: %s", tagName, instance:GetFullName(), tostring(result))
		return
	end

	-- If the handler returns a cleanup function, track it
	if type(result) == "function" then
		trackConnection(instance, result)
	end
end

--============================================================================--
-- PRIVATE : TAG LIFECYCLE
--============================================================================--

--- Sets up full tracking for a tag (instance additions + removals).
local function setupTagLifecycle(tagName: string, handler: Handler)
	-- Handles an instance being added (existing or future)
	local function onInstanceAdded(instance: Instance)
		-- Destroying connection for auto-cleanup
		local destroyConn = instance.Destroying:Connect(function()
			cleanupInstance(instance)
		end)
		trackConnection(instance, destroyConn)

		-- Runs the handler
		task.spawn(safeRunHandler, tagName, handler, instance)

		-- If an UpdateHandler exists and we have a last value, apply it
		local updateHandler = updateHandlers[tagName]
		local lastValue = lastValues[tagName]
		if lastValue ~= nil then
			if updateHandler then
				task.spawn(function()
					local ok, err: any = pcall(updateHandler, instance, lastValue)
					if not ok then
						log:Warn("UpdateHandler error for '%s' on %s: %s", tagName, instance:GetFullName(), tostring(err))
					end
				end)
			else
				-- Default behavior
				applyDefaultUpdate(instance, lastValue)
			end
		end
	end

	-- Handles a tag being removed (not destruction, just the tag being removed)
	local function onInstanceRemoved(instance: Instance)
		cleanupInstance(instance)
	end

	-- Connects existing instances
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		task.spawn(onInstanceAdded, instance)
	end

	-- Connects future instances
	local addedConn = CollectionService:GetInstanceAddedSignal(tagName):Connect(onInstanceAdded)
	table.insert(frameworkConnections, addedConn)

	local removedConn = CollectionService:GetInstanceRemovedSignal(tagName):Connect(onInstanceRemoved)
	table.insert(frameworkConnections, removedConn)
end

--============================================================================--
-- PRIVATE : DEFAULT UPDATE BEHAVIOR
--============================================================================--

--- Applies the default update behavior based on the instance's type.
function applyDefaultUpdate(instance: Instance, value: any)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		(instance :: any).Text = tostring(value)
	end
end

--============================================================================--
-- PUBLIC API : HANDLERS
--============================================================================--

--- Registers an initialization handler for a tag.
--- The handler can return a cleanup function that will be called when the
--- instance is destroyed or the tag is removed.
function UITag.RegisterHandler(tagName: string, handler: Handler)
	if destroyed then
		log:Warn("Cannot register handler, UITag is destroyed")
		return
	end

	if handlers[tagName] then
		log:Warn("Handler already registered for tag '%s', replacing", tagName)
	end

	handlers[tagName] = handler
	registeredTags[tagName] = true

	setupTagLifecycle(tagName, handler)
end

--- Removes a handler and cleans up every instance associated with it.
function UITag.UnregisterHandler(tagName: string)
	if not handlers[tagName] then
		log:Warn("No handler registered for tag '%s'", tagName)
		return
	end

	-- Cleans up every instance currently tagged
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		cleanupInstance(instance)
	end

	handlers[tagName] = nil
	registeredTags[tagName] = nil
end

--- Registers an update handler for a tag.
function UITag.RegisterUpdateHandler(tagName: string, handler: UpdateHandler)
	if destroyed then return end
	updateHandlers[tagName] = handler
end

--- Registers a handler that reacts to attribute changes on a tag's instances.
--- The callback receives (instance, attributeName, newValue).
function UITag.RegisterAttributeHandler(tagName: string, attributeName: string, handler: AttributeHandler)
	if destroyed then return end

	local key = tagName .. "::" .. attributeName
	attributeHandlers[key] = handler

	-- Connects existing instances
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		local conn = instance:GetAttributeChangedSignal(attributeName):Connect(function()
			local newValue = instance:GetAttribute(attributeName)
			local ok, err: any = pcall(handler, instance, attributeName, newValue)
			if not ok then
				log:Warn("AttributeHandler error for '%s.%s': %s", tagName, attributeName, tostring(err))
			end
		end)
		trackConnection(instance, conn)
	end

	-- Future instances will be connected through the existing lifecycle if setupTagLifecycle is extended
	-- For now, connect via GetInstanceAddedSignal
	local addedConn = CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
		local conn = instance:GetAttributeChangedSignal(attributeName):Connect(function()
			local newValue = instance:GetAttribute(attributeName)
			local ok, err: any = pcall(handler, instance, attributeName, newValue)
			if not ok then
				log:Warn("AttributeHandler error for '%s.%s': %s", tagName, attributeName, tostring(err))
			end
		end)
		trackConnection(instance, conn)
	end)
	table.insert(frameworkConnections, addedConn)
end

--============================================================================--
-- PUBLIC API : DATA SYNC
--============================================================================--

--- Updates every instance holding a given tag with a new value.
function UITag.Update(tagName: string, value: any)
	if destroyed then return end

	local handler = updateHandlers[tagName]

	-- Stores the last value for new instances
	lastValues[tagName] = value

	-- Fires the signal for external listeners
	UITag.OnUpdate:Fire(tagName, value)

	-- Updates each tagged instance
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		if handler then
			local ok, err: any = pcall(handler, instance, value)
			if not ok then
				log:Warn("UpdateHandler error for '%s' on %s: %s", tagName, instance:GetFullName(), tostring(err))
			end
		else
			applyDefaultUpdate(instance, value)
		end
	end
end

--- Updates several tags in a single operation.
function UITag.UpdateBatch(data: {[string]: any})
	for tagName, value in pairs(data) do
		UITag.Update(tagName, value)
	end
end

--============================================================================--
-- PUBLIC API : QUERY
--============================================================================--

--- Returns every instance holding a given tag.
function UITag.GetTagged(tagName: string): {Instance}
	return CollectionService:GetTagged(tagName)
end

--- Checks whether an instance holds a given tag.
function UITag.Has(instance: Instance, tagName: string): boolean
	return CollectionService:HasTag(instance, tagName)
end

--- Returns the last value sent for a tag via Update.
function UITag.GetLastValue(tagName: string): any?
	return lastValues[tagName]
end

--- Returns the list of every registered tag.
function UITag.GetRegisteredTags(): {string}
	local tags = {}
	for tag in pairs(registeredTags) do
		table.insert(tags, tag)
	end
	return tags
end

--============================================================================--
-- INITIALIZATION & LIFECYCLE
--============================================================================--

function UITag.Init()
	if initialized then
		log:Warn("UITag already initialized, ignoring duplicate Init()")
		return
	end
	if destroyed then
		log:Warn("Cannot initialize, UITag was destroyed")
		return
	end

	initialized = true
	log:Info("UITag framework v1.0.0 initialized.")
end

--- Fully cleans up the framework: disconnects everything, clears caches.
function UITag.Destroy()
	if destroyed then return end
	destroyed = true

	-- Cleans up every instance connection
	for instance in pairs(instanceConnections) do
		cleanupInstance(instance)
	end

	-- Disconnects the framework's own connections
	for _, conn in ipairs(frameworkConnections) do
		conn:Disconnect()
	end
	table.clear(frameworkConnections)

	-- Clears all state
	table.clear(handlers)
	table.clear(updateHandlers)
	table.clear(attributeHandlers)
	table.clear(registeredTags)
	table.clear(lastValues)

	UITag.OnUpdate:Destroy()

	log:Info("UITag framework destroyed.")
end

return UITag
