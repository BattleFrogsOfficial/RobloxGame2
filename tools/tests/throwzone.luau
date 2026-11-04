--!nocheck
-- The brown throw zone (src/shared/Util/ThrowZone.luau, used by src/server/Services/ThrowService.luau).
--   lune run tools/tests/throwzone.luau        (from the repo root; exit code 1 on any failure)
-- Proves:
--   1. Layout.ThrowZone contract: { MinX, MaxX, MinZ, MaxZ, Y }, Y = HubY, MaxZ = ThrowLine.Z, inside the plaza;
--      Layout.Platform keeps only ThrowSpot (= the zone centre at HubY), no QueueSpots / StandRadius;
--   2. zone membership: XZ inside the rectangle + Game.ThrowZone.EdgeMargin, Y >= Y - YTolerance;
--   3. launch point: (root X clamped into the zone, HubY + LaunchHeight, ThrowLine.Z); landing X blends toward the
--      thrower and stays in |x| <= 56;
--   4. charge rules: no turns (any number of players in the zone can charge at once), one throw in flight each,
--      MinSecondsBetweenThrows per player, ChargeBegin while charging restarts the sweep (rate-limited by
--      MinRestartSeconds), release outside the zone cancels, MaxChargeSeconds cancels (no auto-throw);
--   5. the server wiring (source checks): ThrowQueue is gone, InThrowZone / OnPlatform / ThrowQueuePos attributes,
--      no auto-release, the Robux ball receipt in ShopService.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local Vector3 = roblox.Vector3
local check = Loader.Check

local Shared = Loader.Mount("src/shared")
local Game = Loader.Require(Shared.Config.Game)
local Layout = Loader.Require(Shared.Config.Layout)
local ThrowZone = Loader.Require(Shared.Util.ThrowZone)

-- 1. contract
local Z = Layout.ThrowZone
check(type(Z) == "table" and type(Z.MinX) == "number" and type(Z.MaxX) == "number" and type(Z.MinZ) == "number"
	and type(Z.MaxZ) == "number" and type(Z.Y) == "number", "Layout.ThrowZone = { MinX, MaxX, MinZ, MaxZ, Y }")
check(Z.Y == Layout.HubY, "zone surface = HubY", tostring(Z.Y))
check(Z.MaxZ == Layout.ThrowLine.Z, "zone front edge = the throw line", tostring(Z.MaxZ))
check(Z.MinX >= Layout.Plaza.MinX and Z.MaxX <= Layout.Plaza.MaxX and Z.MinZ >= Layout.Plaza.MinZ, "zone inside the plaza")
check(Z.MaxX - Z.MinX >= 80 and Z.MaxZ - Z.MinZ >= 18 and Z.MaxZ - Z.MinZ <= 24, "big: about the plaza front wide, ~20 deep",
	("%g x %g"):format(Z.MaxX - Z.MinX, Z.MaxZ - Z.MinZ))
local spot = Layout.Platform.ThrowSpot
check(spot == Vector3.new((Z.MinX + Z.MaxX) / 2, Layout.HubY, (Z.MinZ + Z.MaxZ) / 2), "Platform.ThrowSpot = zone centre at HubY",
	tostring(spot))
check(Layout.Platform.QueueSpots == nil and Layout.Platform.StandRadius == nil, "no QueueSpots / StandRadius")
check(ThrowZone.Center() == spot, "ThrowZone.Center() = ThrowSpot")

-- 2. membership
local m, yt = Game.ThrowZone.EdgeMargin, Game.ThrowZone.YTolerance
check(Game.ThrowZone.SampleInterval <= 0.25 + 1e-9, "sampled ~4x per second")
local root = Layout.HubY + 3
check(ThrowZone.Contains(Vector3.new(0, root, 50)), "centre is in")
check(ThrowZone.Contains(Vector3.new(Z.MinX - m + 0.01, root, Z.MinZ - m + 0.01)), "corner + margin is in")
check(not ThrowZone.Contains(Vector3.new(Z.MinX - m - 0.01, root, 50)), "west of the margin is out")
check(not ThrowZone.Contains(Vector3.new(Z.MaxX + m + 0.01, root, 50)), "east of the margin is out")
check(not ThrowZone.Contains(Vector3.new(0, root, Z.MinZ - m - 0.01)), "behind the back edge is out")
check(ThrowZone.Contains(Vector3.new(0, Layout.HubY - yt, 50)), "Y = HubY - YTolerance is in")
check(not ThrowZone.Contains(Vector3.new(0, Layout.HubY - yt - 0.01, 50)), "below HubY - YTolerance (fell off) is out")
check(ThrowZone.Contains(Vector3.new(0, Layout.HubY + 9, 50)), "jumping in the zone is still in")
check(not ThrowZone.Contains(Vector3.new(0, root, 20)), "the plaza (e.g. Z 20) is out")

-- 3. launch + landing
for _, x in { Z.MinX - 1, Z.MinX, -20, 0, 13.5, Z.MaxX, Z.MaxX + 1.4 } do
	local lp = ThrowZone.LaunchPos(Vector3.new(x, root, 45))
	check(lp.X == math.clamp(x, Z.MinX, Z.MaxX) and lp.Y == Layout.HubY + Game.Throw.LaunchHeight and lp.Z == Layout.ThrowLine.Z,
		("launch from the edge in front of a thrower at x %g"):format(x), tostring(lp))
end
check(ThrowZone.LaunchPos(Vector3.new(0, root, 41)).Y == 44, "launch height 44")
for _, x in { Z.MinX, -25, 0, 25, Z.MaxX } do
	for _, u in { -1, 0, 1 } do
		local lx = ThrowZone.LandX(x, u)
		local want = math.clamp(x * 0.5 + u * Game.Throw.LateralScatter * 0.5, -56, 56)
		check(math.abs(lx - want) < 1e-9 and math.abs(lx) <= 56, ("landing X for thrower %g, u %g"):format(x, u), tostring(lx))
	end
end
check(ThrowZone.LaneHalf == 56, "landing lane |x| <= 56")

-- 4. charge rules
local G = Game.Throw
check(G.MaxChargeSeconds == 6 and G.MinSecondsBetweenThrows == 2 and G.MinChargeSeconds == 0.25, "throw timings unchanged")
check(G.MinRestartSeconds > 0 and G.MinRestartSeconds < Game.Meter.Period, "a restart every period is accepted")
local function ctx(t)
	t.Now = t.Now or 100
	if t.InZone == nil then
		t.InZone = true
	end
	return t
end
check(ThrowZone.Begin(ctx({})) == "start", "in the zone, idle: ChargeBegin starts")
check(ThrowZone.Begin(ctx({ InZone = false })) == nil, "outside the zone: refused")
check(ThrowZone.Begin(ctx({ Loaded = false })) == nil, "not loaded: refused")
check(ThrowZone.Begin(ctx({ InFlight = true })) == nil, "a throw in flight: refused (one ball each)")
check(ThrowZone.Begin(ctx({ LastRelease = 98.5 })) == nil, "1.5 s after a release: cooldown")
check(ThrowZone.Begin(ctx({ LastRelease = 98 })) == "start", "2 s after a release: ok")
check(ThrowZone.Begin(ctx({ ChargeStart = 100 - Game.Meter.Period })) == "restart", "ChargeBegin while charging (a period in): restart")
check(ThrowZone.Begin(ctx({ ChargeStart = 99.5 })) == nil, "restart spam (0.5 s in): ignored")
check(ThrowZone.Begin(ctx({ ChargeStart = 96, InZone = false })) == nil, "restart outside the zone: refused")
-- no turns: six players in the zone all start at the same moment
local started = 0
for _ = 1, 6 do
	if ThrowZone.Begin(ctx({})) == "start" then
		started += 1
	end
end
check(started == 6, "no turns: everyone in the zone can charge at once", tostring(started))
check(ThrowZone.Release(ctx({ ChargeStart = 99 })) == "throw", "tap in the zone: throw")
check(ThrowZone.Release(ctx({ ChargeStart = 99, InZone = false })) == "cancel", "tap outside the zone: cancel")
check(ThrowZone.Release(ctx({})) == nil, "tap with no charge: nothing")
check(not ThrowZone.Expired(100, 100 + G.MaxChargeSeconds - 0.01) and ThrowZone.Expired(100, 100 + G.MaxChargeSeconds),
	"MaxChargeSeconds after the (re)start the charge expires")

-- 5. server wiring
local ts = fs.readFile("src/server/Services/ThrowService.luau")
check(not fs.isFile("src/server/Services/ThrowQueue.luau"), "ThrowQueue.luau is gone")
check(not string.find(ts, 'WaitForChild("ThrowQueue")', 1, true) and not string.find(ts, "queue:", 1, true) and not string.find(ts, "QueueSpots", 1, true)
	and not string.find(ts, "StandRadius", 1, true), "ThrowService has no queue / queue spots / StandRadius")
for _, attr in { '"InThrowZone"', '"OnPlatform"', '"ThrowQueuePos"' } do
	check(string.find(ts, attr, 1, true) ~= nil, "ThrowService sets " .. attr)
end
check(string.find(ts, "ThrowZone.Begin(", 1, true) ~= nil and string.find(ts, "ThrowZone.Release(", 1, true) ~= nil,
	"ThrowService uses the shared charge rules")
check(string.find(ts, "release(player) -- auto", 1, true) == nil, "no auto-release on MaxChargeSeconds")
check(string.find(ts, "ThrowZone.LaunchX(rootPos.X)", 1, true) ~= nil, "launch X from the thrower's root")
local shop = fs.readFile("src/server/Services/ShopService.luau")
check(string.find(shop, "(Products :: any).Balls", 1, true) ~= nil, "ShopService reads Products.Balls (guarded)")
check(string.find(shop, "ShopService.FindBallProduct(info.ProductId)", 1, true) ~= nil, "ProcessReceipt handles Robux balls")
local remotes = fs.readFile("src/shared/Remotes.luau")
check(string.find(remotes, "InThrowZone", 1, true) ~= nil and string.find(remotes, "DEPRECATED", 1, true) ~= nil,
	"Remotes header documents InThrowZone and the deprecated attributes")

if Loader.Done("throwzone") > 0 then
	process.exit(1)
end
