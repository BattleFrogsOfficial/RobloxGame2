--!nonstrict
-- The throw: ChargeBegin/ChargeRelease timing (server clock only), one throw in flight per player,
-- cooldowns + rate limits, pad presence, distance/landing/zone, the full roll (RollService), commit to
-- data BEFORE any visuals, ThrowResult to every client, cutscene completion (CutsceneFinished or
-- timeout), broadcasts, runaway spawn on a miss and the Golden Whistle recall (UseWhistle).
local CollectionService = game:GetService("CollectionService")
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

local function zoneById(id: string): any
	for _, z in Zones do
		if z.Id == id then
			return z
		end
	end
	return Zones[1]
end

function ThrowService.PadPosition(index: number): Vector3
	for _, inst in CollectionService:GetTagged("ThrowPad") do
		if inst:GetAttribute("PadIndex") == index and inst:IsA("BasePart") then
			return inst.Position
		end
	end
	return Vector3.new(Layout.ThrowLine.PadsX[index] or 0, Layout.GroundY, Layout.ThrowLine.Z)
end

local function onOwnPad(player: Player, pad: number): boolean
	if not Game.Throw.RequireOnPad then
		return true
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return false
	end
	local p = ThrowService.PadPosition(pad)
	local d = Vector2.new(hrp.Position.X - p.X, hrp.Position.Z - p.Z).Magnitude
	return d <= Game.Throw.PadRadius
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
local function resolveThrow(player: Player, elapsed: number, tutorial: boolean)
	local state = DataService.Get(player)
	local pad = DogService.GetYardIndex(player)
	if not state or not pad then
		return
	end
	local ball = PlayerStats.Ball(state)
	local meterPos, quality, band = Meter.Evaluate(elapsed, tutorial)
	local maxField = PlayerStats.MaxFieldDistance()
	local distance = state.ThrowPower * ball.RangeMult * quality * (1 + rng:Range(-Game.Throw.Scatter, Game.Throw.Scatter))
	distance = math.clamp(distance, Game.Throw.MinDistance, maxField)
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
	state.Stats.Throws += 1
	state.Stats.BestDistance = math.max(state.Stats.BestDistance or 0, distance)
	if tutorial then
		state.TutorialThrowDone = true
	end

	local def = DogCatalog.Get(outcome.DogId)
	local cutLen = (Timers.Cutscene :: any)[outcome.Rarity] or 3
	local canSkip = outcome.Rarity == "Common" and not tutorial
		and (state.CommonCutscenesSeen or 0) >= Timers.CommonSkippableAfter
	if outcome.Rarity == "Common" then
		state.CommonCutscenesSeen = (state.CommonCutscenesSeen or 0) + 1
	end

	-- Commit the outcome to data before anything is shown.
	local record, status = nil, nil
	if outcome.Caught then
		state.Stats.Caught += 1
		record, status = DogService.AddDog(player, outcome.DogId, outcome.Variant, {
			Defer = true,
			SaleDelay = cutLen + Timers.CutscenePadding + Timers.DupeKeepWindow,
		})
		BookService.Record(player, outcome.DogId, outcome.Variant)
	else
		state.Stats.Missed += 1
	end

	local padPos = ThrowService.PadPosition(pad)
	-- Land inside the clear centre lane (|x - centre| <= FieldWidth/4 - 4): the outer 25% bands hold zone
	-- decor, distance markers and arch pillars (QA overlap fix; see docs/qa/OVERLAP.md).
	local fieldCX = (Layout.Field.MinX + Layout.Field.MaxX) / 2
	local laneHalf = (Layout.Field.MaxX - Layout.Field.MinX) * 0.25 - 4
	local landX = math.clamp(fieldCX + (padPos.X - fieldCX) * 0.5
		+ rng:Range(-Game.Throw.LateralScatter, Game.Throw.LateralScatter) * 0.5, fieldCX - laneHalf, fieldCX + laneHalf)
	local adult = DogCatalog.AdultIncome(def, outcome.Variant) * PlayerStats.IncomeMult(ctx)
	local throwId = HttpService:GenerateGUID(false)
	local now = os.clock()

	local result = {
		ThrowId = throwId,
		ThrowerUserId = player.UserId,
		ThrowerName = player.DisplayName,
		PadIndex = pad,
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
		StartPosition = padPos,
		LandingPosition = Vector3.new(landX, Layout.GroundY, Layout.DistanceToZ(distance)),
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
		FinishAt = now + cutLen + Timers.CutscenePadding,
		EarliestFinish = if canSkip then now else now + cutLen * 0.6,
		Finished = false,
		Caught = outcome.Caught,
		Recalled = false,
		WhistleExpires = now + cutLen + Timers.CutscenePadding + Timers.WhistleWindow,
		Status = status,
	}
	inFlight[player] = rec
	throws[throwId] = rec

	Remotes.Get("ThrowResult"):FireAllClients(result)
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
	charges[player] = nil
	local elapsed = os.clock() - charge.Start
	lastRelease[player] = os.clock()
	local ok, err = pcall(resolveThrow, player, elapsed, charge.Tutorial)
	if not ok then
		warn("[ThrowService] resolve error: " .. tostring(err))
	end
end

local function beginCharge(player: Player)
	local state = DataService.Get(player)
	local pad = DogService.GetYardIndex(player)
	if not state or not pad then
		return
	end
	if charges[player] or inFlight[player] then
		return
	end
	if os.clock() - (lastRelease[player] or -math.huge) < Game.Throw.MinSecondsBetweenThrows then
		return
	end
	if not onOwnPad(player, pad) then
		BroadcastService.Notify(player, "Stand on your throw pad (#" .. pad .. ") to throw!", "Hint")
		return
	end
	tokenCounter += 1
	local token = tokenCounter
	charges[player] = {
		Start = os.clock(),
		Token = token,
		Tutorial = Game.Tutorial.Enabled and not state.TutorialThrowDone,
	}
	task.delay(Game.Throw.MaxChargeSeconds, function()
		local c = charges[player]
		if c and c.Token == token then
			release(player) -- auto-release (anti stall / macro)
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
