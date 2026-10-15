--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Results of the generic action system (ActionRequest/ActionResult, see
-- NetworkEvents.lua) -- an example domain, duplicate this file per
-- system (Trade.lua, Combat.lua, ...) instead of piling everything into one.
return {
	Result = Signal.new(), -- (result: any)
}
