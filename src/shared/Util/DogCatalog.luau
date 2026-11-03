--!strict
-- Read-only index over the generated roster (ReplicatedStorage.Shared.Data.Dogs, agent A).
-- If the roster module is missing or fails to load, a clearly-labelled placeholder roster with the
-- correct per-zone counts is generated so the game still runs end to end.
local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))

export type Dog = {
	Id: string,
	Name: string,
	Zone: string,
	Rarity: string,
	Income: number, -- adult $/s before variant mult
	[string]: any,
}

local DogCatalog = {}

local loaded = false
local placeholder = false
local all: { Dog } = {}
local byId: { [string]: Dog } = {}
local byZoneTier: { [string]: { [string]: { Dog } } } = {}
local zoneById: { [string]: any } = {}
for _, z in Zones do
	zoneById[z.Id] = z
end

local function computeIncome(zoneId: string, rarity: string, offset: number): number
	local z = zoneById[zoneId]
	local t = (Rarities.Tiers :: any)[rarity]
	if not z or not t then
		return 0
	end
	return z.BaseIncome * t.IncomeMult * (1 + offset)
end

local function expectedCounts(zoneId: string): { [string]: number }
	local c: { [string]: number } = {}
	for _, tier in Rarities.Order do
		c[tier] = (Rarities.Tiers :: any)[tier].PerZone
	end
	if zoneId == "MythicMeadow" then
		c.Common = 53
		c.Uncommon, c.Rare, c.Epic, c.Legendary = 13, 7, 3, 2
		c.Mythic = 2
	end
	return c
end

local function buildPlaceholder(): { Dog }
	local out: { Dog } = {}
	local letters = { Common = "c", Uncommon = "u", Rare = "r", Epic = "e", Legendary = "l", Mythic = "m" }
	for _, z in Zones do
		local counts = expectedCounts(z.Id)
		for _, tier in Rarities.Order do
			local n = counts[tier]
			for i = 1, n do
				local offset = if n <= 1 then 0 else 0.2 * (i - 1) / (n - 1)
				table.insert(out, {
					Id = string.format("%s_%s%02d", z.Id, letters[tier], i),
					Name = string.format("%s %s #%d", z.Name, tier, i),
					Zone = z.Id,
					Rarity = tier,
					OrderInTier = i,
					Body = "medium_lean",
					Scale = 1,
					CoatPrimary = "#C8A070",
					CoatSecondary = "#FFFFFF",
					Pattern = "none",
					Accessory = "none",
					Vfx = "none",
					UniqueParts = {},
					Income = computeIncome(z.Id, tier, offset),
					Flavor = "Placeholder dog (roster not generated).",
					Placeholder = true,
				})
			end
		end
	end
	return out
end

local function ensure()
	if loaded then
		return
	end
	loaded = true
	local list: { any }? = nil
	local dataFolder = Shared:FindFirstChild("Data")
	local mod = dataFolder and dataFolder:FindFirstChild("Dogs")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok and type(result) == "table" then
			if type(result.All) == "table" then
				list = result.All
			else
				list = result :: any
			end
		else
			warn("[DogCatalog] Data.Dogs failed to load, using placeholder roster: " .. tostring(result))
		end
	else
		warn("[DogCatalog] ReplicatedStorage.Shared.Data.Dogs missing, using placeholder roster")
	end
	if not list or #list == 0 then
		list = buildPlaceholder()
		placeholder = true
	end
	for _, raw in list :: { any } do
		if type(raw) == "table" and type(raw.Id) == "string" then
			local zone = raw.Zone or raw.ZoneId
			local rarity = raw.Rarity
			if type(zone) == "string" and type(rarity) == "string" and zoneById[zone]
				and (Rarities.Tiers :: any)[rarity] then
				if type(raw.Income) ~= "number" then
					raw.Income = computeIncome(zone, rarity, tonumber(raw.IncomeOffset) or 0)
				end
				raw.Zone = zone
				table.insert(all, raw)
				byId[raw.Id] = raw
				byZoneTier[zone] = byZoneTier[zone] or {}
				byZoneTier[zone][rarity] = byZoneTier[zone][rarity] or {}
				table.insert(byZoneTier[zone][rarity], raw)
			end
		end
	end
end

function DogCatalog.IsPlaceholder(): boolean
	ensure()
	return placeholder
end

function DogCatalog.All(): { Dog }
	ensure()
	return all
end

function DogCatalog.Get(id: string): Dog?
	ensure()
	return byId[id]
end

function DogCatalog.ZoneTierList(zoneId: string, rarity: string): { Dog }
	ensure()
	local z = byZoneTier[zoneId]
	return (z and z[rarity]) or {}
end

-- Tiers that have at least one dog in this zone, in Rarities.Order.
function DogCatalog.ZoneTiers(zoneId: string): { string }
	ensure()
	local out = {}
	local z = byZoneTier[zoneId]
	if z then
		for _, tier in Rarities.Order do
			if z[tier] and #z[tier] > 0 then
				table.insert(out, tier)
			end
		end
	end
	return out
end

function DogCatalog.ZoneDogs(zoneId: string): { Dog }
	ensure()
	local out = {}
	local z = byZoneTier[zoneId]
	if z then
		for _, tier in Rarities.Order do
			for _, d in z[tier] or {} do
				table.insert(out, d)
			end
		end
	end
	return out
end

function DogCatalog.ZoneBaseCount(zoneId: string): number
	return #DogCatalog.ZoneDogs(zoneId)
end

function DogCatalog.Zone(zoneId: string): any
	return zoneById[zoneId]
end

-- Adult $/s including the variant multiplier (no puppy factor, no gamepass).
function DogCatalog.AdultIncome(def: Dog, variant: string?): number
	local mult = 1
	if variant then
		local v = (Rarities.Variants :: any)[variant]
		if v then
			mult = v.IncomeMult
		end
	end
	return (def.Income or 0) * mult
end

return DogCatalog
