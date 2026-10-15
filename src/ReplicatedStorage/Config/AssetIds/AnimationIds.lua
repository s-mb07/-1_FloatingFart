--!strict
--[[
	@class AnimationIds
	Registry of animation asset ids keyed by descriptive name.
]]

--- Map of animation name -> `rbxassetid://` string.
export type AnimationIdsType = { [string]: string }

local AnimationIds: AnimationIdsType = table.freeze({
	-- Flight sequence (Traversal/CharacterAnimations), authored on the
	-- AnimationFly rig: Start plays once while the character is locked and
	-- lifted (PRE_LAUNCH), Idle loops during the flight (ACTIVE), End plays
	-- once when it stops (ENDING).
	FlyStart = "rbxassetid://92348732424989",
	FlyIdle = "rbxassetid://93118801283161",
	FlyEnd = "rbxassetid://85638100852916",
	-- Played on the character while it is suspended against a vertical face
	-- (WALL_LOCKED).
	WallIdle = "rbxassetid://102989054700567",
	-- Native Roblox default R15 run animation, looped while on a treadmill.
	TreadmillRun = "rbxassetid://507767714",
}) :: AnimationIdsType

return AnimationIds
