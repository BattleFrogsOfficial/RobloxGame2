--!strict
-- Yard manager: every owned dog as a card (virtualised), sorted by $/s. Display / Kennel / Sell actions,
-- slot and income summary, puppy growth countdowns.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))

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
local VirtualGrid = require(Components:WaitForChild("VirtualGrid"))

local Dogs = {}

export type DogsDeps = {
	Parent: Instance,
	DogAction: (action: string, dogUid: string) -> (boolean, string?),
	Toast: (text: string, icon: string?, palette: string?) -> (),
	OnClose: () -> (),
}

local CELL = Vector2.new(150, 236)

function Dogs.new(deps: DogsDeps)
	local panel = Panel.new({ Title = "My Dogs", Icon = "dog", Palette = "Sky", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Dogs" })
	local body = panel.Body
	Decor.List(body, Enum.FillDirection.Vertical, Theme.Space.M)

	-- Summary row
	local summary: Frame = Make("Frame", { Name = "Summary", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, ZIndex = 53, Parent = body })
	Decor.List(summary, Enum.FillDirection.Horizontal, Theme.Space.M, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local filter = "All"
	local tabs = Tabs.new({
		Items = { { Id = "All", Text = "All" }, { Id = "Yard", Text = "Roaming" }, { Id = "Kennel", Text = "Kennel" }, { Id = "Puppies", Text = "Puppies" } },
		Selected = filter,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(440, 44),
		Parent = summary,
		OnSelect = function(id)
			filter = id
		end,
	})
	local stats = Label.Body({ Name = "Stats", Text = "", Size = UDim2.new(1, -460, 0, 44), XAlign = Enum.TextXAlignment.Right, LayoutOrder = 2, ZIndex = 54, Parent = summary, Font = Theme.Font.BodyBold })

	local list: { any } = {}
	local now = os.time()

	local function rebuildList()
		now = os.time()
		list = {}
		for _, d in State.Dogs() do
			local puppy = PlayerStats.IsPuppy(d, now)
			local include = filter == "All" or (filter == "Yard" and d.Displayed and not d.Held) or (filter == "Kennel" and (not d.Displayed or d.Held)) or (filter == "Puppies" and puppy)
			if include then
				table.insert(list, d)
			end
		end
		table.sort(list, function(a, b)
			local ra, rb = PlayerStats.DogRate(a, now), PlayerStats.DogRate(b, now)
			if ra ~= rb then
				return ra > rb
			end
			return tostring(a.Uid) < tostring(b.Uid)
		end)
		local computed = State.Computed()
		stats.Text = string.format("%d / %d slots   %s   %d puppies", #State.Dogs() - (computed.DogsHeld or 0), State.Slots(), FormatNumber.PerSecond(State.Income()), computed.Puppies or 0)
	end

	local function createCell(): GuiObject
		local cell: Frame = Make("Frame", { Name = "DogCell", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 54 })
		Decor.Corner(cell, Theme.Radius.Card)
		Decor.Stroke(cell, Theme.Stroke.Panel)
		Decor.PaletteGradient(cell, Theme.Palette.Paper)
		local preview: Frame = Make("Frame", { Name = "Preview", BackgroundColor3 = Theme.Color.PaperShade, BorderSizePixel = 0, Size = UDim2.new(1, -16, 0, 84), Position = UDim2.fromOffset(8, 8), ZIndex = 55, Parent = cell })
		Decor.Corner(preview, Theme.Radius.Card - 2)
		Decor.Stroke(preview, 3, Theme.Color.Track)
		Icon.new({ Name = "dog", Size = 48, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 56, Parent = preview }).Name = "DogIcon"
		Icon.new({ Name = "variant_gold", Size = 16, Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), ZIndex = 57, Parent = preview }).Name = "VariantIcon"
		Label.Display({ Name = "Title", Text = "", TextSize = 14, Color = Theme.Color.TextOnPaper, Stroke = false, Font = Theme.Font.BodyBold, Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 96), XAlign = Enum.TextXAlignment.Center, YAlign = Enum.TextYAlignment.Top, Wrap = true, ZIndex = 55, Parent = cell })
		Label.Caption({ Name = "Rarity", Text = "", Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 134), XAlign = Enum.TextXAlignment.Center, Font = Theme.Font.BodyBold, ZIndex = 55, Parent = cell })
		Label.Caption({ Name = "Income", Text = "", Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 150), XAlign = Enum.TextXAlignment.Center, YAlign = Enum.TextYAlignment.Top, Wrap = true, TextSize = Theme.Text.Caption, ZIndex = 55, Parent = cell })
		local row: Frame = Make("Frame", { Name = "Actions", BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -8), AnchorPoint = Vector2.new(0, 1), ZIndex = 55, Parent = cell })
		Decor.List(row, Enum.FillDirection.Horizontal, Theme.Space.XS)
		Button.new({ Name = "Toggle", Text = "Show", Palette = "Sky", TextSize = Theme.Text.Caption + 1, Size = UDim2.fromOffset(84, 44), Shadow = false, ZIndex = 56, LayoutOrder = 1, Parent = row })
		Button.new({ Name = "Sell", Icon = "cash", IconSize = 16, Palette = "Danger", Size = UDim2.fromOffset(46, 44), Shadow = false, ZIndex = 56, LayoutOrder = 2, Parent = row })
		return cell
	end

	local function renderCell(cell: GuiObject, index: number)
		local d = list[index]
		if not d then
			cell.Visible = false
			return
		end
		local def = DogCatalog.Get(d.DogId)
		local name = if def then def.Name else tostring(d.DogId)
		local rarity = if def then def.Rarity else "Common"
		local preview = cell:FindFirstChild("Preview") :: Frame
		local rarityColor = Theme.RarityColor(rarity)
		;(preview:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = rarityColor
		local vIcon = preview:FindFirstChild("VariantIcon") :: Frame
		local variantName = Icon.ForVariant(d.Variant)
		vIcon.Visible = variantName ~= nil
		if variantName then
			Icon.Set(vIcon, variantName)
		end
		;(cell:FindFirstChild("Title") :: TextLabel).Text = name
		local rl = cell:FindFirstChild("Rarity") :: TextLabel
		rl.Text = string.upper(rarity)
		rl.TextColor3 = rarityColor
		local il = cell:FindFirstChild("Income") :: TextLabel
		local puppy = PlayerStats.IsPuppy(d, now)
		local rate = PlayerStats.DogRate(d, now)
		if d.Held then
			il.Text = "Waiting for a slot"
		elseif puppy then
			il.Text = FormatNumber.PerSecond(rate) .. "\ngrows in " .. FormatNumber.Duration((d.GrownAt or now) - now)
		else
			il.Text = FormatNumber.PerSecond(rate)
		end
		local actions = cell:FindFirstChild("Actions") :: Frame
		local toggle = actions:FindFirstChild("Toggle") :: TextButton
		local toggleLabel = toggle:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel
		toggleLabel.Text = if d.Displayed then "Kennel" else "Show"
		-- Rebind click handlers by replacing the invisible overlay each render (cheap: two buttons).
		local old = actions:FindFirstChild("Bind")
		if old then
			old:Destroy()
		end
		local bind = Make("Folder", { Name = "Bind", Parent = actions })
		local c1 = toggle.Activated:Connect(function()
			local ok, msg = deps.DogAction(if d.Displayed then "Kennel" else "Display", d.Uid)
			if not ok then
				deps.Toast(msg or "Couldn't do that", "close", "Danger")
			end
		end)
		local sell = actions:FindFirstChild("Sell") :: TextButton
		local c2 = sell.Activated:Connect(function()
			local ok, msg = deps.DogAction("Sell", d.Uid)
			if ok then
				deps.Toast("Sold " .. name .. " for " .. FormatNumber.Money(PlayerStats.SellValue(d)), "cash", "Cash")
			else
				deps.Toast(msg or "Couldn't sell", "close", "Danger")
			end
		end)
		bind.Destroying:Connect(function()
			c1:Disconnect()
			c2:Disconnect()
		end)
	end

	local grid = VirtualGrid.new({ Parent = body, Size = UDim2.new(1, 0, 1, -(44 + Theme.Space.M)), LayoutOrder = 2, CellSize = CELL, Gap = Theme.Space.M, Count = 0, Create = createCell, Render = renderCell })

	local function refresh()
		rebuildList()
		grid:SetCount(#list)
	end
	local conn = State.Changed:Connect(function()
		if panel:IsOpen() then
			refresh()
		end
	end)
	-- Tabs re-render
	local origSelect = tabs.Select
	tabs.Select = function(self, id)
		origSelect(self, id)
		refresh()
	end

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

return Dogs
