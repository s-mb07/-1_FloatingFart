--!strict
--[[
	@module NotificationDotController
	@description Keeps every button's "!" notification dot drawn above the
	neighbouring buttons. The dot is a `Notification` child centred on its
	button's top-right corner, so half of it spills over the button to the
	right and the row above. Under ZIndexBehavior.Sibling the HUD buttons all
	share ZIndex 1, so whichever sibling rendered later covered the dot.

	Fix: every GuiButton holding a dot is lifted above its plain siblings, and
	dot holders are ranked among themselves bottom row first, then left to
	right, so a dot always draws above the buttons its corner overlaps (even
	when the neighbour has a dot of its own). Re-ranked whenever a holder
	moves (responsive scale, wrap change), and picked up automatically for any
	button that gets a `Notification` child later.
]]

local Players = game:GetService("Players")

local NotificationDotController = {}

local DOT_NAME = "Notification"

local pending: { [Instance]: boolean } = {}

local function restack(container: Instance): ()
	local holders: { GuiObject } = {}
	local baseZ = 0
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			if child:IsA("GuiButton") and child:FindFirstChild(DOT_NAME) then
				table.insert(holders, child)
			else
				baseZ = math.max(baseZ, child.ZIndex)
			end
		end
	end
	-- Ascending draw order: top row first, right to left within a row.
	table.sort(holders, function(a: GuiObject, b: GuiObject): boolean
		local ay, by = a.AbsolutePosition.Y, b.AbsolutePosition.Y
		if math.abs(ay - by) > 1 then
			return ay < by
		end
		return a.AbsolutePosition.X > b.AbsolutePosition.X
	end)
	for i, holder in holders do
		holder.ZIndex = baseZ + i
	end
end

-- Coalesces the burst of AbsolutePosition changes a layout pass fires.
local function scheduleRestack(container: Instance): ()
	if pending[container] then
		return
	end
	pending[container] = true
	task.defer(function()
		pending[container] = nil
		if container.Parent then
			restack(container)
		end
	end)
end

local function track(dot: Instance): ()
	local button = dot.Parent
	if dot.Name ~= DOT_NAME or not (button and button:IsA("GuiButton")) then
		return
	end
	local container = button.Parent
	if not container then
		return
	end
	button:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		scheduleRestack(container)
	end)
	scheduleRestack(container)
end

function NotificationDotController:Init(): () end

function NotificationDotController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(track)
	for _, descendant in playerGui:GetDescendants() do
		track(descendant)
	end
end

return NotificationDotController
