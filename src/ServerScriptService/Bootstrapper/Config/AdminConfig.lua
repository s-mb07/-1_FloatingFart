--!strict
--[[
	@module AdminConfig
	@description Admin permissions and commands configuration.

	Three levels, highest first:
	  - Owner   : everything, including Ban and ResetAll.
	  - Manager : give / set / teleport / resets / kick (no Ban, no ResetAll).
	  - Dev     : testing tools only (own flight, cosmetics, own reset, lobby and
	              already-reached stages), never on another player.
	A level may only kick / ban / reset a player of STRICTLY lower rank
	(a non-admin is rank 0); everyone may target themselves.

	SECURITY: lives under ServerScriptService, NEVER under ReplicatedStorage --
	if replicated, this file would hand any client the list of UserIds to
	target to impersonate an admin role.
]]

export type AdminLevel = "Owner" | "Manager" | "Dev"

local ALL: { AdminLevel } = { "Owner", "Manager", "Dev" }
local STAFF: { AdminLevel } = { "Owner", "Manager" }
local OWNER_ONLY: { AdminLevel } = { "Owner" }

local AdminConfig = {
	-- List of admin IDs
	-- [UserId] = "Level"
	Admins = {
		-- [8721634] = "Owner",
		[4076223974] = "Owner",
		[8504642233] = "Manager",
		[3366659188] = "Manager",
		[1098505692] = "Manager",
		[1570818295] = "Manager", -- no chat tag (see HiddenRole)
		[1487632968] = "Dev",
		[11577260932] = "Dev",
		[2223828755] = "Dev",
		[4811339624] = "Dev",
		[2222331885] = "Dev",
	} :: { [number]: AdminLevel },

	--- Admins whose rights apply but who get no "Dev"/"Owner" chat tag.
	HiddenRole = {
		[1570818295] = true,
	} :: { [number]: boolean },

	--- Higher beats lower. A non-admin has rank 0.
	Ranks = { Owner = 3, Manager = 2, Dev = 1 } :: { [AdminLevel]: number },

	--- AdminService action (or capability) -> levels allowed to use it.
	--- "TargetOthers" = the give-to-player mode (give / set on someone else).
	--- An action missing from this table is refused for everybody.
	Permissions = {
		GetInfiniteStamina = ALL,
		SetInfiniteStamina = ALL,
		GiveAllSkins = ALL,
		GiveAllTrails = ALL,
		TeleportStage = ALL, -- Dev: lobby + stages already reached (enforced in AdminService)
		ResetSelf = ALL,

		TargetOthers = STAFF,
		GiveWins = STAFF,
		GiveXP = STAFF,
		SetMaxLevel = STAFF,
		GiveRebirth = STAFF,
		SetMaxRebirth = STAFF,
		ResetPlayer = STAFF,
		Kick = STAFF,

		ResetAll = OWNER_ONLY,
		Ban = OWNER_ONLY,
	} :: { [string]: { AdminLevel } },

	-- Settings
	Settings = {
		Prefix = "/",
		LogLevel = 2, -- 0: None, 1: Commands only, 2: Everything
	},
}

return AdminConfig
