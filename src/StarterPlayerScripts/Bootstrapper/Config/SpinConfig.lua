--!strict
--[[
	@class SpinConfig
	Cosmetic endless rotations of tagged world objects (SpinController).
	Speeds in degrees per second.
]]

local SpinConfig = table.freeze({
	--- Studio colours: red = X, green = Y, blue = Z (local axes).
	--- Fan model (TagNames.Fan): its `Rotation` child model turns around the
	--- green (Y) axis of that model's PrimaryPart.
	FanSpeed = 240,
	FanAxis = Vector3.yAxis,
	--- Child of the Fan model that turns.
	FanRotationModel = "Rotation",
	--- Part of that model (any depth) whose own axes the spin follows.
	FanPrimaryName = "Primary",
	--- SkinShow showcase parts (TagNames.SkinShow): all turn together around the blue (Z) axis,
	--- much slower than the fans.
	SkinShowSpeed = 30,
	SkinShowAxis = Vector3.zAxis,
})

return SpinConfig
