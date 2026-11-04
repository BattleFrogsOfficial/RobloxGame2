--!strict
-- Pure cutscene timing + rules (no services; Lune-tested by tools/tests/cutscene.luau). docs/DESIGN.md §20.
--   Timeline.FlightSeconds(result.FlightTime) -> on-screen flight length (remapped into Flight.Min..Max)
--   Timeline.Build(rarity, flightSeconds, { Short = bool?, Caught = bool? }) -> { Beats, Total, Release, Touchdown, ByName }
--     Caught (default true): ... DogArrive, Grab, Victory, Counter, CounterHold, HopAway, EndCard
--     Caught = false:        ... DogArrive, Counter, CounterHold, Sniff, Bolt, EndCard
--   Timeline.CanSkip(rarity, beatName) -> boolean         (Skip button rule)
--   Timeline.IsShort(rarity, hideCommonReveals) -> boolean  (Settings.HideCommonReveals)
--   Timeline.FallbackAfter(flightSeconds) -> seconds after the meter release at which a missing ThrowResult
--     gives up (release frame + estimated flight + Fallback.HoldMax)
--   Timeline.EarliestEnd(rarity, flightSeconds, caught?) -> soonest a real client can finish (skip / short Common);
--     the server's CutsceneFinished floor (caught = nil: the sooner of both outcomes)
--   Timeline.LeaveDone(elapsed, distance) -> remove the leaving dog now? (time + distance rule)
--   Timeline.SafetySeconds() -> the longest the HUD may stay locked waiting for a ThrowResult
--   Timeline.Validate(raw) -> (true, normalised) | (false, reason)
-- Every number comes from Config/Cutscene.luau.
local Config = script.Parent.Parent:WaitForChild("Config")
local C = require(Config:WaitForChild("Cutscene"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))

local Timeline = {}

-- Beat names in play order, per outcome. "EndCard" starts at Total (the Reveal card; it waits for the player).
-- CAUGHT: the dog grabs the ball and celebrates BEFORE the counter (nothing leaves before the player has seen the
-- dog be happy). MISSED: the counter (the rarity) comes BEFORE the sniff + bolt (docs/DESIGN.md §8).
Timeline.OrderCaught = { "WindUp", "Flight", "Settle", "DogArrive", "Grab", "Victory", "Counter", "CounterHold", "HopAway", "EndCard" }
Timeline.OrderMissed = { "WindUp", "Flight", "Settle", "DogArrive", "Counter", "CounterHold", "Sniff", "Bolt", "EndCard" }
Timeline.Order = Timeline.OrderCaught

export type Beat = { Name: string, Start: number, Length: number }
export type Plan = {
	Rarity: string,
	Short: boolean,
	Caught: boolean,
	Beats: { Beat },
	ByName: { [string]: Beat },
	Release: number, -- seconds after the meter release when the ball leaves the hand
	Touchdown: number, -- seconds after the meter release when the ball touches LandPos
	Total: number, -- seconds after the meter release when the end card appears
	Flight: number,
}

local function perRarity(row: { [string]: number }, rarity: string): number
	return row[rarity] or row.Common or 0
end

-- result.FlightTime (server seconds, Util/BallFlight.ForThrow incl. the plateau drop: ~1.0..2.3) -> on-screen (Min..Max),
-- linear in between, so longer throws fly longer. Missing / bad input -> Flight.Min.
function Timeline.FlightSeconds(serverFlight: number?): number
	local f = C.Flight
	local s = tonumber(serverFlight)
	if s == nil or s ~= s then
		return f.Min
	end
	local span = math.max(1e-6, f.ServerMax - f.ServerMin)
	local k = math.clamp((s - f.ServerMin) / span, 0, 1)
	return f.Min + (f.Max - f.Min) * k
end

function Timeline.Build(rarity: string, flightSeconds: number, opts: { Short: boolean?, Caught: boolean? }?): Plan
	local short = opts ~= nil and opts.Short == true
	local caught = not (opts ~= nil and opts.Caught == false)
	local order = if caught then Timeline.OrderCaught else Timeline.OrderMissed
	local B = C.Beats :: any
	local function beat(name: string): number
		return if short then 0 else perRarity(B[name], rarity)
	end
	local flight = math.clamp(flightSeconds, C.Flight.Min, C.Flight.Max)
	local lengths: { [string]: number } = {
		WindUp = C.WindUp.ReleaseAt,
		Flight = flight,
		Settle = if short then C.ShortCommon.AfterTouchdown else perRarity(C.Beats.Settle, rarity),
		DogArrive = beat("DogArrive"),
		Grab = beat("Grab"),
		Victory = beat("Victory"),
		Counter = beat("Counter"),
		CounterHold = beat("CounterHold"),
		HopAway = beat("HopAway"),
		Sniff = beat("Sniff"),
		Bolt = beat("Bolt"),
		EndCard = 0,
	}
	local beats: { Beat } = {}
	local byName: { [string]: Beat } = {}
	local t = 0
	for _, name in order do
		local b = { Name = name, Start = t, Length = lengths[name] }
		table.insert(beats, b)
		byName[name] = b
		t += lengths[name]
	end
	return {
		Rarity = rarity,
		Short = short,
		Caught = caught,
		Beats = beats,
		ByName = byName,
		Release = lengths.WindUp,
		Touchdown = lengths.WindUp + flight,
		Total = byName.EndCard.Start,
		Flight = flight,
	}
end

function Timeline.BudgetTotal(rarity: string, caught: boolean?): number
	return Timeline.Build(rarity, C.Budget.ReferenceFlight, { Caught = caught ~= false }).Total
end

-- Skip is offered from Skip.FromBeat on (in the beat's own outcome order), never for Skip.Never rarities and
-- never before the catch celebration is over (Grab / Victory come before the counter). Skipping jumps to the end
-- card. Unknown phases (e.g. "Hold") are never skippable.
function Timeline.CanSkip(rarity: string, beatName: string): boolean
	if (C.Skip.Never :: any)[rarity] or beatName == "EndCard" then
		return false
	end
	for _, order in { Timeline.OrderCaught, Timeline.OrderMissed } do
		local i = table.find(order, beatName)
		local from = table.find(order, C.Skip.FromBeat)
		if i and from then
			return i >= from
		end
	end
	return false
end

function Timeline.IsShort(rarity: string, hideCommonReveals: boolean?): boolean
	return rarity == "Common" and hideCommonReveals == true
end

function Timeline.FallbackAfter(flightSeconds: number): number
	return C.WindUp.ReleaseAt + math.clamp(flightSeconds, C.Flight.Min, C.Flight.Max) + C.Fallback.HoldMax
end

-- The soonest a real client can end this throw's cutscene (seconds after the meter release): skipping at
-- Skip.FromBeat (never for Skip.Never rarities) or a short Common (Settings.HideCommonReveals), then closing the
-- end card at once. ThrowService ignores an earlier CutsceneFinished (it finishes the throw at this point).
function Timeline.EarliestEnd(rarity: string, flightSeconds: number, caught: boolean?): number
	if caught == nil then
		return math.min(Timeline.EarliestEnd(rarity, flightSeconds, true), Timeline.EarliestEnd(rarity, flightSeconds, false))
	end
	local full = Timeline.Build(rarity, flightSeconds, { Caught = caught })
	local t = full.Total
	if rarity == "Common" then
		t = math.min(t, Timeline.Build(rarity, flightSeconds, { Short = true }).Total)
	end
	if not (C.Skip.Never :: any)[rarity] then
		local from = full.ByName[C.Skip.FromBeat]
		if from then
			t = math.min(t, from.Start)
		end
	end
	return t
end

-- The leaving dog (hop away / bolt) is removed by time + distance, never by a frustum check: never before
-- Outcome.HopAwayMinSeconds after it started leaving, then once it is RemoveDistance away, or at HopAwayMaxSeconds.
function Timeline.LeaveDone(elapsed: number, distance: number): boolean
	local o = C.Outcome
	if elapsed < o.HopAwayMinSeconds then
		return false
	end
	return distance >= o.RemoveDistance or elapsed >= o.HopAwayMaxSeconds
end

function Timeline.SafetySeconds(): number
	return C.WindUp.ReleaseAt + C.Flight.Max + C.Fallback.HoldMax + C.Fallback.ShowFor + 2
end

local zoneIds: { [string]: boolean } = {}
for _, z in Zones do
	zoneIds[z.Id] = true
end

-- Checks and lightly normalises a ThrowResult (server or CutsceneTestMode fake). Never changes an outcome.
function Timeline.Validate(raw: any): (boolean, any)
	if type(raw) ~= "table" then
		return false, "ThrowResult is not a table"
	end
	for _, pair in {
		{ "ThrowId", "string" }, { "ThrowerUserId", "number" }, { "Distance", "number" }, { "ZoneId", "string" },
		{ "DogId", "string" }, { "Rarity", "string" }, { "Caught", "boolean" },
	} do
		if type(raw[pair[1]]) ~= pair[2] then
			return false, ("ThrowResult.%s must be a %s (got %s)"):format(pair[1], pair[2], type(raw[pair[1]]))
		end
	end
	if not (Rarities.Tiers :: any)[raw.Rarity] then
		return false, "unknown rarity " .. tostring(raw.Rarity)
	end
	if not zoneIds[raw.ZoneId] then
		return false, "unknown zone " .. tostring(raw.ZoneId)
	end
	local r = table.clone(raw)
	if r.Variant == "" or (r.Variant ~= nil and not (Rarities.Variants :: any)[r.Variant]) then
		r.Variant = nil
	end
	r.LuckyStreakTriggered = r.LuckyStreakTriggered == true
	r.TreatPocketUsed = r.TreatPocketUsed == true
	r.WhistleOwned = r.WhistleOwned == true
	r.WhistleCount = tonumber(r.WhistleCount) or 0
	r.IsTest = r.IsTest == true
	return true, r
end

return Timeline
