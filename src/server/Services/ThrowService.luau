--!nonstrict
-- The throw: ChargeBegin/ChargeRelease timing (server clock only; ONE TAP: the meter sweeps from ChargeBegin, which
-- the client fires the moment the bar appears and again to restart the sweep, and ChargeRelease is the tap), one
-- throw in flight per player, cooldowns + rate limits, the brown THROW ZONE (no turns: everyone in it can throw at
-- once), distance/landing/zone, consumable balls, the full roll (RollService), the outcome committed to the player's
-- data, then ThrowResult to EVERY client immediately (before any visual, toast, StateUpdate or display refresh),
-- cutscene completion (CutsceneFinished or timeout), broadcasts, runaway spawn on a miss and the Golden Whistle
-- recall (UseWhistle).
--
-- Throw zone (Layout.ThrowZone, rules in Util/ThrowZone): a player is "in the zone" while their HumanoidRootPart XZ is
-- inside the rectangle grown by Game.ThrowZone.EdgeMargin and Y >= Layout.ThrowZone.Y - Game.ThrowZone.YTolerance.
-- Sampled every Game.ThrowZone.SampleInterval into the player attributes "InThrowZone" (boolean), plus for one
-- release the deprecated "OnPlatform" (same value) and "ThrowQueuePos" (1 in the zone, 0 otherwise).
-- Charge rules (checked live, not from the sampled attribute):
--   ChargeBegin: refused outside the zone, while a throw of yours is in flight, or within MinSecondsBetweenThrows of
--     your last release; while already charging it RESTARTS the sweep (new timestamp) unless the current charge is
--     younger than Game.Throw.MinRestartSeconds.
--   ChargeRelease: throws at elapsed = now - (last) start; outside the zone it cancels the charge (no throw).
--   No release within Game.Throw.MaxChargeSeconds of the (re)start: the charge is cancelled silently (no auto-throw).
--   Leaving the zone also drops an unreleased charge.
--
-- Flight: the ball leaves the cliff edge in front of the thrower, LaunchPos = (root X clamped into the zone,
-- Layout.ThrowZone.Y + Game.Throw.LaunchHeight = 44, Layout.ThrowLine.Z), and lands on the field at LandPos
-- (Y = Layout.GroundY, Z = ThrowLine.Z + Distance). Util/BallFlight.ForThrow adds that drop to the flight: same
-- horizontal distance, longer flight. ThrowResult.FlightTime = ForThrow(LaunchPos, LandPos).Duration, the arc every
-- client renders.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Layout = require(Config:WaitForChild("Layout"))
local Game = require(Config:WaitForChild("Game"))
local Balls = require(Config:WaitForChild("Balls"))
local Shop = require(Config:WaitForChild("Shop"))
local Timers = require(Config:WaitForChild("Timers"))
local Zones = require(Config:WaitForChild("Zones"))
local Meter = require(Util:WaitForChild("Meter"))
local Odds = require(Util:WaitForChild("Odds"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))
local BallFlight = require(Util:WaitForChild("BallFlight"))
local ThrowZone = require(Util:WaitForChild("ThrowZone"))
local Timeline = require(Shared:WaitForChild("Cutscene"):WaitForChild("Timeline")) -- pure cutscene timing

local Services = script.Parent
local DataService = require(Services:WaitForChild("DataService"))
local DogService = require(Services:WaitForChild("DogService"))
local RollService = require(Services:WaitForChild("RollService"))
local BookService = require(Services:WaitForChild("BookService"))
local EventService = require(Services:WaitForChild("EventService"))
local BroadcastService = require(Services:WaitForChild("BroadcastService"))

local ThrowService = {}

type Charge = { Start: number, Token: number, Tutorial: boolean }
type ThrowRec = {
	Id: string,
	Player: Player,
	Result: any,
	StartedAt: number,
	FinishAt: number,
	EarliestFinish: number,
	Finished: boolean,
	Caught: boolean,
	Recalled: boolean,
	WhistleExpires: number,
	Status: string?,
}

local rng = RollService.NewRng()
local charges: { [Player]: Charge } = {}
local inFlight: { [Player]: ThrowRec } = {}
local lastRelease: { [Player]: number } = {}
local throws: { [string]: ThrowRec } = {}
local tokenCounter = 0

local inZone: { [Player]: boolean } = {}

function ThrowService.IsInThrowZone(player: Player): boolean
	return inZone[player] == true
end

local function zoneById(id: string): any
	for _, z in Zones do
		if z.Id == id then
			return z
		end
	end
	return Zones[1]
end

----------------------------------------------------------------------------------------------------
-- Throw zone geometry: Layout.ThrowZone (Util/ThrowZone)
----------------------------------------------------------------------------------------------------
-- Compatibility: the zone centre (= Layout.Platform.ThrowSpot).
function ThrowService.ThrowSpot(): Vector3
	return Layout.Platform.ThrowSpot
end

-- The ball leaves the thrower's hand: plateau surface + Game.Throw.LaunchHeight (= 44, above the 43.35 railing caps).
function ThrowService.LaunchY(): number
	return Layout.ThrowZone.Y + Game.Throw.LaunchHeight
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") or (hum and hum.Health <= 0) then
		return nil
	end
	return hrp
end

-- Live check (the attribute is the same rule, sampled ~4x per second).
local function isInZone(player: Player): boolean
	local hrp = rootOf(player)
	return hrp ~= nil and ThrowZone.Contains(hrp.Position)
end

function ThrowService.IsInFlight(player: Player): boolean
	return inFlight[player] ~= nil
end

----------------------------------------------------------------------------------------------------
-- Finish (cutscene over): display, broadcasts, runaway
----------------------------------------------------------------------------------------------------
local function finish(rec: ThrowRec)
	if rec.Finished then
		return
	end
	rec.Finished = true
	local player = rec.Player
	if inFlight[player] == rec then
		inFlight[player] = nil
	end
	local r = rec.Result
	local name = player.DisplayName
	local rarityUpper = string.upper(r.Rarity)
	local article = if string.match(rarityUpper, "^[AEIOU]") then "an" else "a"
	if player.Parent then
		DogService.RefreshDisplay(player)
	end
	if rec.Caught or rec.Recalled then
		if rec.Caught and Odds.AtLeast(r.Rarity, Game.Broadcast.CatchServerMin) then
			BroadcastService.Send("Catch", ("%s caught %s %s %s!"):format(name, article, rarityUpper, r.DogName),
				r.Rarity, r.Variant, Odds.AtLeast(r.Rarity, Game.Broadcast.CatchGlobalMin))
		end
		if player.Parent and rec.Status == "Held" then
			BroadcastService.Notify(player, "Yard full: sell a dog or buy a slot. Your new dog waits in the kennel.",
				"YardFull")
		elseif player.Parent and rec.Status == "PendingSale" then
			BroadcastService.Notify(player, ("Duplicate! It auto-sells in %ds unless you press Keep."):format(
				Timers.DupeKeepWindow), "Dupe")
		end
	else
		if Odds.AtLeast(r.Rarity, Game.Broadcast.MissServerMin) then
			local a2 = if string.match(rarityUpper, "^[AEIOU]") then "An" else "A"
			BroadcastService.Send("Miss", ("%s %s %s ran off from %s!"):format(a2, rarityUpper, r.DogName, name),
				r.Rarity, r.Variant, Odds.AtLeast(r.Rarity, Game.Broadcast.MissGlobalMin))
		end
		if player.Parent then
			rec.WhistleExpires = os.clock() + Timers.WhistleWindow
			EventService.SpawnRunaway(rec.Id, player, r.DogId, r.Variant, Timers.RunawaySeconds)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Resolve a release
----------------------------------------------------------------------------------------------------
local function resolveThrow(player: Player, elapsed: number, tutorial: boolean, rootPos: Vector3)
	local state = DataService.Get(player)
	if not state then
		return
	end
	local ball = PlayerStats.Ball(state)
	local meterPos, quality, band = Meter.Evaluate(elapsed, tutorial)
	local distance = PlayerStats.ThrowDistance(state.ThrowPower, ball.RangeMult, quality,
		rng:Range(-Game.Throw.Scatter, Game.Throw.Scatter), Game.Throw.MinDistance)
	local zone
	if tutorial then
		zone = zoneById(Game.Tutorial.ForceZone)
		distance = math.clamp(distance, zone.MinDistance + Game.Throw.MinDistance, zone.MaxDistance - 1)
	else
		zone = PlayerStats.ZoneForDistance(distance)
	end

	local ctx = DataService.Ctx(player)
	local luck = PlayerStats.Luck(state, ctx)
	local catchBonus = PlayerStats.CatchBonus(state, ctx)
	local boosts = PlayerStats.ActiveBoosts(state, ctx)
	local premium = not tutorial and (state.PremiumThrows or 0) > 0
	if premium then
		state.PremiumThrows -= 1
		local asBall = Balls.ById[Shop.PremiumThrow.LuckAsBall]
		luck += math.max(0, asBall.Luck - ball.Luck)
		if not table.find(boosts, "StickyBall") then
			catchBonus += Shop.PremiumThrow.CatchBonus
		end
		table.insert(boosts, "PremiumThrow")
	end

	local outcome = RollService.Resolve(rng, {
		ZoneId = zone.Id,
		Luck = luck,
		CatchBonus = catchBonus,
		LuckyStreak = state.LuckyStreak,
		IsTutorial = tutorial,
		TreatPockets = state.TreatPockets,
		TreatPocketMode = state.Settings.TreatPocketMode,
	})
	if outcome.TreatPocketUsed then
		state.TreatPockets -= 1
		table.insert(boosts, "TreatPocket")
	end
	if outcome.LuckyStreakTriggered then
		table.insert(boosts, "LuckyStreak")
	end
	state.LuckyStreak = outcome.NewLuckyStreak
	-- The throw is accepted: a consumable ball is used up (back to the Tennis Ball at 0).
	local ballsLeft: number? = nil
	if ball.Consumable then
		local left = math.max(0, PlayerStats.BallCount(state, ball.Id) - 1)
		state.Balls[ball.Id] = if left > 0 then left else nil
		ballsLeft = left
		if left <= 0 then
			state.EquippedBall = Balls.Default
		end
	end
	state.Stats.Throws += 1
	state.Stats.BestDistance = math.max(state.Stats.BestDistance or 0, distance)
	if tutorial then
		state.TutorialThrowDone = true
	end

	local def = DogCatalog.Get(outcome.DogId)
	-- Server timeout for the client cutscene (Config/Timers, computed from Config/Cutscene.luau).
	local cutLen = (Timers.Cutscene :: any)[outcome.Rarity] or Timers.Cutscene.Mythic
	local canSkip = outcome.Rarity == "Common" and not tutorial
		and (state.CommonCutscenesSeen or 0) >= Timers.CommonSkippableAfter
	if outcome.Rarity == "Common" then
		state.CommonCutscenesSeen = (state.CommonCutscenesSeen or 0) + 1
	end

	-- Commit the outcome to data before anything is shown.
	local record, status = nil, nil
	if outcome.Caught then
		state.Stats.Caught += 1
		-- Quiet: no StateUpdate / signal yet (they follow the ThrowResult below); Defer: no display refresh
		record, status = DogService.AddDog(player, outcome.DogId, outcome.Variant, {
			Defer = true,
			Quiet = true,
			SaleDelay = cutLen + Timers.CutscenePadding + Timers.DupeKeepWindow,
		})
	else
		state.Stats.Missed += 1
	end

	-- Launch: the cliff edge right in front of the thrower (root X clamped into the zone, Y 44, Z = ThrowLine.Z).
	local launchX = ThrowZone.LaunchX(rootPos.X)
	-- Landing X: half the thrower's offset from the field centre plus a little scatter, clamped to the middle half
	-- of the field (|x - centre| <= FieldWidth/4 - 4 = 56) so the landing wide shot and the dog's hop-in stay well
	-- inside the zone boundaries. The field is filled edge to edge, but every prop / ground-cover part there is
	-- non-colliding and non-queryable (World/Zones/Kit.luau), so nothing can catch the ball. Cutscene/Path.Estimate
	-- mirrors this rule (Config/Cutscene Fallback.EstimateLaneX).
	local landX = ThrowZone.LandX(launchX, rng:Range(-1, 1))
	-- Plateau -> field: same horizontal distance; the arc starts at hand height over the cliff edge and drops to the
	-- field (GroundY); BallFlight adds the drop to the flight time.
	local launchPos, landPos = BallFlight.Endpoints(Vector3.new(launchX, Layout.ThrowZone.Y, Layout.ThrowLine.Z),
		ThrowService.LaunchY(), Layout.ThrowLine.Z, Layout.GroundY, distance, landX)
	local flightTime = BallFlight.ForThrow(launchPos, landPos).Duration
	local adult = DogCatalog.AdultIncome(def, outcome.Variant) * PlayerStats.IncomeMult(ctx)
	local throwId = HttpService:GenerateGUID(false)
	local now = os.clock()

	local result = {
		ThrowId = throwId,
		ThrowerUserId = player.UserId,
		ThrowerName = player.DisplayName,
		PadIndex = 1, -- one shared throw zone (the "ThrowZone" / "ThrowPad"-tagged floor)
		Distance = distance,
		ZoneId = zone.Id,
		DogId = outcome.DogId,
		DogName = def.Name,
		Rarity = outcome.Rarity,
		Variant = outcome.Variant,
		Caught = outcome.Caught,
		CatchChance = outcome.CatchChance,
		Boosts = boosts,
		LuckyStreakTriggered = outcome.LuckyStreakTriggered,
		LuckyStreak = state.LuckyStreak,
		WhistleOwned = (state.Whistles or 0) > 0,
		WhistleCount = state.Whistles or 0,
		IsTutorial = tutorial,
		-- extras (not in the original contract)
		Quality = quality,
		MeterPos = meterPos,
		Band = band,
		BallId = ball.Id,
		BallsLeft = ballsLeft, -- remaining throws of a consumable ball (nil for Tennis)
		LaunchPos = launchPos, -- (thrower X clamped into the zone, ThrowZone.Y + Game.Throw.LaunchHeight = 44, ThrowLine.Z)
		LandPos = landPos, -- on the field: Y = Layout.GroundY (0), Z = ThrowLine.Z + Distance
		FlightTime = flightTime, -- BallFlight.ForThrow(LaunchPos, LandPos).Duration (incl. the 44-stud drop)
		StartPosition = launchPos, -- legacy names (cutscene contract)
		LandingPosition = landPos,
		TreatPocketUsed = outcome.TreatPocketUsed,
		PremiumThrow = premium,
		Income = adult, -- adult $/s incl. variant + gamepass mult (end card)
		IncomeNow = if record and status == "Added" then adult * Timers.PuppyIncomeFraction else 0,
		DogUid = if record then record.Uid else nil,
		Status = status, -- "Added" | "Held" | "PendingSale" | nil (missed)
		CutsceneSeconds = cutLen,
		CanSkip = canSkip,
		ServerTime = workspace:GetServerTimeNow(),
	}

	local rec: ThrowRec = {
		Id = throwId,
		Player = player,
		Result = result,
		StartedAt = now,
		FinishAt = now + flightTime + cutLen + Timers.CutscenePadding,
		-- A CutsceneFinished before this is held to it: the soonest a real client can get there (skip / short
		-- Common, 10% slack for frame timing). Blocks instant-finish spam without delaying an honest skip.
		EarliestFinish = now + 0.9 * Timeline.EarliestEnd(outcome.Rarity, Timeline.FlightSeconds(flightTime)),
		Finished = false,
		Caught = outcome.Caught,
		Recalled = false,
		WhistleExpires = now + flightTime + cutLen + Timers.CutscenePadding + Timers.WhistleWindow,
		Status = status,
	}
	inFlight[player] = rec
	throws[throwId] = rec

	-- First thing anyone sees of this throw: the result, to every client.
	Remotes.Get("ThrowResult"):FireAllClients(result)
	-- Then everything else visible: book entry (pushes state), the added-dog signal, toasts, the state snapshot.
	if outcome.Caught then
		BookService.Record(player, outcome.DogId, outcome.Variant)
		if record then
			DogService.DogAdded:Fire(player, record, status)
		end
	end
	if ball.Consumable and ballsLeft == 0 then
		BroadcastService.Notify(player, ("That was your last %s: back to the Tennis Ball."):format(ball.Name), "Ball")
	end
	DataService.Push(player)
	if Odds.IsLegendaryPlus(outcome.Rarity) then
		task.spawn(DataService.SaveNow, player)
	end
end

local function release(player: Player)
	local charge = charges[player]
	if not charge then
		return
	end
	local hrp = rootOf(player)
	local action = ThrowZone.Release({ InZone = hrp ~= nil and ThrowZone.Contains(hrp.Position),
		ChargeStart = charge.Start, Now = os.clock() })
	charges[player] = nil
	if action ~= "throw" or not hrp then
		return -- tapped outside the zone: the charge is dropped, nothing is thrown
	end
	local elapsed = os.clock() - charge.Start
	lastRelease[player] = os.clock()
	local ok, err = pcall(resolveThrow, player, elapsed, charge.Tutorial, hrp.Position)
	if not ok then
		warn("[ThrowService] resolve error: " .. tostring(err))
	end
end

local function beginCharge(player: Player)
	local state = DataService.Get(player)
	local current = charges[player]
	local action = ThrowZone.Begin({
		Loaded = state ~= nil,
		InZone = isInZone(player),
		InFlight = inFlight[player] ~= nil,
		ChargeStart = if current then current.Start else nil,
		LastRelease = lastRelease[player],
		Now = os.clock(),
	})
	if not action or not state then
		return
	end
	tokenCounter += 1
	local token = tokenCounter
	charges[player] = {
		Start = os.clock(), -- a restart resets the sweep to 0 (the client restarts its meter on the same boundary)
		Token = token,
		Tutorial = Game.Tutorial.Enabled and not state.TutorialThrowDone,
	}
	task.delay(Game.Throw.MaxChargeSeconds, function()
		local c = charges[player]
		if c and c.Token == token then
			charges[player] = nil -- no release in time: cancelled silently (no auto-throw)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Golden Whistle
----------------------------------------------------------------------------------------------------
local function useWhistle(player: Player, throwId: any): (boolean, string)
	if type(throwId) ~= "string" or #throwId > 64 then
		return false, "Bad throw"
	end
	local rec = throws[throwId]
	local state = DataService.Get(player)
	if not rec or not state or rec.Player ~= player then
		return false, "That isn't your throw"
	end
	if rec.Caught or rec.Recalled then
		return false, "Nothing to recall"
	end
	if os.clock() > rec.WhistleExpires then
		return false, "Too late, the dog is gone"
	end
	if (state.Whistles or 0) <= 0 then
		return false, "You have no Golden Whistles"
	end
	state.Whistles -= 1
	rec.Recalled = true
	local r = rec.Result
	local _, status = DogService.AddDog(player, r.DogId, r.Variant, { Defer = not rec.Finished })
	rec.Status = status
	BookService.Record(player, r.DogId, r.Variant)
	if Odds.IsLegendaryPlus(r.Rarity) then
		state.LuckyStreak = 0 -- a recall counts as a catch
	end
	state.Stats.Recalled += 1
	EventService.DespawnRunaway(throwId, "Recalled")
	if Odds.AtLeast(r.Rarity, Game.Broadcast.MissServerMin) then
		BroadcastService.Send("Recall", ("%s recalled the %s %s with a Golden Whistle!"):format(player.DisplayName,
			string.upper(r.Rarity), r.DogName), r.Rarity, r.Variant, false)
	end
	if rec.Finished then
		DogService.RefreshDisplay(player)
	end
	DataService.Push(player)
	if Odds.IsLegendaryPlus(r.Rarity) then
		task.spawn(DataService.SaveNow, player)
	end
	return true, ("%s came back! (%d whistles left)"):format(r.DogName, state.Whistles)
end

----------------------------------------------------------------------------------------------------
-- Throw zone presence (attributes)
----------------------------------------------------------------------------------------------------
local function setZoneAttributes(player: Player, on: boolean)
	if player:GetAttribute("InThrowZone") ~= on then
		player:SetAttribute("InThrowZone", on)
	end
	-- DEPRECATED (one release): the old platform / queue attributes mirror the zone
	if player:GetAttribute("OnPlatform") ~= on then
		player:SetAttribute("OnPlatform", on)
	end
	local pos = if on then 1 else 0
	if player:GetAttribute("ThrowQueuePos") ~= pos then
		player:SetAttribute("ThrowQueuePos", pos)
	end
end

local function tickZone()
	for _, player in Players:GetPlayers() do
		local on = isInZone(player)
		inZone[player] = on
		if not on then
			charges[player] = nil -- walked out: an unreleased charge is dropped
		end
		setZoneAttributes(player, on)
	end
end

----------------------------------------------------------------------------------------------------
function ThrowService.Start()
	local beginLimiter = RateLimiter.new(Game.RateLimits.Charge[1], Game.RateLimits.Charge[2])
	local releaseLimiter = RateLimiter.new(Game.RateLimits.Charge[1], Game.RateLimits.Charge[2])
	local finishLimiter = RateLimiter.new(Game.RateLimits.CutsceneFinished[1], Game.RateLimits.CutsceneFinished[2])
	local whistleLimiter = RateLimiter.new(Game.RateLimits.Whistle[1], Game.RateLimits.Whistle[2])

	local chargeBegin = Remotes.Get("ChargeBegin") :: RemoteEvent
	local chargeRelease = Remotes.Get("ChargeRelease") :: RemoteEvent
	local cutsceneFinished = Remotes.Get("CutsceneFinished") :: RemoteEvent
	local whistleRemote = Remotes.Get("UseWhistle") :: RemoteFunction

	chargeBegin.OnServerEvent:Connect(function(player: Player)
		if beginLimiter:Check(player) then
			beginCharge(player)
		end
	end)
	chargeRelease.OnServerEvent:Connect(function(player: Player)
		if releaseLimiter:Check(player) then
			release(player)
		end
	end)
	cutsceneFinished.OnServerEvent:Connect(function(player: Player, throwId: any)
		if not finishLimiter:Check(player) or type(throwId) ~= "string" then
			return
		end
		local rec = throws[throwId]
		if rec and rec.Player == player and not rec.Finished then
			if os.clock() >= rec.EarliestFinish then
				finish(rec)
			else
				-- early (client cutscene errored / ended fast): finish at EarliestFinish instead of the full timeout
				rec.FinishAt = math.min(rec.FinishAt, rec.EarliestFinish)
			end
		end
	end)
	whistleRemote.OnServerInvoke = function(player: Player, throwId: any)
		if not whistleLimiter:Check(player) then
			return false, "Slow down"
		end
		local ok, a, b = pcall(useWhistle, player, throwId)
		if not ok then
			warn("[ThrowService] whistle error: " .. tostring(a))
			return false, "Error"
		end
		return a, b
	end

	Players.PlayerRemoving:Connect(function(player)
		inZone[player] = nil
		charges[player] = nil
		lastRelease[player] = nil
		local rec = inFlight[player]
		if rec then
			finish(rec) -- broadcasts still go out; runaway is skipped for a player who left
		end
		for id, r in throws do
			if r.Player == player then
				throws[id] = nil
				EventService.DespawnRunaway(id, "Expired")
			end
		end
		beginLimiter:Clear(player)
		releaseLimiter:Clear(player)
		finishLimiter:Clear(player)
		whistleLimiter:Clear(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		setZoneAttributes(player, false)
	end)
	for _, player in Players:GetPlayers() do
		setZoneAttributes(player, false)
	end

	-- throw zone presence (~4x per second)
	task.spawn(function()
		while true do
			task.wait(Game.ThrowZone.SampleInterval)
			local ok, err = pcall(tickZone)
			if not ok then
				warn("[ThrowService] throw zone error: " .. tostring(err))
			end
		end
	end)

	-- cutscene timeouts + cleanup of old throw records
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, rec in inFlight do
				if now >= rec.FinishAt then
					finish(rec)
				end
			end
			for id, rec in throws do
				if rec.Finished and now > rec.WhistleExpires + 30 then
					throws[id] = nil
				end
			end
		end
	end)

end

return ThrowService
