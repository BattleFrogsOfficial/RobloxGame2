--!strict
-- Post-build sanity check for the world (runs in Studio from WorldBuilder, and headless from
-- tools/worldcheck/run.luau). Returns a list of human-readable violations; empty = OK.
--
-- Two levels: hub items (yards, street, plaza, shop, training, platform deck, spawns) stand on the plateau at
-- Layout.HubY; field items (ZoneBand, DistanceMarker) stand on the field at Layout.GroundY.
--   1. Every tagged part sits ON its surface: its bottom is not below the surface it stands on (HubY for hub
--      tags, the deck top = Layout.ThrowLine.Y for ThrowPad / QueueSpot, GroundY for field tags), it is on the
--      right side of the cliff edge (hub items at Z < ThrowLine.Z, field items at Z >= ThrowLine.Z), and the
--      highest collidable ground under its centre is that surface (within 0.5 studs).
--      Ground slabs themselves (YardPlot, ZoneBand) and the deck (ThrowPad) must have their TOP on it.
--      Items that rest on something (spots, stands, spawns, waypoints) must have a collidable support
--      directly under their centre whose top is at their bottom (within 0.6 studs).
--   2. No tagged part is inside another part: it does not intersect any collidable part (touching faces are fine).
--   3. No SpawnLocation's standing volume (its footprint, from its top surface to 6 studs above it)
--      intersects another collidable part.
--   4. Tag counts the services rely on.
-- Uses only CFrame / Size / CanCollide / HasTag so it also runs under Lune's @lune/roblox.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Layout")) :: any

local WorldCheck = {}

WorldCheck.Tags = { "YardPlot", "YardSign", "DogSpot", "KennelSign", "TrophySpot", "ThrowPad", "QueueSpot",
	"TrainingStation", "ShopStand", "PlazaSpawn", "RunawayArea", "SquirrelPath", "ZoneBand", "DistanceMarker" }

-- tags on the field (Layout.GroundY); every other tag is a hub item on the plateau (Layout.HubY)
WorldCheck.FieldTags = { ZoneBand = true, DistanceMarker = true }
-- tags whose TOP is the walking surface
local SURFACE_TAGS = { YardPlot = true, ZoneBand = true, ThrowPad = true }
-- tags that must rest on a support part
local RESTING_TAGS = { DogSpot = true, TrophySpot = true, ShopStand = true, TrainingStation = true, PlazaSpawn = true,
	RunawayArea = true, QueueSpot = true, SquirrelPath = true }
-- tags that live on the platform deck
local DECK_TAGS = { ThrowPad = true, QueueSpot = true }

local EPS = 0.02
WorldCheck.SpawnClearance = 6
WorldCheck.GroundTolerance = 1.05 -- the ground under an item may sit this far below its surface (underlay / plateau top,
-- 1 stud under the floors)

-- the surface a tagged part stands on
function WorldCheck.SurfaceY(tag: string): number
	if WorldCheck.FieldTags[tag] then
		return Layout.GroundY
	elseif DECK_TAGS[tag] then
		return Layout.ThrowLine.Y
	end
	return Layout.HubY
end

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

function WorldCheck.BoxString(b: Box): string
	return ("x %s..%s y %s..%s z %s..%s"):format(fmt(b.MinX), fmt(b.MaxX), fmt(b.MinY), fmt(b.MaxY), fmt(b.MinZ),
		fmt(b.MaxZ))
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

	local edgeZ: number = Layout.ThrowLine.Z
	local counts: { [string]: number } = {}

	for _, p in parts do
		for _, tag in WorldCheck.Tags do
			if not p:HasTag(tag) then
				continue
			end
			counts[tag] = (counts[tag] or 0) + 1
			local b = WorldCheck.Bounds(p)
			local cx, cz = (b.MinX + b.MaxX) / 2, (b.MinZ + b.MaxZ) / 2
			local surface = WorldCheck.SurfaceY(tag)
			local onField = WorldCheck.FieldTags[tag] == true
			-- right side of the cliff edge
			if onField and b.MinZ < edgeZ - EPS then
				add(("%s %s: field item reaches Z %s, behind the cliff edge Z %s"):format(tag, describe(p), fmt(b.MinZ),
					fmt(edgeZ)))
			elseif not onField and b.MaxZ > edgeZ + EPS then
				add(("%s %s: hub item reaches Z %s, past the cliff edge Z %s"):format(tag, describe(p), fmt(b.MaxZ),
					fmt(edgeZ)))
			end
			if SURFACE_TAGS[tag] then
				if math.abs(b.MaxY - surface) > EPS then
					add(("%s %s: top Y %s should be the walking surface Y %s"):format(tag, describe(p), fmt(b.MaxY), fmt(surface)))
				end
			elseif b.MinY < surface - EPS then
				add(("%s %s: bottom Y %s is below its surface Y %s"):format(tag, describe(p), fmt(b.MinY), fmt(surface)))
			end
			if tag == "QueueSpot" and not onDeckXZ(cx, cz) then
				add(("QueueSpot %s at (%s, %s) is not on the platform deck"):format(describe(p), fmt(cx), fmt(cz)))
			end
			-- the ground under the item is its surface (not the field 40 studs below, not a roof)
			local groundTop = -math.huge
			local groundRef = b.MinY
			if SURFACE_TAGS[tag] then
				groundRef = b.MaxY
			end
			for _, c in colliders do
				local cb = c.Box
				if c.Part ~= p and cx >= cb.MinX and cx <= cb.MaxX and cz >= cb.MinZ and cz <= cb.MaxZ
					and cb.MaxY <= groundRef + 0.05 then
					groundTop = math.max(groundTop, cb.MaxY)
				end
			end
			if SURFACE_TAGS[tag] then
				groundTop = b.MaxY -- the slab IS the ground (checked above)
			end
			if groundTop < surface - WorldCheck.GroundTolerance - EPS then
				add(("%s %s: the ground under it is at Y %s, not its surface Y %s"):format(tag, describe(p),
					if groundTop == -math.huge then "none" else fmt(groundTop), fmt(surface)))
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
			-- 2. not inside another (collidable) part
			for _, c in colliders do
				if c.Part ~= p and WorldCheck.Overlaps(b, c.Box) then
					add(("%s %s (%s) is inside collidable %s"):format(tag, describe(p), WorldCheck.BoxString(b),
						describe(c.Part)))
				end
			end
		end
	end

	-- 3. spawn standing volumes
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

	-- 4. contract counts the services rely on
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
