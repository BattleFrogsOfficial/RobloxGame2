--!strict
-- Builds the HUD ScreenGui and its non-overlapping regions (positions from UI/HudLayout only), plus the
-- currencies panel, the right button rail and the left-middle boost timers. Other controllers fill the
-- Feed / Messages / ThrowPanel / Debug regions via HudController.Region(name).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Signal = require(Util:WaitForChild("Signal"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local Shop = require(Config:WaitForChild("Shop"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local HudLayout = require(UI:WaitForChild("HudLayout"))
local Windows = require(UI:WaitForChild("Windows"))
local Components = UI:WaitForChild("Components")
local Create = require(Components:WaitForChild("Create"))
local Button = require(Components:WaitForChild("Button"))

local StateController = require(script.Parent:WaitForChild("StateController"))

local HudController = {}
HudController.LayoutChanged = Signal.new()
HudController.Layout = nil :: HudLayout.Layout?

local gui: ScreenGui = nil :: any
local regions: { [string]: Frame } = {}
local REGION_NAMES = { "Currencies", "Feed", "Messages", "Rail", "Boosts", "ThrowPanel", "Debug" }

function HudController.Region(name: string): Frame
	return regions[name]
end

function HudController.Gui(): ScreenGui
	return gui
end

-- Thrower cutscene hides the whole HUD (the cutscene draws its own UI); spectators keep everything.
function HudController.SetCutsceneMode(on: boolean)
	if gui then
		gui.Enabled = not on
	end
	if on then
		Windows.Close()
	end
end

----------------------------------------------------------------------------------------------------
-- Currencies (top-left)
----------------------------------------------------------------------------------------------------
local function counter(label: TextLabel, format: (number) -> string): (number) -> ()
	local value = Instance.new("NumberValue")
	label.Text = format(0)
	value.Changed:Connect(function(v)
		label.Text = format(v)
	end)
	return function(target: number)
		if math.abs(target - value.Value) < 1 or value.Value <= 0 then
			value.Value = target
		else
			TweenService:Create(value, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Value = target }):Play()
		end
	end
end

local function pill(parent: Instance, order: number, heightFrac: number, iconText: string, iconColor: Color3, textColor: Color3): TextLabel
	local row = Create.New("Frame", { Name = "Row" .. order, BackgroundColor3 = Theme.Color.PanelInset, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, heightFrac), LayoutOrder = order, Parent = parent }, { Create.Corner(Theme.CornerSmall) })
	local icon = Create.New("Frame", { Name = "Icon", BackgroundColor3 = iconColor, Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY, Parent = row }, { Create.Corner(100), Create.Stroke(nil, 2) })
	Create.Label({ Text = iconText, TextColor3 = Theme.Color.TextDark, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1),
		Parent = icon }, Theme.TextMax.Big)
	local holder = Create.New("Frame", { Name = "ValueHolder", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = row })
	return Create.Label({ Name = "Value", Text = "0", TextColor3 = textColor, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6, Size = UDim2.new(1, -4, 0.86, 0), Position = UDim2.fromScale(0, 0.07), Parent = holder },
		Theme.TextMax.Big)
end

local function buildCurrencies(frame: Frame)
	local panel = Create.Panel({ Name = "CurrencyPanel", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.1, Parent = frame })
	Create.Padding(5).Parent = panel
	Create.List(Enum.FillDirection.Vertical, 3).Parent = panel
	local cash = pill(panel, 1, 0.38, "$", Theme.Color.Cash, Theme.Color.Cash)
	local rate = Create.Label({ Name = "Rate", Text = "$0/s", Font = Theme.Font.Body, TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(1, 0.22), LayoutOrder = 2, Parent = panel }, Theme.TextMax.Small)
	local bones = pill(panel, 3, 0.28, "B", Theme.Color.Bones, Theme.Color.Bones)
	-- the value labels sit right of the icon: offset by the icon width once sizes are known
	for _, lbl in { cash, bones } do
		local holder = lbl.Parent :: Frame
		local rowFrame = holder.Parent :: Frame
		local function fit()
			local h = rowFrame.AbsoluteSize.Y
			holder.Position = UDim2.fromOffset(h + 6, 0)
			holder.Size = UDim2.new(1, -(h + 6), 1, 0)
		end
		rowFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end
	local setCash = counter(cash, FormatNumber.Money)
	local setBones = counter(bones, FormatNumber.Compact)
	local function refresh()
		setCash(StateController.Live("Cash"))
		setBones(StateController.Live("Bones"))
		rate.Text = FormatNumber.PerSecond(StateController.Live("IncomePerSec"))
	end
	StateController.Changed:Connect(refresh)
	StateController.LiveChanged:Connect(refresh)
	refresh()
end

----------------------------------------------------------------------------------------------------
-- Right rail
----------------------------------------------------------------------------------------------------
local RAIL = {
	{ Id = "Shop", Text = "Shop", Color = Theme.Color.Accent, Window = "Shop" },
	{ Id = "Book", Text = "Book", Color = Theme.Color.Info, Window = "Book" },
	{ Id = "Yard", Text = "Yard", Color = Theme.Color.Good, Window = "Yard" },
	{ Id = "Boosts", Text = "Boost", Color = Theme.Color.Purple, Window = "Shop", Arg = "Boosts" },
	{ Id = "Odds", Text = "Odds", Color = Color3.fromRGB(240, 130, 70), Window = "Odds" },
}
local railButtons: { [string]: TextButton } = {}

local function buildRail(frame: Frame)
	-- grid so the rail can wrap into 2 columns on short (phone) screens; cell size comes from HudLayout
	local grid = Create.New("UIGridLayout", { CellSize = UDim2.fromOffset(72, 50), CellPadding = UDim2.fromOffset(6, 6),
		FillDirection = Enum.FillDirection.Horizontal, FillDirectionMaxCells = 1, SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = frame })
	for i, def in RAIL do
		local b = Button.new({ Name = def.Id, Text = def.Text, Color = def.Color, LayoutOrder = i, TextMax = 22,
			Size = UDim2.new(1, 0, 0, 50), Corner = Theme.Corner, Parent = frame, OnClick = function()
				if def.Arg then
					Windows.Open(def.Window, def.Arg)
				else
					Windows.Toggle(def.Window)
				end
			end })
		railButtons[def.Id] = b
	end
	HudController.LayoutChanged:Connect(function(layout: HudLayout.Layout)
		grid.CellSize = UDim2.fromOffset(layout.RailButtonW, layout.RailButton)
		grid.CellPadding = UDim2.fromOffset(layout.RailGap, layout.RailGap)
		grid.FillDirectionMaxCells = layout.RailColumns
		-- one text size for every rail button (TextScaled would size "Boost" smaller than "Shop")
		local textSize = math.clamp(math.floor(layout.RailButton * 0.36), 12, 22)
		for _, b in railButtons do
			b.TextScaled = false
			b.TextSize = textSize
		end
	end)
end

-- Small red dot on a rail button (e.g. a claimable Book reward).
function HudController.SetBadge(id: string, on: boolean)
	local b = railButtons[id]
	if not b then
		return
	end
	local dot = b:FindFirstChild("Dot")
	if on and not dot then
		-- centred near the button's top-right corner so it never covers the label on small (phone) buttons
		Create.New("Frame", { Name = "Dot", BackgroundColor3 = Theme.Color.Bad, Size = UDim2.fromOffset(12, 12),
			Position = UDim2.new(1, -3, 0, 3), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5, Parent = b }, { Create.Corner(6),
			Create.Stroke(Color3.new(1, 1, 1), 2) })
	elseif not on and dot then
		dot:Destroy()
	end
end

----------------------------------------------------------------------------------------------------
-- Left-middle boost timers + protection item counts
----------------------------------------------------------------------------------------------------
local function buildBoosts(frame: Frame)
	local list = Create.List(Enum.FillDirection.Vertical, 4)
	list.Parent = frame
	local rows: { [string]: Frame } = {}
	local rowH = 26
	-- one text size for every row (TextScaled made each row a different size)
	local function boostTextSize(): number
		return math.clamp(math.floor(rowH * 0.46), 11, Theme.TextMax.Small)
	end
	local function row(key: string, order: number, color: Color3): (Frame, TextLabel)
		local r = rows[key]
		if not r then
			r = Create.New("Frame", { Name = key, BackgroundColor3 = Theme.Color.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, rowH), LayoutOrder = order, Parent = frame }, { Create.Corner(Theme.CornerSmall), Create.Stroke(nil, 2) })
			Create.New("Frame", { Name = "Bar", BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 6, 1, -8),
				Position = UDim2.fromOffset(4, 4), Parent = r }, { Create.Corner(3) })
			Create.Label({ Name = "Text", Text = "", Font = Theme.Font.Body, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false,
				TextScaled = false, TextSize = boostTextSize(), TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -18, 1, -6), Position = UDim2.fromOffset(14, 3), Parent = r }, Theme.TextMax.Small)
			rows[key] = r
		end
		local fr = r :: Frame
		fr.LayoutOrder = order
		return fr, fr:FindFirstChild("Text") :: TextLabel
	end
	local function refresh()
		local state = StateController.Get()
		local seen: { [string]: boolean } = {}
		if state then
			local now = StateController.ServerNow()
			local order = 0
			for _, id in Shop.BoostOrder do
				local exp = state.Boosts and state.Boosts[id]
				if type(exp) == "number" and exp > now then
					order += 1
					local b = Shop.Boosts[id]
					local _, t = row("Boost_" .. id, order, if b.Kind == "Catch" then Theme.Color.Info else Theme.Color.Good)
					t.Text = ("%s  %s"):format(b.Name, FormatNumber.Duration(exp - now))
					seen["Boost_" .. id] = true
				end
			end
			if (state.ServerLuckUntil or 0) > now then
				order += 1
				local _, t = row("ServerLuck", order, Theme.Color.Accent)
				t.Text = "Server Luck  " .. FormatNumber.Duration(state.ServerLuckUntil - now)
				seen.ServerLuck = true
			end
			if (state.PremiumThrows or 0) > 0 then
				order += 1
				local _, t = row("Premium", order, Theme.Color.Accent)
				t.Text = ("Premium throw x%d"):format(state.PremiumThrows)
				seen.Premium = true
			end
			if (state.Whistles or 0) > 0 then
				order += 1
				local _, t = row("Whistles", order, Color3.fromRGB(255, 205, 60))
				t.Text = ("Golden Whistle x%d"):format(state.Whistles)
				seen.Whistles = true
			end
			if (state.TreatPockets or 0) > 0 then
				order += 1
				local _, t = row("Treats", order, Color3.fromRGB(240, 150, 90))
				t.Text = ("Treat Pocket x%d"):format(state.TreatPockets)
				seen.Treats = true
			end
		end
		-- never overflow the Boosts region (it ends above the Debug button / screen bottom): extra rows are hidden
		local maxRows = math.max(1, math.floor((frame.AbsoluteSize.Y + 4) / (rowH + 4)))
		for key, r in rows do
			r.Visible = seen[key] == true and r.LayoutOrder <= maxRows
		end
	end
	HudController.LayoutChanged:Connect(function(layout: HudLayout.Layout)
		rowH = layout.BoostRow
		for _, r in rows do
			r.Size = UDim2.new(1, 0, 0, rowH)
			local t = r:FindFirstChild("Text")
			if t and t:IsA("TextLabel") then
				t.TextSize = boostTextSize()
			end
		end
	end)
	StateController.Changed:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
	refresh()
end

----------------------------------------------------------------------------------------------------
local function applyLayout()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local layout = HudLayout.Compute(size.X, size.Y, UserInputService.TouchEnabled)
	for _, name in REGION_NAMES do
		HudLayout.Apply(regions[name], (layout :: any)[name])
	end
	HudController.Layout = layout
	if RunService:IsStudio() then
		local problems = HudLayout.Validate(layout, size.X, size.Y)
		if #problems > 0 then
			warn(("[HUD] layout overlap at %dx%d: %s"):format(size.X, size.Y, table.concat(problems, ", ")))
		end
	end
	HudController.LayoutChanged:Fire(layout)
end

function HudController.Start()
	local player = Players.LocalPlayer
	gui = Create.New("ScreenGui", {
		Name = "FetchHUD",
		ResetOnSpawn = false,
		DisplayOrder = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = player:WaitForChild("PlayerGui"),
	})
	for _, name in REGION_NAMES do
		regions[name] = Create.New("Frame", { Name = name, BackgroundTransparency = 1, Parent = gui })
	end
	regions.Debug.Visible = false
	buildCurrencies(regions.Currencies)
	buildRail(regions.Rail)
	buildBoosts(regions.Boosts)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()
end

return HudController
