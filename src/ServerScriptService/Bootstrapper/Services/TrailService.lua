--!strict
--[[
	@module TrailService
	@description Server authority for character trails
	(ReplicatedStorage/Config/TrailConfig has the catalogue and the rules).

	- Init generates the Trail templates into ReplicatedStorage/Cosmetics/Trails
	  (only the ones that don't exist yet), from TrailConfig.
	- "BuyTrail" (RemoteFunction: id, currency "Wins" | "Robux"): Wins spends
	  PriceWins trophies; Robux opens the trail's gamepass prompt (TrailConfig
	  GamePass) -- owning the pass unlocks the trail (GamePassService.WhenOwned).
	  A trail without PriceWins (the VIP trail) refuses Wins.
	  A trail bought with Wins, or with Robux already owned, is equipped right away.
	- "EquipTrail" (RemoteFunction: id, or "" to unequip): owned trails only.
	- The equipped trail is attached SERVER-SIDE to the HumanoidRootPart
	  (two Attachments + the cloned Trail), so it replicates to every client.
	  Re-applied on every spawn and every equip change; the previous
	  attachments/trail are removed first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local GameEvents = require(script.Parent.Parent.GameEvents)
local GamePassConfig = require(ReplicatedStorage.Config.GamePassConfig)
local GamePassService = require(script.Parent.GamePassService)
local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local NotificationService = require(script.Parent.NotificationService)
local PlayerService = require(script.Parent.PlayerService)
local TrailConfig = require(ReplicatedStorage.Config.TrailConfig)

local log = Logger.new("TrailService")
local TrailService = {}

type Result = { Success: boolean, Error: string? }

-- Names of the instances added to the HumanoidRootPart (removed on re-apply).
local ATTACHMENT0_NAME = "TrailAttachment0"
local ATTACHMENT1_NAME = "TrailAttachment1"
local TRAIL_NAME = "EquippedTrail"
local SPARKLES_ATTACHMENT_NAME = "TrailSparklesAttachment"
-- Must match TrailEffectsController (client), which toggles it while idle.
local SPARKLES_NAME = "TrailSparkles"

local templates: Folder

--============================================================================--
-- TEMPLATES
--============================================================================--

local function getOrCreateFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--- Sparkle emitter (TrailConfig.Effect) in the trail's colors. Kept as a
--- child of the Trail template; applyTrail moves a clone onto the character.
local function buildSparkles(colors: ColorSequence): ParticleEmitter
	local fx = TrailConfig.Effect
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = SPARKLES_NAME
	sparkles.Texture = fx.SparkleTexture
	sparkles.Color = colors
	sparkles.LightEmission = fx.LightEmission
	sparkles.Brightness = fx.Brightness
	sparkles.Rate = fx.SparkleRate
	sparkles.Lifetime = fx.SparkleLifetime
	sparkles.Speed = fx.SparkleSpeed
	sparkles.SpreadAngle = fx.SparkleSpread
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = fx.SparkleRotSpeed
	-- Envelope (+/- around the mid size): each particle starts anywhere from
	-- SparkleSize.Min (a dot) to SparkleSize.Max (a star), then shrinks away.
	local mid = (fx.SparkleSize.Min + fx.SparkleSize.Max) / 2
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, mid, fx.SparkleSize.Max - mid),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0, 1)
	sparkles.LockedToPart = false -- left behind along the path, like the ribbon
	sparkles.ZOffset = 1
	sparkles.Enabled = true
	return sparkles
end

local function buildTrail(id: string, def: TrailConfig.TrailDef): Trail
	local fx = TrailConfig.Effect
	local trail = Instance.new("Trail")
	trail.Name = id
	trail.Color = TrailConfig.ColorSequenceOf(def)
	trail.Transparency = NumberSequence.new(fx.HeadTransparency, 1)
	trail.WidthScale = NumberSequence.new(1, def.TailWidth)
	trail.LightEmission = fx.LightEmission
	trail.Brightness = fx.Brightness
	trail.Lifetime = TrailConfig.Lifetime
	trail.MinLength = TrailConfig.MinLength
	trail.FaceCamera = true
	buildSparkles(trail.Color).Parent = trail
	return trail
end

--- Creates the missing templates (existing ones, e.g. hand-tuned in Studio, are kept).
local function generateTemplates(): ()
	local folder: Instance = ReplicatedStorage
	for _, name in TrailConfig.TemplateFolderPath do
		folder = getOrCreateFolder(folder, name)
	end
	templates = folder :: Folder
	for id, def in TrailConfig.Trails do
		if not templates:FindFirstChild(id) then
			buildTrail(id, def).Parent = templates
		end
	end
end

--============================================================================--
-- VISUAL
--============================================================================--

--- Removes the old trail + attachments and attaches the equipped one (if any).
local function applyTrail(player: Player): ()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in { TRAIL_NAME, ATTACHMENT0_NAME, ATTACHMENT1_NAME, SPARKLES_ATTACHMENT_NAME } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local id = DataService:GetEquippedTrail(player)
	local template = if id ~= "" then templates:FindFirstChild(id) else nil
	if not (template and template:IsA("Trail")) then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = ATTACHMENT0_NAME
	a0.Position = TrailConfig.Attachment0Position
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = ATTACHMENT1_NAME
	a1.Position = TrailConfig.Attachment1Position
	a1.Parent = root

	local trail = template:Clone()
	trail.Name = TRAIL_NAME
	trail.Attachment0 = a0
	trail.Attachment1 = a1

	-- Sparkles: the template's emitter, moved onto a centre attachment.
	local sparkles = trail:FindFirstChild(SPARKLES_NAME)
	if sparkles then
		local center = Instance.new("Attachment")
		center.Name = SPARKLES_ATTACHMENT_NAME
		center.Parent = root
		sparkles.Parent = center
	end

	trail.Parent = root
end

--============================================================================--
-- REQUESTS
--============================================================================--

local function equip(player: Player, id: any): Result
	if type(id) ~= "string" or (id ~= "" and not TrailConfig.Trails[id]) then
		return { Success = false, Error = "UnknownTrail" }
	end
	local ok, reason = DataService:SetEquippedTrail(player, id)
	if not ok then
		return { Success = false, Error = reason }
	end
	applyTrail(player)
	return { Success = true }
end

local function buy(player: Player, id: any, currency: any): Result
	local def = if type(id) == "string" then TrailConfig.Trails[id] else nil
	if not def then
		return { Success = false, Error = "UnknownTrail" }
	end
	if DataService:OwnsTrail(player, id) then
		return equip(player, id)
	end

	if currency == "Wins" then
		if not def.PriceWins then
			return { Success = false, Error = "NotForWins" }
		end
		local ok = DataService:SpendTrophies(player, def.PriceWins)
		if not ok then
			NotificationService.Send(player, "Not enough Wins!", "Error")
			return { Success = false, Error = "InsufficientFunds" }
		end
	elseif currency == "Robux" then
		if not GamePassConfig.PlayerHasPass(player, def.GamePass) then
			local ok, reason = GamePassService.Prompt(player, def.GamePass)
			return { Success = false, Error = if ok then "Prompted" else reason }
		end
	else
		return { Success = false, Error = "UnknownCurrency" }
	end

	DataService:UnlockTrail(player, id)
	NotificationService.Send(player, def.DisplayName .. " unlocked!", "Success")
	log:Info("%s bought trail %s with %s.", player.Name, id, currency)
	return equip(player, id)
end

--============================================================================--
-- LIFECYCLE
--============================================================================--

local function watchPlayer(player: Player): ()
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		applyTrail(player)
	end)
	applyTrail(player)
end

--- Unlocks (and equips) the trail sold by pass `key`, once.
local function grantPassTrail(player: Player, key: string): ()
	for id, def in TrailConfig.Trails do
		if def.GamePass == key and not DataService:OwnsTrail(player, id) then
			if DataService:UnlockTrail(player, id) then
				NotificationService.Send(player, def.DisplayName .. " unlocked!", "Success")
				log:Info("%s got trail %s from its gamepass.", player.Name, id)
				equip(player, id)
			end
		end
	end
end

function TrailService:Init(): ()
	generateTemplates()
	GamePassService.WhenOwned(grantPassTrail)
	NetworkEvents.OnServerInvoke("BuyTrail", buy, true)
	NetworkEvents.OnServerInvoke("EquipTrail", equip, true)
	log:Info("Initialized (%d trail templates).", #templates:GetChildren())
end

function TrailService:Start(): ()
	GameEvents.OnPlayerRegistered:Connect(watchPlayer)
	GameEvents.OnDataLoaded:Connect(applyTrail) -- saved equip, once the profile is in
	GameEvents.OnAdminDataChanged:Connect(applyTrail) -- data reset by an admin: the trail goes away
	for _, player in PlayerService.GetRegisteredPlayers() do
		watchPlayer(player)
	end
end

return TrailService
