--!strict
-- The posted odds. Exact numbers, current ball and boosts applied, so the player can check our maths.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local Odds = require(Util:WaitForChild("Odds"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local State = require(UI:WaitForChild("State"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Panel = require(Components:WaitForChild("Panel"))
local Label = require(Components:WaitForChild("Label"))
local Icon = require(Components:WaitForChild("Icon"))

local OddsScreen = {}

export type OddsDeps = { Parent: Instance, OnClose: () -> () }

local COLS = { "Rarity", "Appears", "Catch", "Own one", "This dog" }
local COL_W = { 0.24, 0.19, 0.17, 0.2, 0.2 }

local function pct(p: number): string
	if p <= 0 then
		return "0%"
	end
	if p < 0.0001 then
		return string.format("%.4f%%", p * 100)
	end
	return FormatNumber.Percent(p, if p < 0.01 then 2 else 1)
end

local function oneIn(p: number): string
	if p <= 0 then
		return "never"
	end
	return "1 in " .. FormatNumber.Compact(1 / p)
end

function OddsScreen.new(deps: OddsDeps)
	local panel = Panel.new({ Title = "Odds", Icon = "odds", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Odds", Height = 600 })
	local body = panel.Body
	local scroll: ScrollingFrame = Make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Color.Ink, ZIndex = 53, Parent = body })
	Decor.List(scroll, Enum.FillDirection.Vertical, Theme.Space.M)
	Make("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = scroll })

	local context = Label.Body({ Name = "Context", Text = "", Size = UDim2.new(1, 0, 0, 40), Wrap = true, LayoutOrder = 1, ZIndex = 54, Parent = scroll })

	-- Tier table
	local tierBox = Panel.Section(scroll, "Rarity odds in your reach zone", 2)
	local rows: { [string]: { TextLabel } } = {}
	local function makeRow(parent: Instance, order: number, values: { string }, color: Color3?, bold: boolean?): { TextLabel }
		local row: Frame = Make("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order, ZIndex = 55, Parent = parent })
		local labels = {}
		local x = 0
		for i, v in values do
			local l = if i == 1 and not bold
				then Label.Display({ Text = v, TextSize = 18, Size = UDim2.new(COL_W[i], -4, 1, 0), Position = UDim2.fromScale(x, 0), Color = color, ZIndex = 56, Parent = row })
				else Label.Body({ Text = v, Size = UDim2.new(COL_W[i], -4, 1, 0), Position = UDim2.fromScale(x, 0), Color = if bold then Theme.Color.TextMuted else Theme.Color.TextOnPaper, Font = if bold then Theme.Font.BodyBold else Theme.Font.Body, XAlign = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right, ZIndex = 56, Parent = row })
			table.insert(labels, l)
			x += COL_W[i]
		end
		return labels
	end
	makeRow(tierBox, 1, COLS, Theme.Color.TextMuted, true)
	for i, tier in Rarities.Order do
		rows[tier] = makeRow(tierBox, i + 1, { tier, "", "", "", "" }, Theme.RarityColor(tier))
	end

	-- Variants
	local variantBox = Panel.Section(scroll, "Variants (any non-Common)", 3)
	local vrows: { [string]: { TextLabel } } = {}
	makeRow(variantBox, 1, { "Variant", "Chance", "Income", "", "" }, Theme.Color.TextMuted, true)
	for i, v in Rarities.VariantOrder do
		vrows[v] = makeRow(variantBox, i + 1, { v, "", "", "", "" }, if v == "Shadow" then Theme.Variant.Shadow:Lerp(Theme.Color.White, 0.5) else Theme.Variant[v])
	end

	-- Luck sources
	local luckBox = Panel.Section(scroll, "Your luck", 4)
	local luckList: Frame = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 10), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 55, Parent = luckBox })
	Decor.List(luckList, Enum.FillDirection.Vertical, 2)

	local note = Label.Caption({ Text = "Lucky Streak: after " .. Rarities.LuckyStreakMisses .. " Legendary or Mythic misses in a row, the next one is guaranteed to be caught. Variants roll after the dog is known. All rolls happen on the server before anything is shown.", Size = UDim2.new(1, 0, 0, 48), Wrap = true, LayoutOrder = 5, ZIndex = 54, Parent = scroll })
	note.Name = "Note"

	local function refresh()
		local zone = State.ReachZone()
		local luck, sources = State.Luck()
		local catchBonus = State.CatchBonus()
		local tierOdds = Odds.TierOdds(luck, DogCatalog.ZoneTiers(zone.Id))
		context.Text = string.format("Perfect throw with your %s reaches %s. Luck +%d%%. Catch bonus +%d%%.", State.Ball().Name, zone.Name, math.floor(luck * 100 + 0.5), math.floor(catchBonus * 100 + 0.5))
		for _, tier in Rarities.Order do
			local p = tierOdds[tier] or 0
			local catch = Odds.CatchChance(tier, catchBonus)
			local n = #DogCatalog.ZoneTierList(zone.Id, tier)
			local per = if n > 0 then p / n else 0
			local r = rows[tier]
			r[2].Text = pct(p)
			r[3].Text = pct(catch)
			r[4].Text = oneIn(p * catch)
			r[5].Text = if n > 0 then oneIn(per * catch) else "-"
		end
		local vc = Odds.VariantChances()
		for _, v in Rarities.VariantOrder do
			vrows[v][2].Text = pct(vc[v] or 0)
			vrows[v][3].Text = "x" .. tostring((Rarities.Variants :: any)[v].IncomeMult)
		end
		for _, c in luckList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if #sources == 0 then
			Label.Body({ Text = "No luck bonuses active. Better balls, Lucky Biscuits and Kennel Book milestones add luck.", Size = UDim2.new(1, 0, 0, 36), Wrap = true, ZIndex = 56, Parent = luckList })
		end
		for i, s in sources do
			Label.Body({ Text = string.format("%s   +%d%%", s.Name, math.floor(s.Amount * 100 + 0.5)), Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i, ZIndex = 56, Parent = luckList })
		end
	end

	local conn = State.Changed:Connect(function()
		if panel:IsOpen() then
			refresh()
		end
	end)
	local handle = { Panel = panel } :: any
	function handle.Open()
		refresh()
		panel:Open()
	end
	function handle.Close()
		panel:Close()
	end
	function handle.Destroy()
		conn:Disconnect()
		panel:Destroy()
	end
	return handle
end

return OddsScreen
