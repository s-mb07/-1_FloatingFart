--!strict
--[[
	@module UXEffects
	@description Advanced UX effects library for Roblox.

	This library provides a collection of optimized visual effects
	for creating engaging and satisfying user interfaces.

	@usage
	```lua
	local UXEffects = require(Bootstrapper.Libraries.UXEffects)

	-- Fly-to-UI effect
	UXEffects.FlyToUI.playFromCenter(targetUI, {
		iconId = "rbxassetid://123456",
		count = 5,
	})

	-- Particle burst
	UXEffects.Burst.gold(position)

	-- Toast notification
	UXEffects.Toast.success("Harvest successful!")

	-- Confetti
	UXEffects.Confetti.rainbow()
	```

	@features
	- FlyToUI: Icons flying toward a UI element
	- Burst: 2D particle explosion
	- Shake: Screen/element tremble
	- Pulse: Element pulsation
	- Counter: Animated floating counter
	- Confetti: Confetti rain
	- Glow: Dynamic glow
	- Ripple: Click wave effect
	- Toast: Stackable notifications
	- Scale: Pop-in/out animations

	@performance
	All effects use object pooling to avoid
	frequent allocations and GC latency spikes.
]]

local UXEffects = {}

--============================================================================--
-- CORE MODULES
--============================================================================--

--- Strict types for all effects.
UXEffects.Types = require(script.Types)

--- Object pooling system.
UXEffects.Pool = require(script.Core.Pool)

--- Unified animation engine.
UXEffects.Animator = require(script.Core.Animator)

--============================================================================--
-- EFFECTS
--============================================================================--

--- Icons flying toward a UI element.
--- @see FlyToUI.play
--- @see FlyToUI.playFromWorld
--- @see FlyToUI.playFromCenter
UXEffects.FlyToUI = require(script.Effects.FlyToUI)

--- 2D particle explosion.
--- @see Burst.play
--- @see Burst.gold
--- @see Burst.rainbow
UXEffects.Burst = require(script.Effects.Burst)

--- Screen/element tremble.
--- @see Shake.play
--- @see Shake.error
--- @see Shake.impact
UXEffects.Shake = require(script.Effects.Shake)

--- UI element pulsation.
--- @see Pulse.play
--- @see Pulse.playLoop
--- @see Pulse.stop
UXEffects.Pulse = require(script.Effects.Pulse)

--- Animated floating counter.
--- @see Counter.play
--- @see Counter.gain
--- @see Counter.loss
UXEffects.Counter = require(script.Effects.Counter)

--- Confetti rain.
--- @see Confetti.play
--- @see Confetti.gold
--- @see Confetti.rainbow
UXEffects.Confetti = require(script.Effects.Confetti)

--- Dynamic glow on elements.
--- @see Glow.apply
--- @see Glow.remove
--- @see Glow.gold
UXEffects.Glow = require(script.Effects.Glow)

--- Click wave effect.
--- @see Ripple.play
--- @see Ripple.attachToButton
UXEffects.Ripple = require(script.Effects.Ripple)

--- Toast notifications.
--- @see Toast.show
--- @see Toast.info
--- @see Toast.success
--- @see Toast.error
UXEffects.Toast = require(script.Effects.Toast)

--- Scale animations (pop-in/out).
--- @see Scale.popIn
--- @see Scale.popOut
--- @see Scale.bounce
UXEffects.Scale = require(script.Effects.Scale)

--- Gradient animation (Shimmer/Glow).
--- @see Shimmer.play
--- @see Shimmer.stop
UXEffects.Shimmer = require(script.Effects.Shimmer)

--- Slides UI panels from/to offscreen (top).
--- @see SlidePanel.slideIn
--- @see SlidePanel.slideOut
--- @see SlidePanel.cancel
UXEffects.SlidePanel = require(script.Effects.SlidePanel)

--- Standardized hover/press effects for ImageButtons.
--- @see ButtonFX.attach
--- @see ButtonFX.detach
UXEffects.ButtonFX = require(script.Effects.ButtonFX)

--- Entrance of a tab's selection background (horizontal reveal anchored to the left).
--- @see TabRevealSelect.play
--- @see TabRevealSelect.cancel
UXEffects.TabRevealSelect = require(script.Effects.TabRevealSelect)

--- Animated background blur while a UI is opening.
--- @see Backdrop.track
UXEffects.Backdrop = require(script.Effects.Backdrop)

--- Standard panel open/close (Backdrop + Scale combined,
--- tunable constants in Config.UIAnimationConfig).
--- @see PanelTransition.open
--- @see PanelTransition.close
UXEffects.PanelTransition = require(script.Effects.PanelTransition)

--- Generic circular reveal (a disc that grows/shrinks), independent of the
--- content it reveals -- reusable on any panel.
--- @see CircularReveal.attach
UXEffects.CircularReveal = require(script.Effects.CircularReveal)

--============================================================================--
-- GLOBAL CLEANUP
--============================================================================--

--- Cleans up all resources for all effects.
--- Useful when destroying a screen or switching context.
function UXEffects.cleanup(): ()
	UXEffects.FlyToUI.cleanup()
	UXEffects.Burst.cleanup()
	UXEffects.Shake.cleanup()
	UXEffects.Pulse.cleanup()
	UXEffects.Counter.cleanup()
	UXEffects.Confetti.cleanup()
	UXEffects.Glow.cleanup()
	UXEffects.Ripple.cleanup()
	UXEffects.Toast.cleanup()
	UXEffects.Scale.cleanup()
	UXEffects.Shimmer.cleanup()
	UXEffects.SlidePanel.cleanup()
	UXEffects.ButtonFX.cleanup()
	UXEffects.Backdrop.cleanup()
	UXEffects.TabRevealSelect.cleanup()
end

return UXEffects
