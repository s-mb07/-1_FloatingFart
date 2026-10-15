--!strict
--[[
	@module InactivityConfig
	@description Anti-kick tuning. Roblox kicks a client idle ~20min (Players.Idled,
	not configurable), so InactivityService teleports the player to another server
	of the same place BEFORE that, which resets the engine idle timer.

	Keep IdleTimeout < 20min and PingThrottle << IdleTimeout. The server-side
	rate limit (NetworkEvents.RATE_LIMITS "PlayerActivityPing") must stay
	below PingThrottle.
]]

return table.freeze({
	IdleTimeout = 15 * 60, -- server: seconds without a ping before the teleport
	PingThrottle = 60, -- client: min seconds between two activity pings
})
