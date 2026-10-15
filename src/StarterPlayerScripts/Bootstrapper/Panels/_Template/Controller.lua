--!strict
--[[
	@module Panels._Template.Controller
	@description Copy this FOLDER (Config.lua + Controller.lua) to scaffold a
	new Fusion-built panel -- rename both files' module references and the
	panelId you register it under. Demonstrates the full contract from
	README.md §6: `Init(deps)` opens a Fusion scope and builds `Root`,
	`Destroy()` calls `scope:doCleanup()`. Not registered in `Panels/init.lua`
	by default -- see that file's own comment next to `registerPanel("Settings", ...)`.

	`Root` is a `Frame` (a `GuiObject`, per `PanelDefinition.lua`), NOT the
	`ScreenGui` -- `Navigation.PanelTransition` animates `Root` directly, so
	it must be the actual visible surface. The `ScreenGui` around it is a
	permanent, always-enabled container (same Studio-authored ScreenGui/
	Container split `Panels/Settings` uses, just built in code here instead
	of by hand in Studio).

	The click counter below (a `scope:Value` + a `scope:Computed` derived
	from it) exists to prove the reactive wiring works end to end -- delete
	it along with everything else once you're building real content.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local peek = Fusion.peek

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Template = {}
Template.__index = Template

Template.Config = require(script.Parent.Config)

export type Template = typeof(setmetatable(
	{} :: {
		Root: Frame?,
		Config: typeof(Template.Config),
		_deps: any,
		_scope: Fusion.Scope<typeof(Fusion)>?,
		_screenGui: ScreenGui?,
	},
	Template
))

function Template.new(): Template
	return setmetatable({
		Root = nil,
		Config = Template.Config,
		_deps = nil,
		_scope = nil,
		_screenGui = nil,
	}, Template) :: any
end

function Template.Init(self: Template, deps: any): ()
	self._deps = deps

	local scope = Fusion.scoped(Fusion)
	self._scope = scope

	local clickCount = scope:Value(0)
	local clickLabelText = scope:Computed(function(use)
		return `Clicked {use(clickCount)} times`
	end)

	local rootFrame = scope:New "Frame" {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 220),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		Visible = false,
		[Children] = {
			scope:New "UICorner" {
				CornerRadius = UDim.new(0, 8),
			},
			scope:New "TextLabel" {
				Name = "ClickLabel",
				Text = clickLabelText,
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.fromOffset(0, 20),
				BackgroundTransparency = 1,
				TextColor3 = Color3.new(1, 1, 1),
			},
			scope:New "TextButton" {
				Name = "ClickButton",
				Text = "Click me",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 80),
				Size = UDim2.fromOffset(140, 36),
				[OnEvent "Activated"] = function()
					clickCount:set(peek(clickCount) + 1)
				end,
			},
			scope:New "TextButton" {
				Name = "CloseButton",
				Text = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 10),
				Size = UDim2.fromOffset(60, 28),
				[OnEvent "Activated"] = function()
					(self._deps.Navigation :: any).Pop()
				end,
			},
		},
	}

	local screenGui = scope:New "ScreenGui" {
		Name = "_Template",
		ResetOnSpawn = false,
		Parent = playerGui,
		[Children] = rootFrame,
	}

	self._screenGui = screenGui
	self.Root = rootFrame
end

--- Non-KeepAlive (see Config.lua): Init() reruns on every push, so there's
--- nothing left for Activate() to (re)populate.
function Template.Activate(_self: Template): () end

function Template.Deactivate(_self: Template): () end

--- Tears down the whole Fusion scope in one call -- every instance, Value,
--- and Computed created under it during Init() is destroyed/disconnected.
function Template.Destroy(self: Template): ()
	if self._scope then
		self._scope:doCleanup()
	end
	self._scope = nil
	self.Root = nil
	self._screenGui = nil
end

return Template
