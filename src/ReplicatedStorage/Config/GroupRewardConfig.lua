--!strict
--[[
	@module GroupRewardConfig
	@description One-time reward for joining the game's Roblox group (the
	"like the game" step can't be verified -- Roblox has no API for it -- so
	only the group membership is checked, server-side, by GroupRewardService).
	Shared: the server grants it, Panels/GroupReward shows the amounts and
	prompts the group join.

	GroupId = 0 until the group exists: the membership check is then skipped
	(like MonetizationConfig.FreeMode), so the reward stays testable.
]]

return {
	GroupId = 704268689,
	Wins = 10,
	Length = 1000,
}
