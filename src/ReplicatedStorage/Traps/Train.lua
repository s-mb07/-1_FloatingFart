--!strict
--[[
	@module Traps.Train
	@description Stage 6 train trap, on the folder tagged TagNames.TrainTrap
	(below it: Attachments `TrainStart` / `TrainEnd` in the invisible `TrainPath`
	part, lights `GreenLight` / `RedLight` anywhere).

	Every PERIOD seconds: the red light turns on, LIGHT_LEAD s later the train
	(ReplicatedStorage.Assets.Trap.Stage_6.Train) runs from TrainStart to
	TrainEnd in TRAVEL s, then disappears; LIGHT_LEAD s after that the green
	light is back. The train keeps the asset's own orientation: only the
	attachments' POSITIONS are used.

	No remote: both sides derive the cycle from the synced server clock
	(workspace:GetServerTimeNow()). The server publishes the path as Vector3
	attributes on the folder (PATH_START / PATH_END): a Folder never streams
	out, the TrainPath part may never stream in on a low-end client.
	  - Server: ONE invisible box (the train's bounding box) tagged
	    TagNames.KillPart, parented only while the train runs. LifeService's
	    kill-part handling sends whoever it touches back to the lobby, and the
	    probe's kill-part raycasts hit it: every part of the train kills, for
	    one part replicated instead of 234.
	  - Client: a local clone of the train (no collision/query, the server box
	    is the gameplay truth), the light colours, and the train sounds
	    (Assets/sfx/Traps: TrainHorn + TrainPass, 3D at the train's centre,
	    played when it sets off if SFX are on; they stop when it disappears).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)

local PERIOD = 7
local TRAVEL = 2
local LIGHT_LEAD = 0.3
local LIGHT_OFF = Color3.new(0, 0, 0)
local LIGHT_REFRESH = 0.5
--- Train sounds: names in Assets/sfx/Traps, and how far they carry (studs).
local SOUNDS = { "TrainHorn", "TrainPass" }
local SOUND_MIN_DISTANCE = 60
local SOUND_MAX_DISTANCE = 1000

local PATH_START = "PathStart"
local PATH_END = "PathEnd"

local Train = { Tag = TagNames.TrainTrap }

--- Progress (0..1) of the run at server time `now`, nil while no train is out.
local function progress(now: number): number?
	local t = now % PERIOD - LIGHT_LEAD
	return if t >= 0 and t <= TRAVEL then t / TRAVEL else nil
end

--- Red from LIGHT_LEAD before the train leaves to LIGHT_LEAD after it is gone.
local function isRed(now: number): boolean
	return now % PERIOD < TRAVEL + 2 * LIGHT_LEAD
end

local function template(): Model
	local assets = ReplicatedStorage:WaitForChild("Assets")
	return assets:WaitForChild("Trap"):WaitForChild("Stage_6"):WaitForChild("Train") :: Model
end

--- Server: world position of a path attachment, anywhere below the folder
--- (in the `TrainPath` part). One placed straight under a Folder has no
--- parent part: its Position is already in world space.
local function point(folder: Instance, name: string): Vector3
	local found = folder:FindFirstChild(name, true)
	while not found do
		folder.DescendantAdded:Wait()
		found = folder:FindFirstChild(name, true)
	end
	local attachment = found :: Attachment
	return if attachment.Parent and attachment.Parent:IsA("BasePart")
		then attachment.WorldPosition
		else attachment.Position
end

--- Train pivot at run progress `alpha`: lerped position, asset rotation.
local function pivotAt(from: Vector3, to: Vector3, rotation: CFrame, alpha: number): CFrame
	return CFrame.new(from:Lerp(to, alpha)) * rotation
end

--- Client: the path the server published on the folder (waits for it).
local function publishedPath(folder: Instance): (Vector3, Vector3)
	local from, to = folder:GetAttribute(PATH_START), folder:GetAttribute(PATH_END)
	while typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" do
		folder.AttributeChanged:Wait()
		from, to = folder:GetAttribute(PATH_START), folder:GetAttribute(PATH_END)
	end
	return from :: Vector3, to :: Vector3
end

function Train.Server(folder: Instance): () -> ()
	local from, to = point(folder, "TrainStart"), point(folder, "TrainEnd")
	folder:SetAttribute(PATH_START, from)
	folder:SetAttribute(PATH_END, to)
	-- "On" colour of each light kind, published so a client never has to guess
	-- it from a light it may see already dimmed (or streamed in mid-phase).
	for _, name in { "RedLight", "GreenLight" } do
		local light = folder:FindFirstChild(name, true)
		if light and light:IsA("BasePart") then
			folder:SetAttribute(name, light.Color)
		end
	end
	local model = template()
	local pivot = model:GetPivot()
	local box, size = model:GetBoundingBox()
	local boxOffset = pivot:ToObjectSpace(box)

	local hitbox = Instance.new("Part")
	hitbox.Name = "TrainHitbox"
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.Transparency = 1
	hitbox.Size = size
	CollectionService:AddTag(hitbox, TagNames.KillPart)

	local heartbeat = RunService.Heartbeat:Connect(function()
		local alpha = progress(Workspace:GetServerTimeNow())
		if alpha then
			hitbox.CFrame = pivotAt(from, to, pivot.Rotation, alpha) * boxOffset
			if hitbox.Parent ~= folder then
				hitbox.Parent = folder
			end
		elseif hitbox.Parent then
			hitbox.Parent = nil
		end
	end)
	return function()
		heartbeat:Disconnect()
		hitbox:Destroy()
	end
end

--- Clones the train sounds onto an attachment at the train's centre.
local function addSounds(train: Model): { Sound }
	local library =
		ReplicatedStorage:WaitForChild("Assets"):WaitForChild("sfx"):FindFirstChild("Traps")
	local part = train:FindFirstChildWhichIsA("BasePart", true)
	if not (library and part) then
		return {}
	end
	local centre = Instance.new("Attachment")
	centre.Name = "SoundCentre"
	centre.Parent = part
	centre.WorldPosition = train:GetBoundingBox().Position
	local sounds = {}
	for _, name in SOUNDS do
		local source = library:FindFirstChild(name)
		if source and source:IsA("Sound") then
			local sound = source:Clone()
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = SOUND_MIN_DISTANCE
			sound.RollOffMaxDistance = SOUND_MAX_DISTANCE
			sound.Parent = centre
			table.insert(sounds, sound)
		end
	end
	return sounds
end

function Train.Client(folder: Instance, env: { SoundEnabled: (() -> boolean)? }): () -> ()
	local from, to = publishedPath(folder)
	local train = template():Clone()
	local rotation = train:GetPivot().Rotation
	for _, part in train:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local sounds = addSounds(train)
	local soundEnabled = env.SoundEnabled

	-- Lights stream in and out: looked up at each switch, their "on" colour
	-- read the first time each one is seen.
	-- Weak keys: a light that streamed out is dropped with its instance.
	local onColor: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
	local function setLights(red: boolean): ()
		for _, light in folder:GetDescendants() do
			if
				light:IsA("BasePart") and (light.Name == "RedLight" or light.Name == "GreenLight")
			then
				local published = folder:GetAttribute(light.Name)
				onColor[light] = onColor[light]
					or (if typeof(published) == "Color3" then published else light.Color)
				local lit = (light.Name == "RedLight") == red
				light.Color = if lit then onColor[light] else LIGHT_OFF
			end
		end
	end

	local red: boolean? = nil
	local lastRefresh = 0
	-- A light streaming in mid-phase takes the current colour right away.
	local lateLights = folder.DescendantAdded:Connect(function(descendant: Instance)
		if red ~= nil and (descendant.Name == "RedLight" or descendant.Name == "GreenLight") then
			setLights(red)
		end
	end)
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		local alpha = progress(now)
		if alpha then
			train:PivotTo(pivotAt(from, to, rotation, alpha))
			if not train.Parent then
				train.Parent = Workspace
				if not soundEnabled or soundEnabled() then
					for _, sound in sounds do
						sound:Play()
					end
				end
			end
		elseif train.Parent then
			train.Parent = nil
		end
		-- Re-applied every LIGHT_REFRESH too, not only on a phase change: a
		-- light that streamed in without DescendantAdded reaching us, or was
		-- reset by a streaming round trip, still ends up right.
		local nowRed = isRed(now)
		if nowRed ~= red or now - lastRefresh >= LIGHT_REFRESH then
			red = nowRed
			lastRefresh = now
			setLights(nowRed)
		end
	end)
	return function()
		heartbeat:Disconnect()
		lateLights:Disconnect()
		train:Destroy()
	end
end

return Train
