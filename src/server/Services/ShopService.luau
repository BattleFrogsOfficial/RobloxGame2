--!nonstrict
-- Purchases: consumable balls (each purchase = Balls.ById[id].Uses throws; Tennis is free), training upgrades, yard slots, timed boosts (Sticky Ball, Lucky Biscuit),
-- consumables (Golden Whistle, Treat Pocket), cosmetics (Bones), EquipBall, plus Robux developer
-- products (idempotent ProcessReceipt) and gamepasses. Ids live in Config/Products.luau (0 = disabled).
-- Robux balls: Products.Balls = { [ballId] = { ProductId, Robux, Throws } } (one Robux buy button per consumable ball).
-- ShopPurchase("RobuxBall:<ballId>") prompts it (the client may also prompt the ProductId itself); a receipt for one
-- of those ProductIds grants Throws throws of that ball (capped at Balls.MaxOwned) and equips it, idempotently by
-- PurchaseId like every other receipt.
-- Paid products that influence random outcomes are refused where PolicyService restricts them.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Balls = require(Config:WaitForChild("Balls"))
local Shop = require(Config:WaitForChild("Shop"))
local Training = require(Config:WaitForChild("Training"))
local Products = require(Config:WaitForChild("Products"))
local Game = require(Config:WaitForChild("Game"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local DogService = require(script.Parent:WaitForChild("DogService"))
local BroadcastService = require(script.Parent:WaitForChild("BroadcastService"))

local ShopService = {}

-- Products.Balls is added by the UI side; absent = no Robux balls yet.
local function ballProducts(): { [string]: any }
	local t = (Products :: any).Balls
	return if type(t) == "table" then t else {}
end

-- ballId for a Robux ball ProductId (0 = not configured, never matches)
function ShopService.FindBallProduct(productId: any): string?
	if type(productId) ~= "number" or productId == 0 then
		return nil
	end
	for ballId, def in ballProducts() do
		if type(def) == "table" and def.ProductId == productId and Balls.ById[ballId] then
			return ballId
		end
	end
	return nil
end

-- Grant one Robux ball pack: Throws throws of that ball (capped at Balls.MaxOwned), equipped. Returns the new count.
function ShopService.GrantBallPack(state: any, ballId: string): number
	local ball = Balls.ById[ballId]
	local def = ballProducts()[ballId]
	local throws = math.max(1, math.floor(tonumber(def and def.Throws) or ball.Uses or 1))
	local left = math.min(Balls.MaxOwned, PlayerStats.BallCount(state, ballId) + throws)
	if ball.Consumable then
		state.Balls[ballId] = left
	end
	state.EquippedBall = ballId
	return left
end

local restricted: { [Player]: boolean } = {} -- PolicyService ArePaidRandomItemsRestricted
local pendingGrow: { [Player]: string } = {} -- InstantGrow target uid chosen before the prompt

local function income(player: Player, state: any): number
	return PlayerStats.IncomePerSec(state, DataService.Ctx(player))
end

local function applyBoost(state: any, boostId: string)
	local b = Shop.Boosts[boostId]
	local now = os.time()
	local cur = state.Boosts[boostId]
	local base = if type(cur) == "number" and cur > now then cur else now
	state.Boosts[boostId] = base + b.Duration
end

----------------------------------------------------------------------------------------------------
-- Cash / Bones purchases
----------------------------------------------------------------------------------------------------
local handlers: { [string]: (Player, any, string?) -> (boolean, string) } = {}

-- "Ball:<id>": buy one more pack of throws (repeatable) and equip it. The Tennis Ball is free: just equips.
handlers.Ball = function(player, state, ballId)
	local ball = ballId and Balls.ById[ballId]
	if not ball then
		return false, "Unknown ball"
	end
	if not ball.Consumable then
		state.EquippedBall = ball.Id
		return true, ball.Name .. " equipped"
	end
	local have = PlayerStats.BallCount(state, ball.Id)
	local uses = math.max(1, math.floor(ball.Uses or 1))
	if have + uses > Balls.MaxOwned then
		return false, "You can't carry more"
	end
	if not DataService.TrySpendCash(player, ball.Price) then
		return false, "Need " .. FormatNumber.Money(ball.Price)
	end
	state.Balls[ball.Id] = have + uses
	state.EquippedBall = ball.Id
	return true, ("Bought a %s! (x%d)"):format(ball.Name, have + uses)
end

handlers.Training = function(player, state)
	local level = state.TrainingLevel or 0
	if level >= Training.Upgrades.MaxLevel then
		return false, "Training is maxed"
	end
	local cost = Training.UpgradeCost(level + 1)
	if not DataService.TrySpendCash(player, cost) then
		return false, "Need " .. FormatNumber.Money(cost)
	end
	state.TrainingLevel = level + 1
	state.TutorialDone = true -- the first training purchase ends the scripted FTUE
	return true, ("Training level %d: x%s gains"):format(state.TrainingLevel,
		FormatNumber.Compact(Training.Mult(state.TrainingLevel)))
end

handlers.Slots = function(player, state)
	if state.SlotCount >= Shop.Slots.Max then
		return false, "Yard is at max size"
	end
	local cost = Shop.SlotCost(state.SlotCount)
	if not DataService.TrySpendCash(player, cost) then
		return false, "Need " .. FormatNumber.Money(cost)
	end
	state.SlotCount = math.min(Shop.Slots.Max, state.SlotCount + Shop.Slots.Step)
	DogService.FillSlots(player)
	DogService.RefreshDisplay(player)
	return true, ("Yard now holds %d dogs"):format(state.SlotCount)
end

handlers.Boost = function(player, state, boostId)
	local b = boostId and Shop.Boosts[boostId]
	if not b then
		return false, "Unknown boost"
	end
	local price = Shop.DynamicPrice(b.BaseCost, b.IncomeSeconds, income(player, state))
	if not DataService.TrySpendCash(player, price) then
		return false, "Need " .. FormatNumber.Money(price)
	end
	applyBoost(state, boostId :: string)
	return true, b.Name .. " active!"
end

handlers.Item = function(player, state, itemId)
	local it = itemId and Shop.Items[itemId]
	if not it then
		return false, "Unknown item"
	end
	if (state[it.Field] or 0) >= it.Max then
		return false, "You can't carry more"
	end
	local price = Shop.DynamicPrice(it.BaseCost, it.IncomeSeconds, income(player, state))
	if not DataService.TrySpendCash(player, price) then
		return false, "Need " .. FormatNumber.Money(price)
	end
	state[it.Field] = (state[it.Field] or 0) + it.Amount
	return true, ("%s x%d"):format(it.Name, state[it.Field])
end

handlers.Cosmetic = function(_player, state, cosmeticId)
	local c = cosmeticId and Shop.Cosmetics[cosmeticId]
	if not c then
		return false, "Unknown cosmetic"
	end
	if state.Cosmetics[cosmeticId] then
		return false, "Already owned"
	end
	if state.Bones < c.Bones then
		return false, ("Need %d Bones"):format(c.Bones)
	end
	state.Bones -= c.Bones
	state.Cosmetics[cosmeticId] = true
	return true, "Unlocked " .. c.Name
end

handlers.Product = function(player, state, arg)
	if not arg then
		return false, "Unknown product"
	end
	local key, extra = string.match(arg, "^([%w_]+):?(.*)$")
	local product = key and Products.DeveloperProducts[key]
	if not product then
		return false, "Unknown product"
	end
	if product.Id == 0 then
		return false, "Not available yet"
	end
	if product.RandomInfluence and restricted[player] then
		return false, "Not available in your region"
	end
	if product.Grant.InstantGrow then
		local dog = extra ~= "" and DogService.FindDog(state, extra)
		if not dog or not PlayerStats.IsPuppy(dog, os.time()) then
			return false, "Pick a puppy to grow"
		end
		pendingGrow[player] = dog.Uid
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
	return true, "Prompted"
end

-- "RobuxBall:<ballId>": prompt the Robux pack of a consumable ball (Products.Balls[ballId].ProductId).
handlers.RobuxBall = function(player, state, ballId)
	local ball = ballId and Balls.ById[ballId]
	local def = ballId and ballProducts()[ballId]
	if not ball or not ball.Consumable or type(def) ~= "table" then
		return false, "Unknown ball"
	end
	if (def.ProductId or 0) == 0 then
		return false, "Not available yet"
	end
	local influences = if def.RandomInfluence ~= nil then def.RandomInfluence == true else (ball.Luck or 0) > 0
	if influences and restricted[player] then
		return false, "Not available in your region"
	end
	if PlayerStats.BallCount(state, ball.Id) >= Balls.MaxOwned then
		return false, "You can't carry more"
	end
	MarketplaceService:PromptProductPurchase(player, def.ProductId)
	return true, "Prompted"
end

handlers.Pass = function(player, _state, passKey)
	local pass = passKey and Products.GamePasses[passKey]
	if not pass then
		return false, "Unknown pass"
	end
	if pass.Id == 0 then
		return false, "Not available yet"
	end
	if pass.RandomInfluence and restricted[player] then
		return false, "Not available in your region"
	end
	if DataService.GetPasses(player)[passKey] then
		return false, "Already owned"
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	return true, "Prompted"
end

local function purchase(player: Player, itemId: any): (boolean, string)
	if type(itemId) ~= "string" or #itemId == 0 or #itemId > 100 then
		return false, "Bad item"
	end
	local state = DataService.Get(player)
	if not state then
		return false, "Still loading"
	end
	local kind, arg = string.match(itemId, "^(%a+):?(.*)$")
	local handler = kind and handlers[kind]
	if not handler then
		return false, "Unknown item"
	end
	local ok, msg = handler(player, state, if arg ~= "" then arg else nil)
	if ok then
		DataService.Push(player)
	end
	return ok, msg
end

----------------------------------------------------------------------------------------------------
-- Robux grants
----------------------------------------------------------------------------------------------------
local function grantProduct(player: Player, state: any, key: string)
	local g = Products.DeveloperProducts[key].Grant
	if g.Boost then
		applyBoost(state, g.Boost)
	end
	if g.Whistles then
		state.Whistles += g.Whistles
	end
	if g.TreatPockets then
		state.TreatPockets += g.TreatPockets
	end
	if g.InstantGrow then
		DogService.InstantGrow(player, pendingGrow[player])
		pendingGrow[player] = nil
	end
	if g.CashIncomeSeconds then
		local amount = math.max(g.MinCash or 0, math.floor(income(player, state) * g.CashIncomeSeconds))
		DataService.AddCash(player, amount)
	end
	if g.ServerLuck then
		local sl = DataService.ServerLuck
		local now = os.time()
		sl.Amount = g.ServerLuck
		sl.Until = math.max(now, sl.Until) + (g.Duration or 900)
		BroadcastService.Send("ServerLuck", ("%s activated Server Luck (+%s Luck for everyone) for %s!"):format(
			player.DisplayName, tostring(g.ServerLuck), FormatNumber.Duration(sl.Until - now)))
		for _, p in DataService.Players() do
			DataService.Push(p)
		end
	end
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local state = DataService.WaitForState(player, 15)
	if not state then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if DataService.HasReceipt(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = Products.FindProductKey(info.ProductId)
	local ballId = if key then nil else ShopService.FindBallProduct(info.ProductId)
	if not key and not ballId then
		warn("[ShopService] receipt for unknown product id " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(function()
		if key then
			grantProduct(player, state, key)
		else
			local left = ShopService.GrantBallPack(state, ballId :: string)
			BroadcastService.Notify(player, ("Thanks! %s x%d"):format(Balls.ById[ballId :: string].Name, left), "Purchase")
		end
	end)
	if not ok then
		warn("[ShopService] grant failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.RecordReceipt(player, purchaseId)
	DataService.Push(player)
	if DataService.SaveNow(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- The grant + receipt are in memory; Roblox retries later and the recorded receipt short-circuits.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function refreshPasses(player: Player)
	for key, pass in Products.GamePasses do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns then
				DataService.SetPass(player, key, true)
			end
		end
	end
	DogService.FillSlots(player)
end

function ShopService.IsRestricted(player: Player): boolean
	return restricted[player] == true
end

function ShopService.Start()
	local limiter = RateLimiter.new(Game.RateLimits.Shop[1], Game.RateLimits.Shop[2])
	local shopRemote = Remotes.Get("ShopPurchase") :: RemoteFunction
	shopRemote.OnServerInvoke = function(player: Player, itemId: any)
		if not limiter:Check(player) then
			return false, "Slow down"
		end
		local ok, a, b = pcall(purchase, player, itemId)
		if not ok then
			warn("[ShopService] purchase error: " .. tostring(a))
			return false, "Error"
		end
		return a, b
	end

	local equipLimiter = RateLimiter.new(Game.RateLimits.EquipBall[1], Game.RateLimits.EquipBall[2])
	local equip = Remotes.Get("EquipBall") :: RemoteEvent
	equip.OnServerEvent:Connect(function(player: Player, ballId: any)
		if not equipLimiter:Check(player) or type(ballId) ~= "string" then
			return
		end
		local state = DataService.Get(player)
		-- refuse a consumable ball with no throws left (the Tennis Ball is always available)
		if state and Balls.ById[ballId] and PlayerStats.BallCount(state, ballId) > 0 then
			state.EquippedBall = ballId
			DataService.Push(player)
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local key = Products.FindPassKey(passId)
		if key then
			DataService.SetPass(player, key, true)
			DogService.FillSlots(player)
			DogService.RefreshDisplay(player)
			BroadcastService.Notify(player, "Thanks! " .. Products.GamePasses[key].Name .. " is active.", "Purchase")
		end
	end)

	DataService.OnLoaded(function(player: Player)
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			restricted[player] = info.ArePaidRandomItemsRestricted == true
		end
		player:SetAttribute("PaidRandomItemsRestricted", restricted[player] == true)
		refreshPasses(player)
		DogService.RefreshDisplay(player)
		DataService.Push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		restricted[player] = nil
		pendingGrow[player] = nil
	end)
end

return ShopService
