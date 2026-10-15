--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Payload of both signals: { Message: string, Type: ("Info" | "Success" | "Warning" | "Error")?, Duration: number? }
-- Both are rendered by NotificationController in MainHUD/NotificationsFrame.
return {
	--- Server-pushed (NotificationService "Notify", see NetworkEvents.lua),
	--- fired by NetworkBridgeController only.
	Received = Signal.new(),
	--- Client-local feedback for something this client already knows
	--- happened (a code redeemed, a refused click). Fired by any controller/panel.
	Show = Signal.new(),
}
