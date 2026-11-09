-- Cash upgrades (Luck) and Robux monetization: game passes + dev products.
-- Product/pass IDs live in Config. While an ID is 0 the item is free in
-- Studio (for testing) and unavailable in a live server.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)

local Data = require(script.Parent.Data)
local Pens = require(script.Parent.Pens)

local Shop = {}

local GREEN = Color3.fromRGB(120, 255, 120)

local passByKey, passById = {}, {}
for _, p in Config.Passes do
	passByKey[p.key] = p
	if p.id ~= 0 then
		passById[p.id] = p
	end
end
local productByKey, productById = {}, {}
for _, p in Config.Products do
	productByKey[p.key] = p
	if p.id ~= 0 then
		productById[p.id] = p
	end
end

-- Hooks so Rewards can be granted by a product without a circular require.
Shop.callbacks = {
	skipPlaytime = nil :: ((Player) -> ())?,
}

function Shop.buyLuck(player: Player, times: number?): (boolean, string?)
	local d = Data.get(player)
	if not d then
		return false
	end
	local bought = 0
	for _ = 1, math.clamp(times or 1, 1, 10) do
		if d.luckLevel >= Config.Luck.MaxLevel then
			break
		end
		local cost = Formulas.luckCost(d.luckLevel)
		if not Data.trySpend(player, cost) then
			break
		end
		d.luckLevel += 1
		bought += 1
	end
	if bought == 0 then
		if d.luckLevel >= Config.Luck.MaxLevel then
			return false, "Luck is maxed!"
		end
		return false, "You need " .. Format.cash(Formulas.luckCost(d.luckLevel)) .. "."
	end
	Data.markDirty(player)
	return true, "+" .. bought .. " Luck level" .. (bought > 1 and "s" or "") .. "!"
end

local function grantPass(player: Player, key: string)
	local s = Data.session(player)
	if not s then
		return
	end
	s.passes[key] = true
	Data.markDirty(player)
	Pens.refreshSigns(player)
	Data.notify(player, passByKey[key].name .. " unlocked!", GREEN)
end

-- Returns true once the product's reward has been applied.
local function grantProduct(player: Player, key: string): boolean
	local d = Data.get(player)
	if not d then
		return false
	end
	local income = Data.income(player)
	if key == "StarterPack" then
		Data.addCash(player, 2500)
		Pens.addEgg(player, "Treasure", "Normal")
		d.starterPackBought = true
	elseif key == "CashSmall" then
		Data.addCash(player, math.max(1000, math.floor(income * 600)))
	elseif key == "CashLarge" then
		Data.addCash(player, math.max(10000, math.floor(income * 3600)))
	elseif key == "LuckPotion" then
		d.boosts.luckUntil = math.max(d.boosts.luckUntil, os.time()) + Config.LuckPotionSeconds
	elseif key == "InstantHatch" then
		Pens.instantHatch(player)
	elseif key == "SkipPlaytime" then
		if Shop.callbacks.skipPlaytime then
			Shop.callbacks.skipPlaytime(player)
		end
	else
		return false
	end
	Data.markDirty(player)
	Data.notify(player, productByKey[key].name .. " received!", GREEN)
	return true
end

-- A receipt is only acknowledged once the reward is safely saved. Until
-- then Roblox keeps retrying (and refunds if it never succeeds).
local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local product = productById[info.ProductId]
	if not player or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = Data.get(player)
	local session = Data.session(player)
	if not d or not session or not session.canSave then
		-- This session can't save, so the purchase would vanish on leave.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local rid = tostring(info.PurchaseId)
	local alreadyGranted = table.find(d.receipts, rid) ~= nil
	if not alreadyGranted then
		if not grantProduct(player, product.key) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(d.receipts, rid)
		while #d.receipts > 50 do
			table.remove(d.receipts, 1)
		end
	end
	if Data.save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Granted in memory but not saved yet: the retry will only re-save.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Called by the client when an item has no real ID yet (Studio testing only).
function Shop.studioGrant(player: Player, kind: string, key: string): (boolean, string?)
	if not RunService:IsStudio() then
		return false, "This item isn't set up yet."
	end
	if kind == "pass" and passByKey[key] and passByKey[key].id == 0 then
		grantPass(player, key)
		return true
	elseif kind == "product" and productByKey[key] and productByKey[key].id == 0 then
		return grantProduct(player, key)
	end
	return false
end

local function loadPasses(player: Player)
	for _, p in Config.Passes do
		if p.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.id)
			end)
			if ok and owns then
				local s = Data.session(player)
				if s then
					s.passes[p.key] = true
				end
			end
		end
	end
	Data.markDirty(player)
	Pens.refreshSigns(player)
end

function Shop.init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local p = passById[passId]
		if purchased and p then
			grantPass(player, p.key)
		end
	end)
	Data.Loaded.Event:Connect(loadPasses)
end

return Shop
