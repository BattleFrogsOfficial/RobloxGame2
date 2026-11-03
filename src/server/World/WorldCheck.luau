--!strict
-- Post-build sanity check for the world (runs in Studio from WorldBuilder, and headless from
-- tools/worldcheck/run.luau). Returns a list of human-readable violations; empty = OK.
--
--   1. Every tagged part sits ON its ground: its bottom is not below the surface it stands on
--      (Y = Layout.GroundY for field / plaza / street / yard items, the deck top for platform items).
--      Ground slabs themselves (YardPlot, ZoneBand) and the deck (ThrowPad) must have their TOP on it.
--      Items that rest on something (spots, stands, spawns, waypoints) must have a collidable support
--      directly under their centre whose top is at their bottom (within 0.6 studs).
--   2. No SpawnLocation's standing volume (its footprint, from its top surface to 6 studs above it)
--      intersects another collidable part.
-- Uses only CFrame / Size / CanCollide / HasTag so it also runs under Lune's @lune/roblox.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Layout")) :: any

local WorldCheck = {}

WorldCheck.Tags = { "YardPlot", "YardSign", "DogSpot", "KennelSign", "TrophySpot", "ThrowPad", "QueueSpot",
	"TrainingStation", "ShopStand", "PlazaSpawn", "RunawayArea", "SquirrelPath", "ZoneBand", "DistanceMarker" }

-- tags whose TOP is the walking surface
local SURFACE_TAGS = { YardPlot = true, ZoneBand = true }
-- tags that must rest on a support part
local RESTING_TAGS = { DogSpot = true, TrophySpot = true, ShopStand = true, TrainingStation = true, PlazaSpawn = true,
	RunawayArea = true, QueueSpot = true, SquirrelPath = true }
-- tags that live on the platform deck
local DECK_TAGS = { ThrowPad = true, QueueSpot = true }

local EPS = 0.02
WorldCheck.SpawnClearance = 6

export type Box = { MinX: number, MaxX: number, MinY: number, MaxY: number, MinZ: number, MaxZ: number }

-- world-space AABB of a (possibly rotated) box part
function WorldCheck.Bounds(p: BasePart): Box
	local cf, s = p.CFrame, p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(l.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
	local c = cf.Position
	return { MinX = c.X - ex, MaxX = c.X + ex, MinY = c.Y - ey, MaxY = c.Y + ey, MinZ = c.Z - ez, MaxZ = c.Z + ez }
end

-- strict overlap (touching faces do not count)
function WorldCheck.Overlaps(a: Box, b: Box, eps: number?): boolean
	local e = eps or EPS
	return a.MinX < b.MaxX - e and b.MinX < a.MaxX - e and a.MinY < b.MaxY - e and b.MinY < a.MaxY - e
		and a.MinZ < b.MaxZ - e and b.MinZ < a.MaxZ - e
end

local function fmt(v: number): string
	return string.format("%.2f", v)
end

local function describe(p: Instance): string
	local path = p.Name
	local cur = p.Parent
	local depth = 0
	while cur and depth < 3 and cur.Name ~= "Map" do
		path = cur.Name .. "/" .. path
		cur = cur.Parent
		depth += 1
	end
	return path
end

local function onDeckXZ(x: number, z: number): boolean
	local c: Vector3, s: Vector3 = Layout.Platform.Center, Layout.Platform.Size
	return math.abs(x - c.X) <= s.X / 2 + EPS and math.abs(z - c.Z) <= s.Z / 2 + EPS
end

function WorldCheck.Check(mapRoot: Instance): { string }
	local violations: { string } = {}
	local function add(msg: string)
		table.insert(violations, msg)
	end

	local parts: { BasePart } = {}
	local colliders: { { Part: BasePart, Box: Box } } = {}
	for _, d in mapRoot:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d.CanCollide then
				table.insert(colliders, { Part = d, Box = WorldCheck.Bounds(d) })
			end
		end
	end

	local groundY: number = Layout.GroundY
	local deckY: number = Layout.Platform.Center.Y
	local counts: { [string]: number } = {}

	for _, p in parts do
		for _, tag in WorldCheck.Tags do
			if not p:HasTag(tag) then
				continue
			end
			counts[tag] = (counts[tag] or 0) + 1
			local b = WorldCheck.Bounds(p)
			local cx, cz = (b.MinX + b.MaxX) / 2, (b.MinZ + b.MaxZ) / 2
			local surface = groundY
			if DECK_TAGS[tag] or (onDeckXZ(cx, cz) and b.MinY > deckY - 5) then
				surface = deckY
			end
			if SURFACE_TAGS[tag] or tag == "ThrowPad" then
				if math.abs(b.MaxY - surface) > EPS then
					add(("%s %s: top Y %s should be the walking surface Y %s"):format(tag, describe(p), fmt(b.MaxY), fmt(surface)))
				end
			elseif b.MinY < surface - EPS then
				add(("%s %s: bottom Y %s is below its ground Y %s"):format(tag, describe(p), fmt(b.MinY), fmt(surface)))
			end
			if tag == "QueueSpot" and not onDeckXZ(cx, cz) then
				add(("QueueSpot %s at (%s, %s) is not on the platform deck"):format(describe(p), fmt(cx), fmt(cz)))
			end
			if RESTING_TAGS[tag] then
				local supported = false
				for _, c in colliders do
					local cb = c.Box
					if c.Part ~= p and cx >= cb.MinX and cx <= cb.MaxX and cz >= cb.MinZ and cz <= cb.MaxZ
						and cb.MaxY <= b.MinY + 0.05 and cb.MaxY >= b.MinY - 0.6 then
						supported = true
						break
					end
				end
				if not supported then
					add(("%s %s: nothing collidable directly under it (bottom Y %s at %s, %s)"):format(tag, describe(p),
						fmt(b.MinY), fmt(cx), fmt(cz)))
				end
			end
		end
	end

	-- 2. spawn standing volumes
	for _, p in parts do
		if not p:IsA("SpawnLocation") then
			continue
		end
		local b = WorldCheck.Bounds(p)
		local vol: Box = { MinX = b.MinX, MaxX = b.MaxX, MinY = b.MaxY, MaxY = b.MaxY + WorldCheck.SpawnClearance,
			MinZ = b.MinZ, MaxZ = b.MaxZ }
		for _, c in colliders do
			if c.Part ~= p and WorldCheck.Overlaps(vol, c.Box) then
				add(("SpawnLocation %s: standing volume intersects collidable %s"):format(describe(p), describe(c.Part)))
			end
		end
	end

	-- 3. contract counts the services rely on
	local expect = { ThrowPad = 1, QueueSpot = 5, ShopStand = 1, TrainingStation = 1, YardPlot = Layout.Yards.Count,
		YardSign = Layout.Yards.Count, KennelSign = Layout.Yards.Count, TrophySpot = Layout.Yards.Count,
		DogSpot = Layout.Yards.Count * 12, RunawayArea = 1 }
	for tag, n in expect do
		if (counts[tag] or 0) ~= n then
			add(("tag %s: expected %d tagged parts, found %d"):format(tag, n, counts[tag] or 0))
		end
	end
	if (counts.PlazaSpawn or 0) < 1 then
		add("tag PlazaSpawn: no spawn location")
	end
	if (counts.SquirrelPath or 0) < 2 then
		add("tag SquirrelPath: fewer than 2 waypoints")
	end
	return violations
end

return WorldCheck
