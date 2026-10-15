--!strict
--[[
	@module UITag.StandardHandlers
	@version 2.0.0
	@description Aggregator that registers all built-in UITag handlers.

	The handlers are split into four sub-modules under `Handlers/`:
	  - Effects   : continuous / static UI effects (Axis 1)
	  - Actions   : one-shot click-triggered actions (Axis 2)
	  - Reactive  : reactive effects that observe UIData_* changes (Axis 3)
	  - Presets   : compound tags that apply multiple effect tags at once

	Registration order matters: presets run last so the component tags they
	reference are already bound when AddTag fires.

	Shared string-union types live in `Handlers/Types` and are re-exported here
	for external consumers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local log    = Logger.new("UITag/Standard")

local Effects  = require(script.Parent.Handlers.Effects)
local Actions  = require(script.Parent.Handlers.Actions)
local Reactive = require(script.Parent.Handlers.Reactive)
local Presets  = require(script.Parent.Handlers.Presets)
local Types    = require(script.Parent.Handlers.Types)

local StandardHandlers = {}

--============================================================================--
-- RE-EXPORTED TYPES
--============================================================================--

export type SlideDirection = Types.SlideDirection
export type EntranceMode   = Types.EntranceMode
export type HowToOpen      = Types.HowToOpen
export type HowToClose     = Types.HowToClose
export type BurstStyle     = Types.BurstStyle
export type ConfettiStyle  = Types.ConfettiStyle
export type ShakeStyle     = Types.ShakeStyle
export type ToastType      = Types.ToastType
export type CounterMode    = Types.CounterMode
export type GlowPreset     = Types.GlowPreset
export type SyncPayload    = Types.SyncPayload

--============================================================================--
-- PUBLIC API
--============================================================================--

function StandardHandlers.Register(UITag: any)
	log:Info("Registering standard handlers...")
	Effects.Register(UITag)
	Actions.Register(UITag)
	Reactive.Register(UITag)
	Presets.Register(UITag)
	log:Info("All standard handlers registered.")
end

--- Expose Reactive.InstallFormatter so callers can register per-key
--- number formatters dynamically (e.g. one per currency discovered from
--- the server payload) without mutating this module.
function StandardHandlers.InstallDataFormatter(UITag: any, tagName: string)
	Reactive.InstallFormatter(UITag, tagName)
end

--- Canonical tag-name tables exposed for consumers that want to avoid string
--- literals. Example: `StandardHandlers.Tags.Effect.GLOW_RARITY`.
StandardHandlers.Tags = {
	Effect   = Effects.TAGS,
	Action   = Actions.TAGS,
	Reactive = Reactive.TAGS,
	Preset   = Presets.TAGS,
}

return StandardHandlers
