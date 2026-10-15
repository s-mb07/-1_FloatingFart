--!strict
--[[
	@module AdminService
	@description Server authority of the admin panel (StarterGui/AdminUI).

	SECURITY MODEL
	  - Identity is ONLY `Player.UserId` as handed by the engine to the remote
	    handler: a client cannot choose, forge or send it. The allowed ids live
	    in AdminConfig (ServerScriptService: never replicated to any client).
	  - The client sends an action NAME plus a payload that is treated as
	    hostile: every field is type-checked and every number must be one of
	    the whitelisted amounts below. Nothing the client says is ever used as
	    a key into data, an instance path or a player id: targets are resolved
	    here, by name, among the players of THIS server.
	  - The panel's visibility is client-side convenience (CheckAdminStatus
	    grants nothing): whoever force-opens the UI gets "Denied" for every
	    action -- and is kicked after UNAUTHORIZED_STRIKES attempts.
	  - Remotes are rate limited (NetworkEvents), actions are serialized per
	    admin, destructive ones need an explicit Confirm flag, and every
	    executed action is logged with who/what/whom.

	STAMINA: "infinite stamina" is a per-admin-chosen flag held HERE (memory
	only, never persisted); ProbeService reads it through HasInfiniteStamina.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminConfig = require(script.Parent.Parent.Config.AdminConfig)
local CheckpointService = require(script.Parent.CheckpointService)
local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local ModerationService = require(script.Parent.ModerationService)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local PlayerTeleportService = require(script.Parent.PlayerTeleportService)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)
local SkinConfig = require(ReplicatedStorage.Config.SkinConfig)
local TrailConfig = require(ReplicatedStorage.Config.TrailConfig)
local TraversalProgressionConfig = require(ReplicatedStorage.Config.TraversalProgressionConfig)
local TraversalProgressionService = require(script.Parent.TraversalProgressionService)

local log = Logger.new("AdminService")
local AdminService = {}

type Payload = { [string]: any }
-- `Data` carries state back to the panel (e.g. the stamina flag) so it never guesses.
type Result = { Success: boolean, Message: string, Data: { [string]: any }? }

--- Unauthorized AdminRequest calls tolerated before the caller is kicked.
local UNAUTHORIZED_STRIKES = 3
local MAX_NAME_LENGTH = 40
local BAN_REASON = "You were banned by an administrator."
--- Player attribute read by VipChatTagController ("Owner" | "Dev").
local ROLE_ATTRIBUTE = "ChatRole"

-- The ONLY amounts the client may ask for.
local WINS_AMOUNTS: { [number]: boolean } = { [1] = true, [10] = true, [100] = true }
local XP_AMOUNTS: { [number]: boolean } =
	{ [500] = true, [1000] = true, [10000] = true, [100000] = true, [1000000] = true }
local REBIRTH_AMOUNTS: { [number]: boolean } = { [1] = true, [5] = true, [10] = true }

-- Studs of reach granted by "infinite stamina" (finite: the HUD divides by it).
local INFINITE_REACH = 1e9

local infiniteStamina: { [Player]: boolean } = {}
local strikes: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
-- Highest checkpoint reached since joining (survives teleports back), for Dev teleports.
local highestReached: { [Player]: number } = {}

--============================================================================--
-- AUTHORIZATION
--============================================================================--

local function levelOf(player: Player): AdminConfig.AdminLevel?
	if player.Parent ~= Players then
		return nil
	end
	return AdminConfig.Admins[player.UserId]
end

local function isAdmin(player: Player): boolean
	return levelOf(player) ~= nil
end

--- Rank of a player: 0 for a non-admin (see AdminConfig.Ranks).
local function rankOf(player: Player): number
	local level = levelOf(player)
	return if level then AdminConfig.Ranks[level] else 0
end

--- @return boolean -- true when the player's level may use `action` (AdminConfig.Permissions)
local function can(player: Player, action: string): boolean
	local level = levelOf(player)
	local allowed = AdminConfig.Permissions[action]
	return level ~= nil and allowed ~= nil and table.find(allowed, level) ~= nil
end

--- Every permitted action of the player, for the panel to show only those buttons.
local function permissionsOf(player: Player): { [string]: boolean }
	local actions: { [string]: boolean } = {}
	for action in AdminConfig.Permissions do
		if can(player, action) then
			actions[action] = true
		end
	end
	return actions
end

--- @return boolean -- true while `player` flies with infinite stamina (ProbeService)
function AdminService.HasInfiniteStamina(player: Player): boolean
	return infiniteStamina[player] == true
end

--- @return number -- reach (studs) of an infinite-stamina flight
function AdminService.GetInfiniteReach(): number
	return INFINITE_REACH
end

--============================================================================--
-- TARGETS
--============================================================================--

--- Resolves a typed name among the players of this server: exact Name /
--- DisplayName (case-insensitive), else a UNIQUE prefix of one of them.
local function findPlayer(query: any): (Player?, string?)
	if type(query) ~= "string" then
		return nil, "Enter a player name."
	end
	local name = string.lower(string.match(query, "^%s*(.-)%s*$") :: string)
	if #name == 0 or #name > MAX_NAME_LENGTH then
		return nil, "Enter a player name."
	end

	local prefixMatch: Player? = nil
	local prefixCount = 0
	for _, candidate in Players:GetPlayers() do
		local userName = string.lower(candidate.Name)
		local displayName = string.lower(candidate.DisplayName)
		if userName == name or displayName == name then
			return candidate, nil
		end
		if string.sub(userName, 1, #name) == name or string.sub(displayName, 1, #name) == name then
			prefixMatch = candidate
			prefixCount += 1
		end
	end
	if prefixCount == 1 then
		return prefixMatch, nil
	elseif prefixCount > 1 then
		return nil, "Several players match this name."
	end
	return nil, "Player not found."
end

--- The player a give/set action applies to: the admin itself, or the typed
--- name when the panel's give-to-player mode sent one.
local function resolveTarget(caller: Player, payload: Payload): (Player?, string?)
	local requested = payload.Target
	if requested == nil then
		return caller, nil
	end
	local target, err = findPlayer(requested)
	if target and target ~= caller and not can(caller, "TargetOthers") then
		return nil, "Your rank can only target yourself."
	end
	return target, err
end

--============================================================================--
-- ACTIONS
--============================================================================--

local function amountOf(payload: Payload, allowed: { [number]: boolean }): number?
	local amount = payload.Amount
	if type(amount) == "number" and allowed[amount] == true then
		return amount
	end
	return nil
end

local function ok(message: string, data: { [string]: any }?): (boolean, string, { [string]: any }?)
	return true, message, data
end

local function fail(message: string): (boolean, string, { [string]: any }?)
	return false, message, nil
end

local function resetPlayer(target: Player): (boolean, string, { [string]: any }?)
	local done, reason = DataService:ResetPlayerData(target)
	if not done then
		return fail("Reset failed (" .. tostring(reason) .. ").")
	end
	infiniteStamina[target] = nil
	-- Owned passes come from Roblox, not from the data: re-check them all so
	-- a stale cached one (Studio test purchase, gone gift) is dropped.
	GamePassService.RefreshAll(target)
	-- Then replay the join hooks on the fresh data: perks of passes still
	-- owned are granted again, playtime / daily / tutorial / HUD re-sync.
	GameEvents.OnDataLoaded:Fire(target)
	GameEvents.OnAdminDataChanged:Fire(target)
	return ok("Data reset: " .. target.Name)
end

--- Writes a rebirth count, then re-syncs what depends on it (HUD, treadmill access).
local function applyRebirth(target: Player, count: number): (boolean, string?)
	local done, reason = DataService:ApplyRebirth(target, count)
	if not done then
		return false, reason
	end
	TraversalProgressionService.Publish(target)
	GameEvents.OnAdminDataChanged:Fire(target)
	GameEvents.OnRebirthed:Fire(target)
	return true, nil
end

-- Actions that apply to the admin OR to a typed target (give-to-player mode).
local TARGETED: { [string]: (target: Player, payload: Payload) -> (boolean, string, { [string]: any }?) } = {
	GetInfiniteStamina = function(target, _payload)
		return ok(target.Name, { Enabled = infiniteStamina[target] == true })
	end,

	GiveWins = function(target, payload)
		local amount = amountOf(payload, WINS_AMOUNTS)
		if not amount then
			return fail("Invalid amount.")
		end
		local done, reason = DataService:AddTrophies(target, amount)
		if not done then
			return fail(tostring(reason))
		end
		return ok(("+%d Wins -> %s"):format(amount, target.Name))
	end,

	GiveXP = function(target, payload)
		local amount = amountOf(payload, XP_AMOUNTS)
		if not amount then
			return fail("Invalid amount.")
		end
		local done, reason = TraversalProgressionService.AddXP(target, amount, "Admin")
		if not done then
			return fail(tostring(reason))
		end
		return ok(("+%d XP -> %s"):format(amount, target.Name))
	end,

	SetMaxLevel = function(target, _payload)
		local previous = DataService:GetTraversalLevel(target)
		local maxLevel = TraversalProgressionConfig.MaxLevel
		local done, reason = DataService:SetTraversalLevel(target, maxLevel)
		if not done then
			return fail(tostring(reason))
		end
		if previous ~= maxLevel then
			GameEvents.OnTraversalLevelChanged:Fire(target, maxLevel, previous)
		end
		TraversalProgressionService.Publish(target)
		return ok(("Level %d -> %s"):format(maxLevel, target.Name))
	end,

	GiveRebirth = function(target, payload)
		local amount = amountOf(payload, REBIRTH_AMOUNTS)
		if not amount then
			return fail("Invalid amount.")
		end
		local current = DataService:GetRebirths(target)
		local maxRebirths = RebirthConfig.GetMaxRebirths()
		if current >= maxRebirths then
			return fail(target.Name .. " is already at max rebirth.")
		end
		local newCount = math.min(current + amount, maxRebirths)
		local done, reason = applyRebirth(target, newCount)
		if not done then
			return fail(tostring(reason))
		end
		return ok(("Rebirths %d -> %s"):format(newCount, target.Name))
	end,

	SetMaxRebirth = function(target, _payload)
		local maxRebirths = RebirthConfig.GetMaxRebirths()
		if maxRebirths < 1 then
			return fail("No rebirth configured.")
		end
		local done, reason = applyRebirth(target, maxRebirths)
		if not done then
			return fail(tostring(reason))
		end
		return ok(("Max rebirth (%d) -> %s"):format(maxRebirths, target.Name))
	end,

	SetInfiniteStamina = function(target, payload)
		local enabled = payload.Enabled
		if type(enabled) ~= "boolean" then
			return fail("Invalid value.")
		end
		infiniteStamina[target] = if enabled then true else nil
		return ok(
			("Infinite stamina %s -> %s (next flight)"):format(if enabled then "ON" else "OFF", target.Name),
			{ Enabled = enabled }
		)
	end,

	GiveAllSkins = function(target, _payload)
		for id in SkinConfig.Skins do
			DataService:UnlockSkin(target, id)
		end
		GameEvents.OnAdminDataChanged:Fire(target)
		return ok("All skins -> " .. target.Name)
	end,

	GiveAllTrails = function(target, _payload)
		for id in TrailConfig.Trails do
			DataService:UnlockTrail(target, id)
		end
		GameEvents.OnAdminDataChanged:Fire(target)
		return ok("All trails -> " .. target.Name)
	end,

	--- Stage 0 = lobby (new run), else checkpoint `Stage` (the run resumes
	--- there, like a revive). Yields until the teleport is done.
	TeleportStage = function(target, payload)
		local stage = payload.Stage
		if type(stage) ~= "number" or stage % 1 ~= 0 or stage < 0 then
			return fail("Invalid stage.")
		end
		local destination = if stage == 0
			then PlayerTeleportService.GetLobbyCFrame()
			else CheckpointService.GetSpawnCFrame(stage)
		if not destination then
			return fail(("No stage %d in the map."):format(stage))
		end
		-- A Dev only goes back to stages already reached since joining.
		if stage > 0 and levelOf(target) == "Dev" then
			local reached = math.max(highestReached[target] or 0, CheckpointService.GetStage(target))
			if stage > reached then
				return fail(("Stage %d not reached yet."):format(stage))
			end
		end
		if not PlayerTeleportService.TeleportTo(target, destination, "Admin") then
			return fail(target.Name .. " could not be moved (flying / not spawned?).")
		end
		if stage == 0 then
			CheckpointService.Reset(target)
		else
			CheckpointService.RestoreTo(target, stage)
		end
		return ok(("%s -> %s"):format(target.Name, if stage == 0 then "lobby" else "stage " .. stage))
	end,
}

-- Actions with their own target rules (never the give-to-player mode).
local SPECIAL: { [string]: (caller: Player, payload: Payload) -> (boolean, string, { [string]: any }?) } = {
	ResetSelf = function(caller, payload)
		if payload.Confirm ~= true then
			return fail("Confirmation required.")
		end
		return resetPlayer(caller)
	end,

	ResetPlayer = function(caller, payload)
		if payload.Confirm ~= true then
			return fail("Confirmation required.")
		end
		local target, err = findPlayer(payload.Name)
		if not target then
			return fail(err or "Player not found.")
		end
		if target ~= caller and rankOf(target) >= rankOf(caller) then
			return fail("Cannot target a player of equal or higher rank.")
		end
		return resetPlayer(target)
	end,

	ResetAll = function(caller, payload)
		if payload.Confirm ~= true then
			return fail("Confirmation required.")
		end
		local count = 0
		for _, target in Players:GetPlayers() do
			if target ~= caller and rankOf(target) >= rankOf(caller) then
				continue
			end
			if resetPlayer(target) then
				count += 1
			end
		end
		return ok(("Data reset for %d player(s)."):format(count))
	end,

	Kick = function(caller, payload)
		local target, err = findPlayer(payload.Name)
		if not target then
			return fail(err or "Player not found.")
		end
		if rankOf(target) >= rankOf(caller) then
			return fail("Cannot kick a player of equal or higher rank.")
		end
		target:Kick("You were removed from the server by an administrator.")
		return ok("Kicked " .. target.Name)
	end,

	--- Permanent (DataStore) ban of a player of this server.
	Ban = function(caller, payload)
		if payload.Confirm ~= true then
			return fail("Confirmation required.")
		end
		local target, err = findPlayer(payload.Name)
		if not target then
			return fail(err or "Player not found.")
		end
		if rankOf(target) >= rankOf(caller) then
			return fail("Cannot ban a player of equal or higher rank.")
		end
		ModerationService.Ban(target.UserId, BAN_REASON, caller.UserId)
		return ok("Banned " .. target.Name)
	end,
}

--============================================================================--
-- REQUEST ENTRY POINT
--============================================================================--

local function handleRequest(player: Player, action: any, payload: any): Result
	if not isAdmin(player) then
		local count = (strikes[player] or 0) + 1
		strikes[player] = count
		log:Warn(
			"SECURITY: %s (%d) sent an admin request without admin rights (%d/%d).",
			player.Name,
			player.UserId,
			count,
			UNAUTHORIZED_STRIKES
		)
		if count >= UNAUTHORIZED_STRIKES then
			player:Kick("Unauthorized request.")
		end
		return { Success = false, Message = "Denied." }
	end

	if type(action) ~= "string" or #action > 40 then
		return { Success = false, Message = "Invalid request." }
	end
	if not can(player, action) then
		log:Warn("ADMIN %s (%d): %s refused (rank %s).", player.Name, player.UserId, action, tostring(levelOf(player)))
		return { Success = false, Message = "Your rank cannot do this." }
	end
	local data: Payload = if type(payload) == "table" then payload else {}

	if busy[player] then
		return { Success = false, Message = "Busy, try again." }
	end
	busy[player] = true

	local success, message, resultData = false, "Unknown action.", nil
	local ran, result1, result2, result3 = pcall(function(): (boolean, string, { [string]: any }?)
		local targeted = TARGETED[action]
		if targeted then
			local target, err = resolveTarget(player, data)
			if not target then
				return fail(err or "Player not found.")
			end
			return targeted(target, data)
		end
		local special = SPECIAL[action]
		if special then
			return special(player, data)
		end
		return fail("Unknown action.")
	end)
	busy[player] = nil

	if ran then
		success, message, resultData = result1 :: boolean, result2 :: string, result3 :: any
	else
		log:Error("Admin action '%s' errored: %s", action, tostring(result1))
		message = "Server error."
	end

	-- State queries (the panel refreshing itself) are not worth a log line.
	if action ~= "GetInfiniteStamina" then
		log:Warn(
			"ADMIN %s (%d): %s -> %s [%s]",
			player.Name,
			player.UserId,
			action,
			message,
			if success then "ok" else "refused"
		)
	end
	return { Success = success, Message = message, Data = resultData }
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

--- Replicated chat tag: "Owner" for the owner, "Dev" for every other admin.
--- Display only (VipChatTagController); authority stays on AdminConfig.
local function tagRole(player: Player): ()
	local level = AdminConfig.Admins[player.UserId]
	if level and not AdminConfig.HiddenRole[player.UserId] then
		player:SetAttribute(ROLE_ATTRIBUTE, if level == "Owner" then "Owner" else "Dev")
	end
end

function AdminService:Init(): ()
	Players.PlayerAdded:Connect(tagRole)
	for _, player in Players:GetPlayers() do
		tagRole(player)
	end
	GameEvents.OnCheckpointReached:Connect(function(player: Player, stage: number)
		highestReached[player] = math.max(highestReached[player] or 0, stage)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		highestReached[player] = nil
		infiniteStamina[player] = nil
		strikes[player] = nil
		busy[player] = nil
	end)
	log:Info("Initialized.")
end

function AdminService:Start(): ()
	-- false = not an admin; else the level and the actions the panel may show.
	NetworkEvents.OnServerInvoke("CheckAdminStatus", function(player: Player): any
		local level = levelOf(player)
		if not level then
			return false
		end
		return { Level = level, Actions = permissionsOf(player) }
	end)
	NetworkEvents.OnServerInvoke("AdminRequest", handleRequest, true)
	log:Info("Started.")
end

return AdminService
