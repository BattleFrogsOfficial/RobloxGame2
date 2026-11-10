-- Index (collection book). One tab per variant (Normal / Gold / Platinum /
-- Rainbow);
-- each row is an egg, an arrow, and the three animals it can hatch. Animals
-- you haven't hatched in that variant are dark silhouettes. Every egg you
-- complete (all three animals, in one variant) adds to all your income.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Voxel = require(Shared.Voxel)

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)
local State = require(script.Parent.Parent.State)

local Index = {}

local C = Ui.Colors
local TAB_COLORS = {
	Normal = Color3.fromRGB(175, 182, 195),
	Gold = Color3.fromRGB(235, 190, 45),
	Platinum = Color3.fromRGB(150, 205, 235),
	Rainbow = Color3.fromRGB(200, 110, 245),
}

local list: ScrollingFrame
local countLabel: TextLabel
local bonusLabel: TextLabel
local bonusFill: Frame
local tabs: { [string]: { button: GuiObject, ring: UIStroke } } = {}
local variant = "Normal"
local lastSig: string? = nil

-- A right-pointing arrow drawn from a bar and a diamond.
local function arrow(parent: Instance, position: UDim2)
	local holder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Position = position,
		Size = UDim2.fromOffset(60, 40),
		ZIndex = 23,
		Parent = parent,
	})
	local green = Color3.fromRGB(70, 220, 90)
	local bar = Ui.new("Frame", { BackgroundColor3 = green, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 12), Size = UDim2.fromOffset(34, 16), ZIndex = 23, Parent = holder })
	Ui.stroke(bar, 3)
	local head = Ui.new("Frame", { BackgroundColor3 = green, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(36, 20), Size = UDim2.fromOffset(26, 26), Rotation = 45, ZIndex = 24, Parent = holder })
	Ui.stroke(head, 3)
	-- Hide the diamond's left half so it reads as an arrowhead.
	Ui.new("Frame", { BackgroundColor3 = green, BorderSizePixel = 0, Position = UDim2.fromOffset(18, 15), Size = UDim2.fromOffset(18, 10), ZIndex = 25, Parent = holder })
end

local function discoveredCount(d): number
	local n = 0
	for _, v in Config.VariantOrder do
		for _, a in Config.Animals do
			if d.index[Formulas.indexKey(a.id, v)] then
				n += 1
			end
		end
	end
	return n
end

local function render()
	local d = State.data
	if not d then
		return
	end
	local parts = { variant }
	for _, v in Config.VariantOrder do
		for _, a in Config.Animals do
			table.insert(parts, d.index[Formulas.indexKey(a.id, v)] and "1" or "0")
		end
	end
	local sig = table.concat(parts)
	if sig == lastSig then
		return
	end
	lastSig = sig

	for name, tab in tabs do
		tab.ring.Enabled = name == variant
	end
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end

	for tier, egg in Config.Eggs do
		local rarity = Config.Rarities[tier].color
		local animals = Config.AnimalsByEgg[egg.id]
		local found = 0
		for _, a in animals do
			if d.index[Formulas.indexKey(a.id, variant)] then
				found += 1
			end
		end

		local row = Ui.new("Frame", {
			BackgroundColor3 = found == #animals and Color3.fromRGB(40, 62, 44) or C.Darker,
			Size = UDim2.new(1, -14, 0, 156),
			LayoutOrder = tier,
			ZIndex = 22,
			Parent = list,
		})
		Ui.stroke(row, 3)

		-- The egg (a silhouette until you've hatched something from it).
		local eggHolder = Ui.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(120, 112), ZIndex = 23, Parent = row })
		local eggModel = Voxel.egg(egg.id, variant, false)
		if found == 0 then
			Voxel.silhouette(eggModel)
		end
		Viewport.show(eggHolder, eggModel, { ZIndex = 23 })
		Ui.text({
			Text = found > 0 and egg.name or "???",
			Size = UDim2.fromOffset(130, 24),
			Position = UDim2.fromOffset(5, 124),
			TextColor3 = found > 0 and rarity or Color3.fromRGB(170, 170, 180),
			ZIndex = 24,
			Parent = row,
		})
		arrow(row, UDim2.fromOffset(140, 56))

		for i, a in animals do
			local known = d.index[Formulas.indexKey(a.id, variant)] ~= nil
			local card = Ui.new("Frame", {
				BackgroundColor3 = known and rarity:Lerp(Color3.new(1, 1, 1), 0.25) or rarity:Lerp(Color3.new(0, 0, 0), 0.55),
				Position = UDim2.fromOffset(212 + (i - 1) * 166, 10),
				Size = UDim2.fromOffset(154, 136),
				ZIndex = 23,
				Parent = row,
			})
			Ui.stroke(card, 3)
			local strip = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(34, 36, 44), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 28), ZIndex = 24, Parent = card })
			Ui.text({ Text = known and a.name or "???", Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), ZIndex = 25, Parent = strip })
			local holder = Ui.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 30), Size = UDim2.new(1, -8, 1, -34), ZIndex = 24, Parent = card })
			Viewport.animal(holder, a.id, variant, not known, { ZIndex = 24 })
		end
	end

	local total = #Config.Animals * #Config.VariantOrder
	countLabel.Text = string.format("(%d/%d)", discoveredCount(d), total)
	local completed = Formulas.indexCompleted(d.index)
	local possible = #Config.Eggs * #Config.VariantOrder
	bonusLabel.Text = string.format("+%d%% cash   (%d of %d eggs complete)", math.floor(completed * Config.IndexBonusPerEgg * 100 + 0.5), completed, possible)
	bonusFill.Size = UDim2.fromScale(completed / possible, 1)
end

function Index.init(gui: ScreenGui)
	local win = Ui.window(gui, "Index", "Index", C.Orange, Vector2.new(740, 520), "book")
	win.frame.Position = UDim2.new(0.5, 70, 0.5, -40) -- room for the tabs on the left and the bonus bar below

	countLabel = Ui.text({
		Text = "",
		Size = UDim2.fromOffset(180, 40),
		Position = UDim2.fromOffset(190, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 240, 200),
		ZIndex = 22,
		StrokeThickness = 3,
		Parent = win.frame:FindFirstChild("Header"),
	})

	-- Variant tabs down the left side of the window.
	for i, name in Config.VariantOrder do
		local button = Ui.button({
			Text = string.upper(name),
			Color = TAB_COLORS[name] or C.Blue,
			Size = UDim2.fromOffset(158, 54),
			Position = UDim2.fromOffset(-172, 70 + (i - 1) * 66),
			ZIndex = 21,
			Parent = win.frame,
			OnClick = function()
				variant = name
				render()
			end,
		})
		-- A white ring marks the selected tab.
		local ring = Ui.new("UIStroke", { Thickness = 4, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Enabled = false, Parent = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 8, 1, 8),
			Position = UDim2.fromOffset(-4, -4),
			ZIndex = 21,
			Parent = button,
		}) })
		Ui.corner(ring.Parent, 12)
		tabs[name] = { button = button, ring = ring }
	end

	list = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = win.body,
	})
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = list })
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = list })

	-- Bonus panel under the window.
	local panel = Ui.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(52, 86, 48),
		Position = UDim2.new(0, 0, 1, 12),
		Size = UDim2.new(1, 0, 0, 82),
		ZIndex = 21,
		Parent = win.frame,
	})
	Ui.corner(panel, 10)
	Ui.stroke(panel, 4)
	Ui.text({
		Text = string.format("Gain +%d%% Cash for each Egg you complete", math.floor(Config.IndexBonusPerEgg * 100 + 0.5)),
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 6),
		ZIndex = 22,
		StrokeThickness = 3,
		Parent = panel,
	})
	local track = Ui.new("Frame", { BackgroundColor3 = Color3.fromRGB(28, 46, 26), Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 30), ZIndex = 22, Parent = panel })
	Ui.corner(track, 6)
	bonusFill = Ui.new("Frame", { BackgroundColor3 = C.Green, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 22, Parent = track })
	Ui.corner(bonusFill, 6)
	bonusLabel = Ui.text({ Text = "", Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), TextColor3 = C.Cash, ZIndex = 23, Parent = track })

	win.onOpen = function()
		lastSig = nil
		render()
	end
	State.changed:Connect(function()
		if Ui.isOpen("Index") then
			render()
		end
	end)
end

return Index
