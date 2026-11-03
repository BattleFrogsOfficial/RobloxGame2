--!strict
-- Derived player numbers from a PlayerState snapshot. Pure; used by the server (authority) and
-- available to the client (HUD reach/catch line, odds panel). Times are os.time() seconds.
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Util = script.Parent
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local Layout = require(Config:WaitForChild("Layout"))
local Balls = require(Config:WaitForChild("Balls"))
local Shop = require(Config:WaitForChild("Shop"))
local Training = require(Config:WaitForChild("Training"))
local Timers = require(Config:WaitForChild("Timers"))
local Products = require(Config:WaitForChild("Products"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local Odds = require(Util:WaitForChild("Odds"))

export type Ctx = {
	Now: number?,
	Passes: { [string]: boolean }?, -- owned gamepass keys (Products.GamePasses)
	ServerLuck: number?, -- active server-wide luck boost amount
}
export type Source = { Name: string, Amount: number }

local PlayerStats = {}

local function now(ctx: Ctx?): number
	return (ctx and ctx.Now) or os.time()
end

local function hasPass(ctx: Ctx?, key: string): boolean
	return ctx ~= nil and ctx.Passes ~= nil and ctx.Passes[key] == true
end

function PlayerStats.MaxFieldDistance(): number
	return Layout.Field.MaxZ - Layout.ThrowLine.Z
end

function PlayerStats.ZoneForDistance(distance: number): any
	for i, z in Zones do
		if distance >= z.MinDistance and (distance < z.MaxDistance or i == #Zones) then
			return z
		end
	end
	return if distance < Zones[1].MinDistance then Zones[1] else Zones[#Zones]
end

function PlayerStats.IsPuppy(dog: any, t: number): boolean
	return t < (dog.GrownAt or 0)
end

-- $/s of one owned dog before gamepass multipliers. Held / pending-sale dogs earn nothing.
function PlayerStats.DogRate(dog: any, t: number): number
	if dog.Held or dog.PendingSale then
		return 0
	end
	local def = DogCatalog.Get(dog.DogId)
	if not def then
		return 0
	end
	local r = DogCatalog.AdultIncome(def, dog.Variant)
	if PlayerStats.IsPuppy(dog, t) then
		r *= Timers.PuppyIncomeFraction
	end
	return r
end

function PlayerStats.IncomeMult(ctx: Ctx?): number
	local m = 1
	for key, pass in Products.GamePasses do
		if pass.IncomeMult and hasPass(ctx, key) then
			m *= pass.IncomeMult
		end
	end
	return m
end

function PlayerStats.IncomePerSec(state: any, ctx: Ctx?): number
	local t = now(ctx)
	local total = 0
	for _, dog in state.Dogs or {} do
		total += PlayerStats.DogRate(dog, t)
	end
	return total * PlayerStats.IncomeMult(ctx)
end

function PlayerStats.EffectiveSlots(state: any, ctx: Ctx?): number
	local s = state.SlotCount or Shop.Slots.Start
	for key, pass in Products.GamePasses do
		if pass.Slots and hasPass(ctx, key) then
			s += pass.Slots
		end
	end
	return s
end

function PlayerStats.ActiveBoosts(state: any, ctx: Ctx?): { string }
	local t = now(ctx)
	local out = {}
	for _, id in Shop.BoostOrder do
		local exp = state.Boosts and state.Boosts[id]
		if type(exp) == "number" and exp > t then
			table.insert(out, id)
		end
	end
	return out
end

-- Remaining throws of a ball (PlayerState.Balls = { [ballId]: number }). Non-consumables (Tennis) are
-- always available: math.huge.
function PlayerStats.BallCount(state: any, ballId: string): number
	local ball = Balls.ById[ballId]
	if not ball then
		return 0
	end
	if not ball.Consumable then
		return math.huge
	end
	local n = state.Balls and state.Balls[ballId]
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

-- The ball the next throw uses: the equipped ball if it has throws left, otherwise the Tennis Ball.
function PlayerStats.Ball(state: any): any
	local id = state.EquippedBall or Balls.Default
	local ball = Balls.ById[id]
	if ball and PlayerStats.BallCount(state, id) > 0 then
		return ball
	end
	return Balls.ById[Balls.Default]
end

-- Horizontal throw distance (studs from Layout.ThrowLine.Z). scatterU in [-1, 1] scales Game.Throw.Scatter.
-- Unchanged by the raised platform: the launch height only changes the flight (Util/BallFlight).
function PlayerStats.ThrowDistance(throwPower: number, rangeMult: number, quality: number, scatter: number,
	minDistance: number): number
	local d = throwPower * rangeMult * quality * (1 + scatter)
	return math.clamp(d, minDistance, PlayerStats.MaxFieldDistance())
end

-- Luck for the tier roll (ball + luck boosts + book permanent luck + Lucky Paw + server luck).
function PlayerStats.Luck(state: any, ctx: Ctx?): (number, { Source })
	local sources: { Source } = {}
	local ball = PlayerStats.Ball(state)
	if ball.Luck > 0 then
		table.insert(sources, { Name = ball.Name, Amount = ball.Luck })
	end
	for _, id in PlayerStats.ActiveBoosts(state, ctx) do
		local b = Shop.Boosts[id]
		if b and b.Kind == "Luck" then
			table.insert(sources, { Name = b.Name, Amount = b.Amount })
		end
	end
	if (state.PermanentLuck or 0) > 0 then
		table.insert(sources, { Name = "Kennel Book", Amount = state.PermanentLuck })
	end
	for key, pass in Products.GamePasses do
		if pass.Luck and hasPass(ctx, key) then
			table.insert(sources, { Name = pass.Name, Amount = pass.Luck })
		end
	end
	if ctx and (ctx.ServerLuck or 0) > 0 then
		table.insert(sources, { Name = "Server Luck", Amount = ctx.ServerLuck :: number })
	end
	local luck = 0
	for _, s in sources do
		luck += s.Amount
	end
	return luck, sources
end

-- Additive catch-chance bonus (catch boosts only).
function PlayerStats.CatchBonus(state: any, ctx: Ctx?): (number, { Source })
	local sources: { Source } = {}
	for _, id in PlayerStats.ActiveBoosts(state, ctx) do
		local b = Shop.Boosts[id]
		if b and b.Kind == "Catch" then
			table.insert(sources, { Name = b.Name, Amount = b.Amount })
		end
	end
	local bonus = 0
	for _, s in sources do
		bonus += s.Amount
	end
	return bonus, sources
end

-- Best-case (Perfect) throw distance with the equipped ball.
function PlayerStats.MaxDistance(state: any): number
	local ball = PlayerStats.Ball(state)
	return math.min((state.ThrowPower or 0) * ball.RangeMult, PlayerStats.MaxFieldDistance())
end

function PlayerStats.SellValue(dog: any): number
	local def = DogCatalog.Get(dog.DogId)
	if not def then
		return 0
	end
	return math.floor(DogCatalog.AdultIncome(def, dog.Variant) * Shop.SellIncomeSeconds)
end

-- Everything the HUD needs, sent as PlayerState.Computed (not persisted).
function PlayerStats.Compute(state: any, ctx: Ctx?): { [string]: any }
	local luck, luckSources = PlayerStats.Luck(state, ctx)
	local catchBonus, catchSources = PlayerStats.CatchBonus(state, ctx)
	-- A banked premium throw is spent automatically on the next (non-tutorial) throw, so the posted odds
	-- include it exactly as ThrowService applies it: luck lifted to the Golden ball's, +catch unless a
	-- Sticky Ball is already active.
	if (state.PremiumThrows or 0) > 0 and state.TutorialThrowDone == true then
		local asBall = Balls.ById[Shop.PremiumThrow.LuckAsBall]
		local extraLuck = math.max(0, asBall.Luck - PlayerStats.Ball(state).Luck)
		if extraLuck > 0 then
			luck += extraLuck
			table.insert(luckSources, { Name = "Premium throw", Amount = extraLuck })
		end
		if not table.find(PlayerStats.ActiveBoosts(state, ctx), "StickyBall") then
			catchBonus += Shop.PremiumThrow.CatchBonus
			table.insert(catchSources, { Name = "Premium throw", Amount = Shop.PremiumThrow.CatchBonus })
		end
	end
	local income = PlayerStats.IncomePerSec(state, ctx)
	local catchChances: { [string]: number } = {}
	for _, tier in Rarities.Order do
		catchChances[tier] = Odds.CatchChance(tier, catchBonus)
	end
	local maxDist = PlayerStats.MaxDistance(state)
	local reach = PlayerStats.ZoneForDistance(maxDist)
	local prices: { [string]: number } = {}
	for id, b in Shop.Boosts do
		prices["Boost:" .. id] = Shop.DynamicPrice(b.BaseCost, b.IncomeSeconds, income)
	end
	for id, it in Shop.Items do
		prices["Item:" .. id] = Shop.DynamicPrice(it.BaseCost, it.IncomeSeconds, income)
	end
	local ballCounts: { [string]: number } = {}
	for _, id in Balls.Order do
		local b = Balls.ById[id]
		if b.Consumable then
			prices["Ball:" .. id] = b.Price
			ballCounts[id] = PlayerStats.BallCount(state, id)
		end
	end
	local level = state.TrainingLevel or 0
	if level < Training.Upgrades.MaxLevel then
		prices.Training = Training.UpgradeCost(level + 1)
	end
	if (state.SlotCount or Shop.Slots.Start) < Shop.Slots.Max then
		prices.Slots = Shop.SlotCost(state.SlotCount or Shop.Slots.Start)
	end
	local t = now(ctx)
	local earning, held, puppies = 0, 0, 0
	for _, dog in state.Dogs or {} do
		if dog.Held then
			held += 1
		elseif not dog.PendingSale then
			earning += 1
		end
		if PlayerStats.IsPuppy(dog, t) then
			puppies += 1
		end
	end
	return {
		Luck = luck,
		LuckSources = luckSources,
		CatchBonus = catchBonus,
		CatchSources = catchSources,
		CatchChances = catchChances,
		TierOdds = Odds.TierOdds(luck),
		IncomePerSec = income,
		IncomeMult = PlayerStats.IncomeMult(ctx),
		MaxDistance = maxDist,
		ReachZone = reach.Id,
		EffectiveSlots = PlayerStats.EffectiveSlots(state, ctx),
		DogsEarning = earning,
		DogsHeld = held,
		Puppies = puppies,
		TrainMult = Training.Mult(level),
		PowerCap = Training.PowerCap(level),
		Prices = prices,
		BallCounts = ballCounts, -- consumable balls only (Tennis is unlimited)
		BallId = PlayerStats.Ball(state).Id, -- ball the next throw uses
		ActiveBoosts = PlayerStats.ActiveBoosts(state, ctx),
		LuckyStreakArmed = (state.LuckyStreak or 0) >= Rarities.LuckyStreakMisses,
		PremiumThrowReady = (state.PremiumThrows or 0) > 0,
		ServerTime = t,
	}
end

return PlayerStats
