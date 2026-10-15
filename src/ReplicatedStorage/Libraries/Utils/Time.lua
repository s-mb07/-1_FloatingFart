--!strict
--[[
	@class Time
	Generic, pure helpers for formatting durations. No game-specific logic.
]]

local Time = {}

--- Format a duration in seconds as `M:SS` (or `H:MM:SS` when it spans an hour or more).
--- @param totalSeconds number -- duration in seconds, negative values are treated as 0
--- @return string
function Time.FormatSeconds(totalSeconds: number): string
	local seconds = math.max(0, math.floor(totalSeconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, remainingSeconds)
	end
	return string.format("%d:%02d", minutes, remainingSeconds)
end

return Time
