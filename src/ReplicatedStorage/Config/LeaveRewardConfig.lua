--!strict
--[[
	@module LeaveRewardConfig
	@description The "don't leave!" reward: shown with the red alarm when the
	player opens the Roblox menu (Panels/LeaveReward), granted by
	LeaveRewardService, once per UTC day. Shared: the server grants it, the
	client shows "+N Length".
]]

return {
	Reward = { Kind = "Length" :: "Length", Amount = 100 },
}
