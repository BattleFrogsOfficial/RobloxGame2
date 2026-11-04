--!strict
-- Yard manager: every owned dog as a rarity-coloured card (virtualised; the shop card look: name, rarity word, the
-- dog drawn in its own coat colours, a dark stat strip with its $/s, then Show/Kennel + Sell), sorted by $/s.
-- Slot and income summary, puppy growth countdowns.
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
local Card = require(Components:WaitForChild("Card"))
local VirtualGrid = require(Components:WaitForChild("VirtualGrid"))

local Dogs = {}

export type DogsDeps = {
	Parent: Instance,
	DogAction: (action: string, dogUid: string) -> (boolean, string?),
	Toast: (text: string, icon: string?, palette: string?) -> (),
	OnClose: () -> (),
}

local CELL = Vector2.new(164, 236)

function Dogs.new(deps: DogsDeps)
	local panel = Panel.new({ Title = "My Dogs", Icon = "dog", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Dogs" })
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
	local stats = Label.Display({ Name = "Stats", Text = "", TextSize = 18, Size = UDim2.new(1, -460, 0, 44), XAlign = Enum.TextXAlignment.Right, LayoutOrder = 2, ZIndex = 54, Parent = summary })

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
		Decor.Stroke(cell, Theme.Stroke.Card)
		Card.Paint(cell, Theme.RarityColor("Common"))
		Label.Display({ Name = "Title", Text = "", TextSize = 18, Size = UDim2.new(1, -12, 0, 36), Position = UDim2.fromOffset(6, 3), XAlign = Enum.TextXAlignment.Center, Wrap = true, ZIndex = 55, Parent = cell })
		Label.Display({ Name = "Rarity", Text = "", TextSize = 14, Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 39), XAlign = Enum.TextXAlignment.Center, ZIndex = 55, Parent = cell })
		local preview: Frame = Make("Frame", { Name = "Preview", BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 78), Position = UDim2.fromOffset(6, 58), ZIndex = 55, Parent = cell })
		Icon.new({ Name = "dog", Size = 64, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 56, Parent = preview }).Name = "DogIcon"
		Icon.new({ Name = "variant_gold", Size = 32, Position = UDim2.fromOffset(0, 0), ZIndex = 57, Parent = preview }).Name = "VariantIcon"
		local strip: Frame = Make("Frame", { Name = "Strip", BackgroundColor3 = Theme.Color.Strip, BackgroundTransparency = Theme.StripTransparency, BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 138), ZIndex = 55, Parent = cell })
		Decor.Corner(strip, 6)
		Decor.Stroke(strip, 2)
		Label.Display({ Name = "Income", Text = "", TextSize = 16, Size = UDim2.new(1, -8, 1, -2), Position = UDim2.fromOffset(4, 1), XAlign = Enum.TextXAlignment.Center, Wrap = true, ZIndex = 56, Parent = strip })
		local row: Frame = Make("Frame", { Name = "Actions", BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 44), Position = UDim2.new(0, 6, 1, -6), AnchorPoint = Vector2.new(0, 1), ZIndex = 55, Parent = cell })
		Decor.List(row, Enum.FillDirection.Horizontal, Theme.Space.XS)
		Button.new({ Name = "Toggle", Text = "Show", Palette = "Sky", TextSize = 16, Size = UDim2.new(1, -56, 0, 44), Shadow = false, ZIndex = 56, LayoutOrder = 1, Parent = row })
		Button.new({ Name = "Sell", Icon = "cash", IconSize = 32, Palette = "Danger", Size = UDim2.fromOffset(52, 44), Shadow = false, ZIndex = 56, LayoutOrder = 2, Parent = row })
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
		local rarityColor = Theme.RarityColor(rarity)
		Card.Paint(cell, rarityColor)
		local preview = cell:FindFirstChild("Preview") :: Frame
		Icon.Set(preview:FindFirstChild("DogIcon") :: Frame, "dog", Icon.DogColors(def) or {})
		local vIcon = preview:FindFirstChild("VariantIcon") :: Frame
		local variantName = Icon.ForVariant(d.Variant)
		vIcon.Visible = variantName ~= nil
		if variantName then
			Icon.Set(vIcon, variantName)
		end
		local title = cell:FindFirstChild("Title") :: TextLabel
		title.Text = name
		-- one line when it fits at 14+, else two lines at 14
		title.TextSize = Card.FitSize(name, CELL.X - 12, { 18, 16, 14 })
		local rl = cell:FindFirstChild("Rarity") :: TextLabel
		rl.Text = rarity .. (if d.Variant then " " .. d.Variant else "")
		rl.TextColor3 = Card.TagColor(rarityColor)
		local il = (cell:FindFirstChild("Strip") :: Frame):FindFirstChild("Income") :: TextLabel
		local puppy = PlayerStats.IsPuppy(d, now)
		local rate = PlayerStats.DogRate(d, now)
		if d.Held then
			il.Text = "Waiting for a slot"
		elseif puppy then
			il.Text = FormatNumber.PerSecond(rate) .. "\nGrows in " .. FormatNumber.Duration((d.GrownAt or now) - now)
		else
			il.Text = FormatNumber.PerSecond(rate)
		end
		il.TextSize = if puppy and not d.Held then 14 else 18
		local actions = cell:FindFirstChild("Actions") :: Frame
		local toggle = actions:FindFirstChild("Toggle") :: TextButton
		local toggleLabel = toggle:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel
		toggleLabel.Text = if d.Displayed then "Kennel" else "Show"
		local toggleGradient = toggle:FindFirstChildOfClass("UIGradient")
		if toggleGradient then
			local p = if d.Displayed then Theme.Palette.Slate else Theme.Palette.Sky
			toggleGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(1, p.Bottom) })
		end
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
