--!strict
--[[
	@module Middleware
	Barrel module re-exporting shared network middleware under
	`Libraries/Middleware`. `NetworkEvents.lua` already does per-player,
	per-event rate limiting (`RATE_LIMITS`, `checkRateLimit`) for every
	registered remote -- don't add a second rate-limiting layer here, that's
	the §9.4 DRY violation this kit exists to avoid. This barrel is scoped to
	concerns NetworkEvents doesn't cover, starting with payload validation.

	Usage:
	  local Middleware = require(ReplicatedStorage.Libraries.Middleware)
	  local validated = Middleware.Validation.Create(function(payload) return type(payload) == "table" end)

	  NetworkEvents.OnServerEvent("ActionRequest", function(player, payload)
	      if not validated(player, payload) then return end
	      -- ... handle payload ...
	  end)
]]

local Middleware = {
	Validation = require(script.ValidationMiddleware),
}

return Middleware
