--!nonstrict
-- Player data: DataStore load/save with session locking, autosave, retries + backoff, versioned
-- migrations, and an in-memory mock store for Studio without API access (or Game.UseMockData).
-- Record layout in the store: { Data = PlayerState, Lock = { JobId, Time }? }  key "u_<UserId>".
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Config:WaitForChild("Game"))
local Balls = require(Config:WaitForChild("Balls"))
local Shop = require(Config:WaitForChild("Shop"))
local Timers = require(Config:WaitForChild("Timers"))
local Table = require(Util:WaitForChild("Table"))
local Signal = require(Util:WaitForChild("Signal"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))

local DataService = {}

local STORE_NAME = "FetchLegends_Player_v1"
local CURRENT_VERSION = 1
local LOAD_ATTEMPTS = 6
local SAVE_ATTEMPTS = 4
local MAX_RECEIPTS = 100

DataService.PlayerLoaded = Signal.new() -- (player, state)
DataService.StateChanged = Signal.new() -- (player, state) after each pushed snapshot
-- Server-wide luck boost (ServerLuck dev product). Until is os.time().
DataService.ServerLuck = { Amount = 0, Until = 0 }

type Session = {
	State: any,
	Loaded: boolean,
	Passes: { [string]: boolean },
	PrevLastSeen: number,
	PushQueued: boolean,
	Saving: boolean,
	Leaving: boolean,
	LostLock: boolean,
}
local sessions: { [Player]: Session } = {}
local releasingCallbacks: { (Player, any) -> () } = {}
local usingMock = false
local store: any = nil

----------------------------------------------------------------------------------------------------
-- Default state + migrations
----------------------------------------------------------------------------------------------------
function DataService.DefaultState(): any
	return {
		Version = CURRENT_VERSION,
		Cash = Game.StartingCash,
		Bones = 0,
		ThrowPower = Game.StartingThrowPower,
		Balls = { [Balls.Default] = true },
		EquippedBall = Balls.Default,
		SlotCount = Shop.Slots.Start,
		Dogs = {}, -- { {Uid, DogId, Variant?, BornAt, GrownAt, Displayed?, Locked?, Held?, PendingSale?} }
		Book = {}, -- [DogId] = { Count, FirstAt, Variants = { [variant] = true } }
		BookRewards = {}, -- [ZoneId] = { ["25"] = true, ... } (string keys: DataStore/remote safe)
		Boosts = {}, -- [boostId] = expiresAt (os.time)
		Whistles = 0,
		TreatPockets = 0,
		LuckyStreak = 0,
		LastDailyWalk = -1, -- UTC day number of the last claim
		TutorialDone = false, -- FTUE finished (set after the first training purchase)
		TutorialThrowDone = false, -- the guaranteed tutorial throw has happened
		TrainingLevel = 0,
		PermanentLuck = 0,
		PremiumThrows = 0,
		Settings = {
			KeepDupes = Table.DeepCopy(Shop.DefaultKeepDupes),
			TreatPocketMode = Shop.DefaultTreatPocketMode,
		},
		Cosmetics = {},
		Titles = {},
		EquippedTitle = "",
		Trophies = {}, -- [ZoneId] = true
		VariantBadges = {}, -- ["<ZoneId>:<Variant>"] = true
		CommonCutscenesSeen = 0,
		LastSeen = 0,
		Receipts = {}, -- last MAX_RECEIPTS PurchaseIds (strings)
		Stats = { Throws = 0, Caught = 0, Missed = 0, Recalled = 0, BestDistance = 0, TotalEarned = 0 },
	}
end

-- Migrations[n] upgrades a state at Version n to n + 1. Version 0 = pre-versioned data.
local Migrations: { [number]: (any) -> () } = {
	[0] = function(_state) end,
}

local function migrate(state: any)
	local v = tonumber(state.Version) or 0
	while v < CURRENT_VERSION do
		local m = Migrations[v]
		if m then
			m(state)
		end
		v += 1
		state.Version = v
	end
	Table.Reconcile(state, DataService.DefaultState())
	-- sanitise numbers
	for _, k in { "Cash", "Bones", "ThrowPower", "SlotCount", "Whistles", "TreatPockets", "LuckyStreak",
		"TrainingLevel", "PermanentLuck", "PremiumThrows" } do
		local n = tonumber(state[k])
		if n == nil or n ~= n or n == math.huge or n == -math.huge then
			state[k] = DataService.DefaultState()[k]
		end
	end
	if not Balls.ById[state.EquippedBall] or not state.Balls[state.EquippedBall] then
		state.EquippedBall = Balls.Default
	end
end

----------------------------------------------------------------------------------------------------
-- Store (real or mock)
----------------------------------------------------------------------------------------------------
local MockStore = {}
MockStore.__index = MockStore
function MockStore.new()
	return setmetatable({ Data = {} }, MockStore)
end
function MockStore:UpdateAsync(key: string, fn: (any) -> any)
	local new = fn(Table.DeepCopy(self.Data[key]))
	if new ~= nil then
		self.Data[key] = Table.DeepCopy(new)
	end
	return new
end
function MockStore:GetAsync(key: string)
	return Table.DeepCopy(self.Data[key])
end

local function initStore()
	if Game.UseMockData and RunService:IsStudio() then
		usingMock = true
		store = MockStore.new()
		warn("[DataService] Game.UseMockData: using in-memory store (nothing persists)")
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result and RunService:IsStudio() then
		local probeOk, err = pcall(function()
			result:GetAsync("__probe")
		end)
		if not probeOk then
			warn("[DataService] DataStores unavailable in Studio (" .. tostring(err) .. "); using in-memory store")
			ok = false
		end
	end
	if ok and result then
		store = result
	else
		usingMock = true
		store = MockStore.new()
		if not RunService:IsStudio() then
			warn("[DataService] DataStore unavailable; using in-memory store. DATA WILL NOT PERSIST.")
		end
	end
end

function DataService.IsMock(): boolean
	return usingMock
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

----------------------------------------------------------------------------------------------------
-- Load / save
----------------------------------------------------------------------------------------------------
local function loadRecord(player: Player): (boolean, any)
	local key = keyFor(player)
	for attempt = 1, LOAD_ATTEMPTS do
		if player.Parent == nil then
			return false, "left"
		end
		local steal = attempt == LOAD_ATTEMPTS
		local lockedBy: string? = nil
		local data: any = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				lockedBy = nil
				data = nil
				local rec = if type(old) == "table" then old else {}
				local lock = rec.Lock
				local t = os.time()
				if type(lock) == "table" and lock.JobId ~= game.JobId
					and (t - (tonumber(lock.Time) or 0)) < Timers.SessionLockStale and not steal then
					lockedBy = tostring(lock.JobId)
					return nil -- cancel write; another server holds the session
				end
				if type(lock) == "table" and lock.JobId ~= game.JobId then
					warn(("[DataService] taking over session lock for %s from %s"):format(key, tostring(lock.JobId)))
				end
				rec.Lock = { JobId = game.JobId, Time = t }
				data = rec.Data
				return rec
			end)
		end)
		if ok and lockedBy == nil then
			return true, data
		end
		if not ok then
			warn(("[DataService] load %s attempt %d failed: %s"):format(key, attempt, tostring(err)))
			task.wait(math.min(8, 0.5 * 2 ^ attempt))
		else
			-- locked by another server (it is probably still saving on leave): wait and retry
			task.wait(5)
		end
	end
	return false, "locked"
end

local function saveSession(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session or not session.Loaded or session.LostLock then
		return false
	end
	while session.Saving do
		task.wait(0.1)
	end
	session.Saving = true
	session.State.LastSeen = os.time()
	local payload = Table.DeepCopy(session.State)
	local key = keyFor(player)
	local success = false
	for attempt = 1, SAVE_ATTEMPTS do
		local lost = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				lost = false
				local rec = if type(old) == "table" then old else {}
				local lock = rec.Lock
				if type(lock) == "table" and lock.JobId ~= game.JobId then
					lost = true
					return nil -- another server owns this profile now; never overwrite it
				end
				rec.Data = payload
				rec.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
				return rec
			end)
		end)
		if ok and lost then
			warn("[DataService] session lock lost for " .. key .. "; save skipped")
			session.LostLock = true
			break
		elseif ok then
			success = true
			break
		end
		warn(("[DataService] save %s attempt %d failed: %s"):format(key, attempt, tostring(err)))
		task.wait(math.min(8, 0.5 * 2 ^ attempt))
	end
	session.Saving = false
	return success
end

function DataService.SaveNow(player: Player): boolean
	return saveSession(player, false)
end

----------------------------------------------------------------------------------------------------
-- Accessors
----------------------------------------------------------------------------------------------------
function DataService.Get(player: Player): any
	local s = sessions[player]
	return if s and s.Loaded then s.State else nil
end

function DataService.IsLoaded(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and s.Loaded
end

function DataService.WaitForState(player: Player, timeout: number?): any
	local deadline = os.clock() + (timeout or 20)
	while os.clock() < deadline and player.Parent ~= nil do
		local st = DataService.Get(player)
		if st then
			return st
		end
		task.wait(0.1)
	end
	return DataService.Get(player)
end

function DataService.GetPrevLastSeen(player: Player): number
	local s = sessions[player]
	return if s then s.PrevLastSeen else 0
end

function DataService.GetPasses(player: Player): { [string]: boolean }
	local s = sessions[player]
	return if s then s.Passes else {}
end

function DataService.SetPass(player: Player, key: string, owned: boolean)
	local s = sessions[player]
	if s then
		s.Passes[key] = owned or nil
		DataService.Push(player)
	end
end

function DataService.CurrentServerLuck(): number
	if os.time() < DataService.ServerLuck.Until then
		return DataService.ServerLuck.Amount
	end
	return 0
end

-- PlayerStats context for this player right now.
function DataService.Ctx(player: Player): any
	return { Now = os.time(), Passes = DataService.GetPasses(player), ServerLuck = DataService.CurrentServerLuck() }
end

function DataService.Computed(player: Player): any
	local st = DataService.Get(player)
	if not st then
		return nil
	end
	return PlayerStats.Compute(st, DataService.Ctx(player))
end

function DataService.Snapshot(player: Player): any
	local st = DataService.Get(player)
	if not st then
		return nil
	end
	local snap = table.clone(st)
	snap.Receipts = nil
	snap.Computed = PlayerStats.Compute(st, DataService.Ctx(player))
	snap.Passes = table.clone(DataService.GetPasses(player))
	snap.ServerLuckUntil = DataService.ServerLuck.Until
	snap.IsMockData = usingMock
	return snap
end

-- Live attributes (cheap per-second replication for the HUD; full snapshots go through StateUpdate).
function DataService.SetLiveAttributes(player: Player, incomePerSec: number?)
	local st = DataService.Get(player)
	if not st then
		return
	end
	player:SetAttribute("Cash", st.Cash)
	player:SetAttribute("Bones", st.Bones)
	player:SetAttribute("ThrowPower", st.ThrowPower)
	if incomePerSec then
		player:SetAttribute("IncomePerSec", incomePerSec)
	end
end

-- Queue a full StateUpdate snapshot (coalesced to one per frame).
function DataService.Push(player: Player)
	local s = sessions[player]
	if not s or not s.Loaded or s.PushQueued then
		return
	end
	s.PushQueued = true
	task.defer(function()
		s.PushQueued = false
		if sessions[player] ~= s or player.Parent == nil then
			return
		end
		local snap = DataService.Snapshot(player)
		if snap then
			DataService.SetLiveAttributes(player, snap.Computed.IncomePerSec)
			Remotes.Get("StateUpdate"):FireClient(player, snap)
			DataService.StateChanged:Fire(player, s.State)
		end
	end)
end

function DataService.AddCash(player: Player, amount: number)
	local st = DataService.Get(player)
	if not st or amount ~= amount or amount <= 0 then
		return
	end
	st.Cash += amount
	st.Stats.TotalEarned += amount
end

function DataService.TrySpendCash(player: Player, amount: number): boolean
	local st = DataService.Get(player)
	if not st or amount ~= amount or amount < 0 or st.Cash < amount then
		return false
	end
	st.Cash -= amount
	return true
end

function DataService.AddBones(player: Player, amount: number)
	local st = DataService.Get(player)
	if st and amount > 0 then
		st.Bones += math.floor(amount)
	end
end

function DataService.HasReceipt(player: Player, purchaseId: string): boolean
	local st = DataService.Get(player)
	return st ~= nil and table.find(st.Receipts, purchaseId) ~= nil
end

function DataService.RecordReceipt(player: Player, purchaseId: string)
	local st = DataService.Get(player)
	if not st then
		return
	end
	table.insert(st.Receipts, purchaseId)
	while #st.Receipts > MAX_RECEIPTS do
		table.remove(st.Receipts, 1)
	end
end

-- Call fn(player, state) for every loaded player now and every player that loads later.
function DataService.OnLoaded(fn: (Player, any) -> ())
	DataService.PlayerLoaded:Connect(fn)
	for player, s in sessions do
		if s.Loaded then
			task.spawn(fn, player, s.State)
		end
	end
end

-- fn(player, state) runs synchronously (in registration order) right before the final save on leave.
-- Must not yield.
function DataService.OnReleasing(fn: (Player, any) -> ())
	table.insert(releasingCallbacks, fn)
end

function DataService.Players(): { Player }
	local out = {}
	for player, s in sessions do
		if s.Loaded and player.Parent ~= nil then
			table.insert(out, player)
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	local session: Session = {
		State = nil, Loaded = false, Passes = {}, PrevLastSeen = 0,
		PushQueued = false, Saving = false, Leaving = false, LostLock = false,
	}
	sessions[player] = session
	local ok, data = loadRecord(player)
	if sessions[player] ~= session or player.Parent == nil then
		-- left while loading: give the lock back so the next server can load immediately
		if ok then
			pcall(function()
				store:UpdateAsync(keyFor(player), function(old)
					if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId == game.JobId then
						old.Lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		if sessions[player] == session then
			sessions[player] = nil
		end
		return
	end
	if not ok then
		sessions[player] = nil
		player:Kick("Fetch Legends couldn't load your save (it may still be open on another server). Please rejoin in a minute.")
		return
	end
	local state = if type(data) == "table" then data else DataService.DefaultState()
	migrate(state)
	session.PrevLastSeen = tonumber(state.LastSeen) or 0
	session.State = state
	session.Loaded = true
	DataService.SetLiveAttributes(player, 0)
	DataService.PlayerLoaded:Fire(player, state)
	DataService.Push(player)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.Leaving = true
	if session.Loaded then
		for _, fn in releasingCallbacks do
			local ok, err = pcall(fn, player, session.State)
			if not ok then
				warn("[DataService] releasing callback error: " .. tostring(err))
			end
		end
		saveSession(player, true)
	end
	if sessions[player] == session then
		sessions[player] = nil
	end
end

function DataService.Start()
	initStore()

	local stateLimiter = RateLimiter.new(Game.RateLimits.RequestState[1], Game.RateLimits.RequestState[2])
	local requestState = Remotes.Get("RequestState") :: RemoteFunction
	requestState.OnServerInvoke = function(player: Player)
		if not stateLimiter:Check(player) then
			return nil
		end
		DataService.WaitForState(player, 20)
		return DataService.Snapshot(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	-- Autosave, staggered across players.
	task.spawn(function()
		while true do
			task.wait(Timers.AutosaveInterval)
			for player, s in sessions do
				if s.Loaded and not s.Leaving then
					task.spawn(saveSession, player, false)
					task.wait(0.5)
				end
			end
		end
	end)

	game:BindToClose(function()
		if usingMock then
			return
		end
		local pending = 0
		for player, s in sessions do
			if s.Loaded and not s.Leaving then
				pending += 1
				task.spawn(function()
					s.Leaving = true
					for _, fn in releasingCallbacks do
						pcall(fn, player, s.State)
					end
					saveSession(player, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
