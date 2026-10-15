--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Local-flight lifecycle of the probe/arm mechanic (see ProbeController) --
-- fired only for the LOCAL player's own flight, so HUD/sound systems can
-- react (e.g. a HUD hint, an ambient whoosh) without depending on
-- ProbeController directly.
return {
	LaunchStarted = Signal.new(), -- () -- the server started the take-off (Start) animation
	ProbeStarted = Signal.new(), -- () -- the flight itself is ACTIVE
	FavoritePromptRequested = Signal.new(), -- () -- the server asks for the native "add to favorites" prompt
	ProbeStopped = Signal.new(), -- (reason: string)
}
