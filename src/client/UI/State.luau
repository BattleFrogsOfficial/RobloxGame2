--!strict
-- Client-side store for the PlayerState snapshot plus derived numbers the screens read.
-- The server sends PlayerState.Computed (PlayerStats.Compute); if it is missing we compute locally.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local Signal = require(Util:WaitForChild("Signal"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local Odds = require(Util:WaitForChild("Odds"))
local Config = Shared:WaitForChild("Config")
local Shop = require(Config:WaitForChild("Shop"))
local Balls = require(Config:WaitForChild("Balls"))
local Rarities = require(Config:WaitForChild("Rarities"))

local State = {}

State.Changed = Signal.new() -- (snapshot, previous)
State.Snapshot = nil :: any
State.Previous = nil :: any

-- Local-only settings (persisted client-side; server-affecting ones also go through SetSetting if present).
State.Settings = {
	Music = true,
	Sfx = true,
	ReducedMotion = false,
	TreatPocketMode = Shop.DefaultTreatPocketMode,
	KeepDupes = table.clone(Shop.DefaultKeepDupes),
	HideCommonReveals = false,
}
State.SettingsChanged = Signal.new()

-- Server-wide facts pushed by events (not part of PlayerState).
State.Server = {
	ServerLuck = 0,
	Events = {} :: { [string]: any }, -- Kind -> EventState payload
}
State.EventsChanged = Signal.new()

function State.Set(snapshot: any)
	State.Previous = State.Snapshot
	State.Snapshot = snapshot
	State.Changed:Fire(snapshot, State.Previous)
end

function State.Get(): any
	return State.Snapshot or {}
end

function State.Computed(): { [string]: any }
	local s = State.Get()
	if s.Computed then
		return s.Computed
	end
	local ok, computed = pcall(PlayerStats.Compute, s, { ServerLuck = State.Server.ServerLuck })
	return if ok then computed else {}
end

function State.Cash(): number
	return State.Get().Cash or 0
end

function State.Bones(): number
	return State.Get().Bones or 0
end

function State.ThrowPower(): number
	return State.Get().ThrowPower or 0
end

function State.Income(): number
	local c = State.Computed()
	return c.IncomePerSec or c.Income or 0
end

function State.Ball(): any
	return PlayerStats.Ball(State.Get())
end

function State.OwnsBall(ballId: string): boolean
	local s = State.Get()
	return ballId == Balls.Default or (s.Balls ~= nil and s.Balls[ballId] == true)
end

function State.Luck(): (number, { PlayerStats.Source })
	return PlayerStats.Luck(State.Get(), { ServerLuck = State.Server.ServerLuck })
end

function State.CatchBonus(): number
	local b = PlayerStats.CatchBonus(State.Get(), nil)
	return b
end

function State.MaxDistance(): number
	return PlayerStats.MaxDistance(State.Get())
end

function State.ReachZone(): any
	return PlayerStats.ZoneForDistance(State.MaxDistance())
end

function State.TierOdds(): { [string]: number }
	local luck = State.Luck()
	local zone = State.ReachZone()
	return Odds.TierOdds(luck, DogCatalog.ZoneTiers(zone.Id))
end

function State.Dogs(): { any }
	return State.Get().Dogs or {}
end

function State.Slots(): number
	return PlayerStats.EffectiveSlots(State.Get(), nil)
end

function State.DisplayedCount(): number
	local n = 0
	for _, d in State.Dogs() do
		if d.Displayed then
			n += 1
		end
	end
	return n
end

function State.Book(): { [string]: any }
	return State.Get().Book or {}
end

function State.BookOwned(dogId: string): boolean
	return State.Book()[dogId] ~= nil
end

function State.BookVariants(dogId: string): { [string]: boolean }
	local entry = State.Book()[dogId]
	local out: { [string]: boolean } = {}
	if entry and entry.Variants then
		for k, v in entry.Variants do
			if type(k) == "string" then
				out[k] = v and true or false
			elseif type(v) == "string" then
				out[v] = true
			end
		end
	end
	return out
end

function State.ZoneBookCount(zoneId: string): (number, number)
	local total = DogCatalog.ZoneBaseCount(zoneId)
	local owned = 0
	for _, def in DogCatalog.ZoneDogs(zoneId) do
		if State.BookOwned(def.Id) then
			owned += 1
		end
	end
	return owned, total
end

function State.BookRewardClaimed(zoneId: string, milestone: number): boolean
	local r = State.Get().BookRewards
	if type(r) ~= "table" then
		return false
	end
	local z = r[zoneId]
	if type(z) == "table" then
		return z[milestone] == true or z[tostring(milestone)] == true or table.find(z, milestone) ~= nil
	end
	return false
end

function State.ActiveBoosts(): { { Id: string, Name: string, ExpiresAt: number, Kind: string } }
	local out = {}
	local now = os.time()
	local s = State.Get()
	for _, id in Shop.BoostOrder do
		local exp = s.Boosts and s.Boosts[id]
		if type(exp) == "number" and exp > now then
			local b = Shop.Boosts[id]
			table.insert(out, { Id = id, Name = b.Name, ExpiresAt = exp, Kind = b.Kind })
		end
	end
	return out
end

function State.LuckyStreak(): number
	return State.Get().LuckyStreak or 0
end

function State.Whistles(): number
	return State.Get().Whistles or 0
end

function State.TreatPockets(): number
	return State.Get().TreatPockets or 0
end

function State.RarityIndex(rarity: string): number
	return table.find(Rarities.Order, rarity) or 0
end

function State.SetSetting(key: string, value: any)
	(State.Settings :: any)[key] = value
	State.SettingsChanged:Fire(key, value)
end

function State.SetEvent(kind: string, payload: any)
	if payload and payload.Active then
		State.Server.Events[kind] = payload
	else
		State.Server.Events[kind] = nil
	end
	State.EventsChanged:Fire(kind, payload)
end

return State
