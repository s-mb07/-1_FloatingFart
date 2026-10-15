--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Player data (replaces direct OnClientEvent calls on DataInitialized/DataUpdated)
return {
	Initialized = Signal.new(), -- (data: any)
	Updated     = Signal.new(), -- (patch: any)
}
