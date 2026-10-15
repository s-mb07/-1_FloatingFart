--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Roblox purchase prompts (display only -- granting stays server-side).
return {
	--- (kind: "GamePass" | "Product", id: number) -- a purchase prompt was opened
	--- for the local player. Bridged from MonetizationService's
	--- "PurchasePromptShown"; client code that prompts directly fires it too.
	PromptShown = Signal.new(),
	--- (itemKey: string, detail: number?) -- the server granted a purchase
	--- (product or pass key). Bridged from "PurchaseGranted"; Panels/LeaveReward
	--- fires it too ("LeaveReward") once its free gift is granted.
	Granted = Signal.new(),
}
