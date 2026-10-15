--!strict
--[[
	@module ClaimedButton
	@description The look of a pass/product button once it is owned (or
	maxed): the "Claimed" overlay shown, the button held in its pressed
	scale with no hover (UXEffects.ButtonFX.setPressed), and its spinning
	decor (the SunBurst rays: any GuiObject flagged `Spin`, UISpinConfig)
	hidden. The button stays on screen.

	The overlay is the button's own `ClaimedFrame` (Shop buttons have one,
	authored in Studio). A button without one (the MainHUD boosts) gets a
	clone of the Shop's, rounded with the button's own UICorner.
]]

local Players = game:GetService("Players")

local UISpinConfig = require(script.Parent.Parent.Config.UISpinConfig)
local UXEffects = require(script.Parent.UXEffects)

local OVERLAY_NAME = "ClaimedFrame"
--- The Studio-authored overlay every clone copies.
local TEMPLATE_PATH =
	{ "ShopUI", "MainFrame", "Container", "Container", "PassesFrame", "X2WinsBtn", OVERLAY_NAME }

local ClaimedButton = {}

local function findTemplate(): Instance?
	local node: Instance? = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, name in TEMPLATE_PATH do
		node = if node then node:FindFirstChild(name) else nil
	end
	return node
end

--- Shows `button` as claimed (overlay + held pressed, no hover) or buyable.
--- Safe to call on every render.
--- @param button  GuiButton
--- @param claimed boolean
function ClaimedButton.Set(button: GuiButton, claimed: boolean): ()
	UXEffects.ButtonFX.setPressed(button, claimed)
	for _, descendant in button:GetDescendants() do
		if
			descendant:IsA("GuiObject")
			and descendant:GetAttribute(UISpinConfig.Attribute) == true
		then
			descendant.Visible = not claimed
		end
	end
	local overlay = button:FindFirstChild(OVERLAY_NAME)
	if not overlay and claimed then
		local template = findTemplate()
		if template then
			local clone = template:Clone()
			local corner = button:FindFirstChildWhichIsA("UICorner", true)
			if corner then
				corner:Clone().Parent = clone
			end
			clone.Parent = button
			overlay = clone
		end
	end
	if overlay and overlay:IsA("GuiObject") then
		overlay.Visible = claimed
	end
end

return ClaimedButton
