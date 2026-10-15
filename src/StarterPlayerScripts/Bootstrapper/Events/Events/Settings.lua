--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Local settings that don't come from a server push (see QualityController).
return {
	QualityChanged = Signal.new(), -- (level: string, preset: GraphicsQualityConfig.Preset)
}
