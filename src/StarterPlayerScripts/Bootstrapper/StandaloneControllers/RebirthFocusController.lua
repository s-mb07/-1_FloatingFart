--!strict
--[[
	@module RebirthFocusController
	@description One-time "focus" teaching the first rebirth: the whole
	screen dims except a rectangle around one button.
	  1. The first time the player CAN rebirth (0 rebirths, level >= rebirth
	     #1's requirement, tutorial finished), the focus lands on the HUD
	     button MainHUD/LeftHUD/Rebirth.
	  2. Once the Rebirth panel opens, it moves to the panel's own button
	     (RebirthUI/MainFrame/Container/RebirthBtn).
	  3. It disappears when that button is clicked, or FocusSeconds after the
	     panel opened if the player only looks.
	Shown once ever: NetworkEvents "RebirthFocusShown" is sent as soon as it
	starts, and TutorialService saves it (Tutorial.RebirthFocusShown).
	The dim frames never sink input -- the highlighted button stays clickable.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)
local RebirthConfig = require(ReplicatedStorage.Config.RebirthConfig)
local TutorialConfig = require(ReplicatedStorage.Config.TutorialConfig)
local Bootstrapper = script.Parent.Parent
local EventBus = require(Bootstrapper.Events.EventBus)
local PlayerDataFetcher = require(Bootstrapper.Events.PlayerDataFetcher)
local SafeUIResolver = require(Bootstrapper.Libraries.SafeUIResolver)

local Children = Fusion.Children

local RebirthFocusController = {}

local LocalPlayer = Players.LocalPlayer

--- Seconds the panel-button focus stays if the player doesn't click.
local FOCUS_SECONDS = 5
--- Extra pixels around the highlighted button.
local PADDING = 8
local DIM_TRANSPARENCY = 0.45
--- How far the Top dim frame reaches above the inset line (covers the top bar).
local TOPBAR_COVER = 200

local state = {
	stage = 1,
	focusShown = true, -- assume shown until real data says otherwise
	level = 1,
	rebirths = 0,
}
local running = false

--- Builds the four dim frames + outline; returns (update(target), destroy()).
local function buildOverlay(): ((GuiObject) -> (), () -> ())
	local scope = Fusion.scoped(Fusion)
	local rectPos = scope:Value(Vector2.zero)
	local rectSize = scope:Value(Vector2.zero)

	local function dim(name: string, position: any, size: any): Instance
		return scope:New("Frame")({
			Name = name,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = DIM_TRANSPARENCY,
			BorderSizePixel = 0,
			Active = false,
			Interactable = false, -- never steals clicks from the highlighted button
			Position = position,
			Size = size,
		})
	end

	local function top(use: Fusion.Use): number
		return (use(rectPos) :: Vector2).Y
	end
	local function bottom(use: Fusion.Use): number
		return (use(rectPos) :: Vector2).Y + (use(rectSize) :: Vector2).Y
	end

	scope:New("ScreenGui")({
		Name = "RebirthFocus",
		ResetOnSpawn = false,
		-- AbsolutePosition is measured below the top-bar inset (even for
		-- IgnoreGuiInset guis), so the overlay lives in that same space; the
		-- Top frame reaches up under the top bar to dim it too.
		IgnoreGuiInset = false,
		DisplayOrder = 10, -- above every panel
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = {
			dim(
				"Top",
				UDim2.fromOffset(0, -TOPBAR_COVER),
				scope:Computed(function(use)
					return UDim2.new(1, 0, 0, top(use) + TOPBAR_COVER)
				end)
			),
			dim(
				"Bottom",
				scope:Computed(function(use)
					return UDim2.fromOffset(0, bottom(use))
				end),
				UDim2.fromScale(1, 1)
			),
			dim(
				"Left",
				scope:Computed(function(use)
					return UDim2.fromOffset(0, top(use))
				end),
				scope:Computed(function(use)
					return UDim2.fromOffset(
						(use(rectPos) :: Vector2).X,
						(use(rectSize) :: Vector2).Y
					)
				end)
			),
			dim(
				"Right",
				scope:Computed(function(use)
					local p, s = use(rectPos) :: Vector2, use(rectSize) :: Vector2
					return UDim2.fromOffset(p.X + s.X, p.Y)
				end),
				scope:Computed(function(use)
					return UDim2.new(1, 0, 0, (use(rectSize) :: Vector2).Y)
				end)
			),
			scope:New("Frame")({
				Name = "Outline",
				BackgroundTransparency = 1,
				Interactable = false,
				Position = scope:Computed(function(use)
					local p = use(rectPos) :: Vector2
					return UDim2.fromOffset(p.X, p.Y)
				end),
				Size = scope:Computed(function(use)
					local s = use(rectSize) :: Vector2
					return UDim2.fromOffset(s.X, s.Y)
				end),
				[Children] = {
					scope:New("UIStroke")({ Color = Color3.new(1, 1, 1), Thickness = 3 }),
					scope:New("UICorner")({ CornerRadius = UDim.new(0, 10) }),
				},
			}),
		},
	})

	local function update(target: GuiObject): ()
		-- Whole pixels: fractional edges leave a 1px seam between the dim frames.
		local p = target.AbsolutePosition - Vector2.new(PADDING, PADDING)
		local s = target.AbsoluteSize + Vector2.new(PADDING * 2, PADDING * 2)
		rectPos:set(Vector2.new(math.floor(p.X), math.floor(p.Y)))
		rectSize:set(Vector2.new(math.ceil(s.X), math.ceil(s.Y)))
	end
	local function destroy(): ()
		scope:doCleanup()
	end
	return update, destroy
end

local function run(): ()
	running = true
	NetworkEvents.FireServer("RebirthFocusShown")

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local hudButton: GuiObject? = nil
	local panel: GuiObject? = nil
	local panelButton: GuiButton? = nil
	SafeUIResolver.WaitForPathStringAsync(playerGui, "MainHUD/LeftHUD/Rebirth", function(button)
		hudButton = button :: GuiObject
	end)
	SafeUIResolver.WaitForPathStringAsync(playerGui, "RebirthUI/MainFrame", function(frame)
		panel = frame :: GuiObject
		panelButton = frame:WaitForChild("Container"):WaitForChild("RebirthBtn") :: GuiButton
	end)

	local update, destroy = buildOverlay()
	local panelOpenedAt: number? = nil
	local clicked = false
	local clickConn: RBXScriptConnection? = nil

	local stepConn: RBXScriptConnection
	stepConn = RunService.RenderStepped:Connect(function()
		local onPanel = panel ~= nil and (panel :: GuiObject).Visible and panelButton ~= nil
		if onPanel and not panelOpenedAt then
			panelOpenedAt = os.clock()
			clickConn = (panelButton :: GuiButton).Activated:Connect(function()
				clicked = true
			end)
		end
		local expired = panelOpenedAt ~= nil and os.clock() - panelOpenedAt >= FOCUS_SECONDS
		if clicked or expired then
			stepConn:Disconnect()
			if clickConn then
				clickConn:Disconnect()
			end
			destroy()
			return
		end
		local target = if onPanel then panelButton else hudButton
		if target then
			update(target :: GuiObject)
		end
	end)
end

local function check(): ()
	if running or state.focusShown or state.rebirths > 0 then
		return
	end
	if state.stage < TutorialConfig.GetFinishedStage() then
		return -- never on top of the tutorial
	end
	if state.level >= RebirthConfig.GetRequiredLevel(1) then
		run()
	end
end

local function absorb(data: any): ()
	if type(data) ~= "table" then
		return
	end
	local tutorial = data.Tutorial
	if type(tutorial) == "table" then
		state.stage = tonumber(tutorial.Stage) or state.stage
		state.focusShown = tutorial.RebirthFocusShown == true
	end
	local traversal = data.Traversal
	if type(traversal) == "table" then
		state.level = tonumber(traversal.Level) or state.level
		state.rebirths = tonumber(traversal.Rebirths) or state.rebirths
	end
	check()
end

function RebirthFocusController:Init(): ()
	PlayerDataFetcher.OnReady(absorb)
	EventBus.Data.Updated:Connect(absorb)
end

function RebirthFocusController:Start(): () end

return RebirthFocusController
