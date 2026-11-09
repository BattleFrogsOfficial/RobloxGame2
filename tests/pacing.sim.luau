--!nocheck
-- Pacing simulation: a simple bot plays the economy (run, train, buy) so we
-- can see roughly how long each egg tier takes to reach. Not a pass/fail test.
--
-- Run from the repo root:   lune run tests/pacing.sim.luau

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Color3 = {
	fromRGB = function()
		return { Lerp = function(self) return self end }
	end,
	new = function()
		return {}
	end,
}
local function lcg(seed)
	local state = seed
	local r = {}
	function r:NextNumber()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return r
end

local cache = {}
local function load(name)
	if not cache[name] then
		local path = "src/shared/" .. name .. ".luau"
		cache[name] = luau.load(fs.readFile(path), {
			debugName = path,
			environment = {
				Color3 = Color3,
				script = { Parent = setmetatable({}, { __index = function(_, k) return { m = k } end }) },
				require = function(t) return load(t.m) end,
			},
		})()
	end
	return cache[name]
end

local Config = load("Config")
local Formulas = load("Formulas")
local Format = load("Format")

local WALK = 16
local CLICKS_PER_SECOND = 3 -- a player tapping while training
local TRAIN_SECONDS = 25 -- training between runs
local TRIP_OVERHEAD = 16 -- pen <-> shore walking, charging, hatching

local function simulate(seed)
	local rng = lcg(seed)
	local s = { t = 0, cash = 0, strength = 0, luckLevel = 0, weight = 1, slots = Config.Base.StartSlots, animals = {}, incubating = {} }
	local firstTier = {}
	local milestones = {}

	local function income()
		local total = 0
		for _, a in s.animals do
			total += a
		end
		return total
	end
	local function pass(seconds)
		s.cash += income() * seconds
		s.t += seconds
		-- hatch finished eggs into the pen, keeping the best animals
		local still = {}
		for _, e in s.incubating do
			if e.ready <= s.t then
				table.insert(s.animals, e.income)
				table.sort(s.animals, function(a, b) return a > b end)
				while #s.animals > s.slots do
					s.cash += table.remove(s.animals) * Config.SellAnimalSeconds
				end
			else
				table.insert(still, e)
			end
		end
		s.incubating = still
	end
	local function shop()
		for _ = 1, 20 do
			local bought = false
			local w = Config.Weights[s.weight + 1]
			if w and s.cash >= w.cost then
				s.cash -= w.cost
				s.weight += 1
				bought = true
			end
			if s.slots < Config.Base.MaxSlots and #s.animals >= s.slots - 1 and s.cash >= Formulas.baseCost(s.slots) then
				s.cash -= Formulas.baseCost(s.slots)
				s.slots += Config.Base.SlotsPerLevel
				bought = true
			end
			local luckCost = Formulas.luckCost(s.luckLevel)
			if s.luckLevel < Config.Luck.MaxLevel and luckCost <= s.cash * 0.35 then
				s.cash -= luckCost
				s.luckLevel += 1
				bought = true
			end
			if not bought then
				break
			end
		end
	end

	while s.t < 8 * 3600 do
		-- one run: go for the deepest egg, then one more trip if time allows
		local sp = Formulas.splitParams(s.strength, 1)
		local luck = Formulas.luck(s.luckLevel)
		local eggs = Formulas.rollEggs(rng, sp, luck)
		table.sort(eggs, function(a, b) return a.d > b.d end)
		local clock = 0
		local window = sp.openTime + Config.Ocean.OpenAnim
		for _, e in eggs do
			local arrive = clock + (e.d + 8) / WALK
			if arrive > window + (sp.length - e.d) / sp.closeSpeed then
				continue -- the wave would get there first
			end
			clock = arrive + (e.d + 8) / WALK
			local def = Config.EggById[e.egg]
			local animal = Formulas.rollAnimal(rng, e.egg, luck)
			local inc = Formulas.animalIncome(animal, e.variant)
			table.insert(s.incubating, { ready = s.t + clock + Formulas.hatchSeconds(e.egg), income = inc })
			if not firstTier[def.tier] then
				firstTier[def.tier] = s.t + clock
			end
		end
		pass(clock + TRIP_OVERHEAD)
		shop()
		-- train
		local gain = Config.Weights[s.weight].gain
		s.strength += gain * (CLICKS_PER_SECOND + 1 / Config.Training.AutoLiftInterval) * TRAIN_SECONDS
		pass(TRAIN_SECONDS)
		shop()
		for _, mark in { 5, 15, 30, 60, 120, 240, 480 } do
			if not milestones[mark] and s.t >= mark * 60 then
				milestones[mark] = string.format("%4d min | strength %7s | depth %3d | luck x%.1f | weight %d | slots %2d | income %8s/s",
					mark, Format.short(s.strength), math.floor(sp.length), luck, s.weight, s.slots, Format.cash(income()))
			end
		end
	end
	return firstTier, milestones
end

local first, marks = simulate(7)
print("First egg of each tier (minutes of play):")
for tier, egg in Config.Eggs do
	print(string.format("  %-14s %s", egg.name, first[tier] and string.format("%.1f", first[tier] / 60) or "not within 8 hours"))
end
print("\nProgress over time:")
for _, mark in { 5, 15, 30, 60, 120, 240, 480 } do
	print("  " .. (marks[mark] or "-"))
end
