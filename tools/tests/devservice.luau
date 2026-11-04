--!nocheck
-- Dev tools rules + maths (src/shared/Util/DevTools.luau, used by src/server/Services/DevService.luau and the client
-- Dev panel).   lune run tools/tests/devservice.luau
-- Proves: the permission gate (Studio = everyone; live server = nobody unless StudioOnly = false AND the UserId is
-- listed; Enabled = false = nobody), argument validation, every zone's PowerForZone lands inside that zone for
-- every Good release (quality GoodQualityMin..Max, scatter +-Scatter) with each ball, MaxPower reaches the end of
-- the field with a Perfect Tennis throw, and training never clamps a dev power down (Training.ApplyRep).
local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("./loader")
local check = Loader.Check

local Shared = Loader.Mount("src/shared")
local Game = Loader.Require(Shared.Config.Game)
local Zones = Loader.Require(Shared.Config.Zones)
local Balls = Loader.Require(Shared.Config.Balls)
local Training = Loader.Require(Shared.Config.Training)
local PlayerStats = Loader.Require(Shared.Util.PlayerStats)
local Meter = Loader.Require(Shared.Util.Meter)
local DevTools = Loader.Require(Shared.Util.DevTools)

-- 1. Permission gate
local cfg = Game.DevTools
check(cfg.Enabled == true and cfg.StudioOnly == true and #cfg.UserIds == 0, "shipped config: enabled, Studio only, no UserIds")
check(DevTools.IsAllowed(cfg, true, 123), "Studio: everyone is a dev")
check(not DevTools.IsAllowed(cfg, false, 123), "live server with the shipped config: nobody")
check(not DevTools.IsAllowed({ Enabled = true, StudioOnly = true, UserIds = { 123 } }, false, 123), "live: StudioOnly still gates a listed id")
check(DevTools.IsAllowed({ Enabled = true, StudioOnly = false, UserIds = { 123 } }, false, 123), "live: listed id allowed when StudioOnly = false")
check(not DevTools.IsAllowed({ Enabled = true, StudioOnly = false, UserIds = { 123 } }, false, 456), "live: unlisted id refused")
check(not DevTools.IsAllowed({ Enabled = true, StudioOnly = false, UserIds = {} }, false, 0), "live: empty list refuses everyone")
check(not DevTools.IsAllowed({ Enabled = false, StudioOnly = false, UserIds = { 123 } }, true, 123), "Enabled = false: nobody, even in Studio")
check(not DevTools.IsAllowed(nil, true, 1), "no config: nobody")
-- the server checks the gate on every invoke and in Run (not only on join)
local src = fs.readFile("src/server/Services/DevService.luau")
local _, gates = string.gsub(src, "DevService.IsAllowed%(player%)", "")
check(gates >= 3, "DevService checks permission on join, on invoke and in Run", tostring(gates))
check(string.find(src, "limiter:Check(player)", 1, true) ~= nil, "DevService rate-limits")
check(string.find(src, "DataService.Push(player)", 1, true) ~= nil, "DevService pushes a StateUpdate")
local remotes = fs.readFile("src/shared/Remotes.luau")
check(string.find(remotes, '"DevCommand"', 1, true) ~= nil, "DevCommand is in Remotes.Functions")
check(string.find(fs.readFile("src/server/Main.server.luau"), '"DevService"', 1, true) ~= nil, "DevService starts from Main")

-- 2. Validation
check(DevTools.Validate("AddPower", 100) and DevTools.Validate("AddPower", 1000) and DevTools.Validate("AddPower", 10000), "AddPower steps")
check(not DevTools.Validate("AddPower", 5) and not DevTools.Validate("AddPower", "100") and not DevTools.Validate("AddPower", 1e12), "AddPower rejects other amounts")
for _, z in Zones do
	check(DevTools.Validate("PowerForZone", z.Id), "PowerForZone accepts " .. z.Id)
end
check(not DevTools.Validate("PowerForZone", "Moon") and not DevTools.Validate("PowerForZone", 3), "PowerForZone rejects bad zones")
for _, c in { "MaxPower", "ResetPower", "AddCash", "GiveBalls" } do
	check(DevTools.Validate(c, nil), c .. " without an argument")
	check(not DevTools.Validate(c, 5), c .. " rejects an argument")
end
check(not DevTools.Validate("GiveRobux", nil) and not DevTools.Validate(nil, nil), "unknown commands refused")

-- 3. PowerForZone: every Good release with every ball lands inside the zone
local m = Game.Meter
check(DevTools.GoodQuality() > m.GoodQualityMin and DevTools.GoodQuality() < m.GoodQualityMax, "GoodQuality is inside the Good band")
local _, q1, band1 = Meter.Evaluate(Meter.Period() / 2 * m.GoodMin + 1e-6)
check(band1 == "Good" and math.abs(q1 - m.GoodQualityMin) < 1e-3, "the Good band starts at GoodQualityMin (meter maths)")
local s = Game.Throw.Scatter
for _, id in Balls.Order do
	local ball = Balls.ById[id]
	for _, z in Zones do
		local power = DevTools.PowerForZone(z, ball.RangeMult)
		local okAll = true
		local detail = ""
		for _, q in { m.GoodQualityMin, DevTools.GoodQuality(), m.GoodQualityMax } do
			for _, sc in { -s, 0, s } do
				local d = PlayerStats.ThrowDistance(power, ball.RangeMult, q, sc, Game.Throw.MinDistance)
				local zone = PlayerStats.ZoneForDistance(d)
				if zone.Id ~= z.Id then
					okAll = false
					detail = ("q %.2f scatter %.2f -> %.0f studs (%s)"):format(q, sc, d, zone.Id)
				end
			end
		end
		check(okAll, ("%s: a Good throw at %d power lands in %s"):format(id, power, z.Id), detail)
		local _, reach = DevTools.GoodReach(power, ball.RangeMult)
		check(reach.Id == z.Id, ("%s: the panel's reach line names %s"):format(id, z.Id))
	end
end

-- 4. MaxPower
local maxP = DevTools.MaxPower()
local far = PlayerStats.ThrowDistance(maxP, Balls.ById.Tennis.RangeMult, 1, -s, Game.Throw.MinDistance)
check(math.abs(far - PlayerStats.MaxFieldDistance()) < 1e-6, "MaxPower: a Perfect Tennis throw reaches the field's end even at -scatter", tostring(far))
check(PlayerStats.ZoneForDistance(far).Id == Zones[#Zones].Id, "MaxPower reaches the Mythic Meadow")
check(maxP > Training.MaxThrowPower, "MaxPower is above the training caps (dev bypass)")

-- 5. Training after dev power: never clamps down, still adds below the cap
local cap = Training.PowerCap(0)
check(Training.ApplyRep(maxP, 1, cap) == maxP, "a rep above the cap leaves dev power alone")
check(Training.ApplyRep(cap, 1, cap) == cap, "a rep at the cap adds nothing")
check(Training.ApplyRep(cap - 0.5, 1, cap) == cap, "a rep below the cap stops at the cap")
check(Training.ApplyRep(10, 1, cap) == 11, "a normal rep adds its gain")
check(string.find(fs.readFile("src/server/Services/TrainingService.luau"), "Training.ApplyRep(", 1, true) ~= nil, "TrainingService uses ApplyRep")

process.exit(Loader.Done("devservice") > 0 and 1 or 0)
