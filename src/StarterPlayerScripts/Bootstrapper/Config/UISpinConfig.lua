--!strict
--[[
	@module UISpinConfig
	@description Animation speeds for UISpinController. Studio only carries the
	marker: a boolean attribute `Spin = true` on the instance (StarterGui).
	Everything else lives here. Nothing is matched by instance name: the
	behavior comes from the instance's ClassName.

	  - UIGradient: its color ramp scrolls around (cyclic phase shift) --
	    rotating a gradient distorts it on non-square frames, scrolling doesn't.
	    Speed = full color cycles per second.
	  - anything else with a `Rotation` (ImageLabel...): spins in place.
	    Speed = degrees per second (negative = counter-clockwise).
]]

return {
	--- Attribute that marks an instance as animated.
	Attribute = "Spin",

	--- Scheduler frequency of the (cosmetic) animation task.
	TickHz = 30,

	--- Rotation speed (deg/s) for classes without an entry in `SpeedByClass`.
	DefaultDegreesPerSecond = 45,

	--- Rotation speed (deg/s) by ClassName.
	SpeedByClass = {
		ImageLabel = 50, -- sunburst rays
	} :: { [string]: number },

	--- Full color cycles per second for UIGradient (1/6 = one loop every 6 s).
	GradientCyclesPerSecond = 1 / 6,

	--- Color samples per gradient (ColorSequence caps at 20 keypoints).
	GradientSamples = 19,
}
