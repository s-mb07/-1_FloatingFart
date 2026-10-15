--!strict
--[[
	@module LeaderboardService
	@description The three lobby leaderboards (_WORLD anywhere in Workspace,
	then .../Lobby/Interactive/Leaderboards/<Board>): global top players from one
	OrderedDataStore per board.

	Every REFRESH_SECONDS (and whenever a profile loads): each online player's value is written to the
	board's store if it beats their recorded peak, the top TOP_COUNT is read back and drawn on the board's
	SurfaceGui by cloning its Studio `PlayerTemplate` row (Rank / Name /
	Amount). Server-drawn: the board is a world object every client sees the
	same. The values come from DataService (ProfileStore stays the source of
	truth; the stores only rank).

	Studio without DataStore access: the write/read fail, the board then
	ranks the online players only (warned once).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NumberUtil = require(ReplicatedStorage.Libraries.NumberUtil)

local log = Logger.new("LeaderboardService")
local LeaderboardService = {}

local REFRESH_SECONDS = 60
local TOP_COUNT = 50

type Board = {
	Model: string, -- child of Leaderboards
	Store: string, -- OrderedDataStore name
	Get: (Player) -> number,
}

local BOARDS: { Board } = {
	{
		Model = "WinsLeaderboard",
		Store = "LB_Wins_v1",
		Get = function(player)
			return DataService:GetTrophies(player)
		end,
	},
	{
		Model = "Leaderboard", -- "Most Rebirths"
		Store = "LB_Rebirths_v1",
		Get = function(player)
			return DataService:GetRebirths(player)
		end,
	},
	{
		Model = "PlaneLeaderboard", -- "Most Plane": total length (traversal XP)
		Store = "LB_Length_v1",
		Get = function(player)
			return DataService:GetTraversalXP(player)
		end,
	},
}

type Entry = { UserId: number, Value: number }

local names: { [number]: string } = {}
-- Only players whose profile is loaded are written: before that the getters
-- return template defaults (0), which would overwrite their real score.
local loaded: { [Player]: boolean } = {}
local warnedOffline = false

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local resolved = if ok and type(name) == "string" then name else ("#" .. userId)
	names[userId] = resolved
	return resolved
end

--- Writes the online players then reads the global top. Falls back to the
--- online players when the DataStore is unreachable (Studio without access).
local function fetchTop(board: Board): { Entry }
	local online: { Entry } = {}
	for player in loaded do
		table.insert(online, { UserId = player.UserId, Value = math.floor(board.Get(player)) })
	end

	local ok, top = pcall(function(): { Entry }
		local store = DataStoreService:GetOrderedDataStore(board.Store)
		-- Keep each player's peak: wins drop when spent, length resets on rebirth.
		for _, entry in online do
			store:UpdateAsync(tostring(entry.UserId), function(old: number?): number?
				return if old and old >= entry.Value then nil else entry.Value
			end)
		end
		local page = store:GetSortedAsync(false, TOP_COUNT):GetCurrentPage()
		local entries: { Entry } = {}
		for _, item in page do
			table.insert(entries, { UserId = tonumber(item.key) or 0, Value = item.value })
		end
		return entries
	end)
	if ok then
		return top
	end
	if not warnedOffline then
		warnedOffline = true
		log:Warn("DataStore unreachable (%s): boards show online players only.", tostring(top))
	end
	table.sort(online, function(a, b)
		return a.Value > b.Value
	end)
	return online
end

local function draw(board: Board, entries: { Entry }): ()
	local root = Workspace:FindFirstChild("_WORLD", true)
	local folder = root and root:FindFirstChild("Leaderboards", true)
	local model = folder and folder:FindFirstChild(board.Model)
	local template = model and model:FindFirstChild("PlayerTemplate", true)
	if not (template and template:IsA("GuiObject")) then
		return
	end
	local list = template.Parent :: Instance
	template.Visible = false
	local layout = list:FindFirstChildWhichIsA("UIGridLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	for _, child in list:GetChildren() do
		if child.Name == "Row" then
			child:Destroy()
		end
	end
	for rank, entry in entries do
		local row = template:Clone()
		row.Name = "Row"
		row.LayoutOrder = rank
		row.Visible = true
		;(row:FindFirstChild("Rank") :: TextLabel).Text = "#" .. rank
		;(row:FindFirstChild("Name") :: TextLabel).Text = nameOf(entry.UserId)
		local amount = row:FindFirstChild("Amount") :: TextLabel
		amount.Text = NumberUtil.FormatShort(entry.Value) -- just the number, right-aligned
		amount.TextXAlignment = Enum.TextXAlignment.Right
		row.Parent = list
	end
end

local refreshing = false

local function refresh(): ()
	if refreshing then
		return
	end
	refreshing = true
	for _, board in BOARDS do
		draw(board, fetchTop(board))
	end
	refreshing = false
end

function LeaderboardService:Init(): ()
	GameEvents.OnDataLoaded:Connect(function(player: Player)
		loaded[player] = true
		task.spawn(refresh) -- a joining player shows up right away
	end)
	GameEvents.OnPlayerUnregistered:Connect(function(player: Player)
		loaded[player] = nil
	end)
end

function LeaderboardService:Start(): ()
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
