--!strict
--[[
	@class MeshIds
	Registry of mesh asset ids keyed by descriptive name. Empty until meshes
	are uploaded and their asset ids are added here.
]]

--- Map of mesh name -> `rbxassetid://` string.
export type MeshIdsType = { [string]: string }

local MeshIds: MeshIdsType = table.freeze({}) :: MeshIdsType

return MeshIds
