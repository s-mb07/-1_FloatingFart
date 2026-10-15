--!strict
--[[
	@class SoundIds
	Registry of sound asset ids keyed by descriptive name. Empty until sounds
	are uploaded and their asset ids are added here.
]]

--- Map of sound name -> `rbxassetid://` string.
export type SoundIdsType = { [string]: string }

local SoundIds: SoundIdsType = table.freeze({}) :: SoundIdsType

return SoundIds
