--!nocheck
-- The odds counter (src/shared/Cutscene/OddsCounter.luau).   lune run tools/tests/cutscene_counter.luau
-- Proves: the counter target is the Odds panel's per-dog number (same Util/Odds + DogCatalog maths, same
-- rounding as the panel's FormatNumber.Compact text) for every zone, tier and several luck values; the rarity
-- thresholds; the colour only climbs and ends on the dog's rarity; the tick schedule shows every number up to
-- LinearUpTo, then skips, is strictly increasing, accelerates, lands exactly on the target at the budget end
-- and stays under MaxTicks; click pitch rises; thousands formatting.
local process = require("@lune/process")
local Loader = require("./loader")
local check = Loader.Check

local Shared = Loader.Mount("src/shared")
local C = Loader.Require(Shared.Config.Cutscene)
local Rarities = Loader.Require(Shared.Config.Rarities)
local Zones = Loader.Require(Shared.Config.Zones)
local Odds = Loader.Require(Shared.Util.Odds)
local DogCatalog = Loader.Require(Shared.Util.DogCatalog)
local FormatNumber = Loader.Require(Shared.Util.FormatNumber)
local OC = Loader.Require(Shared.Cutscene.OddsCounter)

check(not DogCatalog.IsPlaceholder(), "real roster loaded (Data/Dogs.luau)")

-- The panel's own computation, copied from src/client/UI/Screens/Odds.luau refresh():
--   tierOdds = Odds.TierOdds(luck, DogCatalog.ZoneTiers(zone.Id)); n = #ZoneTierList; per = p / n;
--   oneIn(p) = "1 in " .. FormatNumber.Compact(1 / p)
local function panelPerDog(zoneId, tier, luck)
	local tierOdds = Odds.TierOdds(luck, DogCatalog.ZoneTiers(zoneId))
	local p = tierOdds[tier] or 0
	local n = #DogCatalog.ZoneTierList(zoneId, tier)
	local per = if n > 0 then p / n else 0
	return per
end
local function panelText(p)
	return "1 in " .. FormatNumber.Compact(1 / p)
end

-- 1. Target == the panel, for every zone x tier x luck.
local lucks = { 0, 0.04, 0.1, 0.2, 0.35, 0.5, 0.85, Odds.MaxEffectiveLuck(), 5 }
for _, z in Zones do
	for _, tier in Rarities.Order do
		for _, luck in lucks do
			local per = panelPerDog(z.Id, tier, luck)
			local target = OC.Target(z.Id, tier, luck)
			if per > 0 then
				check(panelText(per) == "1 in " .. FormatNumber.Compact(target),
					("counter matches panel %s %s luck %.3f"):format(z.Id, tier, luck),
					panelText(per) .. " vs " .. target)
				check(target == math.floor(1 / per), "target is floor(1 / per)")
				check(OC.Thresholds(z.Id, luck)[tier] == target, "threshold of the dog's own tier == target")
			end
		end
	end
end

-- 2. Worked examples (docs/DESIGN.md §6.3): base luck.
check(OC.Target("Backyard", "Common", 0) == 72, "Backyard Common 1 in 72", tostring(OC.Target("Backyard", "Common", 0)))
check(OC.Target("Backyard", "Uncommon", 0) == 76, "Uncommon 1 in 76")
check(OC.Target("Backyard", "Rare", 0) == 127, "Rare 1 in 127")
check(OC.Target("Backyard", "Epic", 0) == 150, "Epic 1 in 150")
check(OC.Target("Backyard", "Legendary", 0) == 500, "Legendary 1 in 500", tostring(OC.Target("Backyard", "Legendary", 0)))
check(OC.Target("Backyard", "Mythic", 0) == 1000, "Mythic 1 in 1,000", tostring(OC.Target("Backyard", "Mythic", 0)))
check(OC.Target("MythicMeadow", "Mythic", 0) == 2000, "Meadow Mythic 1 in 2,000")
check(OC.Target("MythicMeadow", "Common", 0) == 70 or OC.Target("MythicMeadow", "Common", 0) == 71, "Meadow Common ~71")
-- Golden ball (luck 0.5): Mythic 0.15% -> 1 in 666; Legendary 0.6% / 2 -> 1 in 333; Common 62.5% / 54 -> 1 in 86
check(OC.Target("Farm", "Mythic", 0.5) == 666, "Golden ball Mythic 1 in 666", tostring(OC.Target("Farm", "Mythic", 0.5)))
check(OC.Target("Farm", "Legendary", 0.5) == 333, "Golden ball Legendary 1 in 333", tostring(OC.Target("Farm", "Legendary", 0.5)))
check(OC.Target("Farm", "Common", 0.5) == 86, "Golden ball Common 1 in 86", tostring(OC.Target("Farm", "Common", 0.5)))
for _, ex in { { "Backyard", "Mythic", 0 }, { "Farm", "Legendary", 0.5 }, { "Beach", "Rare", 0.1 } } do
	print(("example %-9s %-9s luck %.2f -> panel %s, counter stops at %s"):format(ex[1], ex[2], ex[3],
		panelText(panelPerDog(ex[1], ex[2], ex[3])), OC.Text(OC.Target(ex[1], ex[2], ex[3]))))
end

-- 3. Colour climb.
local th = OC.Thresholds("Backyard", 0)
check(OC.TierAt(1, th, "Mythic") == nil, "starts white")
check(OC.TierAt(71, th, "Mythic") == nil, "white below the Common threshold")
check(OC.TierAt(72, th, "Mythic") == "Common", "Common grey at 72")
check(OC.TierAt(76, th, "Mythic") == "Uncommon", "Uncommon green at 76")
check(OC.TierAt(127, th, "Mythic") == "Rare", "Rare blue at 127")
check(OC.TierAt(150, th, "Mythic") == "Epic", "Epic purple at 150")
check(OC.TierAt(500, th, "Mythic") == "Legendary", "Legendary orange at 500")
check(OC.TierAt(1000, th, "Mythic") == "Mythic", "Mythic pink at 1000")
check(OC.TierAt(140, th, "Rare") == "Rare", "never above the dog's own rarity")
for _, z in Zones do
	for _, luck in lucks do
		local t2 = OC.Thresholds(z.Id, luck)
		for _, tier in Rarities.Order do
			if t2[tier] then
				local s = OC.Schedule(t2[tier], C.Beats.Counter[tier])
				local lastIdx = 0
				for _, v in s.Values do
					local at = OC.TierAt(v, t2, tier)
					local idx = if at then table.find(Rarities.Order, at) else 0
					check(idx >= lastIdx, "colour only climbs")
					lastIdx = idx
				end
				check(OC.TierAt(s.Target, t2, tier) == tier, ("stops on the dog's colour %s %s %.2f"):format(z.Id, tier, luck))
			end
		end
	end
end

-- 4. Schedule.
for _, target in { 1, 2, 10, 29, 30, 31, 72, 76, 150, 500, 1000, 2000, 3333, 6667, 25000 } do
	for _, dur in { 1.5, 2.5, 4 } do
		local s = OC.Schedule(target, dur)
		local m = #s.Values
		check(s.Values[1] == 1, "starts at 1 (" .. target .. ")")
		check(s.Values[m] == target, "lands exactly on " .. target)
		check(m <= C.Counter.MaxTicks, "at most MaxTicks ticks", tostring(m))
		for i = 1, math.min(target, C.Counter.LinearUpTo) do
			check(s.Values[i] == i, "every number up to LinearUpTo (" .. target .. ")")
		end
		if target > C.Counter.LinearUpTo + C.Counter.MaxTicks then
			check(m == C.Counter.MaxTicks, "big counts skip in larger steps")
		end
		for i = 2, m do
			check(s.Values[i] > s.Values[i - 1], "strictly increasing")
			check(s.Times[i] >= s.Times[i - 1], "times monotone")
		end
		check(s.Times[1] == 0 or m == 1, "first tick at 0")
		check(math.abs(s.Times[m] - dur) < 1e-9, "last tick at the budget end")
		check(OC.ValueAt(s, dur) == target and OC.ValueAt(s, dur + 5) == target, "ValueAt(end) == target")
		check(OC.ValueAt(s, 0) == 1, "ValueAt(0) == 1")
		if m >= 4 then
			-- ease-in: ticks get closer together (accelerating)
			check(s.Times[2] - s.Times[1] > s.Times[m] - s.Times[m - 1], "count accelerates")
		end
		-- steps grow (skipping) after the linear part
		if m > C.Counter.LinearUpTo + 2 then
			local first = s.Values[C.Counter.LinearUpTo + 1] - s.Values[C.Counter.LinearUpTo]
			local lastStep = s.Values[m] - s.Values[m - 1]
			check(lastStep >= first, "steps grow")
		end
		local prevV = 0
		for k = 0, 200 do
			local v = OC.ValueAt(s, dur * k / 200)
			check(v >= prevV, "ValueAt monotone")
			prevV = v
		end
	end
end
check(OC.ClickPitch(1, 50) == C.Counter.ClickMinPitch and math.abs(OC.ClickPitch(50, 50) - C.Counter.ClickMaxPitch) < 1e-9,
	"click pitch rises min -> max")
check(OC.ClickPitch(10, 50) < OC.ClickPitch(11, 50), "click pitch increases per tick")

-- 5. Formatting.
check(OC.Format(1) == "1" and OC.Format(999) == "999" and OC.Format(1000) == "1,000" and OC.Format(3333) == "3,333"
	and OC.Format(1234567) == "1,234,567", "thousands separators")
check(OC.Text(72) == "1 out of 72", "counter text")

process.exit(Loader.Done("cutscene_counter") > 0 and 1 or 0)
