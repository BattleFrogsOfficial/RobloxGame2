--!strict
-- Shop panel: Balls, Boosts, Yard (training + slots), Items, Cosmetics, Robux. Prices come from
-- State.Computed().Prices when the server supplies them.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Balls = require(Config:WaitForChild("Balls"))
local ShopConfig = require(Config:WaitForChild("Shop"))
local Training = require(Config:WaitForChild("Training"))
local Products = require(Config:WaitForChild("Products"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local State = require(UI:WaitForChild("State"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Panel = require(Components:WaitForChild("Panel"))
local Tabs = require(Components:WaitForChild("Tabs"))
local Card = require(Components:WaitForChild("Card"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))

local Shop = {}

export type ShopDeps = {
	Parent: Instance,
	Purchase: (itemId: string) -> (boolean, string?),
	EquipBall: (ballId: string) -> (),
	Toast: (text: string, icon: string?, palette: string?) -> (),
	OnClose: () -> (),
}

local TABS = {
	{ Id = "Balls", Text = "Balls", Icon = "ball_tennis" },
	{ Id = "Boosts", Text = "Boosts", Icon = "boost_luck" },
	{ Id = "Yard", Text = "Yard", Icon = "kennel" },
	{ Id = "Items", Text = "Items", Icon = "whistle" },
	{ Id = "Cosmetics", Text = "Style", Icon = "walk" },
	{ Id = "Robux", Text = "Robux", Icon = "star" },
}

function Shop.new(deps: ShopDeps)
	local panel = Panel.new({ Title = "Shop", Icon = "shop", Palette = "Grass", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Shop" })
	local body = panel.Body
	Decor.List(body, Enum.FillDirection.Vertical, Theme.Space.M)

	local current = "Balls"
	local grid: ScrollingFrame = Make("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -(44 + Theme.Space.M)),
		LayoutOrder = 2,
		ZIndex = 53,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Color.Ink,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	Decor.Grid(grid, Vector2.new(Card.DefaultSize.X.Offset, Card.DefaultSize.Y.Offset), Theme.Space.M)
	Make("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = grid })

	local function clear()
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	local function price(key: string, fallback: number): number
		local p = State.Computed().Prices
		if type(p) == "table" and type(p[key]) == "number" then
			return p[key]
		end
		return fallback
	end

	local function buy(itemId: string, label: string)
		local ok, msg = deps.Purchase(itemId)
		if ok then
			deps.Toast("Bought " .. label, "check", "Grass")
		else
			deps.Toast(msg or "Can't buy that yet", "close", "Danger")
		end
	end

	local function renderBalls()
		local s = State.Get()
		local equipped = s.EquippedBall or Balls.Default
		for i, id in Balls.Order do
			local ball = Balls.ById[id]
			local owned = State.OwnsBall(id)
			local isEquipped = equipped == id
			local card = Card.new({
				Title = ball.Name,
				Subtitle = string.format("x%.2f range\n+%d%% luck", ball.RangeMult, math.floor(ball.Luck * 100 + 0.5)),
				Icon = Icon.ForBall(id),
				Owned = owned,
				Price = if isEquipped then "Equipped" elseif owned then "Equip" else FormatNumber.Money(ball.Price),
				PricePalette = if isEquipped then "Slate" elseif owned then "Sky" else "Grass",
				PriceIcon = if owned then nil else "cash",
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					if isEquipped then
						return
					elseif owned then
						deps.EquipBall(id)
					else
						buy("Ball:" .. id, ball.Name)
					end
				end,
			})
			if not owned and State.Cash() < ball.Price then
				card:SetPrice(FormatNumber.Money(ball.Price), false)
			end
		end
	end

	local function renderBoosts()
		local income = State.Income()
		for i, id in ShopConfig.BoostOrder do
			local b = ShopConfig.Boosts[id]
			local p = price("Boost:" .. id, ShopConfig.DynamicPrice(b.BaseCost, b.IncomeSeconds, income))
			local what = if b.Kind == "Luck" then string.format("+%d%% luck", math.floor(b.Amount * 100 + 0.5)) else string.format("+%d%% catch", math.floor(b.Amount * 100 + 0.5))
			local card = Card.new({
				Title = b.Name,
				Subtitle = what .. "  " .. FormatNumber.Duration(b.Duration),
				Icon = if b.Kind == "Luck" then "boost_luck" else "boost_catch",
				Price = FormatNumber.Money(p),
				PriceIcon = "cash",
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					buy("Boost:" .. id, b.Name)
				end,
			})
			if State.Cash() < p then
				card:SetPrice(FormatNumber.Money(p), false)
			end
		end
	end

	local function renderYard()
		local s = State.Get()
		local level = s.TrainingLevel or 0
		local nextLevel = level + 1
		local maxed = level >= Training.Upgrades.MaxLevel
		local tp = price("Training", Training.UpgradeCost(nextLevel))
		local trainCard = Card.new({
			Title = "Training Gear",
			Subtitle = if maxed then "Max level" else string.format("Lv %d > %d   x%.1f gain", level, nextLevel, Training.Mult(nextLevel)),
			Icon = "throw_power",
			Price = if maxed then "Maxed" else FormatNumber.Money(tp),
			PricePalette = if maxed then "Slate" else "Grass",
			PriceIcon = if maxed then nil else "cash",
			LayoutOrder = 1,
			Parent = grid,
			OnBuy = function()
				if not maxed then
					buy("Training", "training gear")
				end
			end,
		})
		if not maxed and State.Cash() < tp then
			trainCard:SetPrice(FormatNumber.Money(tp), false)
		end
		local slots = s.SlotCount or ShopConfig.Slots.Start
		local slotMax = slots >= ShopConfig.Slots.Max
		local sp = price("Slots", ShopConfig.SlotCost(slots))
		local slotCard = Card.new({
			Title = "Yard Slots",
			Subtitle = string.format("%d slots  +%d", State.Slots(), ShopConfig.Slots.Step),
			Icon = "slot",
			Price = if slotMax then "Maxed" else FormatNumber.Money(sp),
			PricePalette = if slotMax then "Slate" else "Grass",
			PriceIcon = if slotMax then nil else "cash",
			LayoutOrder = 2,
			Parent = grid,
			OnBuy = function()
				if not slotMax then
					buy("Slots", "yard slots")
				end
			end,
		})
		if not slotMax and State.Cash() < sp then
			slotCard:SetPrice(FormatNumber.Money(sp), false)
		end
	end

	local function renderItems()
		local income = State.Income()
		local icons = { GoldenWhistle = "whistle", TreatPocket = "treat" }
		local blurbs = { GoldenWhistle = "Call back a dog that ran off", TreatPocket = "Second catch try" }
		for i, id in ShopConfig.ItemOrder do
			local it = ShopConfig.Items[id]
			local p = price("Item:" .. id, ShopConfig.DynamicPrice(it.BaseCost, it.IncomeSeconds, income))
			local have = (State.Get()[it.Field] or 0)
			local card = Card.new({
				Title = it.Name,
				Subtitle = (blurbs[id] or "") .. "  (" .. have .. ")",
				Icon = icons[id] or "info",
				Price = FormatNumber.Money(p),
				PriceIcon = "cash",
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					buy("Item:" .. id, it.Name)
				end,
			})
			if State.Cash() < p or have >= it.Max then
				card:SetPrice(if have >= it.Max then "Max" else FormatNumber.Money(p), false)
			end
		end
	end

	local function renderCosmetics()
		local icons = { Collar = "walk", Hat = "star", YardDecor = "kennel", PadTrail = "paw" }
		local owned = State.Get().Cosmetics or {}
		for i, id in ShopConfig.CosmeticOrder do
			local c = ShopConfig.Cosmetics[id]
			local has = owned[id] == true
			local card = Card.new({
				Title = c.Name,
				Subtitle = c.Slot,
				Icon = icons[c.Slot] or "star",
				Owned = has,
				Price = if has then "Owned" else tostring(c.Bones),
				PricePalette = if has then "Slate" else "Bone",
				PriceIcon = if has then nil else "bone",
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					if not has then
						buy("Cosmetic:" .. id, c.Name)
					end
				end,
			})
			if not has and State.Bones() < c.Bones then
				card:SetPrice(tostring(c.Bones), false)
			end
		end
	end

	local function robuxPreview(): Frame
		local f: Frame = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		Make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = Theme.RobuxImage,
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 55,
			Parent = f,
		})
		return f
	end

	local function renderRobux()
		local i = 0
		local passIcons = { DoubleCash = "cash", ExtraSlots = "slot", FastGrowth = "timer", VIP = "star", LuckyPaw = "luck" }
		for key, pass in Products.GamePasses do
			i += 1
			local owned = State.Get().Passes and State.Get().Passes[key] == true
			Card.new({
				Title = pass.Name,
				Subtitle = if owned then "Owned" else "Game pass",
				Icon = passIcons[key] or "star",
				Owned = owned,
				Price = if owned then "Owned" elseif pass.Id == 0 then "Soon" else "Buy",
				PricePalette = if owned or pass.Id == 0 then "Slate" else "Robux",
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					if not owned and pass.Id ~= 0 then
						buy("Pass:" .. key, pass.Name)
					end
				end,
			})
		end
		local productIcons = { StickyBall = "sticky", LuckyBiscuit = "boost_luck", GoldenWhistle1 = "whistle", GoldenWhistle3 = "whistle", TreatPocket3 = "treat", InstantGrow = "timer", CashSmall = "cash", CashLarge = "cash", ServerLuck = "luck" }
		for key, product in Products.DeveloperProducts do
			i += 1
			Card.new({
				Title = product.Name,
				Subtitle = "One-time",
				Icon = productIcons[key] or "star",
				Price = if product.Id == 0 then "Soon" else "Buy",
				PricePalette = if product.Id == 0 then "Slate" else "Robux",
				LayoutOrder = 100 + i,
				Parent = grid,
				OnBuy = function()
					if product.Id ~= 0 then
						buy("Product:" .. key, product.Name)
					end
				end,
			})
		end
		if i == 0 then
			Label.Body({ Text = "Nothing here yet.", Parent = grid })
		end
	end

	local renderers = { Balls = renderBalls, Boosts = renderBoosts, Yard = renderYard, Items = renderItems, Cosmetics = renderCosmetics, Robux = renderRobux }
	local function render()
		clear()
		local r = renderers[current]
		if r then
			r()
		end
	end

	local tabs = Tabs.new({ Items = TABS, Selected = current, LayoutOrder = 1, Parent = body, Scrollable = true, OnSelect = function(id)
		current = id
		render()
	end })
	grid.Parent = body
	-- Wallet line in the header (cash + bones) so prices are judged in place.
	local wallet = Label.Display({ Name = "Wallet", Text = "", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(240, Panel.HeaderHeight), Position = UDim2.new(1, -64, 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 54, Parent = panel.Header })

	local conn = State.Changed:Connect(function()
		if panel:IsOpen() then
			render()
		end
		wallet.Text = FormatNumber.Money(State.Cash()) .. "   " .. FormatNumber.Compact(State.Bones()) .. " bones"
	end)

	local handle = { Panel = panel, Tabs = tabs } :: any
	function handle.Open(_, tab: string?)
		if tab then
			current = tab
			tabs:Select(tab)
		end
		wallet.Text = FormatNumber.Money(State.Cash()) .. "   " .. FormatNumber.Compact(State.Bones()) .. " bones"
		render()
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

return Shop
