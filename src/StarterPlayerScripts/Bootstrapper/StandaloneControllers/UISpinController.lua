--!strict
--[[
	@module UISpinController
	@description Animates forever every UI instance flagged with the boolean
	attribute `Spin` (UISpinConfig.Attribute) -- the only thing set in Studio,
	under StarterGui. Speeds are code-side (Config/UISpinConfig, by ClassName).

	  - UIGradient: the authored ColorSequence is treated as a closed loop
	    (last color blends back into the first) and scrolled by shifting its
	    phase. This replaces rotating the gradient, which distorts on
	    non-square frames.
	  - Everything else with a `Rotation` (ImageLabel...): spins in place.

	Instances are picked up as soon as they appear in PlayerGui. One cosmetic
	Scheduler task for the whole UI; the animation is derived from the clock
	(stateless), so every instance stays in sync and a missed tick never drifts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scheduler = require(ReplicatedStorage.Libraries.Scheduler)
local Bootstrapper = script.Parent.Parent
local UISpinConfig = require(Bootstrapper.Config.UISpinConfig)

type Spinner = {
	Gradient: UIGradient?, -- set = scrolling gradient, nil = plain rotation
	Speed: number, -- deg/s (rotation) or cycles/s (gradient)
	Times: { number }, -- gradient: keypoint times squeezed to leave room for the wrap segment
	Colors: { Color3 },
	Wrap: number, -- gradient: width of the last -> first blend (0 if already a loop)
}

local UISpinController = {}

local spinners: { [Instance]: Spinner } = {}

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
end

--- Color of the closed-loop ramp at `u` in [0, 1).
local function sampleLoop(spinner: Spinner, u: number): Color3
	local times, colors = spinner.Times, spinner.Colors
	local count = #times
	if u >= times[count] then
		-- wrap segment: last color -> first color
		if spinner.Wrap <= 0 then
			return colors[count]
		end
		return colors[count]:Lerp(colors[1], (u - times[count]) / spinner.Wrap)
	end
	for i = 1, count - 1 do
		local t0, t1 = times[i], times[i + 1]
		if u >= t0 and u <= t1 then
			local span = t1 - t0
			return if span <= 0 then colors[i + 1] else colors[i]:Lerp(colors[i + 1], (u - t0) / span)
		end
	end
	return colors[1]
end

local function makeGradientSpinner(gradient: UIGradient): Spinner
	local keypoints = gradient.Color.Keypoints
	local count = #keypoints
	local first, last = keypoints[1].Value, keypoints[count].Value
	local wrap = if sameColor(first, last) then 0 else 1 / count
	local times, colors = {}, {}
	for i, keypoint in keypoints do
		times[i] = keypoint.Time * (1 - wrap)
		colors[i] = keypoint.Value
	end
	return {
		Gradient = gradient,
		Speed = UISpinConfig.GradientCyclesPerSecond,
		Times = times,
		Colors = colors,
		Wrap = wrap,
	}
end

local function track(instance: Instance): ()
	if instance:GetAttribute(UISpinConfig.Attribute) ~= true then
		return
	end
	if instance:IsA("UIGradient") then
		spinners[instance] = makeGradientSpinner(instance)
	else
		spinners[instance] = {
			Gradient = nil,
			Speed = UISpinConfig.SpeedByClass[instance.ClassName] or UISpinConfig.DefaultDegreesPerSecond,
			Times = {},
			Colors = {},
			Wrap = 0,
		}
	end
end

local function step(now: number): ()
	local samples = UISpinConfig.GradientSamples
	for instance, spinner in spinners do
		local gradient = spinner.Gradient
		if gradient then
			local phase = (now * spinner.Speed) % 1
			local keypoints = table.create(samples)
			for i = 0, samples - 1 do
				local position = i / (samples - 1)
				keypoints[i + 1] = ColorSequenceKeypoint.new(position, sampleLoop(spinner, (position - phase) % 1))
			end
			gradient.Color = ColorSequence.new(keypoints)
		else
			(instance :: any).Rotation = (now * spinner.Speed) % 360
		end
	end
end

function UISpinController:Init(): () end

function UISpinController:Start(): ()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, descendant in playerGui:GetDescendants() do
		track(descendant)
	end
	playerGui.DescendantAdded:Connect(track)
	playerGui.DescendantRemoving:Connect(function(instance: Instance)
		spinners[instance] = nil
	end)

	Scheduler.Every("UISpin", UISpinConfig.TickHz, function()
		step(os.clock())
	end, true)
end

return UISpinController
