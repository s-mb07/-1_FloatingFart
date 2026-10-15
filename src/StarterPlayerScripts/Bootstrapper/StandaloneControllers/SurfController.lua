--!strict
--[[
	@module SurfController
	@description Purely cosmetic surf look of every player training on a fan
	(player attribute TreadmillConfig.TrainingAttribute set by the server):
	the body rides the "waves" (swell, roll, carve) and, depending on the fan
	(Config/SurfConfig), throws tricks between waves -- none on the classic
	fan, ollies on the next one, spins, kickflips, flips on the best ones.

	The motion is an offset on the R15 `LowerTorso.Root` joint, layered over
	the FlyIdle pose the server plays (TreadmillService): the whole body and
	the Fly model on its back move together, nothing touches physics. The
	joint is a Motor6D (offset on its C0) on classic rigs, or an
	AnimationConstraint (offset on its Attachment0, the same frame) with the
	upgraded avatar joints. The edit does not replicate, so every client
	animates every training player itself -- the attribute is all it needs.
	The joint gets its original frame back the moment the session ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local SurfConfig = require(script.Parent.Parent.Config.SurfConfig)
local TreadmillConfig = require(ReplicatedStorage.Config.TreadmillConfig)

local log = Logger.new("SurfController")
local SurfController = {}

local TAU = 2 * math.pi

type Ride = {
	--- Motor6D (C0) or the AnimationConstraint's Attachment0 (CFrame).
	Joint: Motor6D | Attachment,
	Base: CFrame,
	Surf: SurfConfig.FanSurf,
	--- Seconds into the ride when the next trick starts.
	NextTrick: number,
	Trick: SurfConfig.TrickName?,
	TrickStart: number,
	Started: number,
	--- Random wave phase so players side by side don't move in sync.
	Phase: number,
}

local rides: { [Player]: Ride } = {}

local function ease(p: number): number
	return p * p * (3 - 2 * p) -- smoothstep
end

-- Each trick: progress 0..1 -> rotation (the jump height is added on top).
local TRICKS: { [SurfConfig.TrickName]: (p: number) -> CFrame } = {
	Ollie = function(p: number): CFrame
		return CFrame.Angles(math.rad(20) * math.sin(math.pi * p), 0, 0)
	end,
	Spin = function(p: number): CFrame
		return CFrame.Angles(0, TAU * ease(p), 0)
	end,
	Kickflip = function(p: number): CFrame
		return CFrame.Angles(0, 0, TAU * ease(p))
	end,
	Backflip = function(p: number): CFrame
		return CFrame.Angles(TAU * ease(p), 0, 0)
	end,
	Cork = function(p: number): CFrame
		local e = ease(p)
		return CFrame.Angles(0, TAU * e, 0) * CFrame.Angles(TAU * e, 0, 0)
	end,
	Spin720 = function(p: number): CFrame
		return CFrame.Angles(0, 2 * TAU * ease(p), 0)
	end,
}

local function setFrame(joint: Motor6D | Attachment, frame: CFrame): ()
	if joint:IsA("Motor6D") then
		joint.C0 = frame
	else
		joint.CFrame = frame
	end
end

--- The R15 root joint's parent-side frame: a Motor6D, or the Attachment0 of
--- an AnimationConstraint (upgraded avatar joints).
local function findJoint(character: Model?): (Motor6D | Attachment)?
	local lowerTorso = character and character:FindFirstChild("LowerTorso")
	local root = lowerTorso and lowerTorso:FindFirstChild("Root")
	if root and root:IsA("Motor6D") then
		return root
	elseif root and root:IsA("AnimationConstraint") then
		return root.Attachment0
	end
	return nil
end

local function stopRide(player: Player): ()
	local ride = rides[player]
	rides[player] = nil
	if ride and ride.Joint.Parent then
		setFrame(ride.Joint, ride.Base)
	end
end

local function startRide(player: Player, fanId: string): ()
	local surf = SurfConfig.Fans[fanId]
	local joint = findJoint(player.Character)
	if not (surf and joint) then
		log:Debug("%s: no surf (fan %s, joint %s).", player.Name, fanId, tostring(joint))
		return
	end
	local now = os.clock()
	rides[player] = {
		Joint = joint,
		Base = if joint:IsA("Motor6D") then joint.C0 else joint.CFrame,
		Surf = surf,
		NextTrick = surf.TrickEvery * 0.5,
		Trick = nil,
		TrickStart = 0,
		Started = now,
		Phase = math.random() * TAU,
	}
end

local function step(): ()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local fanId = player:GetAttribute(TreadmillConfig.TrainingAttribute)
		local ride = rides[player]
		if ride and (type(fanId) ~= "string" or not ride.Joint:IsDescendantOf(workspace)) then
			stopRide(player)
			ride = nil
		end
		if not ride and type(fanId) == "string" then
			startRide(player, fanId)
			ride = rides[player]
		end
		if not ride then
			continue
		end

		local t = now - ride.Started
		local wave = SurfConfig.Wave
		local a = TAU * t / wave.Period + ride.Phase
		local offset = CFrame.new(0, wave.Bob * math.sin(a), 0)
			* CFrame.Angles(
				math.rad(wave.Pitch) * math.sin(a + 1),
				math.rad(wave.Carve) * math.sin(a * 0.5),
				math.rad(wave.Roll) * math.sin(a * 0.5 + 0.8)
			)

		local surf = ride.Surf
		if not ride.Trick and t >= ride.NextTrick and #surf.Tricks > 0 then
			ride.Trick = surf.Tricks[math.random(#surf.Tricks)]
			ride.TrickStart = t
			ride.NextTrick = t + surf.TrickEvery
		end
		local trick = ride.Trick
		if trick then
			local p = (t - ride.TrickStart) / surf.TrickSeconds
			if p >= 1 then
				ride.Trick = nil
			else
				-- Jump straight up out of the wave, rotate, land back on it.
				offset = CFrame.new(0, SurfConfig.TrickHeight * math.sin(math.pi * p), 0)
					* offset
					* TRICKS[trick](p)
			end
		end
		setFrame(ride.Joint, ride.Base * offset)
	end
end

function SurfController:Init(): ()
	Players.PlayerRemoving:Connect(stopRide)
	log:Info("Initialized.")
end

function SurfController:Start(): ()
	RunService.RenderStepped:Connect(step)
	log:Info("Started.")
end

return SurfController
