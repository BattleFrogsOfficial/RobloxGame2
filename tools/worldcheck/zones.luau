--!nocheck
-- Headless zone check (Lune 0.8 + @lune/roblox). Executes the real World/Field.luau (and every
-- Zones/<ZoneId>.luau decorator) against @lune/roblox Instances through a small require/service shim, then
-- asserts per zone:
--   * a ZoneBand (tag + ZoneId) with the expected ground material
--   * 15-30 decorations (top-level children of <zone>/Decor with Decor=true), all inside 60 < |x| <= 118,
--     non-colliding
--   * exactly one landmark (Landmark=true), |x| <= 150, tall enough for its distance, and not hidden behind
--     anything nearer when seen from the throwing platform (eye at Y = 45, Z = throw line)
--   * a boundary at the band start (BoundaryKind "Arch" with a >= 130 x 30 opening + a themed gate)
--   * the centre lane |x| <= 60 holds nothing collidable or taller than 1 stud (except the arch board,
--     which must clear 30 studs, and invisible non-colliding non-queryable particle volumes)
--   * the part budget (<= 350 per zone, <= 3000 for the field)
--   * the required ParticleEmitters (snowfall, fireflies, stars + debris, sparkles)
--   * no text outside the arch boards, distance markers and the field-end backdrop
-- Usage (from the repo root):  lune run tools/worldcheck/zones.luau     -> exit 1 on any failure
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

local EXPECT_MATERIAL = {
	Backyard = Enum.Material.Grass, Park = Enum.Material.LeafyGrass, Beach = Enum.Material.Sand,
	Farm = Enum.Material.Ground, Forest = Enum.Material.Grass, SnowyPeaks = Enum.Material.Snow,
	CityRooftops = Enum.Material.Concrete, SpaceStation = Enum.Material.DiamondPlate, MythicMeadow = Enum.Material.Glacier,
}
local REQUIRED_EMITTERS = {
	SnowyPeaks = { "Snowfall" }, Forest = { "Fireflies" }, SpaceStation = { "Stars", "Debris" },
	MythicMeadow = { "Sparkles" },
}
local LANE = Kit.LaneHalf -- 60
local DECOR_MAX = Kit.DecorMaxAbsX -- 118
local LANDMARK_MAX = Kit.LandmarkMaxAbsX -- 150
local ZONE_BUDGET, FIELD_BUDGET = 350, 3000
local EYE = Vector3.new(0, 45, Layout.ThrowLine.Z) -- platform top (Y 40) + head height
-- minimum landmark height by distance of its centre: ~40 near, rising to ~250 at the far end
local function minHeight(dist)
	return math.clamp(36 + dist * 0.07, 36, 240)
end

local fieldMinZ = Layout.ThrowLine.Z
local fieldMaxZ = Layout.Field.MaxZ
local rows = {}
local landmarks = {}

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

	-- ZoneBand
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
	end

	-- decorations
	local decorFolder = zf:FindFirstChild("Decor")
	local n = 0
	if decorFolder then
		for _, c in decorFolder:GetChildren() do
			if c:GetAttribute("Decor") == true then
				n += 1
				local b = bounds(c)
				if b == nil then
					fail(zone.Id, "decor " .. c.Name .. " has no parts")
					continue
				end
				local inner = if b.x0 >= 0 then b.x0 elseif b.x1 <= 0 then -b.x1 else 0
				local outer = math.max(math.abs(b.x0), math.abs(b.x1))
				if inner <= LANE or outer > DECOR_MAX + 1e-3 then
					fail(zone.Id, ("decor %s spans |x| %.1f..%.1f (must be inside %d..%d)"):format(c.Name, inner, outer, LANE, DECOR_MAX))
				end
				if b.z0 < z0 - 1e-3 or b.z1 > z1 + 1e-3 then
					fail(zone.Id, ("decor %s spans z %.1f..%.1f outside the band %d..%d"):format(c.Name, b.z0, b.z1, z0, z1))
				end
				for _, p in parts(c) do
					if p.CanCollide then
						fail(zone.Id, "decor part " .. p:GetFullName() .. " is collidable")
					end
					if not p.Anchored then
						fail(zone.Id, "decor part " .. p:GetFullName() .. " is not anchored")
					end
				end
			end
		end
	end
	row.decor = n
	if n < 15 or n > 30 then
		fail(zone.Id, ("%d decorations (want 15-30)"):format(n))
	end

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
		row.landmark = lm:GetAttribute("LandmarkKind") or lm.Name
		row.height = b.y1
		row.footprint = ("x %.0f..%.0f z %.0f..%.0f"):format(b.x0, b.x1, b.z0, b.z1)
		local outer = math.max(math.abs(b.x0), math.abs(b.x1))
		local inner = if b.x0 >= 0 then b.x0 elseif b.x1 <= 0 then -b.x1 else 0
		if outer > LANDMARK_MAX + 1e-3 then
			fail(zone.Id, ("landmark reaches |x| %.1f (> %d)"):format(outer, LANDMARK_MAX))
		end
		if inner <= LANE then
			fail(zone.Id, "landmark enters the lane")
		end
		if b.z0 < z0 or b.z1 > z1 then
			fail(zone.Id, "landmark leaves its band")
		end
		local need = minHeight((b.z0 + b.z1) / 2 - Layout.ThrowLine.Z)
		if b.y1 < need then
			fail(zone.Id, ("landmark %.0f studs tall, want >= %.0f at this distance"):format(b.y1, need))
		end
		table.insert(landmarks, { zone = zone.Id, inst = lm, b = b })
	end

	-- boundary at the band start
	local arch, gate
	for _, d in zf:GetChildren() do
		if d:GetAttribute("Boundary") == true then
			local b = bounds(d)
			if b and math.abs((b.z0 + b.z1) / 2 - z0) <= 20 then
				if d:GetAttribute("BoundaryKind") == "Arch" then
					arch = d
				else
					gate = d
				end
			end
		end
	end
	if arch == nil then
		fail(zone.Id, "no arch at the band start")
	else
		-- opening: inner faces of the parts that reach the ground, and the lowest part over the lane
		local innerX, lowest = math.huge, math.huge
		for _, p in parts(arch) do
			local a = aabb(p)
			if a.x1 > -LANE and a.x0 < LANE then
				lowest = math.min(lowest, a.y0)
			elseif a.y0 <= 1 then
				innerX = math.min(innerX, if a.x0 > 0 then a.x0 else -a.x1)
			end
		end
		row.opening = ("%.0fx%.0f"):format(innerX * 2, lowest)
		if innerX * 2 < 130 or lowest < 30 then
			fail(zone.Id, ("arch opening %.0f wide x %.0f tall (want >= 130 x 30)"):format(innerX * 2, lowest))
		end
	end
	if gate == nil then
		fail(zone.Id, "no themed gate at the band start")
	else
		row.boundary = "Arch+" .. tostring(gate:GetAttribute("BoundaryKind"))
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
	for _, d in zf:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Rate > 120 then
			fail(zone.Id, ("emitter %s rate %d is too high for phones"):format(d.Name, d.Rate))
		end
	end
end

-- lane: nothing collidable or taller than 1 stud in |x| <= 60 inside the field
local laneHits = 0
for _, p in parts(fieldFolder) do
	local a = aabb(p)
	if a.x1 > -LANE and a.x0 < LANE and a.z1 > fieldMinZ and a.z0 < fieldMaxZ then
		if p:HasTag("ZoneBand") or p:FindFirstAncestor("FieldEnd") then -- ground / the end backdrop beyond MaxZ
			continue
		end
		if p:GetAttribute("ParticleVolume") then
			if p.CanCollide or p.CanQuery or p.Transparency < 1 then
				fail("lane", p:GetFullName() .. " particle volume must be invisible, non-colliding, non-queryable")
			end
			continue
		end
		local archModel = ancestorWith(p, "BoundaryKind")
		if archModel and archModel:GetAttribute("BoundaryKind") == "Arch" then
			if a.y0 < 30 then
				fail("lane", p:GetFullName() .. " (arch) hangs below 30 studs over the lane")
			end
			if p.CanQuery then
				fail("lane", p:GetFullName() .. " (arch) must be CanQuery=false")
			end
			continue
		end
		if p.CanCollide or a.y1 > Layout.GroundY + 1 + 1e-3 then
			laneHits += 1
			if laneHits <= 12 then
				fail("lane", ("%s in the lane: collide=%s top=%.2f x %.1f..%.1f z %.0f"):format(p:GetFullName(),
					tostring(p.CanCollide), a.y1, a.x0, a.x1, a.z0))
			end
		end
	end
end

-- text only on arch boards, distance markers and the field end
for _, d in fieldFolder:GetDescendants() do
	if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
		local ok = ancestorWith(d, "BoundaryKind") ~= nil or d:FindFirstAncestor("DistanceMarkers") ~= nil
			or d:FindFirstAncestor("FieldEnd") ~= nil
		if not ok then
			fail("text", d:GetFullName() .. " carries text outside an arch / marker")
		end
	end
end

-- landmark visibility from the platform: the landmark's top fifth must not be fully hidden behind nearer parts
local function angles(x, y, z)
	local dz = z - EYE.Z
	return math.atan2(x - EYE.X, dz), math.atan2(y - EYE.Y, math.sqrt((x - EYE.X) ^ 2 + dz ^ 2))
end
local allParts = parts(fieldFolder)
local boxes = {}
for _, p in allParts do
	if p.Transparency < 1 then
		table.insert(boxes, { p = p, a = aabb(p) })
	end
end
for _, lm in landmarks do
	local b = lm.b
	local topY0 = b.y1 - (b.y1 - 0) * 0.2
	local nearZ = b.z0
	local azL = angles(b.x0, 0, nearZ)
	local azR = angles(b.x1, 0, nearZ)
	local az0, az1 = math.min(azL, azR), math.max(azL, azR)
	local cx = (b.x0 + b.x1) / 2
	local _, elTop = angles(cx, b.y1, nearZ)
	local _, elLow = angles(cx, topY0, nearZ)
	-- sample 5 azimuths across the landmark; visible if any sample's top fifth is unblocked
	local visible = false
	for k = 0, 4 do
		local az = az0 + (az1 - az0) * (k + 0.5) / 5
		local blocked = false
		for _, bx in boxes do
			local a = bx.a
			if a.z1 < nearZ - 1 and a.z0 > EYE.Z and not bx.p:IsDescendantOf(lm.inst) then
				local zz = math.max(a.z0, EYE.Z + 1)
				local azA = angles(a.x0, 0, zz)
				local azB = angles(a.x1, 0, zz)
				local azC = angles(a.x0, 0, a.z1)
				local azD = angles(a.x1, 0, a.z1)
				local lo = math.min(azA, azB, azC, azD)
				local hi = math.max(azA, azB, azC, azD)
				if az >= lo and az <= hi then
					local _, el = angles((a.x0 + a.x1) / 2, a.y1, zz)
					if el >= elLow + (elTop - elLow) * 0.9 then
						blocked = true
						break
					end
				end
			end
		end
		if not blocked then
			visible = true
			break
		end
	end
	for _, r in rows do
		if r.id == lm.zone then
			r.visible = visible
		end
	end
	if not visible then
		fail(lm.zone, "landmark is hidden from the platform behind nearer parts")
	end
end

local total = #allParts
if total > FIELD_BUDGET then
	fail("field", ("%d parts in the field (budget %d)"):format(total, FIELD_BUDGET))
end
for _, w in warnings do
	fail("warn", w)
end

--------------------------------------------------------------------------------------------------------- report
local function pad(s, n)
	s = tostring(s)
	return if #s >= n then s else s .. string.rep(" ", n - #s)
end
print(pad("zone", 13) .. pad("ground", 13) .. pad("landmark", 16) .. pad("h", 6) .. pad("seen", 5) .. pad("boundary", 16)
	.. pad("opening", 9) .. pad("decor", 6) .. pad("parts", 6) .. "particles")
for _, r in rows do
	print(pad(r.id, 13) .. pad(r.ground or "?", 13) .. pad(r.landmark or "-", 16)
		.. pad(r.height and string.format("%.0f", r.height) or "-", 6) .. pad(if r.visible then "yes" else "NO", 5)
		.. pad(r.boundary or "-", 16) .. pad(r.opening or "-", 9) .. pad(r.decor or 0, 6) .. pad(r.parts or 0, 6)
		.. (r.particles or ""))
end
print("landmark footprints:")
for _, r in rows do
	print("  " .. pad(r.id, 13) .. (r.footprint or "-"))
end
print(("field parts: %d (budget %d)"):format(total, FIELD_BUDGET))
if #failures > 0 then
	print(("\nFAIL: %d problem(s)"):format(#failures))
	for _, f in failures do
		print("  " .. f)
	end
	process.exit(1)
end
print("\nOK: all zone checks passed")
