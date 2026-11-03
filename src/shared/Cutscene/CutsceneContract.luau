--!strict
-- CUTSCENE CONTRACT (docs/DESIGN.md §20). Gameplay code talks to the throw cutscene ONLY through this module:
--
--   local handle = CutsceneContract.Play(throwResult, { IsThrower = true, IsSpectator = false, BannerParent = frame? })
--   handle.Finished:Connect(fn)  -- fires once
--   handle:Await()               -- yields until finished
--   handle:Skip()                -- jumps to the end card if CanSkip()
--   handle:CanSkip() -> boolean
--
-- The cutscene ONLY DISPLAYS. The server already rolled the dog, rarity, variant and catch before the
-- ThrowResult was sent; nothing here rolls, changes state or decides an outcome.
--
-- The v1 implementation is PlaceholderCutscene (deliberately simple; the user designs the real one later).
-- A replacement must implement `Play(input: Input) -> Handle` and is installed with
-- CutsceneContract.SetImplementation(module). It must play the beats in Beats order and respect
-- Timing(), CanSkip() and the spectator rules below.
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local Timers = require(Config:WaitForChild("Timers"))
local Zones = require(Config:WaitForChild("Zones"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

export type ThrowResult = {
	ThrowId: string,
	ThrowerUserId: number,
	ThrowerName: string?,
	PadIndex: number,
	Distance: number,
	ZoneId: string,
	DogId: string,
	DogName: string?,
	Rarity: string,
	Variant: string?,
	Caught: boolean,
	CatchChance: number,
	Boosts: { string },
	LuckyStreakTriggered: boolean,
	LuckyStreak: number?,
	WhistleOwned: boolean,
	WhistleCount: number,
	IsTutorial: boolean,
	-- optional extras sent by ThrowService
	BallId: string?,
	StartPosition: Vector3?,
	LandingPosition: Vector3?,
	TreatPocketUsed: boolean?,
	Income: number?, -- adult $/s incl. variant + gamepass mult
	IncomeNow: number?,
	DogUid: string?,
	Status: string?, -- "Added" | "Held" | "PendingSale" | nil
	CutsceneSeconds: number?,
	CanSkip: boolean?,
	IsTest: boolean?, -- CutsceneTestMode fake outcome (never reported to the server)
	[string]: any,
}

export type Options = {
	IsThrower: boolean,
	IsSpectator: boolean,
	BannerParent: GuiObject?, -- spectator banner container (HUD slot); a fallback ScreenGui is used if nil
}

export type Input = { Result: ThrowResult, IsThrower: boolean, IsSpectator: boolean, BannerParent: GuiObject? }

export type Handle = {
	Finished: any, -- Signal (fires once)
	Skip: (self: Handle) -> (),
	CanSkip: (self: Handle) -> boolean,
	Await: (self: Handle) -> (),
	IsFinished: (self: Handle) -> boolean,
	_finish: (self: Handle) -> (),
	_skipRequested: boolean,
	_finished: boolean,
	_canSkip: boolean,
}

export type Beat = "Suspense" | "RevealDog" | "RevealVariant" | "Catch" | "EndCard"
export type Timing = { Total: number, Suspense: number, RevealDog: number, RevealVariant: number, Catch: number,
	EndCard: number, Flight: number }

local CutsceneContract = {}

-- Required beats, in order.
local BEATS: { Beat } = { "Suspense", "RevealDog", "RevealVariant", "Catch", "EndCard" }
CutsceneContract.Beats = BEATS

-- Share of the total length per beat, by rarity (RevealVariant share is folded into the others when the
-- dog has no variant). Totals come from Timers.Cutscene (Common 2 s ... Mythic 15 s).
CutsceneContract.Shares = {
	Common = { Suspense = 0.40, RevealDog = 0.20, RevealVariant = 0.00, Catch = 0.22, EndCard = 0.18 },
	Uncommon = { Suspense = 0.36, RevealDog = 0.20, RevealVariant = 0.10, Catch = 0.18, EndCard = 0.16 },
	Rare = { Suspense = 0.38, RevealDog = 0.18, RevealVariant = 0.10, Catch = 0.20, EndCard = 0.14 },
	Epic = { Suspense = 0.40, RevealDog = 0.18, RevealVariant = 0.10, Catch = 0.20, EndCard = 0.12 },
	Legendary = { Suspense = 0.42, RevealDog = 0.18, RevealVariant = 0.10, Catch = 0.19, EndCard = 0.11 },
	Mythic = { Suspense = 0.45, RevealDog = 0.17, RevealVariant = 0.10, Catch = 0.18, EndCard = 0.10 },
} :: { [string]: { [string]: number } }

CutsceneContract.SpectatorLengthMult = 0.5 -- spectator banner runs ~50% of the thrower's length
CutsceneContract.SpectatorLargeFrom = "Epic" -- Epic+ spectator banners are larger
CutsceneContract.NeverSkipFrom = "Epic" -- Epic, Legendary, Mythic are never skippable
CutsceneContract.MinEndCard = 0.9 -- end card is always readable

local function rarityIndex(r: string): number
	return table.find(Rarities.Order, r) or 1
end

-- Ball flight time from distance (used by the throw visual AND the suspense beat so they line up).
function CutsceneContract.FlightTime(distance: number): number
	return math.clamp(0.7 + distance / 1800, 0.7, 2.2)
end

function CutsceneContract.Timing(rarity: string, hasVariant: boolean, distance: number?): Timing
	local total = (Timers.Cutscene :: any)[rarity] or 3
	local shares = CutsceneContract.Shares[rarity] or CutsceneContract.Shares.Common
	local variantShare = if hasVariant then shares.RevealVariant else 0
	local spare = shares.RevealVariant - variantShare
	local rest = shares.Suspense + shares.RevealDog + shares.Catch + shares.EndCard
	local function share(name: string): number
		return (shares[name] + spare * shares[name] / rest) * total
	end
	local flight = CutsceneContract.FlightTime(distance or 0)
	local t: Timing = {
		Total = 0,
		Flight = flight,
		Suspense = math.max(share("Suspense"), flight + 0.25),
		RevealDog = share("RevealDog"),
		RevealVariant = variantShare * total,
		Catch = math.max(share("Catch"), 0.5),
		EndCard = math.max(share("EndCard"), CutsceneContract.MinEndCard),
	}
	t.Total = t.Suspense + t.RevealDog + t.RevealVariant + t.Catch + t.EndCard
	return t
end

-- Skippability: Commons only, and only once the server says so (4th Common onward, never the tutorial).
-- Uncommon/Rare: not skippable in v1 (TBD-5). Epic+ never. Spectator banners never block, so never "skip".
function CutsceneContract.CanSkip(result: ThrowResult, isThrower: boolean): boolean
	if not isThrower then
		return false
	end
	if rarityIndex(result.Rarity) >= rarityIndex(CutsceneContract.NeverSkipFrom) then
		return false
	end
	return result.Rarity == "Common" and result.CanSkip == true and not result.IsTutorial
end

function CutsceneContract.IsLarge(rarity: string): boolean
	return rarityIndex(rarity) >= rarityIndex(CutsceneContract.SpectatorLargeFrom)
end

local zoneIds: { [string]: boolean } = {}
for _, z in Zones do
	zoneIds[z.Id] = true
end

-- Validates (and lightly normalises) a ThrowResult. Returns (true, result) or (false, reason).
function CutsceneContract.Validate(raw: any): (boolean, any)
	if type(raw) ~= "table" then
		return false, "ThrowResult is not a table"
	end
	local function need(key: string, kind: string): string?
		if type(raw[key]) ~= kind then
			return ("ThrowResult.%s must be a %s (got %s)"):format(key, kind, type(raw[key]))
		end
		return nil
	end
	for _, pair in {
		{ "ThrowId", "string" }, { "ThrowerUserId", "number" }, { "Distance", "number" }, { "ZoneId", "string" },
		{ "DogId", "string" }, { "Rarity", "string" }, { "Caught", "boolean" }, { "CatchChance", "number" },
	} do
		local err = need(pair[1], pair[2])
		if err then
			return false, err
		end
	end
	if not (Rarities.Tiers :: any)[raw.Rarity] then
		return false, "Unknown rarity " .. tostring(raw.Rarity)
	end
	if not zoneIds[raw.ZoneId] then
		return false, "Unknown zone " .. tostring(raw.ZoneId)
	end
	if raw.Variant ~= nil and not (Rarities.Variants :: any)[raw.Variant] then
		return false, "Unknown variant " .. tostring(raw.Variant)
	end
	if raw.Variant ~= nil and raw.Rarity == "Common" then
		return false, "Commons never have variants"
	end
	local r = table.clone(raw)
	r.PadIndex = tonumber(r.PadIndex) or 1
	r.Boosts = if type(r.Boosts) == "table" then r.Boosts else {}
	r.LuckyStreakTriggered = r.LuckyStreakTriggered == true
	r.WhistleOwned = r.WhistleOwned == true
	r.WhistleCount = tonumber(r.WhistleCount) or 0
	r.IsTutorial = r.IsTutorial == true
	if r.Variant == "" then
		r.Variant = nil
	end
	return true, r
end

----------------------------------------------------------------------------------------------------
-- Handle
----------------------------------------------------------------------------------------------------
local HandleMethods = {}
HandleMethods.__index = HandleMethods

function HandleMethods.Skip(self: Handle)
	if self._canSkip and not self._finished then
		self._skipRequested = true
	end
end

function HandleMethods.CanSkip(self: Handle): boolean
	return self._canSkip and not self._finished
end

function HandleMethods.IsFinished(self: Handle): boolean
	return self._finished
end

function HandleMethods.Await(self: Handle)
	if not self._finished then
		self.Finished:Wait()
	end
end

function HandleMethods._finish(self: Handle)
	if self._finished then
		return
	end
	self._finished = true
	self.Finished:Fire()
end

function CutsceneContract.NewHandle(canSkip: boolean): Handle
	local h = setmetatable({
		Finished = Signal.new(),
		_skipRequested = false,
		_finished = false,
		_canSkip = canSkip,
	}, HandleMethods)
	return (h :: any) :: Handle
end

----------------------------------------------------------------------------------------------------
-- Implementation registry + Play
----------------------------------------------------------------------------------------------------
local implementation: any = nil

function CutsceneContract.SetImplementation(impl: any)
	assert(type(impl) == "table" and type(impl.Play) == "function", "cutscene implementation needs Play(input)")
	implementation = impl
end

function CutsceneContract.Play(result: any, opts: Options | boolean | nil): Handle
	local isThrower: boolean
	local banner: GuiObject? = nil
	if type(opts) == "boolean" then
		isThrower = opts
	elseif type(opts) == "table" then
		isThrower = opts.IsThrower == true
		banner = opts.BannerParent
	else
		isThrower = false
	end
	local ok, normalised = CutsceneContract.Validate(result)
	if not ok then
		warn("[Cutscene] invalid ThrowResult: " .. tostring(normalised))
		local h = CutsceneContract.NewHandle(false)
		task.defer(function()
			h:_finish()
		end)
		return h
	end
	if not implementation then
		implementation = require(script.Parent:WaitForChild("PlaceholderCutscene")) :: any
	end
	local input: Input = { Result = normalised, IsThrower = isThrower, IsSpectator = not isThrower, BannerParent = banner }
	return implementation.Play(input)
end

----------------------------------------------------------------------------------------------------
-- CutsceneTestMode: random fake outcomes (client-only debug; never sent to the server)
----------------------------------------------------------------------------------------------------
function CutsceneContract.MakeTestResult(catalog: any, localUserId: number, asSpectator: boolean?): ThrowResult
	local rng = Random.new()
	local zone = Zones[rng:NextInteger(1, #Zones)]
	-- pick a rarity with a bias toward the interesting ones so testers see every branch
	local rarity = Rarities.Order[rng:NextInteger(1, #Rarities.Order)]
	local list = catalog.ZoneTierList(zone.Id, rarity)
	if #list == 0 then
		rarity = "Common"
		list = catalog.ZoneTierList(zone.Id, "Common")
	end
	local def = list[rng:NextInteger(1, math.max(1, #list))]
	local variant: string? = nil
	if rarity ~= "Common" and rng:NextNumber() < 0.5 then
		variant = Rarities.VariantOrder[rng:NextInteger(1, #Rarities.VariantOrder)]
	end
	local distance = rng:NextNumber(zone.MinDistance, zone.MaxDistance)
	local caught = rng:NextNumber() < 0.6
	local income = (def and def.Income or 1) * (if variant then (Rarities.Variants :: any)[variant].IncomeMult else 1)
	return {
		ThrowId = "TEST-" .. tostring(rng:NextInteger(1, 1e9)),
		ThrowerUserId = if asSpectator then -1 else localUserId,
		ThrowerName = if asSpectator then "TestPlayer" else nil,
		PadIndex = rng:NextInteger(1, 6),
		Distance = distance,
		ZoneId = zone.Id,
		DogId = if def then def.Id else "unknown",
		DogName = if def then def.Name else "Test Dog",
		Rarity = rarity,
		Variant = variant,
		Caught = caught,
		CatchChance = (Rarities.Tiers :: any)[rarity].Catch,
		Boosts = {},
		LuckyStreakTriggered = caught and rarityIndex(rarity) >= 5 and rng:NextNumber() < 0.5,
		LuckyStreak = rng:NextInteger(0, 1),
		WhistleOwned = not caught,
		WhistleCount = if caught then 0 else 2,
		IsTutorial = false,
		TreatPocketUsed = caught and rng:NextNumber() < 0.2,
		Income = income,
		IncomeNow = income * Timers.PuppyIncomeFraction,
		Status = if caught then "Added" else nil,
		CanSkip = rarity == "Common",
		IsTest = true,
	}
end

return CutsceneContract
