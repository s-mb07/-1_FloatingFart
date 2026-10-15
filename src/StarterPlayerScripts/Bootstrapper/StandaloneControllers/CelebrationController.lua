--!strict
--[[
	@module CelebrationController
	@description What the OTHER players see and hear when someone levels up or
	rebirths: the same VFX as on the local HUD, on that player's character, and
	the same sfx in 3D from their HumanoidRootPart. The owner never gets their
	own back (CelebrationService skips them; LevelUpController /
	RebirthHudController already play it for them).
]]

local Players = game:GetService("Players")

local Bootstrapper = script.Parent.Parent
local Effects = require(Bootstrapper.Effects)
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerVFX = require(Bootstrapper.Libraries.PlayerVFX)

local CelebrationController = {}

--- Studs beyond which another player's sfx is silent / their VFX is skipped.
local HEARING_DISTANCE = 120
local VFX_DISTANCE = 300
--- Same hold as the owner's rebirth VFX (RebirthHudController).
local REBIRTH_VFX_SECONDS = 6

local KINDS: { [string]: { Vfx: string, Sound: string, Hold: number? } } = {
	LevelUp = { Vfx = "LevelUpVFX", Sound = "LevelUp" },
	Rebirth = { Vfx = "RebirthVFX", Sound = "Rebirth", Hold = REBIRTH_VFX_SECONDS },
}

local function onCelebration(player: Player, kind: string): ()
	local entry = KINDS[kind]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if player == Players.LocalPlayer or not (entry and root and root:IsA("BasePart")) then
		return
	end
	Effects.PlayAt(entry.Sound, root, HEARING_DISTANCE)
	local camera = workspace.CurrentCamera
	if camera and (root.Position - camera.CFrame.Position).Magnitude <= VFX_DISTANCE then
		PlayerVFX.PlayOn(character, entry.Vfx, entry.Hold)
	end
end

function CelebrationController:Init(): () end

function CelebrationController:Start(): ()
	EventBus.Traversal.Celebration:Connect(onCelebration)
end

return CelebrationController
