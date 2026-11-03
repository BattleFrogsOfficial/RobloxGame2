--!nocheck
-- Headless zone check (Lune 0.8 + @lune/roblox). Executes the real World/Field.luau (and every
-- Zones/<ZoneId>.luau decorator) against @lune/roblox Instances through a small require/service shim, then
-- asserts per zone (the plot = the whole field width |x| <= 120 over the zone's distance band):
--   * a ZoneBand (tag + ZoneId) with the expected ground material, inside a Persistent "Ground" model
--   * ground cover: >= 200 one-part items over the whole plot (all three thirds of the width and every quarter
--     of the depth get some), each <= 6 wide / 2.5 tall, CanCollide/CanQuery/CanTouch/CastShadow false, in
--     Atomic CoverCell models; counts ramp up with distance
--   * props: 20-40 Atomic models (Prop=true) inside the plot, non-colliding, non-queryable, anchored; footprints
--     (XZ bounding boxes) >= 6 studs apart edge to edge, and as far from the landmark, boundary line, arch
--     pillars, distance-marker signs and fixed dressing; inside |x| <= 30 (ball-POV corridor) nothing > 10 tall;
--     counts ramp up with distance
--   * exactly one landmark (Persistent, |x| <= 150, tall enough for its distance, top visible from the platform)
--   * a full-width boundary line (every x in -119..119 covered) near the band start, <= 4.5 tall in the first
--     three zones and <= 8 after, plus the side-only name-board arch (nothing in |x| < 70)
--   * the required ParticleEmitters (snowfall, fireflies, stars + debris, sparkles), rates phone-friendly
--   * the part budget (<= 1100 per zone, < 8000 for the field)
-- and field-wide: only the ZoneBand floors collide or answer queries in the landing area; the ball-POV corridor
-- (|x| <= 8, 12..20 studs up) is empty; each zone's ground is mostly visible from the platform camera; text only
-- on the zone-name arch boards; PointLights sparing.
-- Usage (from the repo root):  lune run tools/worldcheck/zones.luau [-- --dump=build/field_parts.json]
--   -> exit 1 on any failure. --dump writes every field part (centre, axes, size, colour, shape) for
--   tools/worldcheck/zones_view.js (renders docs/qa/field/*.png).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local ROOT = string.gsub(process.cwd, "/$", "")
local Instance, Vector3, Vector2, CFrame, Color3, Enum =
	roblox.Instance, roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Color3, roblox.Enum

----------------------------------------------------------------------------------------------------------- shim
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local c = self:FindFirstChild(name)
	if c == nil then
		error("WaitForChild: " .. self:GetFullName() .. "." .. name .. " missing (would yield forever)")
	end
	return c
end)

-- Roblox's Random is not in @lune/roblox: a deterministic Park-Miller stand-in.
local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = math.floor(math.abs(seed or os.time())) % 2147483646 + 1
	return setmetatable({ s = s }, Random)
end
function Random:_next()
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local game = Instance.new("DataModel")
local CollectionShim = {
	AddTag = function(_, inst, tag)
		inst:AddTag(tag)
	end,
	HasTag = function(_, inst, tag)
		return inst:HasTag(tag)
	end,
	RemoveTag = function(_, inst, tag)
		inst:RemoveTag(tag)
	end,
}
local gameProxy = {
	GetService = function(_, name)
		if name == "CollectionService" then
			return CollectionShim
		end
		return game:GetService(name)
	end,
}
local workspace = game:GetService("Workspace")

local warnings = {}
local moduleCache = {}
local env

local function shimRequire(inst)
	if typeof(inst) ~= "Instance" then
		error("shim require: expected a ModuleScript Instance, got " .. typeof(inst))
	end
	local path = inst:GetAttribute("SrcPath")
	if path == nil then
		error("shim require: " .. inst:GetFullName() .. " has no source")
	end
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	local source = fs.readFile(path)
	-- Lune replaces the environment's metatable (globals fallback), so copy the shim globals in directly
	local fenv = { script = inst }
	for k, v in env do
		fenv[k] = v
	end
	local chunk = luau.load(source, { debugName = path, environment = fenv })
	local result = chunk()
	moduleCache[path] = result
	return result
end

env = {
	game = gameProxy,
	workspace = workspace,
	Instance = Instance,
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	BrickColor = roblox.BrickColor,
	Enum = Enum,
	Random = Random,
	task = task,
	require = shimRequire,
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(warnings, table.concat(parts, " "))
	end,
	print = function() end, -- keep the report readable
	typeof = typeof,
}

local function mount(dir, parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			mount(full, folder, entry)
		elseif string.match(entry, "%.luau$") and not string.match(entry, "%.client%.luau$")
			and not string.match(entry, "%.server%.luau$") then
			local ms = Instance.new("ModuleScript")
			ms.Name = string.gsub(entry, "%.luau$", "")
			ms:SetAttribute("SrcPath", full)
			ms.Parent = folder
		end
	end
	folder.Parent = parent
	return folder
end

mount(ROOT .. "/src/shared", game:GetService("ReplicatedStorage"), "Shared")
local server = mount(ROOT .. "/src/server", game:GetService("ServerScriptService"), "Server")
local World = server:FindFirstChild("World")

------------------------------------------------------------------------------------------------------- build
local Field = shimRequire(World:FindFirstChild("Field"))
local Kit = shimRequire(World.Zones:FindFirstChild("Kit"))
local Zones = shimRequire(game:GetService("ReplicatedStorage").Shared.Config:FindFirstChild("Zones"))
local Layout = shimRequire(game:GetService("ReplicatedStorage").Shared.Config:FindFirstChild("Layout"))
local map = Instance.new("Folder")
map.Name = "Map"
local okBuild, errBuild = pcall(Field.Build, map)
if not okBuild then
	print("FAIL Field.Build errored: " .. tostring(errBuild))
	process.exit(1)
end
local fieldFolder = map:FindFirstChild("Field")
local DUMP
for _, a in process.args do
	local v = string.match(a, "^%-%-dump=(.+)$")
	if v then
		DUMP = v
	end
end

------------------------------------------------------------------------------------------------------ geometry
local function aabb(p)
	local cf, s = p.CFrame, p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local r, u, b = cf.RightVector, cf.UpVector, -cf.LookVector
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(b.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(b.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(b.Z) * hz
	local c = cf.Position
	return { x0 = c.X - ex, x1 = c.X + ex, y0 = c.Y - ey, y1 = c.Y + ey, z0 = c.Z - ez, z1 = c.Z + ez }
end

local function parts(inst)
	local out = {}
	if inst:IsA("BasePart") then
		table.insert(out, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function bounds(inst)
	local b
	for _, p in parts(inst) do
		local a = aabb(p)
		if b == nil then
			b = a
		else
			b = { x0 = math.min(b.x0, a.x0), x1 = math.max(b.x1, a.x1), y0 = math.min(b.y0, a.y0),
				y1 = math.max(b.y1, a.y1), z0 = math.min(b.z0, a.z0), z1 = math.max(b.z1, a.z1) }
		end
	end
	return b
end

local function gap(a, b)
	local dx = math.max(0, math.max(a.x0, b.x0) - math.min(a.x1, b.x1))
	local dz = math.max(0, math.max(a.z0, b.z0) - math.min(a.z1, b.z1))
	return math.sqrt(dx * dx + dz * dz)
end

local function ancestorWith(inst, attr)
	local cur = inst
	while cur and cur ~= fieldFolder do
		if cur:GetAttribute(attr) ~= nil then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-------------------------------------------------------------------------------------------------------- checks
local failures = {}
local function fail(zone, msg)
	table.insert(failures, ("[%s] %s"):format(zone, msg))
end
local capped = {}
local function failCapped(key, zone, msg)
	capped[key] = (capped[key] or 0) + 1
	if capped[key] <= 6 then
		fail(zone, msg)
	elseif capped[key] == 7 then
		fail(zone, "... more like the above")
	end
end

local Atomic, Persistent = Enum.ModelStreamingMode.Atomic, Enum.ModelStreamingMode.Persistent
local EXPECT_MATERIAL = {
	Backyard = Enum.Material.Grass, Park = Enum.Material.LeafyGrass, Beach = Enum.Material.Sand,
	Farm = Enum.Material.Ground, Forest = Enum.Material.Grass, SnowyPeaks = Enum.Material.Snow,
	CityRooftops = Enum.Material.Concrete, SpaceStation = Enum.Material.DiamondPlate, MythicMeadow = Enum.Material.Glacier,
}
local REQUIRED_EMITTERS = {
	SnowyPeaks = { "Snowfall" }, Forest = { "Fireflies" }, SpaceStation = { "Stars", "Debris" },
	MythicMeadow = { "Sparkles" },
}
local HALF = Kit.FieldHalf -- 120
local PLOT = Kit.PlotHalf -- 118
local LANDMARK_MAX = Kit.LandmarkMaxAbsX -- 150
local GAP = Kit.PropGap -- 6
local CORRIDOR, CORRIDOR_H = Kit.Corridor, Kit.CorridorMaxH -- 30, 10
local COVER_MIN, PROPS_MIN, PROPS_MAX = 200, 20, 40
local ZONE_BUDGET, FIELD_BUDGET = 1100, 8000
local EYE = Vector3.new(0, 55, 40) -- platform camera (behind and above the deck, looking down +Z)
local function minHeight(dist)
	return math.clamp(36 + dist * 0.07, 36, 240)
end

local fieldMinZ = Layout.ThrowLine.Z
local fieldMaxZ = Layout.Field.MaxZ
local rows = {}
local landmarks = {}
local allProps = {} -- { zone, name, b }
local fixed = {} -- obstacles props must keep GAP from: { name, b }
local prevCover, prevProps = 0, 0

for _, mk in fieldFolder.DistanceMarkers:GetChildren() do
	if mk:IsA("Model") then
		table.insert(fixed, { name = mk.Name, b = bounds(mk) })
		if mk.ModelStreamingMode ~= Atomic then
			failCapped("markerstream", "markers", mk.Name .. " should stream Atomic")
		end
	end
end
local fieldEnd = fieldFolder:FindFirstChild("FieldEnd")
if fieldEnd then
	table.insert(fixed, { name = "FieldEnd", b = bounds(fieldEnd) })
end

for _, zone in Zones do
	local zf = fieldFolder:FindFirstChild(zone.Id)
	local row = { id = zone.Id }
	table.insert(rows, row)
	if zf == nil then
		fail(zone.Id, "zone folder missing")
		continue
	end
	local z0 = Layout.DistanceToZ(zone.MinDistance)
	local z1 = Layout.DistanceToZ(zone.MaxDistance)
	local plotZ0 = math.max(z0, Layout.ThrowLine.Z)

	-- Ground model + ZoneBand
	local ground = zf:FindFirstChild("Ground")
	if ground == nil or not ground:IsA("Model") or ground.ModelStreamingMode ~= Persistent then
		fail(zone.Id, "Ground model missing or not Persistent")
	end
	local band
	for _, d in zf:GetDescendants() do
		if d:IsA("BasePart") and d:HasTag("ZoneBand") then
			band = d
		end
	end
	if band == nil or band:GetAttribute("ZoneId") ~= zone.Id then
		fail(zone.Id, "ZoneBand with ZoneId missing")
	else
		row.ground = band.Material.Name
		if band.Material ~= EXPECT_MATERIAL[zone.Id] then
			fail(zone.Id, ("ZoneBand material %s, expected %s"):format(band.Material.Name, EXPECT_MATERIAL[zone.Id].Name))
		end
		if not band.CanQuery or not band.CanCollide then
			fail(zone.Id, "ZoneBand must collide and answer queries (landing raycast)")
		end
	end
	if ground then
		for _, p in parts(ground) do
			local a = aabb(p)
			if p ~= band and a.y1 - a.y0 > 1 and a.x1 > -HALF and a.x0 < HALF then
				table.insert(fixed, { name = zone.Id .. "/Ground/" .. p.Name, b = a }) -- e.g. the City parapets
			end
		end
	end

	-- ground cover
	local coverFolder = zf:FindFirstChild("Cover")
	local cover = 0
	local thirds, quarters = { 0, 0, 0 }, { 0, 0, 0, 0 }
	if coverFolder == nil then
		fail(zone.Id, "Cover folder missing")
	else
		for _, cell in coverFolder:GetChildren() do
			if not cell:IsA("Model") or cell.ModelStreamingMode ~= Atomic then
				failCapped("cellstream" .. zone.Id, zone.Id, cell.Name .. " is not an Atomic model")
			end
			for _, p in parts(cell) do
				cover += 1
				local a = aabb(p)
				local w = math.max(a.x1 - a.x0, a.z1 - a.z0)
				if p.CanCollide or p.CanQuery or p.CanTouch or p.CastShadow then
					failCapped("coverflags" .. zone.Id, zone.Id, "cover part " .. p:GetFullName() .. " must have CanCollide/CanQuery/CanTouch/CastShadow off")
				end
				if not p.Anchored then
					failCapped("coveranch" .. zone.Id, zone.Id, "cover part " .. p:GetFullName() .. " is not anchored")
				end
				if #p:GetChildren() > 0 then
					failCapped("coverkids" .. zone.Id, zone.Id, "cover part " .. p:GetFullName() .. " has children (one part per item)")
				end
				if w > Kit.CoverMaxW + 1e-3 or a.y1 > Layout.GroundY + Kit.CoverMaxH + 1e-3 then
					failCapped("coversize" .. zone.Id, zone.Id, ("cover part %s too big (%.1f wide, top %.1f)"):format(p:GetFullName(), w, a.y1))
				end
				local cx, cz = (a.x0 + a.x1) / 2, (a.z0 + a.z1) / 2
				if a.x0 < -HALF or a.x1 > HALF or cz < plotZ0 or cz > z1 then
					failCapped("coverplot" .. zone.Id, zone.Id, ("cover part %s at (%.0f, %.0f) is outside the plot"):format(p:GetFullName(), cx, cz))
				end
				local t = math.clamp(math.floor((cx + HALF) / (2 * HALF / 3)) + 1, 1, 3)
				local q = math.clamp(math.floor((cz - plotZ0) / ((z1 - plotZ0) / 4)) + 1, 1, 4)
				thirds[t] += 1
				quarters[q] += 1
			end
		end
	end
	row.cover = cover
	row.density = cover / ((z1 - plotZ0) * 2 * HALF) * 1000
	if cover < COVER_MIN then
		fail(zone.Id, ("%d ground-cover items (want >= %d)"):format(cover, COVER_MIN))
	end
	for i, n in thirds do
		if n < cover * 0.15 then
			fail(zone.Id, ("ground cover misses part of the width (third %d holds %d of %d)"):format(i, n, cover))
		end
	end
	for i, n in quarters do
		if n < cover * 0.1 then
			fail(zone.Id, ("ground cover misses part of the depth (quarter %d holds %d of %d)"):format(i, n, cover))
		end
	end
	if cover < prevCover then
		fail(zone.Id, ("ground cover %d is less than the previous zone's %d (density must ramp up)"):format(cover, prevCover))
	end
	prevCover = cover

	-- props
	local propFolder = zf:FindFirstChild("Props")
	local n, kinds = 0, {}
	local zoneProps = {}
	if propFolder == nil then
		fail(zone.Id, "Props folder missing")
	else
		for _, c in propFolder:GetChildren() do
			if c:GetAttribute("Prop") ~= true then
				fail(zone.Id, "Props/" .. c.Name .. " is not tagged Prop=true")
				continue
			end
			n += 1
			kinds[c:GetAttribute("PropKind") or c.Name] = true
			if not c:IsA("Model") or c.ModelStreamingMode ~= Atomic then
				fail(zone.Id, "prop " .. c.Name .. " is not an Atomic model")
			end
			local b = bounds(c)
			if b == nil then
				fail(zone.Id, "prop " .. c.Name .. " has no parts")
				continue
			end
			if b.x0 < -PLOT - 1e-3 or b.x1 > PLOT + 1e-3 or b.z0 < plotZ0 - 1e-3 or b.z1 > z1 + 1e-3 then
				fail(zone.Id, ("prop %s spans x %.1f..%.1f z %.1f..%.1f, outside the plot"):format(c.Name, b.x0, b.x1, b.z0, b.z1))
			end
			if b.x1 > -CORRIDOR and b.x0 < CORRIDOR and b.y1 > Layout.GroundY + CORRIDOR_H + 1e-3 then
				fail(zone.Id, ("prop %s is %.1f tall inside the ball-POV corridor |x| <= %d (max %d)"):format(c.Name, b.y1, CORRIDOR, CORRIDOR_H))
			end
			for _, p in parts(c) do
				if p.CanCollide or p.CanQuery or p.CanTouch then
					failCapped("propflags" .. zone.Id, zone.Id, "prop part " .. p:GetFullName() .. " must have CanCollide/CanQuery/CanTouch off")
				end
				if not p.Anchored then
					failCapped("propanch" .. zone.Id, zone.Id, "prop part " .. p:GetFullName() .. " is not anchored")
				end
			end
			table.insert(zoneProps, { zone = zone.Id, name = c.Name, b = b })
			table.insert(allProps, { zone = zone.Id, name = c.Name, b = b })
		end
	end
	row.props = n
	local kindList = {}
	for k in kinds do
		table.insert(kindList, k)
	end
	row.kinds = #kindList
	if n < PROPS_MIN or n > PROPS_MAX then
		fail(zone.Id, ("%d props (want %d-%d)"):format(n, PROPS_MIN, PROPS_MAX))
	end
	if n < prevProps then
		fail(zone.Id, ("%d props, fewer than the previous zone's %d (density must ramp up)"):format(n, prevProps))
	end
	prevProps = n
	if #kindList < 5 then
		fail(zone.Id, ("only %d prop kinds (want >= 5 distinct silhouettes)"):format(#kindList))
	end
	local minGap = math.huge
	for i = 1, #zoneProps do
		for j = i + 1, #zoneProps do
			minGap = math.min(minGap, gap(zoneProps[i].b, zoneProps[j].b))
		end
	end
	row.minGap = minGap

	-- landmark
	local lms = {}
	for _, d in zf:GetDescendants() do
		if d:GetAttribute("Landmark") == true then
			table.insert(lms, d)
		end
	end
	if #lms ~= 1 then
		fail(zone.Id, ("%d landmarks (want exactly 1)"):format(#lms))
	end
	local lm = lms[1]
	if lm then
		local b = bounds(lm)
		table.insert(fixed, { name = zone.Id .. "/landmark", b = b })
		row.landmark = lm:GetAttribute("LandmarkKind") or lm.Name
		row.height = b.y1
		row.footprint = ("x %.0f..%.0f z %.0f..%.0f"):format(b.x0, b.x1, b.z0, b.z1)
		if lm.ModelStreamingMode ~= Persistent then
			fail(zone.Id, "landmark must be Persistent (seen from the platform at any distance)")
		end
		local outer = math.max(math.abs(b.x0), math.abs(b.x1))
		local inner = if b.x0 >= 0 then b.x0 elseif b.x1 <= 0 then -b.x1 else 0
		if outer > LANDMARK_MAX + 1e-3 then
			fail(zone.Id, ("landmark reaches |x| %.1f (> %d)"):format(outer, LANDMARK_MAX))
		end
		if inner <= Kit.LaneHalf then
			fail(zone.Id, "landmark reaches into the landing area |x| <= 60")
		end
		if b.z0 < z0 or b.z1 > z1 then
			fail(zone.Id, "landmark leaves its band")
		end
		local need = minHeight((b.z0 + b.z1) / 2 - Layout.ThrowLine.Z)
		if b.y1 < need then
			fail(zone.Id, ("landmark %.0f studs tall, want >= %.0f at this distance"):format(b.y1, need))
		end
		for _, p in parts(lm) do
			if p.CanCollide or p.CanQuery then
				failCapped("lmflags" .. zone.Id, zone.Id, "landmark part " .. p:GetFullName() .. " must be CanCollide/CanQuery false")
			end
		end
		table.insert(landmarks, { zone = zone.Id, inst = lm, b = b })
	end

	-- boundary: arch gantry + full-width line
	local arch, line
	for _, d in zf:GetChildren() do
		if d:GetAttribute("Boundary") == true then
			if d:GetAttribute("BoundaryKind") == "Arch" then
				arch = d
			else
				line = d
			end
		end
	end
	if arch == nil then
		fail(zone.Id, "no name-board arch at the band start")
	else
		if arch.ModelStreamingMode ~= Persistent then
			fail(zone.Id, "arch must be Persistent")
		end
		local inner = math.huge
		for _, p in parts(arch) do
			local a = aabb(p)
			inner = math.min(inner, if a.x0 > 0 then a.x0 elseif a.x1 < 0 then -a.x1 else 0)
			if p.CanQuery or p.CanCollide then
				fail(zone.Id, "arch part " .. p.Name .. " must be CanCollide/CanQuery false")
			end
			if a.y0 <= 1 then
				table.insert(fixed, { name = zone.Id .. "/ArchPillar", b = a })
			end
		end
		row.archInner = inner
		if inner < 66 then
			fail(zone.Id, ("arch reaches |x| %.1f; it must stay out of the field centre (|x| >= 66)"):format(inner))
		end
	end
	if line == nil then
		fail(zone.Id, "no full-width boundary line")
	else
		local b = bounds(line)
		table.insert(fixed, { name = zone.Id .. "/Boundary", b = b })
		row.boundary = line:GetAttribute("BoundaryKind")
		row.bheight = b.y1
		if line.ModelStreamingMode ~= Persistent then
			fail(zone.Id, "boundary line must be Persistent")
		end
		if b.z0 < z0 or b.z0 > z0 + 25 then
			fail(zone.Id, ("boundary line at z %.0f..%.0f is not at the band start %d"):format(b.z0, b.z1, z0))
		end
		local maxH = if zone.Order <= 3 then 4.5 else 8
		if b.y1 > Layout.GroundY + maxH then
			fail(zone.Id, ("boundary line %.1f tall (max %.1f here: platform camera / ball arc)"):format(b.y1, maxH))
		end
		local boxes = {}
		for _, p in parts(line) do
			table.insert(boxes, aabb(p))
			if p.CanCollide or p.CanQuery or p.CanTouch then
				failCapped("lineflags" .. zone.Id, zone.Id, "boundary part " .. p.Name .. " must be CanCollide/CanQuery/CanTouch false")
			end
		end
		local holes = 0
		for x = -HALF + 1, HALF - 1 do
			local hit = false
			for _, a in boxes do
				if x >= a.x0 and x <= a.x1 then
					hit = true
					break
				end
			end
			if not hit then
				holes += 1
			end
		end
		if holes > 0 then
			fail(zone.Id, ("boundary line leaves %d one-stud gaps across the field width"):format(holes))
		end
	end

	-- parts budget
	local count = #parts(zf)
	row.parts = count
	if count > ZONE_BUDGET then
		fail(zone.Id, ("%d parts (budget %d)"):format(count, ZONE_BUDGET))
	end

	-- emitters
	local names = {}
	for _, d in zf:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			names[d.Name] = (names[d.Name] or 0) + 1
			if d.Rate > 120 then
				fail(zone.Id, ("emitter %s rate %d is too high for phones"):format(d.Name, d.Rate))
			end
		end
	end
	local list = {}
	for k in names do
		table.insert(list, k)
	end
	table.sort(list)
	row.particles = table.concat(list, ",")
	for _, need in REQUIRED_EMITTERS[zone.Id] or {} do
		if names[need] == nil then
			fail(zone.Id, "missing ParticleEmitter " .. need)
		end
	end
end

-- spacing: every prop vs every other prop (all zones) and vs the fixed obstacles
local rowById = {}
for _, r in rows do
	rowById[r.id] = r
end
for i = 1, #allProps do
	local a = allProps[i]
	for j = i + 1, #allProps do
		local b = allProps[j]
		local g = gap(a.b, b.b)
		if g < GAP - 1e-3 then
			failCapped("spacing", a.zone, ("props %s and %s/%s are %.2f studs apart (want >= %d)"):format(a.name, b.zone, b.name, g, GAP))
		end
	end
	for _, f in fixed do
		local g = gap(a.b, f.b)
		local r = rowById[a.zone]
		r.minFixed = math.min(r.minFixed or math.huge, g)
		if g < GAP - 1e-3 then
			failCapped("spacingfixed", a.zone, ("prop %s is %.2f studs from %s (want >= %d)"):format(a.name, g, f.name, GAP))
		end
	end
end

-- landing area: only ZoneBand floors collide or answer queries (|x| <= 60 over the field)
local allParts = parts(fieldFolder)
local LANDING = Kit.LaneHalf
local bad = 0
for _, p in allParts do
	local a = aabb(p)
	if a.x1 > -LANDING and a.x0 < LANDING and a.z1 > fieldMinZ and a.z0 < fieldMaxZ then
		if p:HasTag("ZoneBand") or p:FindFirstAncestor("FieldEnd") then
			continue
		end
		if p.CanCollide or p.CanQuery then
			bad += 1
			if bad <= 8 then
				fail("landing", ("%s collide=%s query=%s in the landing area"):format(p:GetFullName(), tostring(p.CanCollide), tostring(p.CanQuery)))
			end
		end
	end
	if p:GetAttribute("ParticleVolume") and (p.CanCollide or p.CanQuery or p.Transparency < 1) then
		fail("particles", p:GetFullName() .. " particle volume must be invisible, non-colliding, non-queryable")
	end
end

-- ball-POV corridor: the cutscene camera follows the ball ~15 studs up along x ~ 0
local povHits = 0
for _, p in allParts do
	if p.Transparency >= 1 then
		continue
	end
	local a = aabb(p)
	if a.x1 > -8 and a.x0 < 8 and a.y1 > 12 and a.y0 < 20 and a.z1 > fieldMinZ and a.z0 < fieldMaxZ - 1 then
		povHits += 1
		if povHits <= 6 then
			fail("pov", p:GetFullName() .. " sits in the ball-POV corridor (|x| <= 8, y 12..20)")
		end
	end
end

-- text only on the zone-name arch boards
for _, d in fieldFolder:GetDescendants() do
	if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
		local m = ancestorWith(d, "BoundaryKind")
		if m == nil or m:GetAttribute("BoundaryKind") ~= "Arch" then
			fail("text", d:GetFullName() .. " carries text outside a zone arch board")
		end
	end
end

-- PointLights sparingly
local lights = 0
for _, d in fieldFolder:GetDescendants() do
	if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
		lights += 1
	end
end
if lights > 12 then
	fail("lights", ("%d lights in the field (max 12 for phones)"):format(lights))
end

-- visibility from the platform camera
local solid = {}
for _, p in allParts do
	if p.Transparency < 1 then
		local a = aabb(p)
		if a.y1 > Layout.GroundY + 1 and not p:FindFirstAncestor("FieldEnd") then
			table.insert(solid, { p = p, a = a })
		end
	end
end
local function rayHitsBox(o, d, a)
	local tmin, tmax = 0, 1
	for _, ax in { { "X", "x0", "x1" }, { "Y", "y0", "y1" }, { "Z", "z0", "z1" } } do
		local oc, dc, lo, hi = o[ax[1]], d[ax[1]], a[ax[2]], a[ax[3]]
		if math.abs(dc) < 1e-9 then
			if oc < lo or oc > hi then
				return false
			end
		else
			local t1, t2 = (lo - oc) / dc, (hi - oc) / dc
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then
				return false
			end
		end
	end
	return true
end
-- ground of each zone: sight lines from the platform camera to points spread over the zone's plot must first hit
-- something of THAT zone (its ground, cover, props, boundary or landmark), not a nearer zone's props
local function zoneOf(p, a)
	local cur = p
	while cur.Parent and cur.Parent ~= fieldFolder do
		cur = cur.Parent
	end
	if cur.Name == "DistanceMarkers" then -- a marker sign belongs to the zone it stands in
		local zc = (a.z0 + a.z1) / 2 - Layout.ThrowLine.Z
		for _, zone in Zones do
			if zc >= zone.MinDistance and zc < zone.MaxDistance then
				return zone.Id
			end
		end
	end
	return cur.Name
end
local hitAll = {}
for _, p in allParts do
	if p.Transparency < 1 and not p:FindFirstAncestor("FieldEnd") then
		table.insert(hitAll, { p = p, a = aabb(p) })
	end
end
local function firstT(o, d, a)
	local tmin, tmax = 0, 1
	for _, ax in { { "X", "x0", "x1" }, { "Y", "y0", "y1" }, { "Z", "z0", "z1" } } do
		local oc, dc, lo, hi = o[ax[1]], d[ax[1]], a[ax[2]], a[ax[3]]
		if math.abs(dc) < 1e-9 then
			if oc < lo or oc > hi then
				return nil
			end
		else
			local t1, t2 = (lo - oc) / dc, (hi - oc) / dc
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end
for _, zone in Zones do
	local z0 = math.max(Layout.DistanceToZ(zone.MinDistance), fieldMinZ + 10)
	local z1 = Layout.DistanceToZ(zone.MaxDistance)
	local own, samples = 0, 0
	for _, fz in { 0.2, 0.5, 0.8 } do
		for _, x in { -80, -40, 0, 40, 80 } do
			samples += 1
			local target = Vector3.new(x, Layout.GroundY - 0.05, z0 + (z1 - z0) * fz)
			local dir = target - EYE
			local best, bestB = math.huge, nil
			for _, bx in hitAll do
				if not bx.p:HasTag("ZoneBand") and bx.a.z1 > EYE.Z then
					local t = firstT(EYE, dir, bx.a)
					if t and t < best then
						best, bestB = t, bx
					end
				end
			end
			local hitZone = if bestB then zoneOf(bestB.p, bestB.a) else zone.Id
			if hitZone == zone.Id then
				own += 1
			elseif process.env.ZDEBUG then
				print(("  [%s] sight (%d, %.0f) first hits %s"):format(zone.Id, x, target.Z, bestB.p:GetFullName()))
			end
		end
	end
	rowById[zone.Id].groundSeen = ("%d/%d"):format(own, samples)
	-- beyond ~1000 studs the sight lines graze the ground (about 8 studs up over the zone before), so far zones
	-- are told apart by their prop tops + landmark instead (checked below)
	if zone.MinDistance < 1000 and own / samples < 0.6 then
		fail(zone.Id, ("only %d/%d platform sight lines into the zone land on the zone itself"):format(own, samples))
	end
	-- prop tops: at least half of the zone's props must show their top to the platform camera
	local seenTops, tops = 0, 0
	for _, pr in allProps do
		if pr.zone == zone.Id then
			tops += 1
			local target = Vector3.new((pr.b.x0 + pr.b.x1) / 2, pr.b.y1 - 0.1, (pr.b.z0 + pr.b.z1) / 2)
			local dir = target - EYE
			local best, bestB = math.huge, nil
			for _, bx in hitAll do
				if not bx.p:HasTag("ZoneBand") and bx.a.z1 > EYE.Z then
					local t = firstT(EYE, dir, bx.a)
					if t and t < best - 1e-3 then
						best, bestB = t, bx
					end
				end
			end
			if bestB == nil or zoneOf(bestB.p, bestB.a) == zone.Id then
				seenTops += 1
			end
		end
	end
	rowById[zone.Id].topsSeen = ("%d/%d"):format(seenTops, tops)
	if tops > 0 and seenTops / tops < 0.5 then
		fail(zone.Id, ("only %d/%d prop tops are visible from the platform camera"):format(seenTops, tops))
	end
end
-- landmark tops: >= 30% of the sight lines to the parts in the top quarter must be clear
for _, lm in landmarks do
	local b = lm.b
	local seen, total = 0, 0
	for _, p in parts(lm.inst) do
		local a = aabb(p)
		if (a.y0 + a.y1) / 2 >= b.y1 * 0.75 then
			for _, target in { Vector3.new((a.x0 + a.x1) / 2, (a.y0 + a.y1) / 2, a.z0 + 0.05),
				Vector3.new((a.x0 + a.x1) / 2, a.y1 - 0.05, a.z0 + 0.05) } do
				total += 1
				local dir = target - EYE
				local hit = false
				for _, bx in solid do
					if bx.a.z0 < b.z0 and not bx.p:IsDescendantOf(lm.inst) and rayHitsBox(EYE, dir, bx.a) then
						hit = true
						break
					end
				end
				if not hit then
					seen += 1
				end
			end
		end
	end
	rowById[lm.zone].seenRays = ("%d/%d"):format(seen, total)
	if seen < math.max(1, math.ceil(total * 0.3)) then
		fail(lm.zone, ("landmark top hidden from the platform (%d/%d sight lines clear)"):format(seen, total))
	end
end

local total = #allParts
if total >= FIELD_BUDGET then
	fail("field", ("%d parts in the field (budget < %d)"):format(total, FIELD_BUDGET))
end
for _, w in warnings do
	fail("warn", w)
end

----------------------------------------------------------------------------------------------------------- dump
if DUMP then
	local shapeOf = function(p)
		if p:IsA("WedgePart") then
			return "Wedge"
		elseif p:IsA("CornerWedgePart") then
			return "Corner"
		elseif p:IsA("Part") then
			if p:FindFirstChildOfClass("SpecialMesh") then
				return "Ellipsoid"
			end
			local sh = p.Shape
			if sh == Enum.PartType.Ball then
				return "Ball"
			elseif sh == Enum.PartType.Cylinder then
				return "Cylinder"
			end
		end
		return "Block"
	end
	local out = {}
	local function r3(v)
		return math.floor(v * 1000 + 0.5) / 1000
	end
	for _, p in allParts do
		if p.Transparency >= 1 then
			continue
		end
		local cf = p.CFrame
		local c, rx, ry, rz = cf.Position, cf.RightVector, cf.UpVector, -cf.LookVector
		local col = p.Color
		local layer = if p:FindFirstAncestor("Cover") then "cover" elseif ancestorWith(p, "Prop") then "prop"
			elseif ancestorWith(p, "Landmark") then "landmark" elseif ancestorWith(p, "Boundary") then "boundary" else "ground"
		table.insert(out, string.format(
			'{"c":[%s,%s,%s],"x":[%s,%s,%s],"y":[%s,%s,%s],"z":[%s,%s,%s],"s":[%s,%s,%s],"col":[%d,%d,%d],"sh":"%s","t":%s,"m":"%s","l":"%s"}',
			r3(c.X), r3(c.Y), r3(c.Z), r3(rx.X), r3(rx.Y), r3(rx.Z), r3(ry.X), r3(ry.Y), r3(ry.Z), r3(rz.X), r3(rz.Y), r3(rz.Z),
			r3(p.Size.X), r3(p.Size.Y), r3(p.Size.Z), math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5),
			math.floor(col.B * 255 + 0.5), shapeOf(p), r3(p.Transparency), p.Material.Name, layer))
	end
	local zonesJson = {}
	for _, zone in Zones do
		table.insert(zonesJson, string.format('{"id":"%s","z0":%d,"z1":%d}', zone.Id, Layout.DistanceToZ(zone.MinDistance),
			Layout.DistanceToZ(zone.MaxDistance)))
	end
	fs.writeFile(DUMP, '{"zones":[' .. table.concat(zonesJson, ",") .. '],"parts":[' .. table.concat(out, ",\n") .. "]}")
	print("dumped " .. #out .. " parts to " .. DUMP)
end

--------------------------------------------------------------------------------------------------------- report
local function pad(s, n)
	s = tostring(s)
	return if #s >= n then s else s .. string.rep(" ", n - #s)
end
local function f1(v)
	return if v == nil or v == math.huge then "-" else string.format("%.1f", v)
end
print(pad("zone", 13) .. pad("ground", 13) .. pad("cover", 6) .. pad("/1k", 5) .. pad("props", 6) .. pad("kinds", 6)
	.. pad("gap", 6) .. pad("fixed", 6) .. pad("landmark", 15) .. pad("h", 5) .. pad("seen", 7) .. pad("grnd", 6)
	.. pad("tops", 6) .. pad("boundary", 10) .. pad("bh", 5) .. pad("parts", 6) .. "particles")
for _, r in rows do
	print(pad(r.id, 13) .. pad(r.ground or "?", 13) .. pad(r.cover or 0, 6) .. pad(f1(r.density), 5) .. pad(r.props or 0, 6)
		.. pad(r.kinds or 0, 6) .. pad(f1(r.minGap), 6) .. pad(f1(r.minFixed), 6) .. pad(r.landmark or "-", 15)
		.. pad(r.height and string.format("%.0f", r.height) or "-", 5) .. pad(r.seenRays or "NO", 7) .. pad(r.groundSeen or "-", 6)
		.. pad(r.topsSeen or "-", 6) .. pad(r.boundary or "-", 10) .. pad(f1(r.bheight), 5) .. pad(r.parts or 0, 6) .. (r.particles or ""))
end
print("landmark footprints:")
for _, r in rows do
	print("  " .. pad(r.id, 13) .. (r.footprint or "-"))
end
print(("field parts: %d (budget < %d), lights %d"):format(total, FIELD_BUDGET, lights))
if #failures > 0 then
	print(("\nFAIL: %d problem(s)"):format(#failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print("\nOK: all zone checks passed")
