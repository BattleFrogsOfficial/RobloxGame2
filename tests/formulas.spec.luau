--!nocheck
-- Tests for the pure shared modules (Config, Formulas, Format), run outside
-- Roblox with tiny stand-ins for Color3 and Random.
--
-- Run from the repo root:   lune run tests/formulas.spec.luau

local readFile, compileChunk
if readfile and compile then
	readFile = readfile
	compileChunk = function(src, name, env)
		local fn = compile(src, name)
		setfenv(fn, setmetatable(env, { __index = _G }))
		return fn
	end
else
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	readFile = fs.readFile
	compileChunk = function(src, name, env)
		return luau.load(src, { debugName = name, environment = env })
	end
end

----------------------------------------------------------------------------
-- Roblox stand-ins
----------------------------------------------------------------------------
local Color3Mt = {}
Color3Mt.__index = Color3Mt
function Color3Mt:Lerp(o, a)
	return setmetatable({ R = self.R + (o.R - self.R) * a, G = self.G + (o.G - self.G) * a, B = self.B + (o.B - self.B) * a }, Color3Mt)
end
_G.Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Mt)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3Mt)
	end,
	fromHSV = function()
		return setmetatable({ R = 1, G = 1, B = 1 }, Color3Mt)
	end,
}

-- Deterministic LCG with Roblox's Random API shape.
local RandomMt = {}
RandomMt.__index = RandomMt
function RandomMt:NextNumber(a, b)
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	local r = self.s / 2147483648
	if a then
		return a + (b - a) * r
	end
	return r
end
function RandomMt:NextInteger(a, b)
	return math.floor(self:NextNumber(a, b + 1))
end
local Random = {
	new = function(seed)
		return setmetatable({ s = (seed or 1) % 2147483648 }, RandomMt)
	end,
}

----------------------------------------------------------------------------
-- Module loader: require(script.Parent.X) -> src/shared/X.luau
----------------------------------------------------------------------------
local cache = {}
local function loadShared(name)
	if cache[name] then
		return cache[name]
	end
	local path = "src/shared/" .. name .. ".luau"
	local fn = compileChunk(readFile(path), path, {
		Color3 = _G.Color3,
		Random = Random,
		script = { Parent = setmetatable({}, {
			__index = function(_, k)
				return { __module = k }
			end,
		}) },
		require = function(t)
			return loadShared(t.__module)
		end,
	})
	cache[name] = fn()
	return cache[name]
end

local Config = loadShared("Config")
local Formulas = loadShared("Formulas")
local Format = loadShared("Format")

----------------------------------------------------------------------------
-- Tiny test framework
----------------------------------------------------------------------------
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
	end
end
local function eq(name, got, want)
	check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

----------------------------------------------------------------------------
-- Format
----------------------------------------------------------------------------
eq("short 0", Format.short(0), "0")
eq("short 999", Format.short(999), "999")
eq("short 1000", Format.short(1000), "1K")
eq("short 1100", Format.short(1100), "1.1K")
eq("short 1500", Format.short(1500), "1.5K")
eq("short 12345", Format.short(12345), "12.3K")
eq("short 123456", Format.short(123456), "123K")
eq("short 1.5M", Format.short(1500000), "1.5M")
eq("short 2B", Format.short(2e9), "2B")
eq("short -2500", Format.short(-2500), "-2.5K")
eq("cash", Format.cash(44000), "$44K")
eq("time 65", Format.time(65), "01:05")
eq("time 3725", Format.time(3725), "1:02:05")
eq("time negative", Format.time(-5), "00:00")

----------------------------------------------------------------------------
-- Config sanity
----------------------------------------------------------------------------
for _, e in Config.Eggs do
	local list = Config.AnimalsByEgg[e.id]
	check("egg has animals: " .. e.id, list ~= nil and #list == 3)
	check("egg hatch positive: " .. e.id, e.hatch > 0)
end
for _, a in Config.Animals do
	check("animal has egg: " .. a.id, Config.EggById[a.egg] ~= nil)
end
for i = 2, #Config.Eggs do
	local prevBest = 0
	for _, a in Config.AnimalsByEgg[Config.Eggs[i - 1].id] do
		prevBest = math.max(prevBest, a.income)
	end
	local worst = math.huge
	for _, a in Config.AnimalsByEgg[Config.Eggs[i].id] do
		worst = math.min(worst, a.income)
	end
	check("tier " .. i .. " worst animal beats tier " .. (i - 1) .. " best", worst > prevBest, worst .. " vs " .. prevBest)
end
for _, r in Config.Playtime do
	check("playtime reward valid", (r.kind == "cash" and r.cash) or (r.kind == "egg" and Config.EggById[r.egg]) or (r.kind == "animal" and Config.AnimalById[r.animal]))
end
for i = 2, #Config.Weights do
	check("weights get heavier " .. i, Config.Weights[i].gain > Config.Weights[i - 1].gain and Config.Weights[i].cost > Config.Weights[i - 1].cost)
end

----------------------------------------------------------------------------
-- Split math
----------------------------------------------------------------------------
local prev = Formulas.splitParams(0, 1)
for _, s in { 1, 5, 20, 100, 1000, 10000, 1e6, 1e9 } do
	local p = Formulas.splitParams(s, 1)
	check("length grows with strength " .. s, p.length >= prev.length)
	check("open time grows with strength " .. s, p.openTime >= prev.openTime)
	check("length within ocean " .. s, p.length <= Config.Ocean.MaxLength)
	check("width capped " .. s, p.width <= Config.Split.MaxWidth)
	prev = p
end
local tap = Formulas.splitParams(100, 0)
local full = Formulas.splitParams(100, 1)
check("tap is shorter than full charge", tap.length < full.length)
check("charge adds open time", math.abs(full.openTime - tap.openTime - Config.Split.ChargeOpenBonus) < 1e-6)

eq("ground at shore", Formulas.groundY(0), 0)
eq("ground mid-ramp", Formulas.groundY(Config.Ocean.RampLength / 2), Config.Ocean.SeabedY / 2)
eq("ground on seabed", Formulas.groundY(100), Config.Ocean.SeabedY)
eq("ground at far shore", Formulas.groundY(Config.Ocean.ShoreZ * 2), 0)

local sp = { length = 100, openTime = 6, closeSpeed = 8 }
eq("length at t=0", Formulas.currentLength(sp, 0), 0)
eq("length after open anim", Formulas.currentLength(sp, Config.Ocean.OpenAnim), 100)
eq("length while open", Formulas.currentLength(sp, Config.Ocean.OpenAnim + 5.9), 100)
check("length shrinks while closing", Formulas.currentLength(sp, Config.Ocean.OpenAnim + 7) < 100)
eq("closed at end", Formulas.currentLength(sp, Formulas.totalDuration(sp)), 0)
eq("stays closed", Formulas.currentLength(sp, Formulas.totalDuration(sp) + 10), 0)

----------------------------------------------------------------------------
-- Egg rolls
----------------------------------------------------------------------------
local rng = Random.new(42)
for _, strength in { 0, 50, 5000 } do
	for _, luck in { 1, 3, 20 } do
		local p = Formulas.splitParams(strength, 1)
		p.cx = 0
		local eggs = Formulas.rollEggs(rng, p, luck)
		check("egg count in range", #eggs >= 1 and #eggs <= Config.Split.MaxEggs, #eggs)
		for _, e in eggs do
			check("egg inside corridor (depth)", e.d >= 0 and e.d <= p.length, e.d .. " / " .. p.length)
			check("egg inside corridor (side)", math.abs(e.x) <= p.width / 2, e.x)
			check("egg id valid", Config.EggById[e.egg] ~= nil)
			check("variant valid", Config.Variants[e.variant] ~= nil)
		end
	end
end

-- Near the shore only the first two tiers can appear.
local maxNear = 0
for _ = 1, 3000 do
	maxNear = math.max(maxNear, Formulas.rollEggTier(rng, 0, 50))
end
check("shallow water caps rarity", maxNear <= 2, maxNear)

-- Deep water with luck reaches the top tier eventually.
local maxDeep = 0
for _ = 1, 20000 do
	maxDeep = math.max(maxDeep, Formulas.rollEggTier(rng, 1, 30))
end
eq("deep + lucky can roll Secret", maxDeep, #Config.Eggs)

-- Luck shifts animals toward the rare end of an egg.
local function rareShare(luck)
	local n = 0
	for _ = 1, 5000 do
		if Formulas.rollAnimal(rng, "Shell", luck) == "Turtle" then
			n += 1
		end
	end
	return n / 5000
end
check("luck favors rare animals", rareShare(10) > rareShare(1))

eq("luck base", Formulas.luck(0), 1)
check("luck pass doubles", math.abs(Formulas.luck(10, true) - Formulas.luck(10) * 2) < 1e-9)
eq("carry base", Formulas.carry(false), 1)
eq("carry pass", Formulas.carry(true), 2)
eq("fast hatch halves", Formulas.hatchSeconds("Coral", true), math.ceil(Config.EggById.Coral.hatch / 2))
eq("gold variant income", Formulas.animalIncome("Crab", "Gold"), Config.AnimalById.Crab.income * Config.Variants.Gold.mult)

----------------------------------------------------------------------------
-- Reachability: with a full charge, can a player run to the farthest point,
-- grab an egg and get home? (Walk speed 16, start ~8 studs behind the shore.)
----------------------------------------------------------------------------
print("\nstrength | depth | open s | close s | farthest egg reachable? | max tier there")
for _, s in { 0, 10, 50, 200, 1000, 5000, 25000, 200000 } do
	local p = Formulas.splitParams(s, 1)
	local farthest = p.length - 6
	local arrive = (farthest + 8) / 16
	local wallAt = Formulas.currentLength(p, arrive)
	local depth = farthest / (Config.Ocean.ShoreZ * 2)
	local maxTier = math.clamp(2 + math.floor(depth * 5.4), 2, #Config.Eggs)
	print(string.format("%8d | %5d | %6.1f | %7.1f | %s | %s", s, p.length, p.openTime, p.length / p.closeSpeed, tostring(farthest <= wallAt), Config.Eggs[maxTier].id))
	check("farthest egg reachable at strength " .. s, farthest <= wallAt + Config.Ocean.SweepGrace)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
