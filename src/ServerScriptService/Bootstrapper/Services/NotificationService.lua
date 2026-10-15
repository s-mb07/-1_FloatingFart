--!strict
--[[
	@module NotificationService
	@description Server-driven push notifications ("you got X", "event started"),
	as opposed to `Effects`/`UXEffects.Toast` which a CLIENT triggers locally
	for its own one-shot feedback (a button press, a reward claim animation
	already running client-side). Fires `NetworkEvents "Notify"`; the client
	only ever displays what it receives here, never decides on its own that
	a server-driven notification should appear.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

export type NotificationType = "Info" | "Success" | "Warning" | "Error"

local NotificationService = {}

--- Send a notification to one player.
--- @param player Player
--- @param message string
--- @param notificationType NotificationType? -- defaults to "Info" client-side
--- @param duration number? -- seconds on screen, defaults to 3 client-side
function NotificationService.Send(
	player: Player,
	message: string,
	notificationType: NotificationType?,
	duration: number?
): ()
	NetworkEvents.FireClient("Notify", player, {
		Message = message,
		Type = notificationType,
		Duration = duration,
	})
end

--- Send a notification to every connected player.
--- @param message string
--- @param notificationType NotificationType?
--- @param duration number?
function NotificationService.Broadcast(message: string, notificationType: NotificationType?, duration: number?): ()
	NetworkEvents.FireAllClients("Notify", {
		Message = message,
		Type = notificationType,
		Duration = duration,
	})
end

function NotificationService:Init(): () end

function NotificationService:Start(): () end

return NotificationService
