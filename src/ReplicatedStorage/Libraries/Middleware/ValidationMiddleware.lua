--!strict
--[[
	@class ValidationMiddleware
	Composable network middleware for generic payload validation. Wraps a
	typed validator function so a remote handler can plug per-endpoint
	payload-shape checks into the same middleware pipeline as
	`RateLimitMiddleware`, instead of hand-rolling `type(payload) == ...`
	checks inline at every call site.
]]

local ValidationMiddleware = {}

export type Validator<T> = (payload: T) -> boolean

export type ValidationMiddlewareFn<T> = (player: Player, payload: T) -> boolean

--- Create a middleware function that validates `payload` with `validator`, ignoring the
--- calling player. Returns false if the payload fails validation.
--- @param validator Validator<T> -- function that returns true when `payload` is well-formed
--- @return ValidationMiddlewareFn<T>
function ValidationMiddleware.Create<T>(validator: Validator<T>): ValidationMiddlewareFn<T>
	return function(_player: Player, payload: T): boolean
		return validator(payload)
	end
end

return ValidationMiddleware
