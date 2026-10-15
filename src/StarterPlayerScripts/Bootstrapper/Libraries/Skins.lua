--!strict
--[[
	@module Skins
	@description Client-side view of the equipped skin. The skin itself (the
	SurfaceAppearance of the Fly model on the character's back) is applied
	by the server (Services/FlyModelService), so all that is left here is
	reading which skin a player has equipped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinConfig = require(ReplicatedStorage.Config.SkinConfig)

local Skins = {}

--- The skin id `player` has equipped (replicated attribute set by
--- SkinService), or the default.
function Skins.GetEquipped(player: Player): string
	local id = player:GetAttribute(SkinConfig.EquippedAttribute)
	return if type(id) == "string" and SkinConfig.Skins[id] then id else SkinConfig.Default
end

return Skins
