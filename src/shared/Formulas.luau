-- Pure game math shared by server (authoritative) and client (display).

local Config = require(script.Parent.Config)

local Formulas = {}

local function log2(x)
	return math.log(x) / math.log(2)
end

-- How many "doublings" of strength the player has; drives most curves.
function Formulas.strengthLevel(strength: number): number
	return log2(1 + math.max(0, strength) / 5)
end

function Formulas.luck(luckLevel: number, hasPass: boolean?, potionActive: boolean?): number
	local l = 1 + Config.Luck.PerLevel * luckLevel
	if hasPass then
		l *= 2
	end
	if potionActive then
		l *= 2
	end
	return l
end

function Formulas.carry(hasPass: boolean?): number
	return Config.Split.BaseCarry + (hasPass and 1 or 0)
end

-- Max distance / open time / width for a split, before charge.
function Formulas.splitParams(strength: number, charge: number)
	local S = Config.Split
	local lvl = Formulas.strengthLevel(strength)
	local c = math.clamp(charge, 0, 1)
	local chargeFactor = S.MinChargeFactor + (1 - S.MinChargeFactor) * c
	local length = (S.BaseLength + S.LengthPerDoubling * lvl) * chargeFactor
	length = math.clamp(length, 12, Config.Ocean.MaxLength)
	local openTime = S.BaseOpenTime + S.OpenTimePerDoubling * lvl + S.ChargeOpenBonus * c
	local width = math.min(S.MaxWidth, S.BaseWidth + lvl * 0.8)
	return {
		length = length,
		openTime = openTime,
		width = width,
		closeSpeed = Config.Ocean.CloseSpeed,
	}
end

-- Open length of a corridor at `elapsed` seconds after it started.
function Formulas.currentLength(sp, elapsed: number): number
	local anim = Config.Ocean.OpenAnim
	if elapsed < anim then
		return sp.length * math.max(0, elapsed) / anim
	end
	local t = elapsed - anim
	if t < sp.openTime then
		return sp.length
	end
	return math.max(0, sp.length - (t - sp.openTime) * sp.closeSpeed)
end

-- Height of the sea floor `d` studs out from a shore (the ramps slope down
-- for RampLength studs at both shores, flat seabed in between).
function Formulas.groundY(d: number): number
	local O = Config.Ocean
	local fromShore = math.min(d, O.ShoreZ * 2 - d)
	return O.SeabedY * math.clamp(fromShore / O.RampLength, 0, 1)
end

-- Seconds until the corridor has fully closed.
function Formulas.totalDuration(sp): number
	return Config.Ocean.OpenAnim + sp.openTime + sp.length / sp.closeSpeed
end

local function pickWeighted(rng: Random, weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return #weights
end

-- Chance of each rarity tier (array of probabilities summing to 1) for an
-- egg found `depth` (0..1 of the whole ocean) out with this much luck.
function Formulas.tierOdds(depth: number, luck: number): { number }
	local maxTier = math.clamp(2 + math.floor(depth * 5.4), 2, #Config.Eggs)
	local weights = {}
	local total = 0
	for tier = 1, maxTier do
		local w = Config.RarityWeights[tier]
		-- Luck and depth each push weight toward rarer tiers.
		w *= luck ^ ((tier - 1) * 0.55)
		w *= (1 + depth * 2.5) ^ ((tier - 1) * 0.9)
		weights[tier] = w
		total += w
	end
	for tier = 1, maxTier do
		weights[tier] /= total
	end
	return weights
end

-- Rarity tier for an egg found `depth` (0..1 of the whole ocean) out.
function Formulas.rollEggTier(rng: Random, depth: number, luck: number): number
	return pickWeighted(rng, Formulas.tierOdds(depth, luck))
end

function Formulas.rollVariant(rng: Random, luck: number): string
	local s = math.sqrt(math.max(1, luck))
	local rainbow = Config.Variants.Rainbow
	local gold = Config.Variants.Gold
	local r = rng:NextNumber()
	if r < math.min(rainbow.cap, rainbow.chance * s) then
		return "Rainbow"
	end
	if r < math.min(rainbow.cap, rainbow.chance * s) + math.min(gold.cap, gold.chance * s) then
		return "Gold"
	end
	return "Normal"
end

-- Eggs scattered through a fresh corridor. Positions are relative:
-- d = distance from the shore, x = sideways offset from the corridor center.
function Formulas.rollEggs(rng: Random, sp, luck: number)
	local S = Config.Split
	local count = S.BaseEggs + math.floor(sp.length / S.EggsPerStuds) + math.floor(log2(math.max(1, luck)))
	count = math.clamp(count, 1, S.MaxEggs)
	local eggs = {}
	local nearest = 14
	local span = math.max(1, sp.length - 6 - nearest)
	for i = 1, count do
		-- Spread along the corridor with jitter so they don't bunch up.
		local slot = (i - 0.5) / count
		local d = nearest + span * math.clamp(slot + (rng:NextNumber() - 0.5) / count, 0, 1)
		local depth = d / (Config.Ocean.ShoreZ * 2)
		local tier = Formulas.rollEggTier(rng, depth, luck)
		table.insert(eggs, {
			id = i,
			d = d,
			x = (rng:NextNumber() - 0.5) * (sp.width - 7),
			egg = Config.Eggs[tier].id,
			variant = Formulas.rollVariant(rng, luck),
		})
	end
	return eggs
end

-- Animal inside an egg. Luck nudges toward the rarer animals in that egg.
function Formulas.rollAnimal(rng: Random, eggId: string, luck: number): string
	local list = Config.AnimalsByEgg[eggId]
	local weights = {}
	for i, a in list do
		weights[i] = a.weight * (luck ^ ((i - 1) * 0.25))
	end
	return list[pickWeighted(rng, weights)].id
end

function Formulas.hatchSeconds(eggId: string, fastPass: boolean?): number
	local base = Config.EggById[eggId].hatch
	return fastPass and math.ceil(base / 2) or base
end

function Formulas.animalIncome(animalId: string, variant: string?): number
	local a = Config.AnimalById[animalId]
	if not a then
		return 0
	end
	local v = Config.Variants[variant or "Normal"] or Config.Variants.Normal
	return a.income * v.mult
end

function Formulas.animalSellPrice(animalId: string, variant: string?): number
	return math.floor(Formulas.animalIncome(animalId, variant) * Config.SellAnimalSeconds)
end

function Formulas.eggSellPrice(eggId: string, variant: string?): number
	local v = Config.Variants[variant or "Normal"] or Config.Variants.Normal
	return math.floor(Config.EggById[eggId].value * v.mult)
end

function Formulas.luckCost(level: number): number
	return math.floor(Config.Luck.BaseCost * Config.Luck.Growth ^ level)
end

function Formulas.baseCost(slots: number): number
	local level = (slots - Config.Base.StartSlots) / Config.Base.SlotsPerLevel
	return math.floor(Config.Base.BaseCost * Config.Base.Growth ^ level)
end

return Formulas
