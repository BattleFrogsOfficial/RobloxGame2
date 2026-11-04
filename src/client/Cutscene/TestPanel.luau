--!strict
-- CutsceneTestMode debug panel (only built when Config/Game.CutsceneTestMode = true). A "Test cutscene" pill
-- opens a kit Panel (modal, registered with the Router) with a button per rarity x caught / missed x with /
-- without a variant, "Play random" and a "Loop random" toggle. Every outcome is a local fake
-- (Shared/Cutscene/FakeResult): random zone + distance, never sent to the server.
--   TestPanel.new({ Parent, IsTouch, Router?, OnPlay = (spec) -> (), OnLoop = (on) -> () }) -> handle
--   handle:SetLooping(on)  handle:Destroy()
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Panel = require(Components:WaitForChild("Panel"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))

local TestPanel = {}

export type Spec = { Rarity: string?, Caught: boolean?, Variant: string? }
export type Deps = {
	Parent: Instance,
	IsTouch: boolean,
	Router: any?,
	OnPlay: (spec: Spec) -> (),
	OnLoop: (on: boolean) -> (),
}

local VARIANTS = { "Gold", "Shadow", "Rainbow", "Random" }

function TestPanel.new(deps: Deps)
	local touch = deps.IsTouch
	local E = if touch then Theme.Space.M else Theme.Space.Edge
	local handle = {} :: any
	local looping = false
	local variantIdx = 4

	-- The opener pill. Desktop: right edge, mid-height (the right-middle is otherwise empty). Touch: left
	-- edge under the side-menu row, above the thumbstick zone.
	local pill = Button.new({
		Name = "CutsceneTest",
		Text = "Test cutscene",
		Icon = "star",
		IconSize = 16,
		Palette = "Purple",
		TextSize = Theme.Text.Body,
		Size = UDim2.fromOffset(170, 44),
		Position = if touch then UDim2.fromOffset(E, E + 58 + Theme.Space.S + 52 + Theme.Space.S) else UDim2.new(1, -E, 0.5, 0),
		AnchorPoint = if touch then Vector2.new(0, 0) else Vector2.new(1, 0.5),
		ZIndex = 44,
		Parent = deps.Parent,
	})
	handle.Pill = pill

	local panel = Panel.new({ Title = "Cutscene test", Icon = "star", Parent = deps.Parent, Name = "CutsceneTestPanel", Width = 640, Height = 600, OnClose = function()
		if deps.Router then
			deps.Router.Close()
		else
			handle.Close()
		end
	end })
	handle.Panel = panel
	local scroll: ScrollingFrame = Make("ScrollingFrame", { Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Color.Ink, ZIndex = 53, Parent = panel.Body })
	Decor.List(scroll, Enum.FillDirection.Vertical, Theme.Space.M)
	Make("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = scroll })

	local function play(spec: Spec)
		if deps.Router then
			deps.Router.Close()
		else
			handle.Close()
		end
		deps.OnPlay(spec)
	end

	-- Controls row: variant choice for the "+ variant" buttons, play random, loop random.
	local controls = Panel.Section(scroll, "Random zone and distance every time", 1)
	local row: Frame = Make("Frame", { Name = "Controls", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, ZIndex = 55, Parent = controls })
	Decor.List(row, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local variantButton: Button.ButtonHandle
	variantButton = Button.new({ Name = "Variant", Text = "Variant: Random", Palette = "Cash", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(176, 44), Shadow = false, LayoutOrder = 1, ZIndex = 56, Parent = row, OnClick = function()
		variantIdx = variantIdx % #VARIANTS + 1
		variantButton:SetText("Variant: " .. VARIANTS[variantIdx])
	end })
	Button.new({ Name = "PlayRandom", Text = "Play random", Palette = "Sky", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(150, 44), Shadow = false, LayoutOrder = 2, ZIndex = 56, Parent = row, OnClick = function()
		play({})
	end })
	local loopButton: Button.ButtonHandle
	loopButton = Button.new({ Name = "Loop", Text = "Loop random: Off", Palette = "Slate", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(176, 44), Shadow = false, LayoutOrder = 3, ZIndex = 56, Parent = row, OnClick = function()
		handle:SetLooping(not looping)
		if looping then
			play({})
		end
	end })

	-- One row per rarity: Caught / Missed / Caught + variant / Missed + variant.
	local grid = Panel.Section(scroll, "Play one outcome", 2)
	for i, tier in Rarities.Order do
		local r: Frame = Make("Frame", { Name = "Row_" .. tier, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, ZIndex = 55, Parent = grid })
		Label.Display({ Text = tier, TextSize = 18, Color = Theme.RarityColor(tier), Size = UDim2.new(0, 108, 1, 0), ZIndex = 56, Parent = r })
		local buttons: Frame = Make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, -112, 1, 0), Position = UDim2.fromOffset(112, 0), ZIndex = 56, Parent = r })
		Decor.List(buttons, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		local entries = { { "Caught", true, false }, { "Missed", false, false } }
		if tier ~= "Common" then
			table.insert(entries, { "Caught +V", true, true })
			table.insert(entries, { "Missed +V", false, true })
		end
		for j, e in entries do
			Button.new({ Name = e[1], Text = e[1], Palette = if e[2] then "Grass" else "Danger", TextSize = Theme.Text.Caption, Size = UDim2.fromOffset(104, 44), Shadow = false, LayoutOrder = j, ZIndex = 57, Parent = buttons, OnClick = function()
				play({ Rarity = tier, Caught = e[2], Variant = if e[3] then VARIANTS[variantIdx] else "None" })
			end })
		end
	end

	function handle.Open()
		panel:Open()
	end
	function handle.Close()
		panel:Close()
	end
	function handle.SetLooping(_, on: boolean)
		looping = on
		loopButton:SetText(if on then "Loop random: On" else "Loop random: Off")
		loopButton:SetPalette(if on then "Grass" else "Slate")
		pill:SetText(if on then "Stop loop" else "Test cutscene")
		pill:SetPalette(if on then "Danger" else "Purple")
		deps.OnLoop(on)
	end
	function handle.IsLooping(): boolean
		return looping
	end
	function handle.Destroy()
		panel:Destroy()
		pill.Root:Destroy()
	end

	pill.Root.Activated:Connect(function()
		if looping then
			handle:SetLooping(false)
			return
		end
		if deps.Router then
			deps.Router.Open("CutsceneTest")
		else
			handle.Open()
		end
	end)
	if deps.Router then
		deps.Router.Register("CutsceneTest", handle)
	end
	return handle
end

return TestPanel
