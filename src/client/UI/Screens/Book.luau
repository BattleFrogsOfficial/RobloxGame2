--!strict
-- Kennel Book: zone tabs, milestone bar with claim buttons, virtualised grid of the zone's base dogs with
-- variant badges. Unknown dogs are silhouettes with a hidden name.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Zones = require(Config:WaitForChild("Zones"))
local Rarities = require(Config:WaitForChild("Rarities"))
local ShopConfig = require(Config:WaitForChild("Shop"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local State = require(UI:WaitForChild("State"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Panel = require(Components:WaitForChild("Panel"))
local Tabs = require(Components:WaitForChild("Tabs"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))
local ProgressBar = require(Components:WaitForChild("ProgressBar"))
local VirtualGrid = require(Components:WaitForChild("VirtualGrid"))

local Book = {}

export type BookDeps = {
	Parent: Instance,
	ClaimReward: (zoneId: string, milestone: number) -> (boolean, string?),
	Toast: (text: string, icon: string?, palette: string?) -> (),
	OnClose: () -> (),
}

local CELL = Vector2.new(118, 142)

local REWARD_TEXT = { [25] = "Cash", [50] = "+2% Luck", [75] = "Trophy", [100] = "Title" }

function Book.new(deps: BookDeps)
	local panel = Panel.new({ Title = "Kennel Book", Icon = "book", Palette = "Purple", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Book" })
	local body = panel.Body
	Decor.List(body, Enum.FillDirection.Vertical, Theme.Space.M)

	local zoneId = Zones[1].Id
	local zoneItems = {}
	for _, z in Zones do
		table.insert(zoneItems, { Id = z.Id, Text = z.Name, Icon = Icon.ForZone(z.Id) })
	end

	-- Milestone strip
	local strip: Frame = Make("Frame", { Name = "Milestones", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 76), LayoutOrder = 2, ZIndex = 53, Parent = body })
	local progress = ProgressBar.new({ Name = "Progress", Palette = "Purple", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 0), ZIndex = 54, Label = "0 / 80", Parent = strip })
	local claims: Frame = Make("Frame", { Name = "Claims", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 32), ZIndex = 54, Parent = strip })
	Decor.List(claims, Enum.FillDirection.Horizontal, Theme.Space.S)
	local claimButtons: { [number]: Button.ButtonHandle } = {}
	for i, m in ShopConfig.BookMilestones do
		claimButtons[m] = Button.new({
			Name = "Claim_" .. m,
			Text = m .. "%  " .. (REWARD_TEXT[m] or ""),
			Palette = "Slate",
			TextSize = Theme.Text.Caption + 1,
			Size = UDim2.fromOffset(150, 44),
			LayoutOrder = i,
			Shadow = false,
			ZIndex = 55,
			Parent = claims,
			OnClick = function()
				local ok, msg = deps.ClaimReward(zoneId, m)
				if ok then
					deps.Toast("Claimed the " .. m .. "% reward", "trophy", "Cash")
				else
					deps.Toast(msg or "Not yet", "lock", "Slate")
				end
			end,
		})
	end

	local dogs: { any } = {}
	local function rebuildList()
		dogs = DogCatalog.ZoneDogs(zoneId)
		-- Order: by rarity then name, Mythic first so the grid opens on the chase.
		table.sort(dogs, function(a, b)
			local ia, ib = State.RarityIndex(a.Rarity), State.RarityIndex(b.Rarity)
			if ia ~= ib then
				return ia > ib
			end
			return (a.Order or 0) < (b.Order or 0)
		end)
	end

	local function refreshMilestones()
		local owned, total = State.ZoneBookCount(zoneId)
		progress:SetFraction(if total > 0 then owned / total else 0)
		progress:SetLabel(string.format("%d / %d dogs", owned, total))
		local pct = if total > 0 then owned / total * 100 else 0
		for m, b in claimButtons do
			local claimed = State.BookRewardClaimed(zoneId, m)
			local reached = pct >= m - 1e-9
			b:SetPalette(if claimed then "Grass" elseif reached then "Cash" else "Slate")
			b:SetText((if claimed then "Done " else m .. "%  ") .. (REWARD_TEXT[m] or ""))
			b:SetEnabled(reached and not claimed)
		end
	end

	local function createCell(): GuiObject
		local cell: Frame = Make("Frame", { Name = "BookCell", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 54 })
		Decor.Corner(cell, Theme.Radius.Card)
		Decor.Stroke(cell, 2)
		Decor.PaletteGradient(cell, Theme.Palette.Paper)
		local preview: Frame = Make("Frame", { Name = "Preview", BackgroundColor3 = Theme.Color.PaperShade, BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 72), Position = UDim2.fromOffset(6, 6), ZIndex = 55, Parent = cell })
		Decor.Corner(preview, Theme.Radius.Card - 2)
		Decor.Stroke(preview, 3, Theme.Color.Track)
		Icon.new({ Name = "dog", Size = 48, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 56, Parent = preview }).Name = "DogIcon"
		local badges: Frame = Make("Frame", { Name = "Badges", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 1, -4), AnchorPoint = Vector2.new(0, 1), ZIndex = 57, Parent = preview })
		Decor.List(badges, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Right)
		for i, v in Rarities.VariantOrder do
			local ic = Icon.new({ Name = Icon.ForVariant(v) :: string, Size = 16, LayoutOrder = i, ZIndex = 58, Parent = badges })
			ic.Name = "Badge_" .. v
		end
		Label.Display({ Name = "Title", Text = "", TextSize = Theme.Text.Caption, Color = Theme.Color.TextOnPaper, Stroke = false, Font = Theme.Font.BodyBold, Size = UDim2.new(1, -8, 0, 36), Position = UDim2.fromOffset(4, 82), XAlign = Enum.TextXAlignment.Center, YAlign = Enum.TextYAlignment.Top, Wrap = true, ZIndex = 55, Parent = cell })
		Label.Caption({ Name = "Rarity", Text = "", Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -6), AnchorPoint = Vector2.new(0, 1), XAlign = Enum.TextXAlignment.Center, Font = Theme.Font.BodyBold, ZIndex = 55, Parent = cell })
		return cell
	end

	local function renderCell(cell: GuiObject, index: number)
		local def = dogs[index]
		if not def then
			cell.Visible = false
			return
		end
		local owned = State.BookOwned(def.Id)
		local color = Theme.RarityColor(def.Rarity)
		local preview = cell:FindFirstChild("Preview") :: Frame
		;(preview:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = if owned then color else Theme.Color.Track
		local dogIcon = preview:FindFirstChild("DogIcon") :: Frame
		for _, px in dogIcon:GetChildren() do
			if px:IsA("Frame") then
				px.BackgroundTransparency = if owned then 0 else 0.55
			end
		end
		local variants = State.BookVariants(def.Id)
		local badges = preview:FindFirstChild("Badges") :: Frame
		for _, v in Rarities.VariantOrder do
			local b = badges:FindFirstChild("Badge_" .. v) :: Frame
			b.Visible = def.Rarity ~= "Common"
			for _, px in b:GetChildren() do
				if px:IsA("Frame") then
					px.BackgroundTransparency = if variants[v] then 0 else 0.75
				end
			end
		end
		;(cell:FindFirstChild("Title") :: TextLabel).Text = if owned then def.Name else "? ? ?"
		local rl = cell:FindFirstChild("Rarity") :: TextLabel
		rl.Text = string.upper(def.Rarity)
		rl.TextColor3 = color
	end

	local grid = VirtualGrid.new({ Parent = body, Size = UDim2.new(1, 0, 1, -(52 + 76 + Theme.Space.M * 2)), LayoutOrder = 3, CellSize = CELL, Gap = Theme.Space.S, Count = 0, Create = createCell, Render = renderCell })

	local function refresh()
		rebuildList()
		refreshMilestones()
		grid:SetCount(#dogs)
	end

	Tabs.new({ Items = zoneItems, Selected = zoneId, LayoutOrder = 1, Parent = body, Scrollable = true, OnSelect = function(id)
		zoneId = id
		refresh()
	end })

	local totals = Label.Display({ Name = "Totals", Text = "", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(260, Panel.HeaderHeight), Position = UDim2.new(1, -64, 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 54, Parent = panel.Header })
	local function refreshTotals()
		local owned, total = 0, 0
		for _, z in Zones do
			local o, t = State.ZoneBookCount(z.Id)
			owned += o
			total += t
		end
		totals.Text = string.format("%d / %d collected", owned, total)
	end

	local conn = State.Changed:Connect(function()
		if panel:IsOpen() then
			refreshMilestones()
			grid:Refresh()
			refreshTotals()
		end
	end)

	local handle = { Panel = panel } :: any
	function handle.Open(_, zone: string?)
		if zone then
			zoneId = zone
		end
		refresh()
		refreshTotals()
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

return Book
