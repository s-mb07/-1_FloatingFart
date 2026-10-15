--!strict
--[[
	@module Traps.Drone
	@description Stage 8 drone trap, on the Part tagged TagNames.DroneTrap
	(`ZoneSpawnDrone`: the volume the drones live in). One drone of each model in
	ReplicatedStorage.Assets.Trap.Stage_8.Drones is spawned at a random free spot
	of the zone.

	Every MOVE_EVERY s ONE drone (never the same twice in a row) slides STEP
	studs along a random axis direction (up/down/left/right/forward/back) in
	MOVE_TIME s, only if its whole sweep stays inside the zone and clear of every
	other drone. Touched by a player a drone explodes (visual only) and comes
	back RESPAWN_DELAY s later at a random free spot, popping in from scale 0.001.

	The server owns everything that matters, the client only draws:
	  - Server: per drone, a Folder under Workspace.Stage8Drones holding its state
	    as attributes (Model, From, To, T0, Alive) and an invisible
	    TagNames.KillPart box (LifeService / the probe do the killing), parented
	    only while the drone is alive. A 10 Hz overlap query vs player characters
	    triggers the explosion.
	  - Client: a local clone per drone, positioned each frame from From/To/T0 on
	    the synced server clock (no remote, no per-frame replication of the
	    model), explosion + pop-in on the Alive flip.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local TagNames = require(ReplicatedStorage.Config.AssetIds.TagNames)

local MOVE_EVERY = 0.3
--- A slide outlasts the tick: several drifting drones at once, none overlapping.
local MOVE_TIME = 1.2
local STEP = 10
local MARGIN = 1
local HIT_HZ = 20
local RESPAWN_DELAY = 3
local RESPAWN_RETRY = 0.5
local SPAWN_TRIES = 30
--- The kill box outlives the explosion a little so the touch that triggered it
--- still kills (LifeService polls at 10 Hz).
local HITBOX_GRACE = 0.4
local POP_TIME = 0.4
local POP_FROM = 0.001
--- Explosion template (Assets/Trap/Stage_8/Explosion): a Part holding
--- ParticleEmitters (attribute EmitCount = particles per burst, default 20) and
--- Sounds, all editable in Studio. Cloned per explosion, removed after the delay.
local EXPLOSION_TEMPLATE = "Explosion"
local EXPLOSION_DEFAULT_EMIT = 20
local EXPLOSION_LIFETIME = 4
--- Attribute the probe stamps on a kill part the plane hit (ProbeService).
local TOUCHED_ATTRIBUTE = "TouchedAt"

local CONTAINER = "Stage8Drones"
local DIRECTIONS =
	{ Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

local Drone = { Tag = TagNames.DroneTrap }

type Shape = {
	size: Vector3,
	--- World-aligned half extents of the box (what collisions use).
	half: Vector3,
	rotation: CFrame,
	pivotInBox: CFrame,
}

local shapes: { [string]: Shape } = {}

local function stage8(): Folder
	local assets = ReplicatedStorage:WaitForChild("Assets")
	return assets:WaitForChild("Trap"):WaitForChild("Stage_8") :: Folder
end

local function templates(): Folder
	return stage8():WaitForChild("Drones") :: Folder
end

--- World-aligned half extents of a box of `size` rotated by `cf`.
local function alignedHalf(cf: CFrame, size: Vector3): Vector3
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
		math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
		math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	) / 2
end

local function shapeOf(name: string): Shape
	local cached = shapes[name]
	if cached then
		return cached
	end
	local model = templates():WaitForChild(name) :: Model
	local box, size = model:GetBoundingBox()
	local shape: Shape = {
		size = size,
		half = alignedHalf(box, size),
		rotation = box.Rotation,
		pivotInBox = box:ToObjectSpace(model:GetPivot()),
	}
	shapes[name] = shape
	return shape
end

--- Box centre `pos` -> the CFrame of the kill box / the model's pivot.
local function boxCFrame(shape: Shape, pos: Vector3): CFrame
	return CFrame.new(pos) * shape.rotation
end

local function pivotCFrame(shape: Shape, pos: Vector3): CFrame
	return boxCFrame(shape, pos) * shape.pivotInBox
end

--- Where a drone is at server time `now` on its From -> To slide.
local function positionAt(from: Vector3, to: Vector3, t0: number, now: number): Vector3
	return from:Lerp(to, math.clamp((now - t0) / MOVE_TIME, 0, 1))
end

--============================================================================--
-- SERVER
--============================================================================--

type Slot = {
	name: string,
	shape: Shape,
	folder: Folder,
	hitbox: Part,
	alive: boolean,
	from: Vector3,
	to: Vector3,
	t0: number,
}

local function overlaps(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3): boolean
	return minA.X < maxB.X + MARGIN
		and maxA.X > minB.X - MARGIN
		and minA.Y < maxB.Y + MARGIN
		and maxA.Y > minB.Y - MARGIN
		and minA.Z < maxB.Z + MARGIN
		and maxA.Z > minB.Z - MARGIN
end

--- Volume a drone claims: its whole current slide (or its resting box).
local function claimed(slot: Slot, now: number): (Vector3, Vector3)
	local half = slot.shape.half
	local from = if now < slot.t0 + MOVE_TIME then slot.from else slot.to
	return from:Min(slot.to) - half, from:Max(slot.to) + half
end

function Drone.Server(zone: Instance): () -> ()
	local part = zone :: BasePart
	local zoneHalf = alignedHalf(part.CFrame, part.Size)
	local zoneMin, zoneMax = part.Position - zoneHalf, part.Position + zoneHalf
	local rng = Random.new()

	local container = Instance.new("Folder")
	container.Name = CONTAINER

	local slots: { Slot } = {}
	for _, model in templates():GetChildren() do
		local shape = shapeOf(model.Name)
		local folder = Instance.new("Folder")
		folder.Name = model.Name
		folder:SetAttribute("Model", model.Name)
		folder:SetAttribute("Alive", false)

		local hitbox = Instance.new("Part")
		hitbox.Name = "Hitbox"
		hitbox.Anchored = true
		hitbox.CanCollide = false
		hitbox.CanTouch = false
		hitbox.Transparency = 1
		hitbox.Size = shape.size
		CollectionService:AddTag(hitbox, TagNames.KillPart)

		table.insert(slots, {
			name = model.Name,
			shape = shape,
			folder = folder,
			hitbox = hitbox,
			alive = false,
			from = Vector3.zero,
			to = Vector3.zero,
			t0 = 0,
		})
		folder.Parent = container
	end

	local stopped = false
	local last: Slot? = nil

	--- True if the box [lo, hi] is inside the zone and clear of every other drone.
	local function isFree(self: Slot, lo: Vector3, hi: Vector3, now: number): boolean
		if lo.X < zoneMin.X or lo.Y < zoneMin.Y or lo.Z < zoneMin.Z then
			return false
		end
		if hi.X > zoneMax.X or hi.Y > zoneMax.Y or hi.Z > zoneMax.Z then
			return false
		end
		for _, other in slots do
			if other ~= self and other.alive then
				local otherLo, otherHi = claimed(other, now)
				if overlaps(lo, hi, otherLo, otherHi) then
					return false
				end
			end
		end
		return true
	end

	local function randomSpot(slot: Slot, now: number): Vector3?
		local half = slot.shape.half
		local lo, hi = zoneMin + half, zoneMax - half
		if lo.X > hi.X or lo.Y > hi.Y or lo.Z > hi.Z then
			return nil
		end
		for _ = 1, SPAWN_TRIES do
			local pos = Vector3.new(
				rng:NextNumber(lo.X, hi.X),
				rng:NextNumber(lo.Y, hi.Y),
				rng:NextNumber(lo.Z, hi.Z)
			)
			if isFree(slot, pos - half, pos + half, now) then
				return pos
			end
		end
		return nil
	end

	local function spawn(slot: Slot): boolean
		if stopped or slot.alive then
			return true
		end
		local now = Workspace:GetServerTimeNow()
		local pos = randomSpot(slot, now)
		if not pos then
			return false
		end
		slot.from, slot.to, slot.t0, slot.alive = pos, pos, now, true
		slot.hitbox.CFrame = boxCFrame(slot.shape, pos)
		slot.hitbox.Parent = slot.folder
		slot.folder:SetAttribute("From", pos)
		slot.folder:SetAttribute("To", pos)
		slot.folder:SetAttribute("T0", now)
		slot.folder:SetAttribute("Alive", true)
		return true
	end

	local function respawn(slot: Slot): ()
		if not spawn(slot) and not stopped then
			task.delay(RESPAWN_RETRY, respawn, slot)
		end
	end

	local function explode(slot: Slot): ()
		slot.alive = false
		slot.folder:SetAttribute("Alive", false)
		task.delay(HITBOX_GRACE, function()
			if not slot.alive then
				slot.hitbox.Parent = nil
			end
		end)
		task.delay(RESPAWN_DELAY, respawn, slot)
	end

	-- The plane (probe flight) reports its hit on the kill part: explode at once,
	-- no waiting for the next overlap tick.
	for _, slot in slots do
		slot.hitbox:GetAttributeChangedSignal(TOUCHED_ATTRIBUTE):Connect(function()
			if slot.alive then
				explode(slot)
			end
		end)
	end

	-- First wave: every drone, in a clear spot (retried like a respawn if the zone is full).
	for _, slot in slots do
		respawn(slot)
	end
	container.Parent = Workspace

	local function shuffle<T>(list: { T }): ()
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end

	local candidates: { Slot } = {}
	local directions = table.clone(DIRECTIONS)
	local function moveOne(): ()
		local now = Workspace:GetServerTimeNow()
		table.clear(candidates)
		for _, slot in slots do
			if slot.alive and slot ~= last and now >= slot.t0 + MOVE_TIME then
				table.insert(candidates, slot)
			end
		end
		shuffle(candidates)
		for _, slot in candidates do
			shuffle(directions)
			for _, direction in directions do
				local target = slot.to + direction * STEP
				local half = slot.shape.half
				local lo = slot.to:Min(target) - half
				local hi = slot.to:Max(target) + half
				if isFree(slot, lo, hi, now) then
					slot.from, slot.t0, slot.to = slot.to, now, target
					slot.folder:SetAttribute("From", slot.from)
					slot.folder:SetAttribute("To", target)
					slot.folder:SetAttribute("T0", now)
					last = slot
					return
				end
			end
		end
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local characters: { Instance } = {}
	local function checkHits(): ()
		table.clear(characters)
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(characters, player.Character)
			end
		end
		if #characters == 0 then
			return
		end
		overlap.FilterDescendantsInstances = characters
		for _, slot in slots do
			if
				slot.alive
				and #Workspace:GetPartBoundsInBox(slot.hitbox.CFrame, slot.hitbox.Size, overlap) > 0
			then
				explode(slot)
			end
		end
	end

	-- The kill box follows the slide on the server clock (only a moving drone writes).
	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, slot in slots do
			if slot.alive and now < slot.t0 + MOVE_TIME + 0.1 then
				slot.hitbox.CFrame = boxCFrame(slot.shape, positionAt(slot.from, slot.to, slot.t0, now))
			end
		end
	end)
	local mover = Scheduler.Every("Stage8DroneMove", 1 / MOVE_EVERY, moveOne)
	local hits = Scheduler.Every("Stage8DroneHit", HIT_HZ, checkHits)

	return function()
		stopped = true
		heartbeat:Disconnect()
		mover:Disconnect()
		hits:Disconnect()
		container:Destroy()
		for _, slot in slots do
			slot.hitbox:Destroy()
		end
	end
end

--============================================================================--
-- CLIENT
--============================================================================--

type View = {
	folder: Folder,
	model: Model,
	shape: Shape,
	alive: boolean?,
	shownAt: Vector3?,
	popT0: number?,
}

--- Clones the Explosion template at `pos`: bursts every emitter, plays its sounds.
local function explosionAt(pos: Vector3, soundOn: boolean): ()
	local template = stage8():FindFirstChild(EXPLOSION_TEMPLATE)
	if not (template and template:IsA("BasePart")) then
		return
	end
	local fx = template:Clone()
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.CanTouch = false
	fx.CFrame = CFrame.new(pos)
	fx.Parent = Workspace
	for _, descendant in fx:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local count = descendant:GetAttribute("EmitCount")
			descendant:Emit(if type(count) == "number" then count else EXPLOSION_DEFAULT_EMIT)
		elseif descendant:IsA("Sound") and soundOn then
			descendant:Play()
		end
	end
	Debris:AddItem(fx, EXPLOSION_LIFETIME)
end

function Drone.Client(_zone: Instance, env: { SoundEnabled: (() -> boolean)? }): () -> ()
	local container = Workspace:WaitForChild(CONTAINER)
	local views: { [Folder]: View } = {}

	local function add(child: Instance): ()
		local name = child:GetAttribute("Model")
		if not child:IsA("Folder") or type(name) ~= "string" or views[child] then
			return
		end
		local model = (templates():WaitForChild(name) :: Model):Clone()
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
		views[child] = { folder = child, model = model, shape = shapeOf(name) }
	end

	for _, child in container:GetChildren() do
		add(child)
	end
	local added = container.ChildAdded:Connect(add)
	local removed = container.ChildRemoved:Connect(function(child: Instance)
		local view = views[child :: Folder]
		if view then
			view.model:Destroy()
			views[child :: Folder] = nil
		end
	end)

	local function update(view: View, now: number): ()
		local folder = view.folder
		local from, to, t0 = folder:GetAttribute("From"), folder:GetAttribute("To"), folder:GetAttribute("T0")
		local alive = folder:GetAttribute("Alive") == true
			and typeof(from) == "Vector3"
			and typeof(to) == "Vector3"
			and type(t0) == "number"
		if alive ~= view.alive then
			local wasAlive = view.alive
			view.alive = alive
			if alive then
				view.shownAt = nil
				-- Pop in from a point after a respawn; the first sight just appears.
				if wasAlive == false then
					view.model:ScaleTo(POP_FROM)
					view.popT0 = os.clock()
				end
				view.model.Parent = Workspace
			else
				if view.shownAt then
					explosionAt(view.shownAt, not env.SoundEnabled or env.SoundEnabled())
				end
				view.popT0 = nil
				view.model.Parent = nil
			end
		end
		if not alive then
			return
		end
		local pos = positionAt(from :: Vector3, to :: Vector3, t0 :: number, now)
		if pos ~= view.shownAt then
			view.shownAt = pos
			view.model:PivotTo(pivotCFrame(view.shape, pos))
		end
		local popT0 = view.popT0
		if popT0 then
			local t = (os.clock() - popT0) / POP_TIME
			if t >= 1 then
				view.model:ScaleTo(1)
				view.popT0 = nil
			else
				local eased = TweenService:GetValue(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				view.model:ScaleTo(POP_FROM + (1 - POP_FROM) * eased)
			end
		end
	end

	local heartbeat = RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, view in views do
			update(view, now)
		end
	end)

	return function()
		heartbeat:Disconnect()
		added:Disconnect()
		removed:Disconnect()
		for _, view in views do
			view.model:Destroy()
		end
		table.clear(views)
	end
end

return Drone
