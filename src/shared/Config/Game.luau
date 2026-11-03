--!strict
-- Global game config. Owned by C1 (server); the Balance pass may tune numbers but not rename keys.
local Game = {}

Game.Name = "Fetch Legends" -- working title; original IP
-- Public servers hold 6 players: one yard + one throw pad each. Set Max Players = 6 in
-- Game Settings > Places; the server assumes <= Layout.Yards.Count players.
Game.MaxPlayers = 6

-- Debug: adds a client button that plays random cutscene outcomes (client/Cutscene reads this).
Game.CutsceneTestMode = false
-- Studio: skip DataStores (in-memory mock) even if API access is on. Mock is also used automatically
-- when DataStores are unavailable in Studio.
Game.UseMockData = false

Game.StartingCash = 50
Game.StartingThrowPower = 60

Game.Tutorial = {
	Enabled = true,
	ForceZone = "Backyard", -- tutorial throw always lands here
	GuaranteedCommon = true, -- tier forced to Common
	GuaranteedCatch = true,
	MeterSpeedMult = 0.5, -- meter sweeps at half speed for the tutorial throw (client + server)
	FirstDogInstantAdult = false, -- design: the tutorial dog is a normal puppy
}

-- Throw meter (deterministic triangle wave). See docs/DESIGN.md §4 and Util/Meter.luau.
Game.Meter = {
	Period = 1.6,
	PerfectMin = 0.92, -- pos >= this: quality 1.0
	GoodMin = 0.75, -- pos in [GoodMin, PerfectMin): lerp GoodQualityMin -> GoodQualityMax
	GoodQualityMin = 0.80,
	GoodQualityMax = 0.97,
	OkQualityMin = 0.35, -- pos < GoodMin: OkQualityMin + OkQualitySpan * (pos / GoodMin)
	OkQualitySpan = 0.45,
	FlubQuality = 0.35, -- release before MinChargeSeconds
}

Game.Throw = {
	MinChargeSeconds = 0.25,
	MaxChargeSeconds = 6, -- server auto-releases after this
	MinSecondsBetweenThrows = 2, -- hard floor measured release -> next ChargeBegin
	Scatter = 0.02, -- distance * (1 + U(-Scatter, Scatter))
	MinDistance = 5,
	RequireOnPad = true,
	PadRadius = 18, -- studs (XZ) from the pad centre
	LateralScatter = 40, -- landing X = pad X + U(-n, n), clamped into the field
}

-- Luck: every non-Common tier's odds are multiplied by (1 + Luck); Common absorbs the difference.
Game.Luck = {
	MinCommonOdds = 0.40, -- luck is effectively capped so Common never falls below this
}

Game.Catch = {
	MaxChance = 0.99, -- natural catch chance cap (streak / tutorial can still force 1.0)
}

-- Broadcast thresholds (Rarities.Order names).
Game.Broadcast = {
	CatchServerMin = "Rare",
	CatchGlobalMin = "Legendary",
	MissServerMin = "Epic",
	MissGlobalMin = "Legendary",
	Topic = "FetchLegends_Broadcast",
	MinPublishInterval = 2, -- seconds between cross-server publishes per server
	QueueDropAfter = 30, -- queued global messages older than this are dropped
}

-- Remote rate limits: {rate per second, burst}
Game.RateLimits = {
	Charge = { 2, 3 },
	Train = { 3, 4 },
	Shop = { 5, 5 },
	DogAction = { 5, 8 },
	Whistle = { 5, 5 },
	Claim = { 5, 5 },
	EquipBall = { 2, 3 },
	RequestState = { 0.2, 2 },
	CutsceneFinished = { 2, 4 },
}

Game.AfkSeconds = 15 * 60 -- training stops crediting after this long without movement

return Game
