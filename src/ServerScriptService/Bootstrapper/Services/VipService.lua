--!strict
--[[
	@module VipService
	@description The floating tags above the head of a player: "🔱 Owner" /
	"🔧 Dev" (admins, `ChatRole` attribute set by AdminService) and "👑 VIP"
	(VIP gamepass owners), stacked in ONE billboard so they coexist. Built
	server-side on the character's Head so every client sees it; rebuilt on
	every spawn and as soon as the pass becomes owned (purchase or gift,
	GamePassService.WhenOwned).

	The other VIP perks live with their own systems: Golden Plane skin
	(SkinService), VIP trail (TrailService), chat tags (VipChatTagController).
]]

local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassService = require(script.Parent.GamePassService)
local PlayerService = require(script.Parent.PlayerService)

local VipService = {}

local VIP_PASS = "VIP"
local TAG_NAME = "VipOverheadTag"
local ROLE_ATTRIBUTE = "ChatRole" -- set by AdminService
local STROKE = Color3.fromRGB(0, 0, 0)
local LINE_HEIGHT = 1.2 -- studs per tag line

type Line = { Text: string, Color: Color3 }

local ROLE_LINES: { [string]: Line } = {
	Owner = { Text = "🔱 Owner", Color = Color3.fromRGB(255, 75, 75) },
	Dev = { Text = "🔧 Dev", Color = Color3.fromRGB(90, 210, 255) },
}
local VIP_LINE: Line = { Text = "👑 VIP", Color = Color3.fromRGB(255, 205, 40) }

--- The lines `player` currently earns, top to bottom (role, then VIP).
local function linesOf(player: Player): { Line }
	local lines: { Line } = {}
	local role = player:GetAttribute(ROLE_ATTRIBUTE)
	if type(role) == "string" and ROLE_LINES[role] then
		table.insert(lines, ROLE_LINES[role])
	end
	if GamePassService.HasPass(player, VIP_PASS) then
		table.insert(lines, VIP_LINE)
	end
	return lines
end

--- (Re)builds the tag on `player`'s current character.
local function attachTag(player: Player): ()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local old = head:FindFirstChild(TAG_NAME)
	if old then
		old:Destroy()
	end
	local lines = linesOf(player)
	if #lines == 0 then
		return
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Adornee = head
	tag.Size = UDim2.fromScale(4, LINE_HEIGHT * #lines) -- studs
	-- Above the default name/health display.
	tag.StudsOffsetWorldSpace = Vector3.new(0, 3.2 + LINE_HEIGHT * (#lines - 1) / 2, 0)
	tag.MaxDistance = 80
	tag.LightInfluence = 0

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tag

	for index, line in lines do
		local text = Instance.new("TextLabel")
		text.LayoutOrder = index
		text.Size = UDim2.fromScale(1, 1 / #lines)
		text.BackgroundTransparency = 1
		text.Text = line.Text
		text.TextScaled = true
		text.Font = Enum.Font.FredokaOne
		text.TextColor3 = line.Color
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = STROKE
		stroke.Parent = text
		text.Parent = tag
	end

	tag.Parent = head
end

local function watchPlayer(player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		attachTag(player)
	end)
	attachTag(player)
end

function VipService:Init(): ()
	GamePassService.WhenOwned(function(player: Player, key: string)
		if key == VIP_PASS then
			attachTag(player)
		end
	end)
end

function VipService:Start(): ()
	GameEvents.OnPlayerRegistered:Connect(watchPlayer)
	for _, player in PlayerService.GetRegisteredPlayers() do
		watchPlayer(player)
	end
end

return VipService
