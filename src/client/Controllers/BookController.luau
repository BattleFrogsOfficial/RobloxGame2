--!strict
-- Kennel Book: every form ever caught (720 base dogs + Gold/Shadow/Rainbow forms of every non-Common).
-- The grid is VIRTUALISED (UI/Components/VirtualGrid): only the visible cells exist, pooled while scrolling.
-- Per-zone milestones (25/50/75/100% of base dogs) are claimed here via ClaimBookReward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Zones = require(Config:WaitForChild("Zones"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Shop = require(Config:WaitForChild("Shop"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local VariantFX = require(Shared:WaitForChild("Dog"):WaitForChild("VariantFX"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Windows = require(UI:WaitForChild("Windows"))
local Components = UI:WaitForChild("Components")
local Create = require(Components:WaitForChild("Create"))
local Button = require(Components:WaitForChild("Button"))
local Window = require(Components:WaitForChild("Window"))
local Tabs = require(Components:WaitForChild("Tabs"))
local VirtualGrid = require(Components:WaitForChild("VirtualGrid"))

local StateController = require(script.Parent:WaitForChild("StateController"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local BookController = {}

type Form = { Def: any, Variant: string? }

local allForms: { Form } = {}
local visible: { Form } = {}
local zoneFilter = "All"
local variantFilter = "All forms"
local grid: VirtualGrid.Grid? = nil
local progressLabel: TextLabel? = nil
local milestoneRow: Frame? = nil
local detail: TextLabel? = nil
local detailOverlay = false -- compact layout: the detail line is a popup over the grid, shown after a tap
local detailToken = 0

local VARIANT_TABS = { "All forms", "Base", "Gold", "Shadow", "Rainbow" }

local function hex(v: any, fallback: Color3): Color3
	if type(v) == "string" then
		local ok, c = pcall(Color3.fromHex, v)
		if ok then
			return c
		end
	end
	return fallback
end

local function buildForms()
	table.clear(allForms)
	for _, def in DogCatalog.All() do
		table.insert(allForms, { Def = def })
	end
	for _, v in Rarities.VariantOrder do
		for _, def in DogCatalog.All() do
			if def.Rarity ~= "Common" then
				table.insert(allForms, { Def = def, Variant = v })
			end
		end
	end
end

local function owns(state: any, form: Form): boolean
	local entry = state and state.Book and state.Book[form.Def.Id]
	if not entry then
		return false
	end
	if not form.Variant then
		return true
	end
	local vs = entry.Variants
	if type(vs) ~= "table" then
		return false
	end
	return table.find(vs, form.Variant) ~= nil or vs[form.Variant] == true
end

local function zoneProgress(state: any, zoneId: string): (number, number)
	local total, have = 0, 0
	for _, def in DogCatalog.ZoneDogs(zoneId) do
		total += 1
		if state and state.Book and state.Book[def.Id] then
			have += 1
		end
	end
	return have, total
end

local function claimable(state: any): boolean
	if not state then
		return false
	end
	for _, z in Zones do
		local have, total = zoneProgress(state, z.Id)
		local pct = if total > 0 then have / total * 100 else 0
		local claimed = (state.BookRewards and state.BookRewards[z.Id]) or {}
		for _, m in Shop.BookMilestones do
			if pct >= m and not claimed[tostring(m)] then
				return true
			end
		end
	end
	return false
end

local function applyFilter()
	table.clear(visible)
	for _, f in allForms do
		local zoneOk = zoneFilter == "All" or f.Def.Zone == zoneFilter
		local variantOk = variantFilter == "All forms" or (variantFilter == "Base" and f.Variant == nil) or f.Variant == variantFilter
		if zoneOk and variantOk then
			table.insert(visible, f)
		end
	end
	if grid then
		grid:SetCount(#visible)
		grid:ScrollToTop()
	end
end

local function zoneIdFromTab(name: string): string
	for _, z in Zones do
		if z.Name == name then
			return z.Id
		end
	end
	return "All"
end

local function refreshHeader()
	local state = StateController.Get()
	local pl = progressLabel
	local row = milestoneRow
	if not pl or not row then
		return
	end
	local owned, total = 0, 0
	for _, f in visible do
		total += 1
		if owns(state, f) then
			owned += 1
		end
	end
	pl.Text = ("%d / %d forms"):format(owned, total)
	for _, c in row:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if zoneFilter == "All" then
		Create.Label({ Text = "Pick a zone to see its milestone rewards (25/50/75/100% of its base dogs).", Font = Theme.Font.Body,
			TextColor3 = Theme.Color.TextDim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row }, Theme.TextMax.Small)
		return
	end
	local have, zoneTotal = zoneProgress(state, zoneFilter)
	local pct = if zoneTotal > 0 then have / zoneTotal * 100 else 0
	local claimed = (state and state.BookRewards and state.BookRewards[zoneFilter]) or {}
	local rewardNames = { [25] = "Cash", [50] = "+Luck", [75] = "Trophy", [100] = "Title" }
	for i, m in Shop.BookMilestones do
		local isClaimed = claimed[tostring(m)] == true
		local ready = pct >= m and not isClaimed
		Button.new({
			Text = ("%d%% %s"):format(m, if isClaimed then "done" else (rewardNames[m] or "")),
			Color = if ready then Theme.Color.Good elseif isClaimed then Theme.Color.PanelInset else Theme.Color.PanelLight,
			Size = UDim2.new(0.25, -6, 1, 0), LayoutOrder = i, TextMax = 16, Parent = row,
			OnClick = function()
				if not ready then
					return
				end
				local remote = Remotes.Get("ClaimBookReward") :: RemoteFunction
				local ok, success, msg = pcall(function()
					return remote:InvokeServer(zoneFilter, m)
				end)
				NotificationController.Toast(if ok then tostring(msg) else "Try again", if ok and success then "Purchase" else "Error")
			end,
		})
	end
end

----------------------------------------------------------------------------------------------------
-- cells
----------------------------------------------------------------------------------------------------
local function createCell(): GuiObject
	local cell = Create.New("TextButton", { Name = "Cell", Text = "", AutoButtonColor = true, BackgroundColor3 = Theme.Color.PanelLight,
		BorderSizePixel = 0 }, { Create.Corner(Theme.CornerSmall), Create.Stroke(nil, 2) })
	local swatch = Create.New("Frame", { Name = "Swatch", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.44, 0.44),
		Position = UDim2.fromScale(0.5, 0.06), AnchorPoint = Vector2.new(0.5, 0), SizeConstraint = Enum.SizeConstraint.RelativeXX,
		ClipsDescendants = true, Parent = cell }, { Create.Corner(100), Create.Stroke(nil, 2) })
	Create.New("Frame", { Name = "Half", BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0),
		Parent = swatch })
	Create.Label({ Name = "Q", Text = "?", TextColor3 = Theme.Color.TextDim, Visible = false, Parent = swatch }, 30)
	Create.Label({ Name = "DogName", Text = "", Font = Theme.Font.Body, Size = UDim2.new(1, -6, 0.25, 0), Position = UDim2.new(0, 3, 0.57, 0),
		Parent = cell }, Theme.TextMax.Small)
	Create.Label({ Name = "Tier", Text = "", Font = Theme.Font.Body, Size = UDim2.new(1, -8, 0.14, 0), Position = UDim2.new(0, 4, 0.83, 0),
		Parent = cell }, Theme.TextMax.Tiny)
	-- variant ribbon across the bottom of the swatch (wide enough for "RAINBOW" at the tiny text size)
	local tag = Create.New("Frame", { Name = "VariantTag", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.86, 0.15),
		Position = UDim2.fromScale(0.5, 0.4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 2, Visible = false, Parent = cell },
		{ Create.Corner(6), Create.Stroke(nil, 2) })
	Create.New("UIGradient", { Name = "Grad", Parent = tag })
	Create.Label({ Name = "Text", Text = "", Font = Theme.Font.Body, TextStrokeTransparency = 0.4, TextWrapped = false, ZIndex = 3,
		Size = UDim2.new(1, -4, 1, 0), Position = UDim2.fromOffset(2, 0), Parent = tag }, Theme.TextMax.Tiny)
	cell.Activated:Connect(function()
		local idx = cell:GetAttribute("FormIndex")
		local form = if type(idx) == "number" then visible[idx] else nil
		local d = detail
		if form and d then
			local state = StateController.Get()
			local def = form.Def
			local zone = DogCatalog.Zone(def.Zone)
			local income = DogCatalog.AdultIncome(def, form.Variant)
			if owns(state, form) then
				d.Text = ('<b>%s</b>%s · <font color="#%s">%s</font> · %s · %s\n%s'):format(def.Name,
					if form.Variant then " (" .. form.Variant .. ")" else "", Theme.Rarity(def.Rarity):ToHex(), def.Rarity,
					if zone then zone.Name else def.Zone, FormatNumber.PerSecond(income), tostring(def.Flavor or ""))
			else
				d.Text = ('<b>???</b> · <font color="#%s">%s</font>%s · found in %s · %s when caught'):format(
					Theme.Rarity(def.Rarity):ToHex(), def.Rarity, if form.Variant then " " .. form.Variant .. " form" else "",
					if zone then zone.Name else def.Zone, FormatNumber.PerSecond(income))
			end
			if detailOverlay then
				d.Visible = true
				detailToken += 1
				local token = detailToken
				task.delay(5, function()
					if detailToken == token and detailOverlay then
						d.Visible = false
					end
				end)
			end
		end
	end)
	return cell
end

local function renderCell(cellObj: GuiObject, index: number)
	local cell = cellObj :: TextButton
	local form = visible[index]
	if not form then
		cell.Visible = false
		return
	end
	cell:SetAttribute("FormIndex", index)
	local state = StateController.Get()
	local have = owns(state, form)
	local def = form.Def
	local color = Theme.Rarity(def.Rarity)
	local stroke = cell:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	cell.BackgroundColor3 = if have then Theme.Color.PanelLight else Theme.Color.PanelInset
	local swatch = cell:FindFirstChild("Swatch") :: Frame
	local half = swatch:FindFirstChild("Half") :: Frame
	local q = swatch:FindFirstChild("Q") :: TextLabel
	if have then
		local p = hex(def.CoatPrimary, Color3.fromRGB(200, 160, 110))
		local s2 = hex(def.CoatSecondary, Color3.new(1, 1, 1))
		if form.Variant then
			p = VariantFX.BadgeColor(form.Variant)
			s2 = Theme.Lighten(p, 0.4)
		end
		swatch.BackgroundColor3 = p
		half.BackgroundColor3 = s2
		half.Visible = true
		q.Visible = false
	else
		swatch.BackgroundColor3 = Theme.Color.Panel
		half.Visible = false
		q.Visible = true
	end
	local nameLabel = cell:FindFirstChild("DogName") :: TextLabel
	nameLabel.Text = if have then def.Name else "???"
	nameLabel.TextColor3 = if have then Theme.Color.Text else Theme.Color.TextDim
	local tier = cell:FindFirstChild("Tier") :: TextLabel
	tier.Text = def.Rarity
	tier.TextColor3 = color
	local tag = cell:FindFirstChild("VariantTag") :: Frame
	tag.Visible = form.Variant ~= nil
	if form.Variant then
		local grad = tag:FindFirstChild("Grad") :: UIGradient
		grad.Color = VariantFX.BadgeGradient(form.Variant)
		local tagText = tag:FindFirstChild("Text") :: TextLabel
		tagText.Text = string.upper(form.Variant)
	end
end

----------------------------------------------------------------------------------------------------
function BookController.Start()
	buildForms()
	Windows.Register("Book", function(_host)
		local w = Window.new("Kennel Book", Theme.Color.Info, Windows.Close)
		local zoneNames = { "All" }
		for _, z in Zones do
			table.insert(zoneNames, z.Name)
		end
		local zt = Tabs.new(w.Body, zoneNames, function(name)
			zoneFilter = zoneIdFromTab(name)
			applyFilter()
			refreshHeader()
		end, 28)
		local filterRow = Create.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 32),
			Parent = w.Body })
		local vt = Tabs.new(filterRow, VARIANT_TABS, function(name)
			variantFilter = name
			applyFilter()
			refreshHeader()
		end, 26)
		vt.Frame.Size = UDim2.new(0.62, 0, 1, 0)
		local progress = Create.Label({ Name = "Progress", Text = "", Font = Theme.Font.Body, TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.37, 0, 0, 26), Position = UDim2.new(0.63, 0, 0, 32), Parent = w.Body }, Theme.TextMax.Small)
		progressLabel = progress
		local mRow = Create.New("Frame", { Name = "Milestones", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 62), Parent = w.Body })
		Create.List(Enum.FillDirection.Horizontal, 6).Parent = mRow
		milestoneRow = mRow
		local detailLabel = Create.Label({ Name = "Detail", Text = "Tap a dog for details.", RichText = true, Font = Theme.Font.Body,
			TextColor3 = Theme.Color.TextDim, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.new(0, 0, 1, -28), BackgroundColor3 = Theme.Color.PanelLight, ZIndex = 5, Parent = w.Body }, Theme.TextMax.Small)
		Create.Corner(Theme.CornerSmall).Parent = detailLabel
		Create.Padding(2, 6).Parent = detailLabel
		detail = detailLabel
		local g = VirtualGrid.new({
			Parent = w.Body,
			Size = UDim2.new(1, 0, 1, -124),
			Position = UDim2.fromOffset(0, 92),
			CellMinWidth = 96,
			CellAspect = 1.05,
			MaxColumns = 10,
			Padding = 6,
			CreateCell = createCell,
			Render = renderCell,
		})
		grid = g
		-- Short screens (phone landscape): milestones + progress move to one bottom line, the detail line becomes
		-- a popup over the grid (shown for 5 s after a tap) and cells are smaller, so ~2 grid rows stay visible.
		local compact: boolean? = nil
		local function relayout()
			local bodyH = w.Body.AbsoluteSize.Y
			local isCompact = bodyH > 0 and bodyH < 300
			if isCompact == compact then
				return
			end
			compact = isCompact
			if isCompact then
				zt.Frame.Size = UDim2.new(1, 0, 0, 26)
				filterRow.Position = UDim2.fromOffset(0, 30)
				filterRow.Size = UDim2.new(1, 0, 0, 24)
				vt.Frame.Size = UDim2.new(1, 0, 1, 0)
				g.Frame.Position = UDim2.fromOffset(0, 58)
				g.Frame.Size = UDim2.new(1, 0, 1, -84)
				mRow.Position = UDim2.new(0, 0, 1, -22)
				mRow.Size = UDim2.new(0.62, 0, 0, 22)
				progress.Size = UDim2.new(0.37, 0, 0, 22)
				progress.Position = UDim2.new(0.63, 0, 1, -22)
				detailLabel.Size = UDim2.new(1, -12, 0, 30)
				detailLabel.Position = UDim2.new(0, 6, 1, -58)
				detailLabel.BackgroundTransparency = 0.05
				detailOverlay = true
				detailLabel.Visible = false
				g:SetCellSize(84, 0.9)
			else
				zt.Frame.Size = UDim2.new(1, 0, 0, 28)
				filterRow.Position = UDim2.fromOffset(0, 32)
				filterRow.Size = UDim2.new(1, 0, 0, 26)
				vt.Frame.Size = UDim2.new(0.62, 0, 1, 0)
				mRow.Position = UDim2.fromOffset(0, 62)
				mRow.Size = UDim2.new(1, 0, 0, 26)
				g.Frame.Position = UDim2.fromOffset(0, 92)
				g.Frame.Size = UDim2.new(1, 0, 1, -124)
				detailLabel.Size = UDim2.new(1, 0, 0, 28)
				detailLabel.Position = UDim2.new(0, 0, 1, -28)
				detailLabel.BackgroundTransparency = 1
				detailOverlay = false
				detailLabel.Visible = true
				progress.Size = UDim2.new(0.37, 0, 0, 26)
				progress.Position = UDim2.new(0.63, 0, 0, 32)
				g:SetCellSize(96, 1.05)
			end
		end
		w.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		relayout()
		applyFilter()
		return {
			Frame = w.Frame,
			OnOpen = function(_arg: any)
				if grid then
					grid:Refresh()
				end
				refreshHeader()
			end,
		}
	end)
	StateController.Changed:Connect(function(state)
		HudController.SetBadge("Book", claimable(state))
		if Windows.IsOpen("Book") then
			if grid then
				grid:Refresh()
			end
			refreshHeader()
		end
	end)
end

return BookController
