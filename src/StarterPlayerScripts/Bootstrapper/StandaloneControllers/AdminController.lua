--!strict
--[[
	@module AdminController
	@description Admin panel (StarterGui/AdminUI). The frame (MainFrame,
	TopFrame, Close, Container) is authored in Studio; every button and field
	inside MainFrame/Container is built here, in the look of the other panels
	(CodesUI: sliced button image + tinted gradient + tiles/slash, dark-blue
	fields, GothamSSm texts).

	SECURITY: this file decides NOTHING. Whether the player is an admin, which
	action runs, on whom, and with which amount is decided by AdminService on
	the server, from the engine-set UserId. Here:
	  - CheckAdminStatus is only used to avoid keeping the UI for ordinary
	    players (a non-admin who forces it open gets "Denied" for every click,
	    and is kicked by the server after a few tries);
	  - the L key opens / closes the panel (admins only);
	  - destructive buttons ask for a second click, and the server insists on
	    its own Confirm flag besides.

	STATE: nothing is remembered blindly. Every time the panel opens it goes
	back to its rest state (status line, armed buttons) and re-reads the real
	infinite-stamina flag from the server (also after a reset, a target change
	or a mode switch). A pending "click again" disarms itself on a timer, when
	the panel closes, and when it opens.

	Give-to-player mode: while ON, the give / set buttons target the typed
	name instead of the admin (Teleport too). Reset player and Kick always use
	the name field.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage.Libraries.Logger)
local NetworkEvents = require(ReplicatedStorage.Libraries.NetworkEvents)

local log = Logger.new("AdminController")
local AdminController = {}

local LocalPlayer = Players.LocalPlayer
local TOGGLE_KEY = Enum.KeyCode.L
local CONFIRM_WINDOW = 3 -- seconds to press a destructive button again
--- Teleport buttons: one per checkpoint (Hitbox_Checkpoint `Stage` 1..12 in Studio).
local STAGE_COUNT = 12

--============================================================================--
-- STYLE (copied from the other panels, see CodesUI)
--============================================================================--

local BUTTON_IMAGE = "rbxassetid://120469257154615"
local BUTTON_PRESSED_IMAGE = "rbxassetid://86825397810940"
local TILES_IMAGE = "rbxassetid://81485688609281"
local SLASH_IMAGE = "rbxassetid://85708744611945"
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

local FIELD_COLOR = Color3.fromRGB(2, 44, 74) -- the dark blue of CodesUI/TextBox
local PLACEHOLDER_COLOR = Color3.fromRGB(150, 160, 170)
local OK_COLOR = Color3.fromRGB(120, 240, 140)
local ERROR_COLOR = Color3.fromRGB(255, 110, 110)

--- Button tints: a 3-stop gradient (bottom -> top) over the grey button image.
local TINTS: { [string]: { Color3 } } = {
	Green = { Color3.new(0, 1, 0), Color3.new(0.451, 1, 0), Color3.new(0.765, 1, 0) },
	Red = { Color3.new(1, 0.1, 0.15), Color3.new(1, 0.3, 0.2), Color3.new(1, 0.5, 0.3) },
	Grey = { Color3.new(0.4, 0.42, 0.5), Color3.new(0.55, 0.57, 0.65), Color3.new(0.72, 0.74, 0.8) },
	Orange = { Color3.new(1, 0.45, 0), Color3.new(1, 0.65, 0), Color3.new(1, 0.85, 0.2) },
}

local function tintSequence(name: string): ColorSequence
	local colors = TINTS[name]
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.5, colors[2]),
		ColorSequenceKeypoint.new(1, colors[3]),
	})
end

local function addCorner(instance: Instance, radius: number): ()
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addStroke(instance: Instance, thickness: number, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = instance
	return stroke
end

--- Plain text (section titles, status line): GothamSSm Bold, white, black outline.
local function makeText(parent: Instance, text: string, size: number, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.FontFace = FONT_BOLD
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.LayoutOrder = order
	label.Parent = parent
	addStroke(label, 1.5)
	return label
end

--- A dark-blue rounded block (the CodesUI field look).
local function makeBlock(parent: Instance, order: number): Frame
	local block = Instance.new("Frame")
	block.BackgroundColor3 = FIELD_COLOR
	block.BackgroundTransparency = 0.4
	block.BorderSizePixel = 0
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.Size = UDim2.new(1, 0, 0, 0)
	block.LayoutOrder = order
	block.Parent = parent
	addCorner(block, 8)
	addStroke(block, 1.5, 0.4)
	return block
end

--- A titled section holding a 3-column grid of buttons.
local function makeSection(parent: Instance, title: string, order: number): Frame
	local section = makeBlock(parent, order)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = section

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = section

	makeText(section, title, 18, 0)

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.LayoutOrder = 1
	grid.Parent = section

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.31, 0, 0, 46)
	layout.CellPadding = UDim2.new(0.02, 0, 0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	return grid
end

--- A button in the Claim look. Hover / press scale comes from
--- ButtonHoverController (every GuiButton of the PlayerGui).
local function makeButton(
	parent: Instance,
	text: string,
	tint: string,
	order: number,
	onClick: (button: ImageButton) -> ()
): ImageButton
	local button = Instance.new("ImageButton")
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Image = BUTTON_IMAGE
	button.PressedImage = BUTTON_PRESSED_IMAGE
	button.ScaleType = Enum.ScaleType.Slice
	button.SliceCenter = Rect.new(105, 205, 105, 205)
	button.SliceScale = 0.1 -- the art is made for a big button; this one is ~46px high
	button.ZIndex = 2
	button.LayoutOrder = order
	button.Parent = parent

	local tiles = Instance.new("ImageLabel")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	tiles.Image = TILES_IMAGE
	tiles.ScaleType = Enum.ScaleType.Tile
	tiles.TileSize = UDim2.fromOffset(30, 30)
	tiles.ImageTransparency = 0.75
	tiles.Size = UDim2.fromScale(1, 1)
	tiles.ZIndex = 3
	tiles.Parent = button
	addCorner(tiles, 8)

	local slash = Instance.new("ImageLabel")
	slash.Name = "Slash"
	slash.BackgroundTransparency = 1
	slash.Image = SLASH_IMAGE
	slash.ScaleType = Enum.ScaleType.Fit
	slash.ImageTransparency = 0.78
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromScale(0.53, 0.5)
	slash.Size = UDim2.fromScale(0.85, 0.85)
	slash.ZIndex = 3
	slash.Parent = button

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.FontFace = FONT_HEAVY
	title.Text = text
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.TextWrapped = true
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.45)
	title.Size = UDim2.fromScale(0.85, 0.7)
	title.ZIndex = 4
	title.Parent = button
	addStroke(title, 2)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 20
	constraint.MinTextSize = 8
	constraint.Parent = title

	local gradient = Instance.new("UIGradient")
	gradient.Name = "Tint"
	gradient.Rotation = 270
	gradient.Color = tintSequence(tint)
	gradient.Parent = button

	button.Activated:Connect(function()
		onClick(button)
	end)
	return button
end

local function setButton(button: ImageButton, text: string?, tint: string?): ()
	local title = button:FindFirstChild("Title") :: TextLabel?
	local gradient = button:FindFirstChild("Tint") :: UIGradient?
	if title and text then
		title.Text = text
	end
	if gradient and tint then
		gradient.Color = tintSequence(tint)
	end
end

--- The CodesUI text field: dark block, centred bold text, grey placeholder.
local function makeField(parent: Instance, placeholder: string, order: number): (TextBox, Frame)
	local block = makeBlock(parent, order)
	block.AutomaticSize = Enum.AutomaticSize.None
	block.Size = UDim2.new(1, 0, 0, 44)

	local input = Instance.new("TextBox")
	input.BackgroundTransparency = 1
	input.ClearTextOnFocus = false
	input.FontFace = FONT_BOLD
	input.PlaceholderText = placeholder
	input.PlaceholderColor3 = PLACEHOLDER_COLOR
	input.Text = ""
	input.TextColor3 = Color3.new(1, 1, 1)
	input.TextScaled = true
	input.TextWrapped = true
	input.AnchorPoint = Vector2.new(0.5, 0.5)
	input.Position = UDim2.fromScale(0.5, 0.5)
	input.Size = UDim2.fromScale(0.9, 0.6)
	input.Parent = block
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 22
	constraint.Parent = input
	return input, block
end

--============================================================================--
-- PANEL
--============================================================================--

--- Autocomplete under the name field: the players of this server whose name or
--- display name contains what is typed (all of them while it is empty). A click
--- fills the field. `block` is the field's frame; the list hangs below it.
local function attachPlayerDropdown(block: Frame, input: TextBox, onPick: () -> ()): ()
	local ROW_HEIGHT = 30
	local MAX_ROWS = 6

	local list = Instance.new("ScrollingFrame")
	list.Name = "PlayerDropdown"
	list.BackgroundColor3 = FIELD_COLOR
	list.BorderSizePixel = 0
	list.Visible = false
	list.ZIndex = 20
	list.Position = UDim2.new(0, 0, 1, 4)
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = block
	addCorner(list, 8)
	addStroke(list, 1.5, 0.2)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function refresh(): ()
		for _, child in list:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local query = string.lower(input.Text)
		local rows = 0
		for _, player in Players:GetPlayers() do
			local matches = query == ""
				or string.find(string.lower(player.Name), query, 1, true) ~= nil
				or string.find(string.lower(player.DisplayName), query, 1, true) ~= nil
			if not matches then
				continue
			end
			rows += 1
			local row = Instance.new("TextButton")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.FontFace = FONT_BOLD
			row.Text = if player.DisplayName == player.Name
				then player.Name
				else ("%s (@%s)"):format(player.DisplayName, player.Name)
			row.TextColor3 = Color3.new(1, 1, 1)
			row.TextSize = 16
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.ZIndex = 21
			row.LayoutOrder = rows
			row.Parent = list
			row.Activated:Connect(function()
				input.Text = player.Name
				list.Visible = false
				onPick()
			end)
		end
		list.Size = UDim2.new(1, 0, 0, math.min(rows, MAX_ROWS) * ROW_HEIGHT)
		list.Visible = rows > 0 and input:IsFocused()
	end

	input.Focused:Connect(refresh)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if input:IsFocused() then
			refresh()
		end
	end)
	input.FocusLost:Connect(function()
		task.delay(0.2, function() -- let a click on a row register first
			if not input:IsFocused() then
				list.Visible = false
			end
		end)
	end)
end

local function buildPanel(ui: ScreenGui, allowed: { [string]: boolean }): () -> ()
	local container = ui:WaitForChild("MainFrame"):WaitForChild("Container") :: GuiObject

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AdminScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = scroll

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	local status = makeText(scroll, "", 16, 0)
	local function show(success: boolean, message: string): ()
		status.Text = message
		status.TextColor3 = if success then OK_COLOR else ERROR_COLOR
	end

	--== Target =============================================================--
	local giveToPlayer = false
	local targetSection = makeSection(scroll, "Player", 1)
	local nameField, nameBlock = makeField(targetSection, "Player name", 1)
	local modeButton: ImageButton
	-- Over the sections below it, so the dropdown is never drawn under them.
	local targetFrame = targetSection.Parent :: GuiObject
	targetFrame.ZIndex = 10
	-- Only ranks that act on other players need the name field.
	targetFrame.Visible = allowed.TargetOthers == true

	--== Server calls =======================================================--
	local pending = false

	--- One round trip. `usesTarget`: honours the give-to-player mode.
	local function send(
		action: string,
		payload: { [string]: any }?,
		usesTarget: boolean,
		onDone: ((result: any) -> ())?
	): ()
		if pending then
			return
		end
		local body: { [string]: any } = payload or {}
		if usesTarget and giveToPlayer then
			if nameField.Text == "" then
				show(false, "Enter a player name (give mode is ON).")
				return
			end
			body.Target = nameField.Text
		end
		pending = true
		task.spawn(function()
			local ok, result = pcall(NetworkEvents.InvokeServer, "AdminRequest", action, body)
			pending = false
			if ok and type(result) == "table" then
				show(result.Success == true, tostring(result.Message))
				if onDone then
					onDone(result)
				end
			else
				show(false, "No answer from the server.")
			end
		end)
	end

	--== Infinite stamina (state read from the server) ======================--
	local staminaButton: ImageButton? = nil
	local staminaOn = false
	local function applyStamina(enabled: boolean): ()
		staminaOn = enabled
		if not staminaButton then
			return
		end
		setButton(
			staminaButton,
			if enabled then "Infinite stamina: ON" else "Infinite stamina: OFF",
			if enabled then "Green" else "Grey"
		)
	end

	--- Re-reads the flag of whoever the buttons currently target.
	local refreshToken = 0
	local function refreshStamina(): ()
		refreshToken += 1
		local token = refreshToken
		local body: { [string]: any } = {}
		if giveToPlayer then
			if nameField.Text == "" then
				applyStamina(false)
				return
			end
			body.Target = nameField.Text
		end
		task.spawn(function()
			local ok, result = pcall(NetworkEvents.InvokeServer, "AdminRequest", "GetInfiniteStamina", body)
			if token ~= refreshToken then
				return -- a newer refresh is in flight
			end
			local data = if ok and type(result) == "table" and result.Success == true then result.Data else nil
			applyStamina(type(data) == "table" and data.Enabled == true)
		end)
	end

	--== Destructive buttons: arm, then confirm =============================--
	local armed: { [ImageButton]: { Label: string, Token: number } } = {}
	local armCounter = 0

	local function disarm(button: ImageButton): ()
		local entry = armed[button]
		if entry then
			armed[button] = nil
			setButton(button, entry.Label, "Red")
		end
	end
	local function disarmAll(): ()
		for button in armed do
			disarm(button)
		end
	end

	local function confirmed(button: ImageButton, label: string, run: () -> ()): ()
		if armed[button] then
			disarm(button)
			run()
			return
		end
		armCounter += 1
		local token = armCounter
		armed[button] = { Label = label, Token = token }
		setButton(button, "Click again to confirm", "Orange")
		task.delay(CONFIRM_WINDOW, function()
			local entry = armed[button]
			if entry and entry.Token == token then
				disarm(button)
			end
		end)
	end

	--== Buttons ============================================================--
	modeButton = makeButton(targetSection, "Give to player: OFF", "Grey", 2, function(button)
		giveToPlayer = not giveToPlayer
		setButton(
			button,
			if giveToPlayer then "Give to player: ON" else "Give to player: OFF",
			if giveToPlayer then "Green" else "Grey"
		)
		refreshStamina()
	end)
	nameField.FocusLost:Connect(function()
		refreshStamina()
	end)
	attachPlayerDropdown(nameBlock, nameField, refreshStamina)

	-- Only what the server allows this rank to do is built (the server re-checks anyway).
	local function can(action: string): boolean
		return allowed[action] == true
	end

	if can("GiveWins") then
		local wins = makeSection(scroll, "Give Wins", 2)
		for i, amount in { 1, 10, 100 } do
			makeButton(wins, "+" .. amount, "Green", i, function()
				send("GiveWins", { Amount = amount }, true)
			end)
		end
	end

	if can("GiveXP") then
		local xp = makeSection(scroll, "Give XP", 3)
		local xpAmounts = {
			{ 500, "+500" },
			{ 1000, "+1k" },
			{ 10000, "+10k" },
			{ 100000, "+100k" },
			{ 1000000, "+1M" },
		}
		for i, entry in xpAmounts do
			makeButton(xp, entry[2] :: string, "Green", i, function()
				send("GiveXP", { Amount = entry[1] }, true)
			end)
		end
	end

	if can("SetMaxLevel") then
		local levels = makeSection(scroll, "Levels", 4)
		makeButton(levels, "Set max level", "Green", 1, function()
			send("SetMaxLevel", nil, true)
		end)
	end

	if can("GiveRebirth") or can("SetMaxRebirth") then
		local rebirths = makeSection(scroll, "Rebirths", 5)
		if can("GiveRebirth") then
			for i, amount in { 1, 5, 10 } do
				makeButton(rebirths, "+" .. amount, "Green", i, function()
					send("GiveRebirth", { Amount = amount }, true)
				end)
			end
		end
		if can("SetMaxRebirth") then
			makeButton(rebirths, "Set max rebirth", "Green", 4, function()
				send("SetMaxRebirth", nil, true)
			end)
		end
	end

	if can("SetInfiniteStamina") then
		local staminaSection = makeSection(scroll, "Flight", 6)
		staminaButton = makeButton(staminaSection, "Infinite stamina: OFF", "Grey", 1, function()
			send("SetInfiniteStamina", { Enabled = not staminaOn }, true, function(result)
				local data = result.Data
				if result.Success == true and type(data) == "table" then
					applyStamina(data.Enabled == true)
				end
			end)
		end)
	end

	if can("GiveAllSkins") or can("GiveAllTrails") then
		local cosmetics = makeSection(scroll, "Cosmetics", 7)
		if can("GiveAllSkins") then
			makeButton(cosmetics, "Give every skin", "Green", 1, function()
				send("GiveAllSkins", nil, true)
			end)
		end
		if can("GiveAllTrails") then
			makeButton(cosmetics, "Give every trail", "Green", 2, function()
				send("GiveAllTrails", nil, true)
			end)
		end
	end

	-- Stage 0 = lobby; the server refuses a stage the map doesn't have (or, for a
	-- Dev, one not reached yet).
	if can("TeleportStage") then
		local teleport = makeSection(scroll, "Teleport", 8)
		for stage = 0, STAGE_COUNT do
			local label = if stage == 0 then "Lobby" else "Stage " .. stage
			makeButton(teleport, label, if stage == 0 then "Grey" else "Green", stage, function()
				send("TeleportStage", { Stage = stage }, true)
			end)
		end
	end

	local danger = makeSection(scroll, "Danger zone", 9)
	local function dangerButton(label: string, order: number, action: string, payload: () -> { [string]: any })
		if not can(action) then
			return
		end
		makeButton(danger, label, "Red", order, function(button)
			confirmed(button, label, function()
				send(action, payload(), false, function()
					refreshStamina() -- a reset clears the flag
				end)
			end)
		end)
	end
	dangerButton("Reset my data", 1, "ResetSelf", function()
		return { Confirm = true }
	end)
	dangerButton("Reset player data", 2, "ResetPlayer", function()
		return { Confirm = true, Name = nameField.Text }
	end)
	dangerButton("Reset EVERY player", 3, "ResetAll", function()
		return { Confirm = true }
	end)
	dangerButton("Kick player", 4, "Kick", function()
		return { Name = nameField.Text }
	end)
	dangerButton("Ban player", 5, "Ban", function()
		return { Confirm = true, Name = nameField.Text }
	end)

	--- Back to the rest state: called whenever the panel opens or closes.
	local function reset(): ()
		disarmAll()
		pending = false
		status.Text = ""
		scroll.CanvasPosition = Vector2.zero
	end
	return function(): ()
		reset()
		refreshStamina()
	end
end

local function setupAdmin(ui: ScreenGui, allowed: { [string]: boolean }): ()
	local onOpen = buildPanel(ui, allowed)

	-- Single place that reacts to opening / closing, whoever toggled it.
	ui:GetPropertyChangedSignal("Enabled"):Connect(function()
		onOpen() -- closing resets too: nothing stays armed behind the scenes
	end)

	local close = ui:WaitForChild("MainFrame"):WaitForChild("TopFrame"):WaitForChild("Close") :: GuiButton
	close.Activated:Connect(function()
		ui.Enabled = false
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			ui.Enabled = not ui.Enabled
		end
	end)
	log:Info("Admin panel ready (press %s).", TOGGLE_KEY.Name)
end

function AdminController:Init(): () end

function AdminController:Start(): ()
	task.spawn(function()
		local playerGui = LocalPlayer:WaitForChild("PlayerGui")
		local ui = playerGui:WaitForChild("AdminUI", 30)
		if not (ui and ui:IsA("ScreenGui")) then
			return
		end

		-- false = not an admin; { Level, Actions } = the rank and what it may do.
		local status: any = nil
		for _ = 1, 3 do
			local answer = NetworkEvents.InvokeServer("CheckAdminStatus")
			if answer ~= nil then
				status = answer
				break
			end
			task.wait(2.5) -- rate limited / not ready yet: ask again
		end

		if type(status) ~= "table" or type(status.Actions) ~= "table" then
			ui:Destroy() -- nothing for an ordinary player to open
			return
		end
		setupAdmin(ui, status.Actions)
	end)
end

return AdminController
