--!strict
--[[
	@module Effects.Channels.World
	@description Effects' world VFX channel (particles at a 3D position).
	Clones a template already authored under ReplicatedStorage/Assets/VFX/<Effect>
	at the given position, and cleans it up after `Lifetime` seconds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local EffectsConfig = require(script.Parent.Parent.Parent.Config.EffectsConfig)
local Settings = require(script.Parent.Parent.Settings)

local World = {}

local DEFAULT_LIFETIME = 3

function World.Play(spec: EffectsConfig.WorldSpec, context: any): ()
	if not Settings.Get("Vfx") then return end
	if not context.Position then return end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assets and assets:FindFirstChild("VFX")
	local template = vfxFolder and vfxFolder:FindFirstChild(spec.Effect)
	if not template then
		warn("[Effects] VFX asset not found under Assets/VFX: " .. spec.Effect)
		return
	end

	local clone = template:Clone()
	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(context.Position))
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(context.Position)
	end
	clone.Parent = Workspace

	Debris:AddItem(clone, spec.Lifetime or DEFAULT_LIFETIME)
end

return World
