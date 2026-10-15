--!strict
--[[
	@module UITag.Handlers.Types
	@description Shared Luau type unions used across UITag handler sub-modules.

	Centralising these unions lets strict mode catch typos at call site and
	keeps attribute contracts aligned between Effects / Actions / Reactive /
	Presets and the docs.
]]

local Types = {}

--============================================================================--
-- SLIDE / ENTRANCE
--============================================================================--

export type SlideDirection = "Top" | "Bottom" | "Left" | "Right"

export type EntranceMode = "Pop" | "Bounce" | "Fade" | "Slide"

--============================================================================--
-- OPEN / CLOSE ACTIONS
--============================================================================--

-- HowToOpen supports "Scale", "Bounce" and any "Slide<Direction>" shorthand.
-- We type it loosely as string (since Slide variants are suffix-parsed), but
-- document the known canonical values here.
export type HowToOpen =
	  "Scale" | "Bounce"
	| "SlideTop" | "SlideBottom" | "SlideLeft" | "SlideRight"

export type HowToClose =
	  "Scale" | "Fade" | "Instant"
	| "SlideTop" | "SlideBottom" | "SlideLeft" | "SlideRight"

--============================================================================--
-- STYLE ENUMS (one-shot action variants)
--============================================================================--

export type BurstStyle    = "default" | "gold" | "rainbow" | "custom"
export type ConfettiStyle = "default" | "gold" | "rainbow" | "light"
export type ShakeStyle    = "default" | "error" | "impact"
export type ToastType     = "Info" | "Success" | "Warning" | "Error"
export type CounterMode   = "gain" | "loss"
export type ShakeAxis     = "X" | "Y" | "XY"

--============================================================================--
-- GLOW PRESETS
--============================================================================--

export type GlowPreset = "Gold" | "Legendary" | "Rare"

--============================================================================--
-- SERVER SYNC PAYLOAD (client-side view)
--============================================================================--

--- Minimal shape we consume on the client for UI data sync. The server sends
--- partial patches, so every field is optional.
export type SyncPayload = {
	Currencies: { [string]: number }?,
	Level: number?,
}

--============================================================================--
-- NARROWING HELPERS (Instance subtypes used after :IsA() checks)
--============================================================================--

export type TextGui  = TextLabel | TextButton
export type ImageGui = ImageLabel | ImageButton

--============================================================================--
-- PARSING
--============================================================================--

--- Extract the direction suffix from a "Slide<Dir>" string.
--- Returns nil if the value is not a Slide shorthand.
function Types.ParseSlideShorthand(value: string): SlideDirection?
	if typeof(value) ~= "string" then return nil end
	if value:sub(1, 5) ~= "Slide" then return nil end
	local dir = value:sub(6)
	if dir == "Top" or dir == "Bottom" or dir == "Left" or dir == "Right" then
		return dir :: SlideDirection
	end
	return nil
end

--- Coerce an unknown string into a SlideDirection, with fallback.
function Types.ToSlideDirection(value: any, fallback: SlideDirection?): SlideDirection
	if value == "Top" or value == "Bottom" or value == "Left" or value == "Right" then
		return value :: SlideDirection
	end
	return fallback or "Top"
end

--- Coerce an unknown string into an EntranceMode, with fallback.
function Types.ToEntranceMode(value: any, fallback: EntranceMode?): EntranceMode
	if value == "Pop" or value == "Bounce" or value == "Fade" or value == "Slide" then
		return value :: EntranceMode
	end
	return fallback or "Pop"
end

return Types
