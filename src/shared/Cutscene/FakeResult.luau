--!strict
-- CutsceneTestMode fake ThrowResults, generated locally from DogCatalog. They carry IsTest = true and are
-- NEVER sent to the server (no CutsceneFinished, no UseWhistle, no DogAction). Pure; Lune-tested.
--   FakeResult.Make(rng, { Rarity?, Caught?, Variant? ("Random" | "None" | name), ZoneId?, UserId? }) -> result
-- Unspecified fields are random: zone, distance inside that zone's band, dog of the rarity in that zone.
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local C = require(Config:WaitForChild("Cutscene"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local Layout = require(Config:WaitForChild("Layout"))
local Game = require(Config:WaitForChild("Game"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local BallFlight = require(Util:WaitForChild("BallFlight"))

local FakeResult = {}

export type Spec = {
	Rarity: string?,
	Caught: boolean?,
	Variant: string?, -- "Random" | "None" | "Gold" | "Shadow" | "Rainbow"; nil = Random
	ZoneId: string?,
	UserId: number?,
	BallId: string?,
}

local counter = 0

function FakeResult.Make(rng: Random, spec: Spec?): { [string]: any }
	local s: Spec = spec or {}
	local zone = Zones[rng:NextInteger(1, #Zones)]
	if s.ZoneId then
		for _, z in Zones do
			if z.Id == s.ZoneId then
				zone = z
			end
		end
	end
	local rarity = s.Rarity or Rarities.Order[rng:NextInteger(1, #Rarities.Order)]
	local list = DogCatalog.ZoneTierList(zone.Id, rarity)
	if #list == 0 then
		rarity = "Common"
		list = DogCatalog.ZoneTierList(zone.Id, rarity)
	end
	local def = list[rng:NextInteger(1, math.max(1, #list))]
	local variant: string? = nil
	if rarity ~= "Common" then
		local want = s.Variant or "Random"
		if want == "Random" then
			if rng:NextNumber() < C.Test.VariantChance then
				variant = Rarities.VariantOrder[rng:NextInteger(1, #Rarities.VariantOrder)]
			end
		elseif want ~= "None" and (Rarities.Variants :: any)[want] then
			variant = want
		end
	end
	local caught = if s.Caught ~= nil then s.Caught else rng:NextNumber() < C.Test.CaughtChance
	local maxD = Layout.Field.MaxZ - Layout.ThrowLine.Z
	local distance = math.clamp(rng:NextNumber(zone.MinDistance + 2, zone.MaxDistance - 2), Game.Throw.MinDistance, maxD)
	local spot = Layout.Platform.ThrowSpot
	local cx = (Layout.Field.MinX + Layout.Field.MaxX) / 2
	local laneHalf = (Layout.Field.MaxX - Layout.Field.MinX) * 0.25 - 4
	local landX = math.clamp(cx + (spot.X - cx) * 0.5 + rng:NextNumber(-1, 1) * Game.Throw.LateralScatter * 0.5,
		cx - laneHalf, cx + laneHalf)
	local launch, land = BallFlight.Endpoints(spot, spot.Y + Game.Throw.LaunchHeight, Layout.ThrowLine.Z, Layout.GroundY,
		distance, landX)
	local catch = (Rarities.Tiers :: any)[rarity].Catch
	local legendaryPlus = (table.find(Rarities.Order, rarity) or 1) >= 5
	local lucky = caught and legendaryPlus and rng:NextNumber() < 0.35
	local treat = caught and not lucky and rng:NextNumber() < 0.25
	local whistles = if caught then 0 else rng:NextInteger(0, 2)
	counter += 1
	local income = if def then DogCatalog.AdultIncome(def, variant) else 1
	return {
		ThrowId = ("TEST-%d-%d"):format(counter, rng:NextInteger(1, 1e6)),
		ThrowerUserId = s.UserId or 0,
		PadIndex = 1,
		Distance = distance,
		ZoneId = zone.Id,
		DogId = if def then def.Id else "unknown",
		DogName = if def then def.Name else "Test Dog",
		Rarity = rarity,
		Variant = variant,
		Caught = caught,
		CatchChance = catch,
		Boosts = {},
		LuckyStreakTriggered = lucky,
		TreatPocketUsed = treat,
		WhistleOwned = whistles > 0,
		WhistleCount = whistles,
		IsTutorial = false,
		BallId = s.BallId or "Tennis",
		LaunchPos = launch,
		LandPos = land,
		FlightTime = BallFlight.ForThrow(launch, land).Duration,
		Income = income,
		IncomeNow = income * 0.2,
		Status = if caught then "Added" else nil,
		IsTest = true,
	}
end

return FakeResult
