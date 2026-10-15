--!strict
--[[
	@module MobileLaunchController
	@description Wires the Studio-authored FLY / STOP button
	(PlayerGui/MainHUD/FlyBtn) for touch devices. Phones and tablets have
	neither Space nor a mouse click, so without it they could never fly. A tap
	does exactly what Space does: ProbeController.Trigger() (launch, or stop the
	current flight); the server validates as always.

	Hidden on every device without a touchscreen. While the local player flies
	(EventBus.Traversal.Started / Stopped) the `Stop` gradient is enabled and the
	text reads "Stop"; otherwise the `Start` gradient and "Fly". Studio names
	used: FlyBtn (TextButton), FlyBtn.Start / FlyBtn.Stop (UIGradient),
	FlyBtn.Text (TextLabel) and its TextStroke child (TextLabel).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)
local UXEffects = require(Bootstrapper.Libraries.UXEffects)
local ProbeController = require(script.Parent.ProbeController)

local MobileLaunchController = {}

local LocalPlayer = Players.LocalPlayer
local BUTTON_PATH = "MainHUD/FlyBtn"

--- Shows the Start (fly) or Stop look of the button.
local function render(button: GuiButton, flying: boolean): ()
	local start = button:FindFirstChild("Start")
	local stop = button:FindFirstChild("Stop")
	if start and start:IsA("UIGradient") then
		start.Enabled = not flying
	end
	if stop and stop:IsA("UIGradient") then
		stop.Enabled = flying
	end
	local label = button:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		local text = if flying then "Stop" else "Fly"
		label.Text = text
		local stroke = label:FindFirstChild("TextStroke")
		if stroke and stroke:IsA("TextLabel") then
			stroke.Text = text
		end
	end
end

function MobileLaunchController:Init(): () end

function MobileLaunchController:Start(): ()
	SafeUIResolver.WaitForPathStringAsync(
		LocalPlayer:WaitForChild("PlayerGui"),
		BUTTON_PATH,
		function(instance: Instance)
			if not instance:IsA("GuiButton") then
				return
			end
			local button = instance
			button.Visible = UserInputService.TouchEnabled
			if not button.Visible then
				return
			end

			render(button, ProbeController.IsFlying())
			UXEffects.ButtonFX.attach(button, { hoverScale = 1, pressScale = 0.88 })
			button.Activated:Connect(function()
				ProbeController.Trigger()
			end)
			EventBus.Traversal.Started:Connect(function(player: Player)
				if player == LocalPlayer then
					render(button, true)
				end
			end)
			EventBus.Traversal.Stopped:Connect(function(player: Player)
				if player == LocalPlayer then
					render(button, false)
				end
			end)
		end
	)
end

return MobileLaunchController
