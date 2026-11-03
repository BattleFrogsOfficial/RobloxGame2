--!strict
-- Pure odds maths shared by RollService (server) and the odds panel (client). docs/DESIGN.md §6.
local Config = script.Parent.Parent:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local Game = require(Config:WaitForChild("Game"))

local Odds = {}

local function nonCommonBase(): number
	local s = 0
	for _, tier in Rarities.Order do
		if tier ~= "Common" then
			s += (Rarities.Tiers :: any)[tier].Odds
		end
	end
	return s
end

-- Highest luck that still has an effect (Common odds floor).
function Odds.MaxEffectiveLuck(): number
	return (1 - Game.Luck.MinCommonOdds) / nonCommonBase() - 1
end

-- Tier probabilities for a luck value. Non-Common odds x (1 + luck), Common absorbs the rest
-- (never below Game.Luck.MinCommonOdds). If `available` is given (tiers that exist in a zone),
-- the result is restricted to those tiers and renormalised.
function Odds.TierOdds(luck: number, available: { string }?): { [string]: number }
	local mult = math.min(1 + math.max(0, luck), 1 + Odds.MaxEffectiveLuck())
	local out: { [string]: number } = {}
	local nonCommon = 0
	for _, tier in Rarities.Order do
		if tier ~= "Common" then
			local w = (Rarities.Tiers :: any)[tier].Odds * mult
			out[tier] = w
			nonCommon += w
		end
	end
	out.Common = math.max(0, 1 - nonCommon)
	if available then
		local allowed: { [string]: boolean } = {}
		for _, t in available do
			allowed[t] = true
		end
		local total = 0
		for _, tier in Rarities.Order do
			if allowed[tier] then
				total += out[tier]
			else
				out[tier] = 0
			end
		end
		if total > 0 then
			for _, tier in Rarities.Order do
				out[tier] /= total
			end
		end
	end
	return out
end

function Odds.CatchChance(rarity: string, catchBonus: number): number
	local tier = (Rarities.Tiers :: any)[rarity]
	local base = if tier then tier.Catch else 0
	return math.clamp(base + math.max(0, catchBonus), 0, Game.Catch.MaxChance)
end

function Odds.RarityIndex(rarity: string): number
	return table.find(Rarities.Order, rarity) or 0
end

function Odds.AtLeast(rarity: string, minRarity: string): boolean
	return Odds.RarityIndex(rarity) >= Odds.RarityIndex(minRarity)
end

function Odds.IsLegendaryPlus(rarity: string): boolean
	return Odds.AtLeast(rarity, "Legendary")
end

-- Per-variant appearance chance for a non-Common (Rainbow checked first, then Shadow, then Gold).
function Odds.VariantChances(): { [string]: number }
	local out: { [string]: number } = {}
	local remaining = 1
	for i = #Rarities.VariantOrder, 1, -1 do
		local v = Rarities.VariantOrder[i]
		local c = (Rarities.Variants :: any)[v].Chance
		out[v] = remaining * c
		remaining *= (1 - c)
	end
	out.None = remaining
	return out
end

return Odds
