--!strict
-- Shop panel: Balls (consumable, repeat purchases), Boosts, Yard (training + slots), Items (Sticky Ball,
-- Golden Whistle, Treat Pocket, Instant Grow), Cosmetics, Robux. This panel is the only way to buy Yard /
-- Boost / Item upgrades (they have no world stands). Prices come from State.Computed().Prices when the
-- server supplies them.
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
local Button = require(Components:WaitForChild("Button"))

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

	-- Balls: every ball but the Tennis Ball is a consumable (one purchase = Uses throws). Each card shows the
	-- throws you hold ("x3"), the price per throw, a repeatable Buy button and an Equip button while count > 0.
	local function renderBalls()
		local equipped = State.EquippedBallId()
		local active = State.Ball().Id -- what the next throw uses (Tennis once the equipped ball runs out)
		for i, id in Balls.Order do
			local ball = Balls.ById[id]
			local count = State.BallCount(id)
			local isActive = active == id
			local stats = string.format("x%.2f", ball.RangeMult)
			if ball.Luck > 0 then
				stats ..= string.format(" +%d%% luck", math.floor(ball.Luck * 100 + 0.5))
			else
				stats ..= " range"
			end
			if not ball.Consumable then
				local card = Card.new({
					Title = ball.Name,
					Subtitle = stats .. "\nFree, unlimited",
					Icon = Icon.ForBall(id),
					Owned = true,
					Price = if isActive then "Equipped" else "Equip",
					PricePalette = if isActive then "Slate" else "Sky",
					LayoutOrder = i,
					Parent = grid,
					OnBuy = function()
						if not isActive then
							deps.EquipBall(id)
						end
					end,
				})
				card:SetSelected(isActive)
				continue
			end
			local uses = math.max(1, ball.Uses or 1)
			local perThrow = ball.Price / uses
			local p = price("Ball:" .. id, ball.Price)
			local card = Card.new({
				Title = ball.Name,
				Subtitle = stats .. "\n" .. FormatNumber.Money(perThrow) .. "/throw",
				Icon = Icon.ForBall(id),
				Price = FormatNumber.Money(p),
				PricePalette = "Grass",
				PriceIcon = if count > 0 then nil else "cash", -- half-width button when Equip shares the row
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					buy("Ball:" .. id, ball.Name)
				end,
			})
			card:SetSelected(isActive)
			if State.Cash() < p then
				card:SetPrice(FormatNumber.Money(p), false)
			end
			-- owned count badge in the preview corner
			Label.Display({
				Name = "Count",
				Text = "x" .. FormatNumber.Compact(count),
				TextSize = Theme.Text.Body,
				Size = UDim2.fromOffset(56, 22),
				Position = UDim2.fromOffset(6, 4),
				XAlign = Enum.TextXAlignment.Left,
				ZIndex = card.Preview.ZIndex + 2,
				Parent = card.Preview,
			})
			local buyBtn = card.Buy
			if count > 0 and buyBtn then
				-- split the bottom row: Buy (left) + Equip / On (right)
				local pad = Theme.Space.S
				buyBtn.Root.Size = UDim2.new(0.5, -math.ceil(pad * 1.5), 0, 44)
				local equipBtn = Button.new({
					Name = "Equip",
					Text = if isActive then "On" else "Equip",
					Palette = if isActive then "Slate" else "Sky",
					TextSize = Theme.Text.Caption + 2,
					Size = UDim2.new(0.5, -math.ceil(pad * 1.5), 0, 44),
					Position = UDim2.new(1, -pad, 1, -pad),
					AnchorPoint = Vector2.new(1, 1),
					Shadow = false,
					ZIndex = buyBtn.Root.ZIndex,
					Parent = card.Root,
					OnClick = function()
						if equipped ~= id then
							deps.EquipBall(id)
						end
					end,
				})
				if isActive then
					equipBtn:SetEnabled(false)
				end
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

	-- The puppy an Instant Grow would target: the one with the longest wait left.
	local function growTarget(): (any, number)
		local best: any, bestLeft = nil, 0
		local now = os.time()
		for _, d in State.Dogs() do
			local left = (d.GrownAt or 0) - now
			if left > bestLeft and not d.Held and not d.PendingSale then
				best, bestLeft = d, left
			end
		end
		return best, bestLeft
	end

	local function renderItems()
		local income = State.Income()
		-- Sticky Ball (timed catch boost; same purchase as the Boosts tab)
		local sticky = ShopConfig.Boosts.StickyBall
		local order = 0
		if sticky then
			order += 1
			local sp = price("Boost:StickyBall", ShopConfig.DynamicPrice(sticky.BaseCost, sticky.IncomeSeconds, income))
			local card = Card.new({
				Title = sticky.Name,
				Subtitle = string.format("+%d%% catch  %s", math.floor(sticky.Amount * 100 + 0.5), FormatNumber.Duration(sticky.Duration)),
				Icon = "boost_catch",
				Price = FormatNumber.Money(sp),
				PriceIcon = "cash",
				LayoutOrder = order,
				Parent = grid,
				OnBuy = function()
					buy("Boost:StickyBall", sticky.Name)
				end,
			})
			if State.Cash() < sp then
				card:SetPrice(FormatNumber.Money(sp), false)
			end
		end
		local icons = { GoldenWhistle = "whistle", TreatPocket = "treat" }
		local blurbs = { GoldenWhistle = "Call back a dog that ran off", TreatPocket = "Second catch try" }
		for _, id in ShopConfig.ItemOrder do
			local it = ShopConfig.Items[id]
			order += 1
			local p = price("Item:" .. id, ShopConfig.DynamicPrice(it.BaseCost, it.IncomeSeconds, income))
			local have = (State.Get()[it.Field] or 0)
			local card = Card.new({
				Title = it.Name,
				Subtitle = (blurbs[id] or "") .. "  (" .. have .. ")",
				Icon = icons[id] or "info",
				Price = FormatNumber.Money(p),
				PriceIcon = "cash",
				LayoutOrder = order,
				Parent = grid,
				OnBuy = function()
					buy("Item:" .. id, it.Name)
				end,
			})
			if State.Cash() < p or have >= it.Max then
				card:SetPrice(if have >= it.Max then "Max" else FormatNumber.Money(p), false)
			end
		end
		-- Instant Grow (Robux product; grows the puppy with the longest wait)
		local grow = Products.DeveloperProducts.InstantGrow
		if grow then
			order += 1
			local target, left = growTarget()
			local available = grow.Id ~= 0 and target ~= nil
			Card.new({
				Title = "Instant Grow",
				Subtitle = if target then "Grow a puppy now (" .. FormatNumber.Duration(left) .. " left)" else "No puppies to grow",
				Icon = "timer",
				Price = if grow.Id == 0 then "Soon" elseif target then "Buy" else "None",
				PricePalette = if available then "Robux" else "Slate",
				LayoutOrder = order,
				Parent = grid,
				OnBuy = function()
					local t = growTarget()
					if grow.Id ~= 0 and t then
						buy("Product:InstantGrow:" .. tostring(t.Uid), "Instant Grow")
					end
				end,
			})
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
