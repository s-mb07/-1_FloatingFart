--!strict
--[[
	@module LeaderstatsService
	@description Creates and owns the `leaderstats` Folder under each player
	(the Roblox convention Studio's default leaderboard reads from). Other
	services update a displayed stat through `SetStat` below instead of
	writing to `player.leaderstats` values directly -- keeps stat-value
	creation (IntValue vs NumberValue, first-write) in one place.

	Leaderstats are a DISPLAY concern only -- the authoritative value still
	lives in the player's ProfileStore data (see DataService). Call `SetStat`
	whenever the underlying data changes (e.g. from a GameEvents.OnCurrencyEarned
	handler), don't treat the leaderstat itself as the source of truth.
]]

local GameEvents = require(script.Parent.Parent.GameEvents)

local LeaderstatsService = {}

local function ensureFolder(player: Player): Folder
	local existing = player:FindFirstChild("leaderstats")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	folder.Parent = player
	return folder
end

--- Set a leaderstat value for a player, creating the stat (as an IntValue) if it
--- does not exist yet.
--- @param player Player -- the player whose leaderstat is being set
--- @param statName string -- the leaderstat name, e.g. "Wins"
--- @param value number -- the new value
function LeaderstatsService.SetStat(player: Player, statName: string, value: number): ()
	local folder = ensureFolder(player)
	local stat = folder:FindFirstChild(statName)
	if not stat then
		stat = Instance.new("IntValue")
		stat.Name = statName
		stat.Parent = folder
	end
	(stat :: IntValue).Value = value
end

function LeaderstatsService:Init(): ()
	GameEvents.OnPlayerRegistered:Connect(function(player: Player)
		ensureFolder(player) -- empty leaderstats visible immediately, stats fill in as data loads
	end)
end

function LeaderstatsService:Start(): () end

return LeaderstatsService
