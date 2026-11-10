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

-- Depth, starting width and lifetime of a split.
function Formulas.splitParams(strength: number, charge: number)
	local S = Config.Split
	local lvl = Formulas.strengthLevel(strength)
	local c = math.clamp(charge, 0, 1)
	local chargeFactor = S.MinChargeFactor + (1 - S.MinChargeFactor) * c
	local length = (S.BaseLength + S.LengthPerDoubling * lvl) * chargeFactor
	length = math.clamp(length, 12, Config.Ocean.Reach)
	return {
		length = length,
		width = math.min(S.MaxWidth, S.BaseWidth + lvl * S.WidthPerLevel),
		-- Seconds from the end of the cutscene until the walls meet.
		duration = S.BaseDuration + S.DurationPerStud * length + S.ChargeOpenBonus * c,
	}
end

local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Cutscene length, and the fraction of it at which the staff slams down,
-- for this split (they differ by cast; see Config.Casts).
function Formulas.anim(sp): number
	return sp.anim or Config.Ocean.OpenAnim
end

function Formulas.slam(sp): number
	return sp.slam or Config.Ocean.SlamAt
end

-- Fraction of the cutscene the tear takes to travel from the shore to the
-- far end (slam + rip + opening = the whole cutscene).
function Formulas.ripSpan(sp): number
	return 1 - 0.35 - Formulas.slam(sp)
end

-- Half the corridor's width `elapsed` seconds after the split began. Nothing
-- moves until the staff slams down partway through the cutscene; then the
-- shore tears open first. After the cutscene both walls close in steadily
-- along the whole corridor.
function Formulas.halfWidth(sp, elapsed: number): number
	local anim = Formulas.anim(sp)
	local full = sp.width / 2
	if elapsed < anim then
		return full * smooth((elapsed / anim - Formulas.slam(sp)) / 0.35)
	end
	return full * math.max(0, 1 - (elapsed - anim) / sp.duration)
end

-- Half-width at a point `d` studs out from the shore. After the slam the sea
-- peels open from the shore outward, so far points open later; by the end
-- of the cutscene the whole corridor is fully open.
function Formulas.halfWidthAt(sp, d: number, elapsed: number): number
	local anim = Formulas.anim(sp)
	if elapsed >= anim then
		return Formulas.halfWidth(sp, elapsed)
	end
	local start = Formulas.slam(sp) + math.clamp(d / sp.length, 0, 1) * Formulas.ripSpan(sp)
	return sp.width / 2 * smooth((elapsed / anim - start) / 0.35)
end

-- Is there still room to stand in the corridor?
function Formulas.isOpen(sp, elapsed: number): boolean
	return elapsed < Formulas.anim(sp) or Formulas.halfWidth(sp, elapsed) > Config.Ocean.MinGap
end

-- Has the water already covered this egg?
function Formulas.eggCovered(sp, egg, elapsed: number): boolean
	return elapsed >= Formulas.anim(sp) and math.abs(egg.x) > Formulas.halfWidth(sp, elapsed) - 0.5
end

-- Which cast a split gets, from a 0..1 roll: rarest first.
function Formulas.rollCast(roll: number)
	local used = 0
	for i = #Config.Casts, 2, -1 do
		used += Config.Casts[i].chance
		if roll < used then
			return Config.Casts[i]
		end
	end
	return Config.Casts[1]
end

function Formulas.walkSpeed(speedLevel: number): number
	return Config.Speed.Base + Config.Speed.PerLevel * speedLevel
end

function Formulas.speedCost(level: number): number
	return math.floor(Config.Speed.BaseCost * Config.Speed.Growth ^ level)
end

-- Height of the sea floor `d` studs out from the shore (a ramp slopes down
-- for RampLength studs, then flat seabed).
function Formulas.groundY(d: number): number
	local O = Config.Ocean
	return O.SeabedY * math.clamp(d / O.RampLength, 0, 1)
end

-- Seconds from the start of a split until the corridor is shut.
function Formulas.totalDuration(sp): number
	return Formulas.anim(sp) + sp.duration
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

-- The luck zone `d` studs out from the shore.
function Formulas.zoneAt(d: number)
	local zones = Config.Zones
	for i = #zones, 1, -1 do
		if d >= zones[i].from then
			return zones[i]
		end
	end
	return zones[1]
end

-- Chance of each rarity tier (array of probabilities summing to 1) for an
-- egg found `depth` (0..1 of the ocean's reach) out with this much luck.
function Formulas.tierOdds(depth: number, luck: number): { number }
	local zone = Formulas.zoneAt(depth * Config.Ocean.Reach)
	local effective = luck * zone.luck
	local weights = {}
	local total = 0
	for tier = 1, zone.maxTier do
		local w = Config.RarityWeights[tier] * effective ^ ((tier - 1) * Config.Odds.LuckPower)
		weights[tier] = w
		total += w
	end
	for tier = 1, zone.maxTier do
		weights[tier] /= total
	end
	return weights
end

-- Index key for an animal in a variant ("Crab", "Crab|Gold").
function Formulas.indexKey(animalId: string, variant: string?): string
	if variant and variant ~= "Normal" then
		return animalId .. "|" .. variant
	end
	return animalId
end

-- How many eggs are complete (all three animals found) across all variants.
function Formulas.indexCompleted(index): number
	local done = 0
	for _, variant in Config.VariantOrder do
		for _, egg in Config.Eggs do
			local all = true
			for _, a in Config.AnimalsByEgg[egg.id] do
				if not index[Formulas.indexKey(a.id, variant)] then
					all = false
					break
				end
			end
			if all then
				done += 1
			end
		end
	end
	return done
end

-- Income multiplier earned from the Index (1 = no bonus).
function Formulas.indexBonus(index): number
	return 1 + Config.IndexBonusPerEgg * Formulas.indexCompleted(index)
end

-- Rarity tier for an egg found `depth` (0..1 of the whole ocean) out.
function Formulas.rollEggTier(rng: Random, depth: number, luck: number): number
	return pickWeighted(rng, Formulas.tierOdds(depth, luck))
end

function Formulas.rollVariant(rng: Random, luck: number): string
	local s = math.sqrt(math.max(1, luck))
	local r = rng:NextNumber()
	-- Rarest first: each variant takes its slice of the roll.
	local used = 0
	for i = #Config.VariantOrder, 2, -1 do
		local name = Config.VariantOrder[i]
		local v = Config.Variants[name]
		used += math.min(v.cap, v.chance * s)
		if r < used then
			return name
		end
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
	local nearest = math.min(14, sp.length * 0.45)
	local span = math.max(1, sp.length - 4 - nearest)
	for i = 1, count do
		-- Spread along the corridor with jitter so they don't bunch up.
		local slot = (i - 0.5) / count
		local d = nearest + span * math.clamp(slot + (rng:NextNumber() - 0.5) / count, 0, 1)
		local depth = d / Config.Ocean.Reach
		local tier = Formulas.rollEggTier(rng, depth, luck)
		-- Keep every egg reachable: by the time a player sprinting from the
		-- shore gets this deep, the walls must not have covered it yet.
		local runTime = (d + 10) / 16
		local roomThen = sp.width / 2 * math.max(0, 1 - runTime / sp.duration)
		local maxX = math.max(0, roomThen - 2)
		table.insert(eggs, {
			id = i,
			d = d,
			x = (rng:NextNumber() * 2 - 1) * maxX,
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
