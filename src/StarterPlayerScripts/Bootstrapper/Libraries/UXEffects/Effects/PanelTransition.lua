--!strict
--[[
	@module UXEffects.Effects.PanelTransition
	@description Standard open/close for a UI panel: background blur
	(Backdrop) + zoom (Scale), values read from Config.UIAnimationConfig.

	The SINGLE call site for "blur + zoom like the Inventory" -- avoids
	duplicating Backdrop.track + Scale.popIn/popOut in every UIHandler (Index,
	SpinWheel, TradingWindow, ...) and in UITag/Handlers/Actions.
]]

local Bootstrapper = script.Parent.Parent.Parent.Parent
local UIAnimationConfig = require(Bootstrapper.Config.UIAnimationConfig)

local Backdrop = require(script.Parent.Backdrop)
local Scale = require(script.Parent.Scale)

local PanelTransition = {}

--- Background blur + entrance zoom. `onComplete` called at the end of the zoom.
function PanelTransition.open(target: GuiObject, onComplete: (() -> ())?): ()
	Backdrop.track(target)
	Scale.popIn(target, UIAnimationConfig.PanelOpen :: any, onComplete)
end

--- Background blur (removed once no tracked panel is visible anymore) + exit
--- zoom. `onComplete` called at the end of the zoom (Visible already reset to false).
function PanelTransition.close(target: GuiObject, onComplete: (() -> ())?): ()
	Backdrop.track(target)
	Scale.popOut(target, UIAnimationConfig.PanelClose :: any, onComplete)
end

return PanelTransition
