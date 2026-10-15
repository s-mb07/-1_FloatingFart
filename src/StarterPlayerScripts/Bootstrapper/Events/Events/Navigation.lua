--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Panel lifecycle, fired by Navigation.Controller at the exact moment a
-- transition STARTS (not when it ends), so feedback (sound...) lines up with
-- what the player sees. A panel switch fires Closed(old) then Opened(new).
return {
	--- (panelId: string) -- a panel starts opening
	PanelOpened = Signal.new(),
	--- (panelId: string) -- a panel starts closing
	PanelClosed = Signal.new(),
}
