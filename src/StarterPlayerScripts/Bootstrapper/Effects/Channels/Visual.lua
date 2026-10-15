--!strict
--[[
	@module Effects.Channels.Visual
	@description Effects' visual channel: a list of UXEffects effects addressed by name.

	Variants of the same effect share their signature, with one exception:
	Burst's screen-space shortcuts (gold, rainbow) take a Vector2, whereas
	a recipe only knows a world position or a UI target. Burst therefore has
	its own branch; everything else goes through ARG_KIND.
]]

local EffectsConfig = require(script.Parent.Parent.Parent.Config.EffectsConfig)
local UXEffects = require(script.Parent.Parent.Parent.Libraries.UXEffects)
local Settings = require(script.Parent.Parent.Settings)

local Visual = {}

--- Argument shape expected by each effect's variants.
local ARG_KIND: {[string]: string} = {
	Confetti = "none",
	Toast    = "text",
	Glow     = "target",
	Shake    = "target",
	Pulse    = "target",
	Scale    = "target",
	Ripple   = "target",
	Burst    = "burst",
}

--- Variant used when the recipe doesn't specify one.
local DEFAULT_VARIANT: {[string]: string} = {
	Confetti = "play",
	Toast    = "info",
	Glow     = "apply",
	Shake    = "play",
	Pulse    = "play",
	Scale    = "popIn",
	Ripple   = "playAt",
}

local function playBurst(module: any, context: any): ()
	if context.Position then
		module.playFromWorld(context.Position)
	elseif context.Target then
		module.playAt(context.Target)
	end
end

local function invoke(step: EffectsConfig.VisualStep, context: any): ()
	local module = (UXEffects :: any)[step.Effect]
	if not module then
		warn("[Effects] Unknown effect: " .. step.Effect)
		return
	end

	local kind = ARG_KIND[step.Effect]
	if not kind then
		warn("[Effects] Effect not routable from a recipe: " .. step.Effect)
		return
	end

	if kind == "burst" then
		playBurst(module, context)
		return
	end

	local variantName = step.Variant or DEFAULT_VARIANT[step.Effect]
	local variant = module[variantName]
	if not variant then
		warn("[Effects] Unknown variant: " .. step.Effect .. "." .. tostring(variantName))
		return
	end

	if kind == "none" then
		variant()
	elseif kind == "text" then
		if context.Text then
			variant(context.Text)
		end
	elseif kind == "target" then
		if context.Target then
			variant(context.Target)
		end
	end
end

function Visual.Play(steps: {EffectsConfig.VisualStep}, context: any): ()
	if not Settings.Get("Vfx") then return end

	for _, step in steps do
		if step.Delay and step.Delay > 0 then
			task.delay(step.Delay, invoke, step, context)
		else
			invoke(step, context)
		end
	end
end

return Visual
