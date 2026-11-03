--!nocheck
-- Throw cutscene timing + rules (src/shared/Cutscene/Timeline.luau, src/shared/Config/Cutscene.luau).
--   lune run tools/tests/cutscene.luau        (from the repo root; exit code 1 on any failure)
-- Proves: every beat per rarity sums to Config.Budget (release -> end card) at the reference flight; every
-- config value is a number in range; the flight remap stays in Flight.Min..Max and grows with distance;
-- skip rules (from the counter on, never Legendary / Mythic); HideCommonReveals shortens Commons only;
-- the fallback / HUD-safety deadlines; Validate never changes an outcome; fake results are well formed; the
-- server timeout (Config/Timers.Cutscene) covers the longest real cutscene and EarliestEnd never blocks a skip.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local check = Loader.Check

local Shared = Loader.Mount("src/shared")
local C = Loader.Require(Shared.Config.Cutscene)
local Rarities = Loader.Require(Shared.Config.Rarities)
local Zones = Loader.Require(Shared.Config.Zones)
local Layout = Loader.Require(Shared.Config.Layout)
local Game = Loader.Require(Shared.Config.Game)
local Timeline = Loader.Require(Shared.Cutscene.Timeline)
local FakeResult = Loader.Require(Shared.Cutscene.FakeResult)
local BallFlight = Loader.Require(Shared.Util.BallFlight)
local DogCatalog = Loader.Require(Shared.Util.DogCatalog)

local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-9)
end

-- 1. Budgets: sum every beat per rarity.
print("rarity      wind  flight settle dog   count hold  outc  = total (budget)")
for _, r in Rarities.Order do
	local b = C.Beats
	local sum = C.WindUp.ReleaseAt + C.Budget.ReferenceFlight + b.Settle[r] + b.DogArrive[r] + b.Counter[r]
		+ b.CounterHold[r] + b.Outcome[r]
	local plan = Timeline.Build(r, C.Budget.ReferenceFlight)
	print(string.format("%-10s  %.2f  %.2f   %.2f   %.2f  %.2f  %.2f  %.2f  = %.2f (%.2f)", r, C.WindUp.ReleaseAt,
		C.Budget.ReferenceFlight, b.Settle[r], b.DogArrive[r], b.Counter[r], b.CounterHold[r], b.Outcome[r], sum, C.Budget[r]))
	check(near(sum, C.Budget[r], C.Budget.Tolerance), r .. " beats sum to its budget", ("%.3f vs %.3f"):format(sum, C.Budget[r]))
	check(near(plan.Total, sum, 1e-9), r .. " Timeline.Build total == summed beats")
	check(near(Timeline.BudgetTotal(r), C.Budget[r], C.Budget.Tolerance), r .. " BudgetTotal")
	-- beats are contiguous and in order
	local t = 0
	for i, beat in plan.Beats do
		check(beat.Name == Timeline.Order[i], r .. " beat order " .. i)
		check(near(beat.Start, t), r .. " beat " .. beat.Name .. " starts where the last ended")
		check(beat.Length >= 0, r .. " beat " .. beat.Name .. " non-negative")
		t += beat.Length
	end
	check(near(plan.Touchdown, C.WindUp.ReleaseAt + C.Budget.ReferenceFlight), r .. " touchdown = release + flight")
	-- a long throw only adds flight time
	local long = Timeline.Build(r, C.Flight.Max)
	check(near(long.Total - plan.Total, C.Flight.Max - C.Budget.ReferenceFlight), r .. " longer flight only adds flight")
	-- counter budget 1.5 s (Common) .. 4 s (Mythic)
	check(b.Counter[r] >= 1.5 - 1e-9 and b.Counter[r] <= 4 + 1e-9, r .. " counter within 1.5..4 s")
end
check(near(C.Beats.Counter.Common, 1.5), "Common counter is 1.5 s")
check(near(C.Beats.Counter.Mythic, 4.0), "Mythic counter is 4 s")
check(C.Budget.Common <= 6 and C.Budget.Common >= 4.5, "Common about 5 s", tostring(C.Budget.Common))
check(near(C.Budget.Mythic, 12, 0.5), "Mythic about 12 s", tostring(C.Budget.Mythic))
local prev = 0
for _, r in Rarities.Order do
	check(C.Budget[r] > prev, r .. " budget grows with rarity")
	prev = C.Budget[r]
end
check(C.WindUp.ReleaseAt < C.WindUp.Duration, "release frame inside the wind-up")
check(near(C.WindUp.Duration, 1.2, 0.3), "wind-up about 1.2 s")
check(C.Beats.DogArrive.Mythic <= 1.6, "dog arrives in about 1.5 s")
check(C.Landing.Share > 0 and C.Landing.Share < 1 and near(C.Landing.Share, 0.25), "landing eases over the last 25%")
check(C.Landing.Bounces >= 2 and C.Landing.Bounces <= 3, "2-3 bounces")
check(near(C.Fallback.HoldMax, 3), "fallback holds up to 3 s")

-- 2. Every config value is a number / string / boolean / table (no nils), and every zone has impact FX.
local function walk(t, path)
	for k, v in t do
		local p = path .. "." .. tostring(k)
		local ty = typeof(v)
		if ty == "table" then
			walk(v, p)
		else
			check(ty == "number" or ty == "string" or ty == "boolean" or ty == "Color3", "config value type " .. p, ty)
			if ty == "number" then
				check(v == v and v > -1e6 and v < 1e6, "config number finite " .. p)
			end
		end
	end
end
walk(C, "Cutscene")
for _, z in Zones do
	local fx = C.ImpactFX[z.Id]
	check(fx ~= nil, "impact FX for " .. z.Id)
	if fx then
		check(C.SoundIds[fx.Sound] ~= nil, z.Id .. " impact sound id exists", fx.Sound)
		check(#fx.Colors >= 1 and fx.Count > 0, z.Id .. " impact colours + count")
	end
end
check(C.ImpactFX.SpaceStation.Sparks == true and C.ImpactFX.SpaceStation.Sound == "ImpactMetal", "Space Station clanks + sparks")
for _, r in Rarities.Order do
	for name, row in C.Beats do
		check(type(row[r]) == "number", ("Beats.%s.%s set"):format(name, r))
	end
end
-- Pose keys: ordered, first and last are the rest pose, last key ends at Duration + Recover
for i = 2, #C.Pose do
	check(C.Pose[i].At > C.Pose[i - 1].At, "pose keys ordered " .. i)
end
local last = C.Pose[#C.Pose]
check(near(last.At * C.WindUp.Duration, C.WindUp.Duration + C.WindUp.Recover, 0.01), "last pose key = Duration + Recover")
for _, key in { C.Pose[1], last } do
	for joint, v in key do
		if joint ~= "At" then
			for _, a in v do
				check(a % 360 == 0, "rest pose angle is a multiple of 360 for " .. joint)
			end
		end
	end
end

-- 3. Flight remap: server FlightTime -> on-screen seconds within Min..Max, monotone in distance, lands exactly.
check(near(Timeline.FlightSeconds(C.Flight.ServerMin), C.Flight.Min), "shortest server flight -> Flight.Min")
check(near(Timeline.FlightSeconds(C.Flight.ServerMax), C.Flight.Max), "longest server flight -> Flight.Max")
check(near(Timeline.FlightSeconds(0.1), C.Flight.Min) and near(Timeline.FlightSeconds(99), C.Flight.Max), "flight clamped")
check(near(Timeline.FlightSeconds(nil), C.Flight.Min), "missing FlightTime -> Min")
check(C.Flight.Min == 1.5 and C.Flight.Max == 4, "flight 1.5 .. 4 s")
local spot = Layout.Platform.ThrowSpot
local launchY = spot.Y + Game.Throw.LaunchHeight
local prevSeconds = 0
local minServer, maxServer = math.huge, 0
for _, d in { 5, 100, 400, 700, 1000, 1400, 1900, 2500, 3200 } do
	local a, b = BallFlight.Endpoints(spot, launchY, Layout.ThrowLine.Z, Layout.GroundY, d, 0)
	local ft = BallFlight.ForThrow(a, b).Duration
	minServer, maxServer = math.min(minServer, ft), math.max(maxServer, ft)
	local s = Timeline.FlightSeconds(ft)
	check(s >= C.Flight.Min - 1e-9 and s <= C.Flight.Max + 1e-9, "on-screen flight in range at d=" .. d, tostring(s))
	if d >= 400 then
		check(s >= prevSeconds - 1e-9, "longer throws fly at least as long, d=" .. d)
	end
	prevSeconds = s
end
check(minServer >= C.Flight.ServerMin - 0.05 and maxServer <= C.Flight.ServerMax + 0.05,
	"Flight.ServerMin/Max match the server's BallFlight range", ("%.2f..%.2f"):format(minServer, maxServer))

-- 4. Skip rules.
for _, r in Rarities.Order do
	local never = r == "Legendary" or r == "Mythic"
	for _, beat in Timeline.Order do
		local idx = table.find(Timeline.Order, beat)
		local counterIdx = table.find(Timeline.Order, "Counter")
		local expect = (not never) and idx >= counterIdx and beat ~= "EndCard"
		check(Timeline.CanSkip(r, beat) == expect, ("CanSkip(%s, %s) == %s"):format(r, beat, tostring(expect)))
	end
end

-- 5. Short Commons (Settings.HideCommonReveals): launch + landing + end card, no counter.
check(Timeline.IsShort("Common", true) and not Timeline.IsShort("Common", false), "short Common only with the setting")
for _, r in Rarities.Order do
	if r ~= "Common" then
		check(not Timeline.IsShort(r, true), r .. " is never shortened")
	end
end
local short = Timeline.Build("Common", 1.5, { Short = true })
check(short.ByName.Counter.Length == 0 and short.ByName.DogArrive.Length == 0 and short.ByName.Outcome.Length == 0,
	"short Common has no dog / counter / outcome")
check(near(short.Total, C.WindUp.ReleaseAt + 1.5 + C.ShortCommon.AfterTouchdown), "short Common = release + flight + settle")
check(short.Total < Timeline.Build("Common", 1.5).Total, "short Common is shorter")

-- 6. Fallback + HUD safety.
check(near(Timeline.FallbackAfter(2), C.WindUp.ReleaseAt + 2 + 3), "fallback = release + estimated flight + 3 s")
check(Timeline.SafetySeconds() > Timeline.FallbackAfter(C.Flight.Max) + C.Fallback.ShowFor, "HUD safety outlasts the fallback")

-- 7. Validate keeps outcomes, normalises flags.
local ok, r = Timeline.Validate({ ThrowId = "a", ThrowerUserId = 1, Distance = 50, ZoneId = "Backyard", DogId = "x",
	Rarity = "Epic", Caught = false, Variant = "", LuckyStreakTriggered = nil, TreatPocketUsed = true })
check(ok and r.Caught == false and r.Rarity == "Epic" and r.Variant == nil and r.TreatPocketUsed == true
	and r.LuckyStreakTriggered == false, "Validate normalises without changing the outcome")
check(not Timeline.Validate({ ThrowId = "a" }), "Validate rejects a partial result")
check(not Timeline.Validate({ ThrowId = "a", ThrowerUserId = 1, Distance = 5, ZoneId = "Mars", DogId = "x", Rarity = "Epic",
	Caught = true }), "Validate rejects an unknown zone")

-- 8. Fake results (CutsceneTestMode): every rarity x caught/missed x variant, random zone + distance.
-- Lune has no Random datatype: a tiny stand-in with the two methods FakeResult uses.
math.randomseed(7)
local rng = {
	NextInteger = function(_, a, b)
		return math.random(a, b)
	end,
	NextNumber = function(_, a, b)
		local x = math.random()
		return if a then a + (b - a) * x else x
	end,
}
for _, rar in Rarities.Order do
	for _, caught in { true, false } do
		for _, v in { "None", "Gold", "Shadow", "Rainbow", "Random" } do
			local f = FakeResult.Make(rng, { Rarity = rar, Caught = caught, Variant = v })
			local zone
			for _, z in Zones do
				if z.Id == f.ZoneId then
					zone = z
				end
			end
			local def = DogCatalog.Get(f.DogId)
			check(f.IsTest == true, "fake is flagged IsTest")
			check(f.Rarity == rar and f.Caught == caught, "fake rarity / outcome as asked")
			check(def ~= nil and def.Rarity == rar and def.Zone == f.ZoneId, "fake dog is a real " .. rar .. " of its zone")
			check(f.Distance >= zone.MinDistance and f.Distance <= zone.MaxDistance, "fake distance inside the zone band")
			check(math.abs(f.LandPos.Z - (Layout.ThrowLine.Z + f.Distance)) < 0.01, "fake LandPos at the distance (float32)")
			if rar == "Common" then
				check(f.Variant == nil, "Common fakes have no variant")
			elseif v ~= "Random" and v ~= "None" then
				check(f.Variant == v, "fake variant as asked")
			elseif v == "None" then
				check(f.Variant == nil, "fake variant None")
			end
			check(Timeline.Validate(f), "fake validates")
			check(not (f.LuckyStreakTriggered and f.TreatPocketUsed), "at most one flourish")
			check(not f.Caught or not f.WhistleOwned, "whistle only on a miss")
		end
	end
end

-- Server timeout (Config/Timers.Cutscene, computed from Config/Cutscene) and the CutsceneFinished floor
-- (Timeline.EarliestEnd): the server never finishes before the longest real client cutscene, and never holds an
-- honest skip / short Common back.
do
	local Timers = Loader.Require(Shared.Config.Timers)
	print("server timeout (s): " .. table.concat((function()
		local t = {}
		for _, r in Rarities.Order do
			table.insert(t, ("%s %.1f"):format(r, Timers.Cutscene[r]))
		end
		return t
	end)(), ", "))
	for _, r in Rarities.Order do
		local longest = Timeline.Build(r, C.Flight.Max).Total + C.Fallback.HoldMax + C.EndCard.AutoClose[r] + C.Return.Time
		check(type(Timers.Cutscene[r]) == "number" and Timers.Cutscene[r] + 1e-9 >= longest,
			"server timeout covers the longest " .. r .. " cutscene", ("%s < %s"):format(tostring(Timers.Cutscene[r]), longest))
		check(C.EndCard.AutoClose[r] < 30, r .. " end card closes before the Director's 30 s guard")
		for _, sf in { 0.99, 1.4, 2.3 } do
			local fl = Timeline.FlightSeconds(sf)
			local e = Timeline.EarliestEnd(r, fl)
			local full = Timeline.Build(r, fl)
			check(e > C.WindUp.ReleaseAt + fl and e <= full.Total + 1e-9, r .. " earliest end after touchdown, <= full")
			if C.Skip.Never[r] then
				check(near(e, full.Total), r .. " (never skippable) earliest end = the full timeline")
			else
				check(e <= full.ByName[C.Skip.FromBeat].Start + 1e-9, r .. " earliest end <= the Skip point")
			end
			if r == "Common" then
				check(e <= Timeline.Build(r, fl, { Short = true }).Total + 1e-9, "Common earliest end <= short Common")
			end
		end
	end
	check(Timers.CutscenePadding > 0, "server timeout padding > 0")
end

process.exit(Loader.Done("cutscene") > 0 and 1 or 0)
