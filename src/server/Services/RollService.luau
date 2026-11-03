--!strict
-- Pure roll functions (no Roblox state, no DataStore). Every function takes an Rng so tests can seed it.
-- Order (docs/DESIGN.md §6.1): tier (luck) -> dog (uniform in tier among the zone's dogs) ->
-- variant (non-Common only, Rainbow -> Shadow -> Gold) -> catch (+catch boosts, Lucky Streak,
-- tutorial guarantee) -> Treat Pocket second roll.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local Rng = require(Util:WaitForChild("Rng"))
local Odds = require(Util:WaitForChild("Odds"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))

type RngT = Rng.Rng

export type ResolveCtx = {
	ZoneId: string,
	Luck: number,
	CatchBonus: number,
	LuckyStreak: number,
	IsTutorial: boolean?,
	TreatPockets: number?,
	TreatPocketMode: string?, -- "Always" | "EpicPlus" | "Off"
	-- Optional override for tests: tier -> list of dog defs. Defaults to DogCatalog for ZoneId.
	ZoneTierLists: { [string]: { any } }?,
}

export type Outcome = {
	DogId: string,
	Rarity: string,
	Variant: string?,
	Caught: boolean,
	CatchChance: number,
	LuckyStreakTriggered: boolean,
	TreatPocketUsed: boolean,
	NewLuckyStreak: number,
}

local RollService = {}

RollService.NewRng = Rng.new

function RollService.RollTier(rng: RngT, luck: number, available: { string }?): string
	local odds = Odds.TierOdds(luck, available)
	return rng:Weighted(Rarities.Order, odds) or (available and available[1]) or "Common"
end

function RollService.PickDog(rng: RngT, list: { any }): any?
	if #list == 0 then
		return nil
	end
	return rng:Pick(list)
end

function RollService.RollVariant(rng: RngT, rarity: string): string?
	if rarity == "Common" then
		return nil
	end
	for i = #Rarities.VariantOrder, 1, -1 do
		local v = Rarities.VariantOrder[i]
		if rng:Float() < (Rarities.Variants :: any)[v].Chance then
			return v
		end
	end
	return nil
end

-- Returns caught, displayed chance, luckyStreakTriggered.
function RollService.RollCatch(rng: RngT, rarity: string, catchBonus: number, luckyStreak: number,
	forced: boolean?): (boolean, number, boolean)
	local chance = Odds.CatchChance(rarity, catchBonus)
	if forced then
		return true, 1, false
	end
	if Odds.IsLegendaryPlus(rarity) and luckyStreak >= Rarities.LuckyStreakMisses then
		return true, 1, true
	end
	return rng:Float() < chance, chance, false
end

-- Lucky Streak counter after a resolved Legendary+ attempt (Commons..Epics never touch it).
function RollService.NextStreak(streak: number, rarity: string, caught: boolean): number
	if not Odds.IsLegendaryPlus(rarity) then
		return streak
	end
	if caught then
		return 0
	end
	return streak + 1
end

function RollService.ShouldUseTreat(mode: string?, rarity: string): boolean
	if mode == "Off" then
		return false
	elseif mode == "EpicPlus" then
		return Odds.AtLeast(rarity, "Epic")
	end
	return true -- "Always" / default
end

function RollService.Resolve(rng: RngT, ctx: ResolveCtx): Outcome
	local lists = ctx.ZoneTierLists
	local available: { string } = {}
	for _, tier in Rarities.Order do
		local list = if lists then lists[tier] else DogCatalog.ZoneTierList(ctx.ZoneId, tier)
		if list and #list > 0 then
			table.insert(available, tier)
		end
	end
	assert(#available > 0, "RollService.Resolve: zone has no dogs: " .. tostring(ctx.ZoneId))

	local tier: string
	if ctx.IsTutorial and table.find(available, "Common") then
		tier = "Common"
	else
		tier = RollService.RollTier(rng, ctx.Luck, available)
	end
	local list = if lists then lists[tier] else DogCatalog.ZoneTierList(ctx.ZoneId, tier)
	local def = RollService.PickDog(rng, list or {})
	assert(def ~= nil, "RollService.Resolve: empty tier list")

	local variant = if ctx.IsTutorial then nil else RollService.RollVariant(rng, tier)
	local caught, chance, triggered = RollService.RollCatch(rng, tier, ctx.CatchBonus, ctx.LuckyStreak,
		ctx.IsTutorial)

	local treatUsed = false
	if not caught and (ctx.TreatPockets or 0) > 0 and RollService.ShouldUseTreat(ctx.TreatPocketMode, tier) then
		treatUsed = true
		caught = rng:Float() < chance
	end

	return {
		DogId = def.Id,
		Rarity = tier,
		Variant = variant,
		Caught = caught,
		CatchChance = chance,
		LuckyStreakTriggered = triggered,
		TreatPocketUsed = treatUsed,
		NewLuckyStreak = RollService.NextStreak(ctx.LuckyStreak, tier, caught),
	}
end

return RollService
