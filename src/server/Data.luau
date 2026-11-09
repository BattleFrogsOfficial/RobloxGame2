-- Player save data + per-session state, and syncing it to each client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local Data = {}

local STORE_NAME = "SplitTheOcean_v1"
local AUTOSAVE_SECONDS = 90

local StateEvent = Remotes.get("State")
local NotifyEvent = Remotes.get("Notify")
local EffectEvent = Remotes.get("Effect")

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStore unavailable, progress will not save:", result)
	end
end

local function defaultData()
	return {
		cash = 0,
		strength = 0,
		luckLevel = 0,
		weightTier = 1,
		baseSlots = Config.Base.StartSlots,
		eggs = {}, -- stored eggs: { egg, variant }
		animals = {}, -- stored animals: { uid, animal, variant }
		pen = {}, -- ["1".."20"] = { kind = "egg", egg, variant, start, dur } | { kind = "animal", uid, animal, variant }
		index = {}, -- [animalId] = 1 (discovered) | 2 (reward claimed)
		daily = { last = 0, streak = 0 },
		boosts = { luckUntil = 0 },
		stats = { eggsCollected = 0, hatched = 0, totalEarned = 0, splits = 0 },
		receipts = {},
		starterPackBought = false,
		nextUid = 1,
		lastOnline = 0,
	}
end

-- Fill in any keys missing from older saves.
local function reconcile(target, template)
	for k, v in template do
		if target[k] == nil then
			target[k] = if type(v) == "table" then table.clone(v) else v
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil then
			reconcile(target[k], v)
		end
	end
	return target
end

local profiles: { [Player]: any } = {}
local sessions: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}
local inFlight = 0 -- saves currently being written

Data.Loaded = Instance.new("BindableEvent") -- fires (player) once data is ready

function Data.get(player: Player)
	return profiles[player]
end

function Data.session(player: Player)
	return sessions[player]
end

function Data.markDirty(player: Player)
	dirty[player] = true
end

function Data.notify(player: Player, text: string, color: Color3?)
	NotifyEvent:FireClient(player, text, color)
end

function Data.effect(player: Player, kind: string, payload: any?)
	EffectEvent:FireClient(player, kind, payload)
end

function Data.hasPass(player: Player, key: string): boolean
	local s = sessions[player]
	return s ~= nil and s.passes[key] == true
end

function Data.luck(player: Player): number
	local d = profiles[player]
	if not d then
		return 1
	end
	return Formulas.luck(d.luckLevel, Data.hasPass(player, "DoubleLuck"), d.boosts.luckUntil > os.time())
end

function Data.newUid(player: Player): number
	local d = profiles[player]
	local uid = d.nextUid
	d.nextUid += 1
	return uid
end

-- Income per second from animals placed in the pen.
function Data.income(player: Player): number
	local d = profiles[player]
	if not d then
		return 0
	end
	local total = 0
	for _, item in d.pen do
		if item.kind == "animal" then
			total += Formulas.animalIncome(item.animal, item.variant)
		end
	end
	if Data.hasPass(player, "DoubleCash") then
		total *= 2
	end
	return total
end

function Data.addCash(player: Player, amount: number)
	local d = profiles[player]
	d.cash += amount
	if amount > 0 then
		d.stats.totalEarned += amount
	end
	Data.markDirty(player)
end

function Data.trySpend(player: Player, amount: number): boolean
	local d = profiles[player]
	if not d or d.cash < amount then
		return false
	end
	d.cash -= amount
	Data.markDirty(player)
	return true
end

-- Snapshot sent to the client: save data plus derived values.
local function buildState(player: Player)
	local d = profiles[player]
	local s = sessions[player]
	return {
		cash = d.cash,
		strength = d.strength,
		luckLevel = d.luckLevel,
		luck = Data.luck(player),
		weightTier = d.weightTier,
		baseSlots = d.baseSlots,
		eggs = d.eggs,
		animals = d.animals,
		pen = d.pen,
		index = d.index,
		daily = d.daily,
		boosts = d.boosts,
		stats = d.stats,
		starterPackBought = d.starterPackBought,
		income = Data.income(player),
		carry = Formulas.carry(Data.hasPass(player, "ExtraCarry")),
		passes = s.passes,
		sessionStart = s.sessionStart,
		playtimeClaimed = s.playtimeClaimed,
		fastHatch = Data.hasPass(player, "FastHatch"),
		saving = s.canSave,
		serverDay = math.floor(os.time() / 86400),
		osTime = os.time(),
	}
end

-- The player-list leaderboard (top right in Roblox).
local function makeLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	for _, name in { "Cash", "Strength", "Eggs" } do
		local value = Instance.new("StringValue")
		value.Name = name
		value.Value = "0"
		value.Parent = folder
	end
	folder.Parent = player
end

local function updateLeaderstats(player: Player, d)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local values = { Cash = Format.cash(d.cash), Strength = Format.short(d.strength), Eggs = Format.short(d.stats.eggsCollected) }
	for name, text in values do
		local value = folder:FindFirstChild(name)
		if value and value.Value ~= text then
			value.Value = text
		end
	end
end

local function flush()
	for player in dirty do
		dirty[player] = nil
		local d = profiles[player]
		if d and player.Parent then
			StateEvent:FireClient(player, buildState(player))
			updateLeaderstats(player, d)
		end
	end
end

local function key(player: Player)
	return "p_" .. player.UserId
end

local function load(player: Player)
	if not store then
		return defaultData(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			return reconcile(result or defaultData(), defaultData()), true
		end
		warn("[Data] load failed (attempt " .. attempt .. "):", result)
		task.wait(attempt)
	end
	-- Could not read: play on fresh data but never overwrite the real save.
	return defaultData(), false
end

-- Returns true only if the data was actually written.
function Data.save(player: Player): boolean
	local d = profiles[player]
	local s = sessions[player]
	if not d or not s or not s.canSave or not store then
		return false
	end
	d.lastOnline = os.time()
	inFlight += 1
	local ok, err = pcall(function()
		store:SetAsync(key(player), d, { player.UserId })
	end)
	inFlight -= 1
	if not ok then
		warn("[Data] save failed for", player.Name, err)
	end
	return ok
end

local function onPlayerAdded(player: Player)
	local data, canSave = load(player)
	if not player.Parent then
		return
	end
	profiles[player] = data
	sessions[player] = {
		passes = {},
		sessionStart = workspace:GetServerTimeNow(),
		playtimeClaimed = {},
		canSave = canSave,
	}
	makeLeaderstats(player)
	Data.Loaded:Fire(player)
	Data.markDirty(player)
	if not canSave then
		if RunService:IsStudio() then
			Data.notify(player, "Studio: enable API access to save progress.", Color3.fromRGB(255, 200, 80))
		else
			Data.notify(player, "Couldn't load your save. Progress this session won't be saved.", Color3.fromRGB(255, 90, 90))
		end
	end
end

-- Other systems register work to do just before a leaving player is saved
-- (e.g. putting carried eggs into storage).
local leavingHooks: { (Player) -> () } = {}
function Data.onLeaving(fn: (Player) -> ())
	table.insert(leavingHooks, fn)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		for _, fn in leavingHooks do
			local ok, err = pcall(fn, player)
			if not ok then
				warn("[Data] leaving hook failed:", err)
			end
		end
	end
	local s = sessions[player]
	local alreadySaving = s ~= nil and s.leaving == true
	if s then
		s.leaving = true
	end
	if not alreadySaving then
		Data.save(player)
	end
	profiles[player] = nil
	sessions[player] = nil
	dirty[player] = nil
end

function Data.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	task.spawn(function()
		while true do
			task.wait(0.15)
			flush()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(Data.save, player)
			end
		end
	end)

	game:BindToClose(function()
		-- PlayerRemoving already saves leaving players; save the rest, then wait
		-- until every profile has been written and released.
		for player in profiles do
			local s = sessions[player]
			if s and not s.leaving then
				s.leaving = true
				task.spawn(Data.save, player)
			end
		end
		local t = os.clock()
		task.wait()
		while inFlight > 0 and os.clock() - t < 25 do
			task.wait(0.1)
		end
	end)
end

return Data
