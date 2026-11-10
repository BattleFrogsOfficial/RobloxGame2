-- Pets, Eggs and Sell windows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)
local State = require(script.Parent.Parent.State)
local Placement = require(script.Parent.Parent.Placement)

local Inventory = {}

local C = Ui.Colors
local CELL = Vector2.new(156, 222)

local function rarityColor(r: string): Color3
	return Config.Rarities[Config.RarityIndex[r]].color
end

local function smallButton(parent: Instance, text: string, color: Color3, x: number, w: number, onClick: () -> ())
	return Ui.button({
		Text = text,
		Color = color,
		Size = UDim2.new(w, -6, 0, 30),
		Position = UDim2.new(x, 3, 1, -36),
		Stroke = 2,
		Radius = 8,
		ZIndex = 24,
		Parent = parent,
		OnClick = onClick,
	})
end

-- Shared card layout: preview on top, then up to three lines of text.
local function baseCard(parent: Instance, order: number, tag: string?, tagColor: Color3?)
	local card = Ui.card(parent, order)
	local holder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -10, 0, 100),
		Position = UDim2.fromOffset(5, 4),
		ZIndex = 23,
		Parent = card,
	})
	if tag then
		Ui.text({
			Text = tag,
			Size = UDim2.new(1, -10, 0, 18),
			Position = UDim2.fromOffset(6, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = tagColor or C.White,
			ZIndex = 25,
			Parent = card,
		})
	end
	local lines = {}
	for i = 1, 3 do
		lines[i] = Ui.text({
			Text = "",
			Size = UDim2.new(1, -8, 0, i == 1 and 22 or 18),
			Position = UDim2.fromOffset(4, 104 + (i - 1) * 22),
			ZIndex = 24,
			Parent = card,
		})
	end
	return card, holder, lines
end


local function emptyNote(parent: Instance, text: string)
	Ui.text({
		Text = text,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0.45, 0),
		TextColor3 = Color3.fromRGB(190, 190, 200),
		ZIndex = 23,
		Parent = parent,
	})
end

local function sortedPen(d)
	local list = {}
	for key, item in d.pen do
		table.insert(list, { key = key, item = item })
	end
	table.sort(list, function(a, b)
		return tonumber(a.key) < tonumber(b.key)
	end)
	return list
end

local function itemSig(i): string
	return table.concat({ i.kind or "", i.egg or "", i.animal or "", tostring(i.variant), tostring(i.start or ""), tostring(i.uid or "") }, ":")
end

-- Canonical text for the parts of state a window shows (skip re-render if same).
local function stateSig(d): string
	local t = {}
	for _, e in sortedPen(d) do
		table.insert(t, e.key .. "=" .. itemSig(e.item))
	end
	table.insert(t, "|")
	for _, e in d.eggs do
		table.insert(t, e.egg .. ":" .. e.variant)
	end
	table.insert(t, "|")
	for _, a in d.animals do
		table.insert(t, tostring(a.uid))
	end
	table.insert(t, "|" .. d.baseSlots)
	return table.concat(t, ",")
end

local function penUsed(d): number
	local n = 0
	for _ in d.pen do
		n += 1
	end
	return n
end

----------------------------------------------------------------------------
-- Pets
----------------------------------------------------------------------------
local pets = {}

local function animalLines(lines, animal: string, variant: string)
	local a = Config.AnimalById[animal]
	lines[1].Text = (variant ~= "Normal" and variant .. " " or "") .. a.name
	lines[1].TextColor3 = variant ~= "Normal" and Config.Variants[variant].color or C.White
	lines[2].Text = a.rarity
	lines[2].TextColor3 = rarityColor(a.rarity)
	lines[3].Text = Format.cash(Formulas.animalIncome(animal, variant)) .. "/s"
	lines[3].TextColor3 = C.Cash
end

local function renderPets()
	local d = State.data
	if not d then
		return
	end
	local sig = stateSig(d)
	if sig == pets.sig then
		return
	end
	pets.sig = sig
	for _, c in pets.grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local order = 0
	for _, entry in sortedPen(d) do
		local item = entry.item
		if item.kind == "animal" then
			order += 1
			local card, holder, lines = baseCard(pets.grid, order, "IN BASE", C.Green)
			Viewport.animal(holder, item.animal, item.variant)
			animalLines(lines, item.animal, item.variant)
			local key = entry.key
			smallButton(card, "Store", C.Blue, 0, 0.5, function()
				State.action("StoreAnimal", key)
			end)
			smallButton(card, "Sell", C.Orange, 0.5, 0.5, function()
				State.action("SellAnimal", "pen", key)
			end)
		end
	end
	for _, a in d.animals do
		order += 1
		local card, holder, lines = baseCard(pets.grid, order, "STORED", Color3.fromRGB(200, 200, 210))
		Viewport.animal(holder, a.animal, a.variant)
		animalLines(lines, a.animal, a.variant)
		local uid = a.uid
		smallButton(card, "Place", C.Green, 0, 0.5, function()
			State.action("PlaceAnimal", uid)
		end)
		smallButton(card, "Sell", C.Orange, 0.5, 0.5, function()
			State.action("SellAnimal", "storage", uid)
		end)
	end
	if order == 0 then
		emptyNote(pets.grid, "No pets yet! Part the sea, grab an egg and hatch it.")
	end
	pets.info.Text = string.format(
		"Base: %d/%d slots   |   Income: %s/s   |   Stored: %d",
		penUsed(d),
		d.baseSlots,
		Format.cash(d.income),
		#d.animals
	)
end

----------------------------------------------------------------------------
-- Eggs
----------------------------------------------------------------------------
local eggs = { timers = {} }

local function eggLines(lines, egg: string, variant: string)
	local e = Config.EggById[egg]
	lines[1].Text = (variant ~= "Normal" and variant .. " " or "") .. e.name
	lines[1].TextColor3 = variant ~= "Normal" and Config.Variants[variant].color or C.White
	lines[2].Text = e.rarity
	lines[2].TextColor3 = rarityColor(e.rarity)
end

local function tickEggTimers()
	local d = State.data
	if not d then
		return
	end
	-- Server os.time() plus how long since that state arrived.
	local now = d.osTime + (os.clock() - (eggs.stateClock or os.clock()))
	for _, t in eggs.timers do
		local left = t.item.start + t.item.dur - now
		if left <= 0 then
			t.label.Text = "Ready!"
			t.label.TextColor3 = C.Cash
			t.hatch.Visible = true
		else
			t.label.Text = "Hatches in " .. Format.time(left)
			t.label.TextColor3 = C.Yellow
			t.hatch.Visible = false
		end
	end
end

local function renderEggs()
	local d = State.data
	if not d then
		return
	end
	local sig = stateSig(d)
	if sig == eggs.sig then
		return
	end
	eggs.sig = sig
	table.clear(eggs.timers)
	for _, c in eggs.grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local order = 0
	for _, entry in sortedPen(d) do
		local item = entry.item
		if item.kind == "egg" then
			order += 1
			local card, holder, lines = baseCard(eggs.grid, order, "INCUBATING", C.Yellow)
			Viewport.egg(holder, item.egg, item.variant)
			eggLines(lines, item.egg, item.variant)
			local hatch = smallButton(card, "Hatch!", C.Green, 0, 1, function()
				State.action("HatchAll")
			end)
			table.insert(eggs.timers, { label = lines[3], item = item, hatch = hatch })
		end
	end
	for i, e in d.eggs do
		order += 1
		local card, holder, lines = baseCard(eggs.grid, order, "STORED", Color3.fromRGB(200, 200, 210))
		Viewport.egg(holder, e.egg, e.variant)
		eggLines(lines, e.egg, e.variant)
		lines[3].Text = "Sells for " .. Format.cash(Formulas.eggSellPrice(e.egg, e.variant))
		lines[3].TextColor3 = C.Cash
		smallButton(card, "Place", C.Green, 0, 0.5, function()
			-- Close the window and pick a spot in the plot.
			Ui.close("Eggs")
			Placement.start(i)
		end)
		smallButton(card, "Sell", C.Orange, 0.5, 0.5, function()
			State.action("SellEgg", i)
		end)
	end
	if order == 0 then
		emptyNote(eggs.grid, "No eggs! Walk to the shoreline and part the sea.")
	end
	eggs.info.Text = string.format("Base: %d/%d slots   |   Stored eggs: %d", penUsed(d), d.baseSlots, #d.eggs)
	tickEggTimers()
end

----------------------------------------------------------------------------
-- Sell
----------------------------------------------------------------------------
local sell = {}

local function renderSell()
	local d = State.data
	if not d then
		return
	end
	local sig = stateSig(d)
	if sig == sell.sig then
		return
	end
	sell.sig = sig
	for _, c in sell.grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local order, total = 0, 0
	for _, a in d.animals do
		order += 1
		local price = Formulas.animalSellPrice(a.animal, a.variant)
		total += price
		local card, holder, lines = baseCard(sell.grid, order, "STORED", Color3.fromRGB(200, 200, 210))
		Viewport.animal(holder, a.animal, a.variant)
		animalLines(lines, a.animal, a.variant)
		local uid = a.uid
		smallButton(card, "Sell " .. Format.cash(price), C.Orange, 0, 1, function()
			State.action("SellAnimal", "storage", uid)
		end)
	end
	for i, e in d.eggs do
		order += 1
		local price = Formulas.eggSellPrice(e.egg, e.variant)
		total += price
		local card, holder, lines = baseCard(sell.grid, order, "EGG", C.Yellow)
		Viewport.egg(holder, e.egg, e.variant)
		eggLines(lines, e.egg, e.variant)
		smallButton(card, "Sell " .. Format.cash(price), C.Orange, 0, 1, function()
			State.action("SellEgg", i)
		end)
	end
	for _, entry in sortedPen(d) do
		local item = entry.item
		if item.kind == "animal" then
			order += 1
			local price = Formulas.animalSellPrice(item.animal, item.variant)
			local card, holder, lines = baseCard(sell.grid, order, "IN BASE", C.Green)
			Viewport.animal(holder, item.animal, item.variant)
			animalLines(lines, item.animal, item.variant)
			local key = entry.key
			smallButton(card, "Sell " .. Format.cash(price), C.Red, 0, 1, function()
				State.action("SellAnimal", "pen", key)
			end)
		end
	end
	if order == 0 then
		emptyNote(sell.grid, "Nothing to sell yet.")
	end
	Ui.setButtonText(sell.allBtn, "Sell All Stored (" .. Format.cash(total) .. ")")
	sell.allBtn.Visible = total > 0
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------
local function windowWithGrid(gui: ScreenGui, name: string, title: string, color: Color3, icon: string)
	local win = Ui.window(gui, name, title, color, Vector2.new(840, 560), icon)
	local info = Ui.text({
		Text = "",
		Size = UDim2.new(1, -260, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 220, 230),
		ZIndex = 23,
		Parent = win.body,
	})
	local holder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		ZIndex = 22,
		Parent = win.body,
	})
	local grid = Ui.scrollGrid(holder, CELL, 12)
	return win, info, grid
end

function Inventory.init(gui: ScreenGui)
	local win
	win, pets.info, pets.grid = windowWithGrid(gui, "Pets", "Pets", C.Orange, "pets")
	win.onOpen = function()
		pets.sig = nil
		renderPets()
	end
	Ui.button({
		Text = "Place Best",
		Color = C.Green,
		Size = UDim2.fromOffset(200, 34),
		Position = UDim2.new(1, 0, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 24,
		Parent = win.body,
		OnClick = function()
			State.action("PlaceBest")
		end,
	})

	win, eggs.info, eggs.grid = windowWithGrid(gui, "Eggs", "Eggs", C.Teal, "egg")
	win.onOpen = function()
		eggs.sig = nil
		renderEggs()
	end
	Ui.button({
		Text = "Hatch All Ready",
		Color = C.Green,
		Size = UDim2.fromOffset(230, 34),
		Position = UDim2.new(1, 0, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 24,
		Parent = win.body,
		OnClick = function()
			State.action("HatchAll")
		end,
	})

	win, sell.info, sell.grid = windowWithGrid(gui, "Sell", "Sell", C.Orange, "cash")
	sell.info.Text = "Sell pets and eggs you don't need for cash."
	win.onOpen = function()
		sell.sig = nil
		renderSell()
	end
	sell.allBtn = Ui.button({
		Text = "Sell All Stored",
		Color = C.Red,
		Size = UDim2.fromOffset(260, 34),
		Position = UDim2.new(1, 0, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 24,
		Parent = win.body,
		OnClick = function()
			State.action("SellAllStored")
		end,
	})

	State.changed:Connect(function()
		eggs.stateClock = os.clock()
		if Ui.isOpen("Pets") then
			renderPets()
		end
		if Ui.isOpen("Eggs") then
			renderEggs()
		end
		if Ui.isOpen("Sell") then
			renderSell()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Ui.isOpen("Eggs") then
				tickEggTimers()
			end
		end
	end)
end

return Inventory
