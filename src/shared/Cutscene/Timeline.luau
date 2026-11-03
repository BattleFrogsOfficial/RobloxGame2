--!strict
-- Pure cutscene timing + rules (no services; Lune-tested by tools/tests/cutscene.luau). docs/DESIGN.md §20.
--   Timeline.FlightSeconds(result.FlightTime) -> on-screen flight length (remapped into Flight.Min..Max)
--   Timeline.Build(rarity, flightSeconds, { Short = bool? }) -> { Beats, Total, Release, Touchdown, ByName }
--   Timeline.CanSkip(rarity, beatName) -> boolean         (Skip button rule)
--   Timeline.IsShort(rarity, hideCommonReveals) -> boolean  (Settings.HideCommonReveals)
--   Timeline.FallbackAfter(flightSeconds) -> seconds after the meter release at which a missing ThrowResult
--     gives up (release frame + estimated flight + Fallback.HoldMax)
--   Timeline.SafetySeconds() -> the longest the HUD may stay locked waiting for a ThrowResult
--   Timeline.Validate(raw) -> (true, normalised) | (false, reason)
-- Every number comes from Config/Cutscene.luau.
local Config = script.Parent.Parent:WaitForChild("Config")
local C = require(Config:WaitForChild("Cutscene"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))

local Timeline = {}

-- Beat names in play order. "EndCard" starts at Total (the Reveal card; it waits for the player).
Timeline.Order = { "WindUp", "Flight", "Settle", "DogArrive", "Counter", "CounterHold", "Outcome", "EndCard" }

export type Beat = { Name: string, Start: number, Length: number }
export type Plan = {
	Rarity: string,
	Short: boolean,
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

-- result.FlightTime (server seconds, BallFlight.DefaultFlightTime: 0.7..2.2) -> on-screen seconds (Min..Max),
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

function Timeline.Build(rarity: string, flightSeconds: number, opts: { Short: boolean? }?): Plan
	local short = opts ~= nil and opts.Short == true
	local flight = math.clamp(flightSeconds, C.Flight.Min, C.Flight.Max)
	local lengths: { [string]: number } = {
		WindUp = C.WindUp.ReleaseAt,
		Flight = flight,
		Settle = if short then C.ShortCommon.AfterTouchdown else perRarity(C.Beats.Settle, rarity),
		DogArrive = if short then 0 else perRarity(C.Beats.DogArrive, rarity),
		Counter = if short then 0 else perRarity(C.Beats.Counter, rarity),
		CounterHold = if short then 0 else perRarity(C.Beats.CounterHold, rarity),
		Outcome = if short then 0 else perRarity(C.Beats.Outcome, rarity),
		EndCard = 0,
	}
	local beats: { Beat } = {}
	local byName: { [string]: Beat } = {}
	local t = 0
	for _, name in Timeline.Order do
		local b = { Name = name, Start = t, Length = lengths[name] }
		table.insert(beats, b)
		byName[name] = b
		t += lengths[name]
	end
	return {
		Rarity = rarity,
		Short = short,
		Beats = beats,
		ByName = byName,
		Release = lengths.WindUp,
		Touchdown = lengths.WindUp + flight,
		Total = byName.EndCard.Start,
		Flight = flight,
	}
end

function Timeline.BudgetTotal(rarity: string): number
	return Timeline.Build(rarity, C.Budget.ReferenceFlight).Total
end

local function beatIndex(name: string): number
	return table.find(Timeline.Order, name) or math.huge
end

-- Skip is offered from Skip.FromBeat on, never for Skip.Never rarities. Skipping jumps to the end card.
function Timeline.CanSkip(rarity: string, beatName: string): boolean
	if (C.Skip.Never :: any)[rarity] then
		return false
	end
	return beatIndex(beatName) >= beatIndex(C.Skip.FromBeat) and beatName ~= "EndCard"
end

function Timeline.IsShort(rarity: string, hideCommonReveals: boolean?): boolean
	return rarity == "Common" and hideCommonReveals == true
end

function Timeline.FallbackAfter(flightSeconds: number): number
	return C.WindUp.ReleaseAt + math.clamp(flightSeconds, C.Flight.Min, C.Flight.Max) + C.Fallback.HoldMax
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
