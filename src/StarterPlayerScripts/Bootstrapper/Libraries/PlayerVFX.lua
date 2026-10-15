--!strict
--[[
	@module PlayerVFX
	@description One-shot VFX on the local character. Clones a template
	authored under ReplicatedStorage/Assets/VFX/Player/<Name> (an Attachment
	of disabled ParticleEmitters) into the HumanoidRootPart, emits it, and
	destroys the clone once the last particle is gone.

	Per-emitter attributes (VFX plugin convention):
	  - EmitCount    : burst of N particles via :Emit(N)
	  - EmitDuration : no EmitCount -> enabled for that many seconds
	                   (0 = a single particle)
	  - EmitDelay    : seconds to wait before emitting (optional)

	With `holdSeconds`, every emitter also stays Enabled (at its authored
	Rate) for that long after the burst, so the effect is still running
	once the player closes the UI that triggered it.

	Honors the "Vfx" player setting, like Effects' World channel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(script.Parent.Parent.Effects.Settings)

local PlayerVFX = {}

local CLEANUP_MARGIN = 0.5

--- `holding`: the emitter is held Enabled by `hold`, so only the EmitCount
--- burst fires here (an EmitDuration toggle would switch it off mid-hold).
local function emit(emitter: ParticleEmitter, holding: boolean): number
	local delay = tonumber(emitter:GetAttribute("EmitDelay")) or 0
	local count = tonumber(emitter:GetAttribute("EmitCount"))
	local duration = tonumber(emitter:GetAttribute("EmitDuration")) or 0
	task.delay(delay, function()
		if count then
			emitter:Emit(count)
		elseif holding then
			return
		elseif duration > 0 then
			emitter.Enabled = true
			task.delay(duration, function()
				emitter.Enabled = false
			end)
		else
			emitter:Emit(1)
		end
	end)
	return delay + (if count then 0 else duration) + emitter.Lifetime.Max
end

local function hold(emitter: ParticleEmitter, seconds: number): number
	emitter.Enabled = true
	task.delay(seconds, function()
		emitter.Enabled = false
	end)
	return seconds + emitter.Lifetime.Max
end

--- Emits (per-emitter attributes, see header) every ParticleEmitter under
--- `container` without cloning or destroying anything. Honors the "Vfx" setting.
--- @param container Instance -- an Attachment (or any parent) of ParticleEmitters
function PlayerVFX.Burst(container: Instance): ()
	if not Settings.Get("Vfx") then
		return
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			emit(descendant, false)
		end
	end
end

--- Plays Assets/VFX/Player/<name> on the local character.
--- @param name string -- template name under Assets/VFX/Player
--- @param holdSeconds number? -- keep every emitter enabled this long (default: burst only)
function PlayerVFX.Play(name: string, holdSeconds: number?): ()
	PlayerVFX.PlayOn(Players.LocalPlayer.Character, name, holdSeconds)
end

--- Plays Assets/VFX/Player/<name> on any character (another player's included).
--- @param character Model? -- nil does nothing
--- @param name string -- template name under Assets/VFX/Player
--- @param holdSeconds number? -- keep every emitter enabled this long (default: burst only)
function PlayerVFX.PlayOn(character: Model?, name: string, holdSeconds: number?): ()
	if not Settings.Get("Vfx") then
		return
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local folder = vfx and vfx:FindFirstChild("Player")
	local template = folder and folder:FindFirstChild(name)
	if not template then
		warn("[PlayerVFX] VFX asset not found under Assets/VFX/Player: " .. name)
		return
	end

	local clone = template:Clone()
	clone.Parent = root
	local longest = 0
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			longest = math.max(longest, emit(descendant, holdSeconds ~= nil))
			if holdSeconds then
				longest = math.max(longest, hold(descendant, holdSeconds))
			end
		end
	end
	task.delay(longest + CLEANUP_MARGIN, function()
		clone:Destroy()
	end)
end

return PlayerVFX
