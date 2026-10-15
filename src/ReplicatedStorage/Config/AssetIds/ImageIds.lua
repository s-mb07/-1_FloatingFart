--!strict
--[[
	@class ImageIds
	Registry of image asset ids keyed by descriptive name. Empty until images
	are uploaded and their asset ids are added here.
]]

--- Map of image name -> `rbxassetid://` string.
export type ImageIdsType = { [string]: string }

local ImageIds: ImageIdsType = table.freeze({}) :: ImageIdsType

return ImageIds
