--!strict
-- Global game config. Owned by C1 (server); the Balance pass may tune numbers but not rename keys.
local Game = {}

Game.Name = "Throw a Ball for Dogs"
-- Public servers hold 6 players: one yard each, one shared throwing platform with a queue. Set Max
-- Players = 6 in Game Settings > Places; the server assumes <= Layout.Yards.Count players.
Game.MaxPlayers = 6

-- Debug: adds a client button that plays random cutscene outcomes (client/Cutscene reads this).
Game.CutsceneTestMode = false
-- Studio: skip DataStores (in-memory mock) even if API access is on. Mock is also used automatically
-- when DataStores are unavailable in Studio.
Game.UseMockData = false

-- Character movement, applied on every spawn (server CharacterService; Humanoid.UseJumpPower = true).
Game.WalkSpeed = 32
Game.JumpPower = 60

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
	MinSecondsBetweenThrows = 2, -- hard floor measured release -> next ChargeBegin; also the gap after a turn ends
	Scatter = 0.02, -- distance * (1 + U(-Scatter, Scatter))
	MinDistance = 5,
	-- The ball leaves at the deck surface (Layout.ThrowLine.Y = Layout.HubY = 40) + this = 44, above the railing caps
	-- (43.35), and lands on the field at Layout.GroundY: Util/BallFlight adds that 44-stud drop to the flight time.
	LaunchHeight = 4,
	LateralScatter = 40, -- landing X = 0.5 x platform X + 0.5 x U(-n, n), clamped to the middle half of the field (|x| <= 56)
}

-- The one shared throwing platform (Layout.Platform) and its FIFO queue (ThrowService).
-- On the platform = root inside the deck rectangle (Layout.Platform Center/Size) grown by EdgeMargin, and
-- Y >= Layout.ThrowLine.Y - YTolerance. The deck is flush with the plaza, so the rectangle (not a radius) decides.
Game.Platform = {
	SampleInterval = 0.25, -- presence sampling (~4x per second)
	YTolerance = 4,
	EdgeMargin = 1.5,
	TurnStartSeconds = 15, -- the player at position 1 must ChargeBegin within this or goes to the back
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
	Topic = "ThrowABallForDogs_Broadcast",
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

-- Fall rescue (CharacterService): a character whose root drops this far below Layout.HubY (e.g. glitched over the
-- cliff edge onto the field) is put back on a PlazaSpawn.
Game.FallRescueDepth = 12

Game.AfkSeconds = 15 * 60 -- training stops crediting after this long without movement

return Game
