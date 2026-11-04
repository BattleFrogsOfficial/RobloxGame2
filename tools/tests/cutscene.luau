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

-- 1. Budgets: sum every beat per rarity, per outcome. CAUGHT: grab + victory before the counter, hop away after;
-- MISSED: the counter (the rarity) before the sniff + bolt (docs/DESIGN.md §8).
print("rarity      wind  flight settle dog   grab  vict  count hold  hop   = caught (budget) | sniff bolt = missed (budget)")
for _, r in Rarities.Order do
	local b = C.Beats
	local pre = C.WindUp.ReleaseAt + C.Budget.ReferenceFlight + b.Settle[r] + b.DogArrive[r]
	local caughtSum = pre + b.Grab[r] + b.Victory[r] + b.Counter[r] + b.CounterHold[r] + b.HopAway[r]
	local missedSum = pre + b.Counter[r] + b.CounterHold[r] + b.Sniff[r] + b.Bolt[r]
	print(string.format("%-10s  %.2f  %.2f   %.2f   %.2f  %.2f  %.2f  %.2f  %.2f  %.2f  = %.2f (%.2f) | %.2f  %.2f = %.2f (%.2f)", r,
		C.WindUp.ReleaseAt, C.Budget.ReferenceFlight, b.Settle[r], b.DogArrive[r], b.Grab[r], b.Victory[r], b.Counter[r],
		b.CounterHold[r], b.HopAway[r], caughtSum, C.Budget[r], b.Sniff[r], b.Bolt[r], missedSum, C.Budget.Missed[r]))
	check(near(caughtSum, C.Budget[r], C.Budget.Tolerance), r .. " caught beats sum to its budget", ("%.3f vs %.3f"):format(caughtSum, C.Budget[r]))
	check(near(missedSum, C.Budget.Missed[r], C.Budget.Tolerance), r .. " missed beats sum to Budget.Missed",
		("%.3f vs %.3f"):format(missedSum, C.Budget.Missed[r]))
	check(C.Budget.Missed[r] < C.Budget[r], r .. " missed is shorter than caught (Budget[r] is the longest: the server timeout)")
	for _, caught in { true, false } do
		local label = r .. (if caught then " caught" else " missed")
		local plan = Timeline.Build(r, C.Budget.ReferenceFlight, { Caught = caught })
		check(near(plan.Total, if caught then caughtSum else missedSum, 1e-9), label .. " Timeline.Build total == summed beats")
		check(near(Timeline.BudgetTotal(r, caught), if caught then C.Budget[r] else C.Budget.Missed[r], C.Budget.Tolerance), label .. " BudgetTotal")
		check(plan.Caught == caught, label .. " plan.Caught")
		local order = if caught then Timeline.OrderCaught else Timeline.OrderMissed
		local t = 0
		for i, beat in plan.Beats do
			check(beat.Name == order[i], label .. " beat order " .. i)
			check(near(beat.Start, t), label .. " beat " .. beat.Name .. " starts where the last ended")
			check(beat.Length >= 0, label .. " beat " .. beat.Name .. " non-negative")
			t += beat.Length
		end
		check(near(plan.Touchdown, C.WindUp.ReleaseAt + C.Budget.ReferenceFlight), label .. " touchdown = release + flight")
		local long = Timeline.Build(r, C.Flight.Max, { Caught = caught })
		check(near(long.Total - plan.Total, C.Flight.Max - C.Budget.ReferenceFlight), label .. " longer flight only adds flight")
		local by = plan.ByName
		if caught then
			-- dog arrives -> grab ball -> victory beat -> counter -> hop away
			check(by.Grab.Start >= by.DogArrive.Start + by.DogArrive.Length - 1e-9 and by.Victory.Start > by.Grab.Start
				and by.Counter.Start > by.Victory.Start and by.HopAway.Start > by.Counter.Start, label .. ": arrive < grab < victory < counter < hop away")
			check(by.Sniff == nil and by.Bolt == nil, label .. ": no sniff / bolt")
			check(by.Victory.Length >= 1.9 and by.Victory.Length <= 2.5, label .. ": victory beat about 2 s", tostring(by.Victory.Length))
			check(by.HopAway.Length - C.Outcome.TurnTime >= C.Outcome.HopAwayMinSeconds - 1e-9,
				label .. ": the dog hops in frame >= HopAwayMinSeconds before the end card")
		else
			-- dog arrives -> counter (rarity seen) -> sniff -> bolt
			check(by.Counter.Start >= by.DogArrive.Start + by.DogArrive.Length - 1e-9 and by.Sniff.Start > by.Counter.Start
				and by.Bolt.Start > by.Sniff.Start, label .. ": arrive < counter < sniff < bolt (rarity before the loss)")
			check(by.Grab == nil and by.Victory == nil and by.HopAway == nil, label .. ": no grab / victory / hop away")
			check(near(by.Sniff.Length, 1.5, 0.2), label .. ": sniff beat about 1.5 s")
		end
	end
	check(b.Counter[r] >= 1.5 - 1e-9 and b.Counter[r] <= 4 + 1e-9, r .. " counter within 1.5..4 s")
end
check(near(C.Beats.Counter.Common, 1.5), "Common counter is 1.5 s")
check(near(C.Beats.Counter.Mythic, 4.0), "Mythic counter is 4 s")
-- the user accepted longer totals for the catch celebration: Common catch ~9 s, Mythic catch ~15 s
check(C.Budget.Common <= 9.5 and C.Budget.Common >= 8.5, "Common catch about 9 s", tostring(C.Budget.Common))
check(near(C.Budget.Mythic, 14.75, 0.5), "Mythic catch about 15 s", tostring(C.Budget.Mythic))
local prev, prevMissed = 0, 0
for _, r in Rarities.Order do
	check(C.Budget[r] > prev, r .. " budget grows with rarity")
	check(C.Budget.Missed[r] > prevMissed, r .. " missed budget grows with rarity")
	prev, prevMissed = C.Budget[r], C.Budget.Missed[r]
end
-- the leaving dog: time + distance removal, never before HopAwayMinSeconds
do
	local o = C.Outcome
	check(o.HopAwayMinSeconds >= 1 and o.HopAwayMaxSeconds > o.HopAwayMinSeconds and o.RemoveDistance > 0, "leave rule config")
	check(not Timeline.LeaveDone(0, 1e6) and not Timeline.LeaveDone(o.HopAwayMinSeconds - 1e-3, 1e6), "never removed before HopAwayMinSeconds")
	check(not Timeline.LeaveDone(o.HopAwayMinSeconds + 0.01, o.RemoveDistance - 1), "still near: kept")
	check(Timeline.LeaveDone(o.HopAwayMinSeconds + 0.01, o.RemoveDistance), "far enough after the minimum: removed")
	check(Timeline.LeaveDone(o.HopAwayMaxSeconds, 0), "removed at HopAwayMaxSeconds at the latest")
end
check(C.WindUp.ReleaseAt < C.WindUp.Duration, "release frame inside the wind-up")
check(near(C.WindUp.Duration, 1.5, 0.3), "wind-up about 1.5 s")
-- a readable wind-up: at least ~1.1 s on screen before the release, and the camera sweep has settled on the front
-- shot before the cocked pose (Pose[3]) so the arm wind-back is seen from a still camera
check(C.WindUp.ReleaseAt >= 1.1, "wind-up has screen time before the release", tostring(C.WindUp.ReleaseAt))
check(C.WindUp.SweepTime <= C.Pose[3].At * C.WindUp.Duration, "sweep settles before the cocked pose")
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

-- 4. Skip rules: from the counter on in each outcome's order, never Legendary / Mythic, never during the catch
-- celebration (Grab / Victory come before the counter).
for _, r in Rarities.Order do
	local never = r == "Legendary" or r == "Mythic"
	for _, order in { Timeline.OrderCaught, Timeline.OrderMissed } do
		local counterIdx = table.find(order, "Counter")
		for idx, beat in order do
			local expect = (not never) and idx >= counterIdx and beat ~= "EndCard"
			check(Timeline.CanSkip(r, beat) == expect, ("CanSkip(%s, %s) == %s"):format(r, beat, tostring(expect)))
		end
	end
	check(not Timeline.CanSkip(r, "Victory") and not Timeline.CanSkip(r, "Grab"), r .. " victory beat never skippable")
	check(not Timeline.CanSkip(r, "Hold"), r .. " unknown phase not skippable")
end

-- 5. Short Commons (Settings.HideCommonReveals): launch + landing + end card, no counter.
check(Timeline.IsShort("Common", true) and not Timeline.IsShort("Common", false), "short Common only with the setting")
for _, r in Rarities.Order do
	if r ~= "Common" then
		check(not Timeline.IsShort(r, true), r .. " is never shortened")
	end
end
local short = Timeline.Build("Common", 1.5, { Short = true })
check(short.ByName.Counter.Length == 0 and short.ByName.DogArrive.Length == 0 and short.ByName.HopAway.Length == 0
	and short.ByName.Victory.Length == 0 and Timeline.Build("Common", 1.5, { Short = true, Caught = false }).ByName.Bolt.Length == 0,
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
		-- the longest real client cutscene: either outcome at the longest flight, a late result, the end card left to
		-- close itself, the return tween (and the leaving dog, which only waits when the card closed at once)
		local longest = 0
		for _, caught in { true, false } do
			local total = Timeline.Build(r, C.Flight.Max, { Caught = caught }).Total + C.Fallback.HoldMax + C.EndCard.AutoClose[r]
				+ C.Return.Time
			longest = math.max(longest, total)
		end
		check(type(Timers.Cutscene[r]) == "number" and Timers.Cutscene[r] + 1e-9 >= longest,
			"server timeout covers the longest " .. r .. " cutscene", ("%s < %s"):format(tostring(Timers.Cutscene[r]), longest))
		check(Timers.Cutscene[r] - longest < 1e-6 + 0.5, r .. " server timeout derived from the caught budget (no slack drift)")
		check(C.EndCard.AutoClose[r] < 30, r .. " end card closes before the Director's 30 s guard")
		for _, sf in { 0.99, 1.4, 2.3 } do
			local fl = Timeline.FlightSeconds(sf)
			local both = Timeline.EarliestEnd(r, fl)
			for _, caught in { true, false } do
				local label = r .. (if caught then " caught" else " missed")
				local e = Timeline.EarliestEnd(r, fl, caught)
				check(both <= e + 1e-9, label .. ": the server floor (either outcome) never exceeds this outcome's earliest end")
				local full = Timeline.Build(r, fl, { Caught = caught })
				check(e > C.WindUp.ReleaseAt + fl and e <= full.Total + 1e-9, label .. " earliest end after touchdown, <= full")
				if C.Skip.Never[r] then
					check(near(e, full.Total), label .. " (never skippable) earliest end = the full timeline")
				else
					check(e <= full.ByName[C.Skip.FromBeat].Start + 1e-9, label .. " earliest end <= the Skip point")
					if caught and r ~= "Common" then -- (a Common may be shortened by Settings.HideCommonReveals)
						check(e >= full.ByName.Victory.Start + full.ByName.Victory.Length - 1e-9, label .. " the victory beat is always seen")
					end
				end
				if r == "Common" then
					check(e <= Timeline.Build(r, fl, { Short = true }).Total + 1e-9, "Common earliest end <= short Common")
				end
			end
		end
	end
	check(Timers.CutscenePadding > 0, "server timeout padding > 0")
end

process.exit(Loader.Done("cutscene") > 0 and 1 or 0)
