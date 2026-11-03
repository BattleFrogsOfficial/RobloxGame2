--!strict
-- Pure maths for the "1 out of N" odds counter (beat 5). Display only: the target is computed from the
-- player's posted odds, never from anything that decides an outcome. Lune-tested (tools/tests/cutscene_counter.luau).
--
-- The target uses EXACTLY the Odds panel's maths (src/client/UI/Screens/Odds.luau):
--   tierOdds = Odds.TierOdds(luck, DogCatalog.ZoneTiers(zoneId))   -- luck = State.Luck() (PlayerStats.Luck)
--   per      = tierOdds[rarity] / #DogCatalog.ZoneTierList(zoneId, rarity)
--   oneIn    = 1 / per          (x Odds.CatchChance(rarity, catchBonus) as well if Counter.IncludeCatch)
--   target   = floor(oneIn)     -- the panel prints FormatNumber.Compact(oneIn), which floors, so
--                                  Compact(target) == Compact(oneIn) == the panel's "1 in X" text
-- Rarity thresholds (the colour climb) are the same number for a specific dog of each tier in that zone.
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local C = require(Config:WaitForChild("Cutscene"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Odds = require(Util:WaitForChild("Odds"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))

local OddsCounter = {}

-- Raw 1/p for one specific dog of `rarity` in `zoneId` (nil if the zone has no dog of that tier).
function OddsCounter.OneIn(zoneId: string, rarity: string, luck: number, catchBonus: number?): number?
	local tierOdds = Odds.TierOdds(luck, DogCatalog.ZoneTiers(zoneId))
	local p = tierOdds[rarity] or 0
	local n = #DogCatalog.ZoneTierList(zoneId, rarity)
	if n <= 0 or p <= 0 then
		return nil
	end
	local per = p / n
	if C.Counter.IncludeCatch then
		per *= Odds.CatchChance(rarity, catchBonus or 0)
	end
	return 1 / per
end

function OddsCounter.Target(zoneId: string, rarity: string, luck: number, catchBonus: number?): number
	local x = OddsCounter.OneIn(zoneId, rarity, luck, catchBonus)
	if not x then
		return 1
	end
	return math.max(1, math.floor(x))
end

-- { [rarity] = threshold } for every tier present in the zone.
function OddsCounter.Thresholds(zoneId: string, luck: number, catchBonus: number?): { [string]: number }
	local out: { [string]: number } = {}
	for _, tier in Rarities.Order do
		if OddsCounter.OneIn(zoneId, tier, luck, catchBonus) then
			out[tier] = OddsCounter.Target(zoneId, tier, luck, catchBonus)
		end
	end
	return out
end

-- The colour tier for a displayed value: the highest tier, up to the dog's own, whose threshold has been
-- reached. nil = still white. Only climbs (white -> Common grey -> Uncommon green -> ... -> the dog's tier),
-- and at value == target it is always the dog's own tier (its threshold IS the target).
function OddsCounter.TierAt(value: number, thresholds: { [string]: number }, dogRarity: string): string?
	local maxIdx = table.find(Rarities.Order, dogRarity) or 1
	local best: string? = nil
	for i = 1, maxIdx do
		local tier = Rarities.Order[i]
		local th = thresholds[tier]
		if th and value >= th then
			best = tier
		end
	end
	return best
end

export type Schedule = { Values: { number }, Times: { number }, Target: number, Duration: number }

-- Displayed numbers and when each appears. Every number 1..LinearUpTo, then geometric steps to the target
-- (at most MaxTicks numbers in all), strictly increasing, last == target. Tick i of M shows at
-- duration * (1 - (1 - (i-1)/(M-1))^EasePower): an ease-in, so the count keeps accelerating.
function OddsCounter.Schedule(target: number, duration: number): Schedule
	local cfg = C.Counter
	local tgt = math.max(1, math.floor(target))
	local values: { number } = {}
	local linear = math.min(tgt, cfg.LinearUpTo)
	for v = 1, linear do
		table.insert(values, v)
	end
	if tgt > linear then
		local k = math.max(1, math.min(tgt - linear, cfg.MaxTicks - linear))
		local prev = linear
		local ratio = tgt / linear
		for j = 1, k do
			local v = math.floor(linear * ratio ^ (j / k) + 0.5)
			v = math.max(v, prev + 1)
			v = math.min(v, tgt - (k - j)) -- leave room so the sequence stays strictly increasing
			if j == k then
				v = tgt
			end
			table.insert(values, v)
			prev = v
		end
	end
	local m = #values
	local times: { number } = {}
	for i = 1, m do
		if m == 1 then
			times[i] = duration
		else
			local x = (i - 1) / (m - 1)
			times[i] = duration * (1 - (1 - x) ^ cfg.EasePower)
		end
	end
	return { Values = values, Times = times, Target = tgt, Duration = duration }
end

-- Index of the tick showing at time t (1 at t <= 0, #Values at t >= Duration).
function OddsCounter.IndexAt(s: Schedule, t: number): number
	local lo, hi = 1, #s.Values
	if t >= s.Duration then
		return hi
	end
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if s.Times[mid] <= t then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

function OddsCounter.ValueAt(s: Schedule, t: number): number
	return s.Values[OddsCounter.IndexAt(s, t)]
end

-- Click PlaybackSpeed for tick i of m: rises linearly from ClickMinPitch to ClickMaxPitch.
function OddsCounter.ClickPitch(i: number, m: number): number
	local cfg = C.Counter
	local x = if m <= 1 then 1 else math.clamp((i - 1) / (m - 1), 0, 1)
	return cfg.ClickMinPitch + (cfg.ClickMaxPitch - cfg.ClickMinPitch) * x
end

-- 3333 -> "3,333"
function OddsCounter.Format(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	while true do
		local nextOut, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = nextOut
		if k == 0 then
			break
		end
	end
	return out
end

function OddsCounter.Text(n: number): string
	return "1 out of " .. OddsCounter.Format(n)
end

return OddsCounter
