--!nonstrict
-- RollService distribution checks. Run from the Studio command bar (server side, e.g. in Play Solo
-- "Server" view or Run mode):
--   require(game.ServerScriptService.Server.Tests["RollService.spec"])()
-- Prints PASS/FAIL per check and returns (passed, failed). Uses seeded RNGs, so results are stable.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities")) :: any
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game")) :: any
local Odds = require(Shared:WaitForChild("Util"):WaitForChild("Odds")) :: any
local RollService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services"):WaitForChild("RollService")) :: any

local N = 200000

-- Fake zone: n dogs per tier (ids "<Tier>_<i>").
local function fakeZone(counts: { [string]: number }): { [string]: { any } }
	local lists: { [string]: { any } } = {}
	for tier, n in counts do
		lists[tier] = {}
		for i = 1, n do
			table.insert(lists[tier], { Id = tier .. "_" .. i, Rarity = tier })
		end
	end
	return lists
end
local STANDARD = fakeZone({ Common = 54, Uncommon = 13, Rare = 7, Epic = 3, Legendary = 2, Mythic = 1 })
local MEADOW = fakeZone({ Common = 53, Mythic = 2 })

-- tolerance: 5 standard deviations of a binomial proportion, at least 0.0005
local function close(observed: number, expected: number, n: number): boolean
	local sd = math.sqrt(math.max(expected * (1 - expected), 1e-9) / n)
	return math.abs(observed - expected) <= math.max(5 * sd, 0.0005)
end

return function(): (number, number)
	local passed, failed = 0, 0
	local function check(name: string, cond: boolean, detail: string?)
		if cond then
			passed += 1
			print("PASS  " .. name)
		else
			failed += 1
			warn("FAIL  " .. name .. (if detail then ("  (" .. detail .. ")") else ""))
		end
	end

	-- 1. Base tier odds
	do
		local rng = RollService.NewRng(1)
		local counts: { [string]: number } = {}
		for _ = 1, N do
			local t = RollService.RollTier(rng, 0, nil)
			counts[t] = (counts[t] or 0) + 1
		end
		for _, tier in Rarities.Order do
			local obs = (counts[tier] or 0) / N
			local exp = Rarities.Tiers[tier].Odds
			check("base odds " .. tier, close(obs, exp, N), ("obs %.5f exp %.5f"):format(obs, exp))
		end
	end

	-- 2. Luck 0.5 multiplies every non-Common tier by 1.5 (Common absorbs)
	do
		local o = Odds.TierOdds(0.5)
		local ok = true
		for _, tier in Rarities.Order do
			if tier ~= "Common" and math.abs(o[tier] - Rarities.Tiers[tier].Odds * 1.5) > 1e-9 then
				ok = false
			end
		end
		check("luck 0.5 shifts non-Common x1.5", ok)
		check("luck 0.5 Common = 0.625", math.abs(o.Common - 0.625) < 1e-9, tostring(o.Common))
		local rng = RollService.NewRng(2)
		local legendaryPlus = 0
		for _ = 1, N do
			local t = RollService.RollTier(rng, 0.5, nil)
			if t == "Legendary" or t == "Mythic" then
				legendaryPlus += 1
			end
		end
		check("luck 0.5 rolled Legendary+ ~0.75%", close(legendaryPlus / N, 0.0075, N),
			("obs %.5f"):format(legendaryPlus / N))
	end

	-- 3. Luck cap keeps Common at the floor
	do
		local o = Odds.TierOdds(100)
		check("luck cap Common floor", math.abs(o.Common - Game.Luck.MinCommonOdds) < 1e-9, tostring(o.Common))
		local sum = 0
		for _, tier in Rarities.Order do
			sum += o[tier]
		end
		check("odds sum to 1", math.abs(sum - 1) < 1e-9, tostring(sum))
	end

	-- 4. Meadow-style zone only rolls tiers that exist there (renormalised)
	do
		local rng = RollService.NewRng(3)
		local other, mythic = 0, 0
		for _ = 1, N do
			local out = RollService.Resolve(rng, { ZoneId = "MythicMeadow", Luck = 0, CatchBonus = 0, LuckyStreak = 0,
				ZoneTierLists = MEADOW })
			if out.Rarity == "Mythic" then
				mythic += 1
			elseif out.Rarity ~= "Common" then
				other += 1
			end
		end
		local exp = 0.001 / (0.75 + 0.001)
		check("meadow rolls only Common/Mythic", other == 0, tostring(other))
		check("meadow Mythic renormalised", close(mythic / N, exp, N), ("obs %.5f exp %.5f"):format(mythic / N, exp))
	end

	-- 5. Uniform dog pick within a tier
	do
		local rng = RollService.NewRng(4)
		local hits: { [string]: number } = {}
		local n = 70000
		for _ = 1, n do
			local d = RollService.PickDog(rng, STANDARD.Uncommon)
			hits[d.Id] = (hits[d.Id] or 0) + 1
		end
		local ok = true
		for _, d in STANDARD.Uncommon do
			if not close((hits[d.Id] or 0) / n, 1 / 13, n) then
				ok = false
			end
		end
		check("uniform pick among 13 Uncommons", ok)
	end

	-- 6. Variants (non-Common only; Rainbow -> Shadow -> Gold)
	do
		local rng = RollService.NewRng(5)
		local v: { [string]: number } = {}
		for _ = 1, N do
			local r = RollService.RollVariant(rng, "Rare") or "None"
			v[r] = (v[r] or 0) + 1
		end
		local exp = Odds.VariantChances()
		for _, name in { "Gold", "Shadow", "Rainbow", "None" } do
			check("variant " .. name, close((v[name] or 0) / N, exp[name], N),
				("obs %.5f exp %.5f"):format((v[name] or 0) / N, exp[name]))
		end
		local commonVariant = 0
		for _ = 1, 10000 do
			if RollService.RollVariant(rng, "Common") then
				commonVariant += 1
			end
		end
		check("Commons never roll variants", commonVariant == 0)
	end

	-- 7. Catch chances (+bonus, cap)
	do
		local rng = RollService.NewRng(6)
		for _, case in { { "Rare", 0, 0.80 }, { "Legendary", 0.10, 0.55 }, { "Common", 0.5, Game.Catch.MaxChance } } do
			local caught = 0
			for _ = 1, N do
				if (RollService.RollCatch(rng, case[1], case[2], 0)) then
					caught += 1
				end
			end
			check(("catch %s +%.2f"):format(case[1], case[2]), close(caught / N, case[3], N),
				("obs %.4f exp %.4f"):format(caught / N, case[3]))
		end
	end

	-- 8. Lucky Streak
	do
		local rng = RollService.NewRng(7)
		local allCaught, allTriggered = true, true
		for _ = 1, 1000 do
			local c, chance, trig = RollService.RollCatch(rng, "Mythic", 0, Rarities.LuckyStreakMisses)
			allCaught = allCaught and c and chance == 1
			allTriggered = allTriggered and trig
		end
		check("armed streak guarantees Legendary+", allCaught and allTriggered)
		local _, _, epicTrig = RollService.RollCatch(rng, "Epic", 0, 5)
		check("streak ignores Epic", not epicTrig)
		check("streak +1 on Legendary miss", RollService.NextStreak(1, "Legendary", false) == 2)
		check("streak resets on Legendary+ catch", RollService.NextStreak(2, "Mythic", true) == 0)
		check("streak untouched by Rare", RollService.NextStreak(1, "Rare", false) == 1)
		-- long-run Legendary own-rate with streak ~54%
		local streak, caught, attempts = 0, 0, 0
		for _ = 1, N do
			local c = RollService.RollCatch(rng, "Legendary", 0, streak)
			attempts += 1
			if c then
				caught += 1
			end
			streak = RollService.NextStreak(streak, "Legendary", c)
		end
		local q = 0.55
		local exp = 1 / (1 + q + q * q)
		check("streak long-run Legendary rate ~54%", close(caught / attempts, exp, attempts),
			("obs %.4f exp %.4f"):format(caught / attempts, exp))
	end

	-- 9. Tutorial: Common + caught + no variant, always
	do
		local rng = RollService.NewRng(8)
		local ok = true
		for _ = 1, 5000 do
			local out = RollService.Resolve(rng, { ZoneId = "Backyard", Luck = 5, CatchBonus = 0, LuckyStreak = 0,
				IsTutorial = true, ZoneTierLists = STANDARD })
			if out.Rarity ~= "Common" or not out.Caught or out.Variant ~= nil then
				ok = false
			end
		end
		check("tutorial is a guaranteed Common catch", ok)
	end

	-- 10. Treat Pocket: second roll at the same chance -> miss rate (1-p)^2
	do
		local rng = RollService.NewRng(9)
		local miss, used = 0, 0
		local zone = fakeZone({ Epic = 1 })
		for _ = 1, N do
			local out = RollService.Resolve(rng, { ZoneId = "X", Luck = 0, CatchBonus = 0, LuckyStreak = 0,
				TreatPockets = 1, TreatPocketMode = "Always", ZoneTierLists = zone })
			if not out.Caught then
				miss += 1
			end
			if out.TreatPocketUsed then
				used += 1
			end
		end
		check("treat pocket miss rate (1-p)^2", close(miss / N, 0.35 * 0.35, N), ("obs %.4f"):format(miss / N))
		check("treat pocket used only on first miss", close(used / N, 0.35, N), ("obs %.4f"):format(used / N))
		check("treat mode EpicPlus skips Rare", not RollService.ShouldUseTreat("EpicPlus", "Rare"))
		check("treat mode Off", not RollService.ShouldUseTreat("Off", "Mythic"))
	end

	-- 11. Determinism
	do
		local a, b = RollService.NewRng(42), RollService.NewRng(42)
		local same = true
		for _ = 1, 1000 do
			if RollService.RollTier(a, 0.3, nil) ~= RollService.RollTier(b, 0.3, nil) then
				same = false
			end
		end
		check("same seed -> same rolls", same)
	end

	print(("RollService.spec: %d passed, %d failed"):format(passed, failed))
	return passed, failed
end
