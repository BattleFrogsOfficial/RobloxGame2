--!nocheck
-- Plateau-to-field ball flight test (Util/BallFlight + the throw distance maths).
--   lune run tools/tests/ballflight.luau       (from the repo root; exit code 1 on any failure)
-- Proves:
--   1. the horizontal landing distance for a given meter elapsed time is EXACTLY the old (pre-platform) formula
--      Distance = clamp(ThrowPower x RangeMult x Quality(elapsed) x (1 + scatter), MinDistance, Field.MaxZ - ThrowLine.Z)
--      measured from Layout.ThrowLine.Z, for every ball, several powers, scatters and elapsed times (tutorial too);
--   2. the arc starts at LaunchPos = hand height on the deck (deck surface Layout.ThrowLine.Y = Layout.HubY = 40,
--      + Game.Throw.LaunchHeight = 44, above the 43.35 railing caps) and ends at LandPos on the field
--      (Y = Layout.GroundY = 0) at that distance;
--   3. Z is monotone (strictly increasing) along the flight; X is linear; the apex is above the deck;
--   4. the drop is ADDED to the flight: the arc's Duration (= ThrowResult.FlightTime) is longer than the old flat
--      pacing DefaultFlightTime(d), by exactly the extra fall time of the same throw (same apex, same gravity) over
--      the 40 extra studs; a hand-height drop over flat ground gives back DefaultFlightTime exactly;
--   5. Solve() honours ApexHeight / FlightTime in every parameter combination.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local Vector3 = roblox.Vector3
local check = Loader.Check

local Shared = Loader.Mount("src/shared")
local Game = Loader.Require(Shared.Config.Game)
local Layout = Loader.Require(Shared.Config.Layout)
local Balls = Loader.Require(Shared.Config.Balls)
local Meter = Loader.Require(Shared.Util.Meter)
local PlayerStats = Loader.Require(Shared.Util.PlayerStats)
local BallFlight = Loader.Require(Shared.Util.BallFlight)

local EPS = 1e-9
check(Layout.HubY == 40 and Layout.GroundY == 0, "hub plateau at Y 40, field at Y 0", ("%s / %s"):format(Layout.HubY, Layout.GroundY))
check(Layout.ThrowLine.Y == Layout.HubY, "Layout.ThrowLine.Y is the (flush) deck surface = HubY", tostring(Layout.ThrowLine.Y))
local spot = Layout.Platform.ThrowSpot
check(spot.Y == Layout.ThrowLine.Y, "ThrowSpot on the deck surface")
local DECK_Y = Layout.ThrowLine.Y + Game.Throw.LaunchHeight -- launch height
check(DECK_Y == 44 and DECK_Y > 43.35, "launch height 44, above the railing caps", tostring(DECK_Y))
check(BallFlight.ReferenceDrop == Game.Throw.LaunchHeight, "reference throw drops LaunchHeight (hand height on flat ground)")

-- The OLD formula, written out independently of Meter/PlayerStats (docs/DESIGN.md §4.2-4.4).
local function oldQuality(elapsed: number, tutorial: boolean): number
	local m = Game.Meter
	local period = if tutorial then m.Period / Game.Tutorial.MeterSpeedMult else m.Period
	local phase = (math.max(0, elapsed) % period) / period
	local pos = 1 - math.abs(2 * phase - 1)
	if elapsed < Game.Throw.MinChargeSeconds then
		return m.FlubQuality
	elseif pos >= m.PerfectMin then
		return 1
	elseif pos >= m.GoodMin then
		return m.GoodQualityMin + (m.GoodQualityMax - m.GoodQualityMin) * ((pos - m.GoodMin) / (m.PerfectMin - m.GoodMin))
	end
	return m.OkQualityMin + m.OkQualitySpan * (pos / m.GoodMin)
end
local function oldDistance(power, rangeMult, elapsed, tutorial, scatter)
	local d = power * rangeMult * oldQuality(elapsed, tutorial) * (1 + scatter)
	return math.clamp(d, Game.Throw.MinDistance, Layout.Field.MaxZ - Layout.ThrowLine.Z)
end

-- What ThrowService does now.
local function newThrow(power, rangeMult, elapsed, tutorial, scatter, landX)
	local _, quality = Meter.Evaluate(elapsed, tutorial)
	local distance = PlayerStats.ThrowDistance(power, rangeMult, quality, scatter, Game.Throw.MinDistance)
	local launch, land = BallFlight.Endpoints(spot, DECK_Y, Layout.ThrowLine.Z, Layout.GroundY, distance, landX)
	return distance, BallFlight.ForThrow(launch, land), launch, land
end

-- Vector3 components are 32-bit floats in Roblox (and in @lune/roblox): positions carry ~1e-7 relative error.
local F32 = function(z: number): number
	return math.max(1e-5, math.abs(z) * 2e-7)
end
local cases, worstDiff, worstVecDiff = 0, 0, 0
local monotoneFails, endFails, startFails, longerFails, extraFails = 0, 0, 0, 0, 0
local minExtra, maxExtra = math.huge, 0
for _, power in { 60, 145, 385, 1000, 2000 } do
	for _, ballId in Balls.Order do
		local rm = Balls.ById[ballId].RangeMult
		for _, scatter in { -Game.Throw.Scatter, 0, Game.Throw.Scatter } do
			for _, tutorial in { false, true } do
				for step = 0, 600, 7 do
					local elapsed = step / 100
					local landX = ((step % 23) - 11) * 5 -- inside the clear lane |x| <= 56
					local old = oldDistance(power, rm, elapsed, tutorial, scatter)
					local distance, arc, launch, land = newThrow(power, rm, elapsed, tutorial, scatter, landX)
					cases += 1
					local horiz = land.Z - Layout.ThrowLine.Z
					worstDiff = math.max(worstDiff, math.abs(distance - old))
					worstVecDiff = math.max(worstVecDiff, math.abs(horiz - old) - F32(land.Z))
					local p0, p1 = arc.Position(0), arc.Position(arc.Duration)
					-- the drop is added: longer than the flat pacing, by the extra fall of the same throw
					local horizD = math.sqrt((land.X - launch.X) ^ 2 + (land.Z - launch.Z) ^ 2)
					local T0 = BallFlight.DefaultFlightTime(horizD)
					local g = BallFlight.FlatGravity(horizD)
					local H = BallFlight.DefaultApex(horizD)
					local expect = T0 - math.sqrt(2 * (H + Game.Throw.LaunchHeight) / g) + math.sqrt(2 * (H + (DECK_Y - Layout.GroundY)) / g)
					if arc.Duration <= T0 then
						longerFails += 1
					end
					if math.abs(arc.Duration - expect) > 1e-9 or math.abs(arc.Gravity - g) > 1e-9 then
						extraFails += 1
					end
					minExtra = math.min(minExtra, arc.Duration - T0)
					maxExtra = math.max(maxExtra, arc.Duration - T0)
					if (p0 - launch).Magnitude > EPS then
						startFails += 1
					end
					if math.abs(p1.Y - 0) > EPS or math.abs(p1.Z - (Layout.ThrowLine.Z + old)) > F32(p1.Z)
						or math.abs(p1.X - landX) > F32(landX) then
						endFails += 1
					end
					-- also the analytic end (not the clamped shortcut): position just before Duration
					local pe = arc.Position(arc.Duration - 1e-7)
					if math.abs(pe.Y) > 1e-3 or math.abs(pe.Z - land.Z) > 1e-3 then
						endFails += 1
					end
					local prevZ = -math.huge
					for i = 0, 100 do
						local z = arc.Position(arc.Duration * i / 100).Z
						if z <= prevZ then
							monotoneFails += 1
							break
						end
						prevZ = z
					end
				end
			end
		end
	end
end
check(worstDiff == 0, "distance identical to the old formula for every case", ("worst diff %g over %d cases"):format(worstDiff, cases))
check(worstVecDiff <= 0, "LandPos.Z - ThrowLine.Z = distance (to float32 precision)", ("excess %g"):format(worstVecDiff))
print(("%d throws compared with the old formula: max |new - old| = %g"):format(cases, worstDiff))
check(startFails == 0, "arc starts at LaunchPos (deck, Y = 44)", tostring(startFails) .. " bad")
check(endFails == 0, "arc ends at LandPos (Y = GroundY at ThrowLine.Z + distance)", tostring(endFails) .. " bad")
check(longerFails == 0, "every flight is longer than the flat pacing (the ball stays in the air longer)", tostring(longerFails) .. " bad")
check(extraFails == 0, "Duration = flat pacing + the extra fall time over the drop (same apex, same gravity)", tostring(extraFails) .. " bad")
print(("flight time added by the 40-stud drop: %.3f .. %.3f s"):format(minExtra, maxExtra))
-- the reference: a hand-height throw over flat ground keeps the old pacing exactly
do
	local a = BallFlight.ForThrow(Vector3.new(0, Game.Throw.LaunchHeight, 56), Vector3.new(0, 0, 556))
	check(math.abs(a.Duration - BallFlight.DefaultFlightTime(500)) < 1e-9, "flat reference throw = DefaultFlightTime",
		tostring(a.Duration))
end
check(monotoneFails == 0, "Z strictly increasing along the flight", tostring(monotoneFails) .. " bad")

-- A typical throw in detail.
do
	local distance, arc, launch, land = newThrow(385, 1.25, 0.8, false, 0, 10)
	check(math.abs(distance - 385 * 1.25) < EPS, "perfect 0.8 s release: 385 x 1.25 studs", tostring(distance))
	check(arc.ApexHeight > 0 and arc.Apex.Y > DECK_Y, "apex above the deck", tostring(arc.Apex.Y))
	local horiz = math.sqrt((land.X - launch.X) ^ 2 + (land.Z - launch.Z) ^ 2)
	check(arc.Duration > BallFlight.DefaultFlightTime(horiz), "duration longer than the flat pacing")
	check(math.abs(arc.Gravity - BallFlight.FlatGravity(horiz)) < 1e-9, "gravity = flat reference gravity")
	check(math.abs(arc.ApexHeight - BallFlight.DefaultApex(horiz)) < 1e-6, "apex height = default apex", tostring(arc.ApexHeight))
	-- parabola: sample-based apex never exceeds the analytic one
	local maxY = -math.huge
	for i = 0, 1000 do
		maxY = math.max(maxY, arc.Position(arc.Duration * i / 1000).Y)
	end
	check(maxY <= arc.Apex.Y + 1e-6 and maxY >= arc.Apex.Y - 0.05, "sampled apex matches analytic apex")
	-- X linear in t
	local mid = arc.Position(arc.Duration / 2)
	check(math.abs(mid.X - (launch.X + land.X) / 2) < 1e-6 and math.abs(mid.Z - (launch.Z + land.Z) / 2) < 1e-6,
		"horizontal motion is uniform")
	print(("typical throw: %.1f studs, flight %.2f s (flat pacing %.2f s), apex %.1f studs above the deck, launch vy %.1f, g %.1f"):format(
		distance, arc.Duration, BallFlight.DefaultFlightTime(horiz), arc.ApexHeight, arc.Velocity.Y, arc.Gravity))
end

-- Parameter combinations.
do
	local launch, land = Vector3.new(0, 40, 56), Vector3.new(5, 0, 900)
	local a = BallFlight.Solve(launch, land, { ApexHeight = 80, FlightTime = 1.5 })
	check(math.abs(a.Duration - 1.5) < EPS and math.abs(a.ApexHeight - 80) < 1e-6, "apex+time honoured")
	check((a.Position(a.Duration - 1e-9) - land).Magnitude < 1e-3, "apex+time lands")
	local b = BallFlight.Solve(launch, land, { ApexHeight = 50 })
	check(math.abs(b.Gravity - BallFlight.DefaultGravity) < EPS and math.abs(b.ApexHeight - 50) < 1e-6, "apex only honoured")
	check((b.Position(b.Duration - 1e-9) - land).Magnitude < 1e-3, "apex only lands")
	local c = BallFlight.Solve(launch, land, { FlightTime = 2 })
	check(math.abs(c.Duration - 2) < EPS, "time only honoured")
	check((c.Position(c.Duration - 1e-9) - land).Magnitude < 1e-3, "time only lands")
	local d = BallFlight.Solve(launch, land, { FlightTime = 0.2 }) -- shorter than a free fall: thrown downward
	check((d.Position(d.Duration - 1e-9) - land).Magnitude < 1e-3 and d.Velocity.Y < 0, "very short flight is a downward throw")
end

if Loader.Done("ballflight") > 0 then
	process.exit(1)
end
