--!strict
-- Shop panel: Balls (consumable, repeat purchases), Boosts, Yard (training + slots), Items (Sticky Ball,
-- Golden Whistle, Treat Pocket, Instant Grow), Cosmetics, Robux. This panel is the only way to buy Yard /
-- Boost / Item upgrades (they have no world stands). Prices come from State.Computed().Prices when the
-- server supplies them. Every tab is a row of tall reference-style cards (Components/Card): rarity-coloured
-- background, name, rarity word, big icon, stat strip, grey cash button + purple Robux button.
local Players = game:GetService("Players")
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
	{ Id = "Robux", Text = "Robux", Icon = "robux" },
}

-- Ball tiers wear the rarity colours in order (Tennis Common ... Golden Legendary).
local BALL_RARITY = { Tennis = "Common", Rubber = "Uncommon", FlyingDisc = "Rare", Glow = "Epic", Golden = "Legendary" }

local function pctText(x: number): string
	return string.format("+%d%%", math.floor(x * 100 + 0.5))
end

-- "Not available yet" unless the product id is configured; otherwise the Roblox purchase prompt.
local function promptProduct(productId: number, toast: (string, string?, string?) -> ())
	if productId == 0 then
		toast("Not available yet", "robux", "Slate")
		return
	end
	local ok = pcall(function()
		game:GetService("MarketplaceService"):PromptProductPurchase(Players.LocalPlayer, productId)
	end)
	if not ok then
		toast("Not available yet", "robux", "Slate")
	end
end

function Shop.new(deps: ShopDeps)
	local panel = Panel.new({ Title = "Shop", Icon = "shop", Parent = deps.Parent, OnClose = deps.OnClose, Name = "Shop" })
	local body = panel.Body
	Decor.List(body, Enum.FillDirection.Vertical, Theme.Space.S)

	local current = "Balls"
	-- One row of tall cards, scrolling sideways when a tab has more than fit.
	local grid: ScrollingFrame = Make("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -(44 + Theme.Space.S)),
		LayoutOrder = 2,
		ZIndex = 53,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Palette.Header.Top,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
	})
	Decor.List(grid, Enum.FillDirection.Horizontal, Theme.Space.M, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Make("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), Parent = grid })

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

	-- Balls: every ball but the Tennis Ball is a consumable (one purchase = Uses throws). The card shows the throws
	-- you hold as the corner badge ("x3"), the cash price and the Robux pack (Products.Balls). Equipping is the
	-- hotbar's job; the active ball's card has a white border.
	local function renderBalls()
		local active = State.Ball().Id -- what the next throw uses (Tennis once the equipped ball runs out)
		for i, id in Balls.Order do
			local ball = Balls.ById[id]
			local count = State.BallCount(id)
			local isActive = active == id
			local stat = string.format("x%.2f Range", ball.RangeMult)
			if ball.Luck > 0 then
				stat ..= "  " .. pctText(ball.Luck) .. " Luck"
			end
			if not ball.Consumable then
				local card = Card.new({
					Title = ball.Name,
					Rarity = BALL_RARITY[id] or "Common",
					Icon = Icon.ForBall(id),
					Stat = stat,
					Badge = "Free",
					Action = if isActive then "Equipped" else "Equip",
					ActionPalette = if isActive then "Slate" else "Grass",
					LayoutOrder = i,
					Parent = grid,
					OnAction = function()
						if not isActive then
							deps.EquipBall(id)
						end
					end,
				})
				card:SetSelected(isActive)
				continue
			end
			local p = price("Ball:" .. id, ball.Price)
			local pack = (Products :: any).Balls and (Products :: any).Balls[id]
			local card = Card.new({
				Title = ball.Name,
				Rarity = BALL_RARITY[id] or "Common",
				Icon = Icon.ForBall(id),
				Stat = stat,
				Badge = if count > 0 then "x" .. FormatNumber.Compact(count) else nil,
				Price = FormatNumber.Money(p),
				PriceEnabled = State.Cash() >= p,
				Robux = if pack then pack.Robux else nil,
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					buy("Ball:" .. id, ball.Name)
				end,
				OnRobux = function()
					if pack then
						promptProduct(pack.ProductId, deps.Toast)
					end
				end,
			})
			card:SetSelected(isActive)
		end
	end

	local function renderBoosts()
		local income = State.Income()
		local active: { [string]: number } = {}
		for _, b in State.ActiveBoosts() do
			active[b.Id] = b.ExpiresAt - os.time()
		end
		for i, id in ShopConfig.BoostOrder do
			local b = ShopConfig.Boosts[id]
			local p = price("Boost:" .. id, ShopConfig.DynamicPrice(b.BaseCost, b.IncomeSeconds, income))
			local left = active[id]
			Card.new({
				Title = b.Name,
				Tag = FormatNumber.Duration(b.Duration) .. " Boost",
				Rarity = if b.Kind == "Luck" then "Uncommon" else "Rare",
				Icon = if b.Kind == "Luck" then "boost_luck" else "boost_catch",
				Stat = pctText(b.Amount) .. (if b.Kind == "Luck" then " Luck" else " Catch"),
				Badge = if left and left > 0 then FormatNumber.Duration(left) else nil,
				Price = FormatNumber.Money(p),
				PriceEnabled = State.Cash() >= p,
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					buy("Boost:" .. id, b.Name)
				end,
			})
		end
	end

	local function renderYard()
		local s = State.Get()
		local level = s.TrainingLevel or 0
		local nextLevel = level + 1
		local maxed = level >= Training.Upgrades.MaxLevel
		local tp = price("Training", Training.UpgradeCost(nextLevel))
		Card.new({
			Title = "Training Gear",
			Tag = "Level " .. level,
			Rarity = "Epic",
			Icon = "throw_power",
			Stat = if maxed then "Max level" else string.format("x%.1f Strength gain", Training.Mult(nextLevel)),
			Price = if maxed then nil else FormatNumber.Money(tp),
			PriceEnabled = State.Cash() >= tp,
			Action = if maxed then "Maxed" else nil,
			LayoutOrder = 1,
			Parent = grid,
			OnBuy = function()
				if not maxed then
					buy("Training", "training gear")
				end
			end,
		})
		local slots = s.SlotCount or ShopConfig.Slots.Start
		local slotMax = slots >= ShopConfig.Slots.Max
		local sp = price("Slots", ShopConfig.SlotCost(slots))
		Card.new({
			Title = "Yard Slots",
			Tag = State.Slots() .. " slots",
			Rarity = "Rare",
			Icon = "slot",
			Stat = "+" .. ShopConfig.Slots.Step .. " Slots",
			Price = if slotMax then nil else FormatNumber.Money(sp),
			PriceEnabled = State.Cash() >= sp,
			Action = if slotMax then "Maxed" else nil,
			LayoutOrder = 2,
			Parent = grid,
			OnBuy = function()
				if not slotMax then
					buy("Slots", "yard slots")
				end
			end,
		})
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
			Card.new({
				Title = sticky.Name,
				Tag = FormatNumber.Duration(sticky.Duration) .. " Boost",
				Rarity = "Rare",
				Icon = "sticky",
				Stat = pctText(sticky.Amount) .. " Catch",
				Price = FormatNumber.Money(sp),
				PriceEnabled = State.Cash() >= sp,
				LayoutOrder = order,
				Parent = grid,
				OnBuy = function()
					buy("Boost:StickyBall", sticky.Name)
				end,
			})
		end
		local icons = { GoldenWhistle = "whistle", TreatPocket = "treat" }
		local stats = { GoldenWhistle = "Calls back a runaway", TreatPocket = "Second catch try" }
		local tiers = { GoldenWhistle = "Legendary", TreatPocket = "Uncommon" }
		for _, id in ShopConfig.ItemOrder do
			local it = ShopConfig.Items[id]
			order += 1
			local p = price("Item:" .. id, ShopConfig.DynamicPrice(it.BaseCost, it.IncomeSeconds, income))
			local have = (State.Get()[it.Field] or 0)
			local full = have >= it.Max
			Card.new({
				Title = it.Name,
				Tag = "Item",
				Rarity = tiers[id] or "Common",
				Icon = icons[id] or "info",
				Stat = stats[id] or "",
				Badge = if have > 0 then "x" .. have else nil,
				Price = if full then "Max" else FormatNumber.Money(p),
				PriceEnabled = State.Cash() >= p and not full,
				LayoutOrder = order,
				Parent = grid,
				OnBuy = function()
					buy("Item:" .. id, it.Name)
				end,
			})
		end
		-- Instant Grow (Robux product; grows the puppy with the longest wait)
		local grow = Products.DeveloperProducts.InstantGrow
		if grow then
			order += 1
			local target, left = growTarget()
			Card.new({
				Title = "Instant Grow",
				Tag = if target then FormatNumber.Duration(left) .. " left" else "No puppies",
				Rarity = "Mythic",
				Icon = "timer",
				Stat = "Grow a puppy now",
				Robux = "Buy",
				LayoutOrder = order,
				Parent = grid,
				OnRobux = function()
					local t = growTarget()
					if grow.Id == 0 then
						deps.Toast("Not available yet", "robux", "Slate")
					elseif t then
						buy("Product:InstantGrow:" .. tostring(t.Uid), "Instant Grow")
					else
						deps.Toast("No puppies to grow", "dog", "Slate")
					end
				end,
			})
		end
	end

	local function renderCosmetics()
		local icons = { Collar = "walk", Hat = "star", YardDecor = "kennel", PadTrail = "paw" }
		local slotNames = { Collar = "Collar", Hat = "Hat", YardDecor = "Yard Decor", PadTrail = "Pad Trail" }
		local owned = State.Get().Cosmetics or {}
		for i, id in ShopConfig.CosmeticOrder do
			local c = ShopConfig.Cosmetics[id]
			local has = owned[id] == true
			local tier = if c.Bones >= 500 then "Epic" elseif c.Bones >= 250 then "Rare" elseif c.Bones >= 100 then "Uncommon" else "Common"
			Card.new({
				Title = c.Name,
				Tag = slotNames[c.Slot] or c.Slot,
				Rarity = tier,
				Icon = icons[c.Slot] or "star",
				Stat = "Looks only",
				Action = if has then "Owned" else nil,
				Price = if has then nil else FormatNumber.Compact(c.Bones),
				PriceIcon = if has then nil else "bone",
				PriceEnabled = State.Bones() >= c.Bones,
				LayoutOrder = i,
				Parent = grid,
				OnBuy = function()
					if not has then
						buy("Cosmetic:" .. id, c.Name)
					end
				end,
			})
		end
	end

	local function renderRobux()
		local i = 0
		local passIcons = { DoubleCash = "cash", ExtraSlots = "slot", FastGrowth = "timer", VIP = "star", LuckyPaw = "luck" }
		local passTier = { DoubleCash = "Legendary", ExtraSlots = "Rare", FastGrowth = "Uncommon", VIP = "Mythic", LuckyPaw = "Epic" }
		local passOrder = { "DoubleCash", "LuckyPaw", "VIP", "ExtraSlots", "FastGrowth" }
		for _, key in passOrder do
			local pass = Products.GamePasses[key]
			if not pass then
				continue
			end
			i += 1
			local owned = State.Get().Passes and State.Get().Passes[key] == true
			Card.new({
				Title = pass.Name,
				Tag = "Game Pass",
				Rarity = passTier[key] or "Rare",
				Icon = passIcons[key] or "star",
				Stat = "Forever",
				Action = if owned then "Owned" else nil,
				Robux = if owned then nil elseif pass.Id == 0 then "Soon" else "Buy",
				LayoutOrder = i,
				Parent = grid,
				OnRobux = function()
					if pass.Id == 0 then
						deps.Toast("Not available yet", "robux", "Slate")
					elseif not owned then
						buy("Pass:" .. key, pass.Name)
					end
				end,
			})
		end
		local productIcons = { StickyBall = "sticky", LuckyBiscuit = "boost_luck", GoldenWhistle1 = "whistle", GoldenWhistle3 = "whistle", TreatPocket3 = "treat", InstantGrow = "timer", CashSmall = "cash", CashLarge = "cash", ServerLuck = "luck" }
		local productOrder = { "CashSmall", "CashLarge", "ServerLuck", "LuckyBiscuit", "StickyBall", "GoldenWhistle1", "GoldenWhistle3", "TreatPocket3", "InstantGrow" }
		for _, key in productOrder do
			local product = Products.DeveloperProducts[key]
			if not product then
				continue
			end
			i += 1
			Card.new({
				Title = product.Name,
				Tag = "One-time",
				Rarity = if string.find(key, "Cash") then "Legendary" elseif string.find(key, "Luck") then "Uncommon" else "Rare",
				Icon = productIcons[key] or "star",
				Robux = if product.Id == 0 then "Soon" else "Buy",
				LayoutOrder = 100 + i,
				Parent = grid,
				OnRobux = function()
					if product.Id == 0 then
						deps.Toast("Not available yet", "robux", "Slate")
					else
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
	-- Wallet in the header (cash + bones) so prices are judged in place.
	local wallet: Frame = Make("Frame", { Name = "Wallet", BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 40), Position = UDim2.new(1, -(Button.CloseSize + 24), 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 54, Parent = panel.Header })
	Decor.List(wallet, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	Icon.new({ Name = "cash", Size = 32, LayoutOrder = 1, ZIndex = 55, Parent = wallet })
	local cashText = Label.Display({ Name = "Cash", Text = "", TextSize = 24, Size = UDim2.fromOffset(110, 40), LayoutOrder = 2, ZIndex = 55, Parent = wallet })
	Icon.new({ Name = "bone", Size = 32, LayoutOrder = 3, ZIndex = 55, Parent = wallet })
	local bonesText = Label.Display({ Name = "Bones", Text = "", TextSize = 24, Size = UDim2.fromOffset(80, 40), LayoutOrder = 4, ZIndex = 55, Parent = wallet })
	local function refreshWallet()
		cashText.Text = FormatNumber.Money(State.Cash())
		bonesText.Text = FormatNumber.Compact(State.Bones())
	end

	local conn = State.Changed:Connect(function()
		if panel:IsOpen() then
			render()
		end
		refreshWallet()
	end)

	local handle = { Panel = panel, Tabs = tabs } :: any
	function handle.Open(_, tab: string?)
		if tab then
			current = tab
			tabs:Select(tab)
		end
		refreshWallet()
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
