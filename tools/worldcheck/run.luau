--!nocheck
-- Headless world check. Builds the REAL world (src/server/World + src/shared) with Lune's @lune/roblox
-- instances, then runs:
--   * WorldCheck.Check (tagged parts on their ground, spawn standing volumes clear, tag counts)
--   * area overlap checks (yards / street / plaza / platform / ramp / shop / training / spawns / lawn / walls)
--   * walls: outside the field + margin, >= 200 studs tall, part budget, no overlap with gameplay parts
--   * landing lane |x| <= 56 over the field: nothing of ours in it (Field-owned items are reported apart)
--   * camera box above/behind the thrower + ball launch: nothing in the way, front railing below launch
--   * walking path lengths (grid shortest path around collidable obstacles + the ramp) between every
--     yard gate, the platform throw spot, the ball shop and the training area: must be <= 300 studs
-- Usage (from the repo root):
--   lune run tools/worldcheck/run.luau -- [--no-field] [--quiet] [--dump=parts.json]
-- Exit code 1 on any failure.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local ARGS = {}
for _, a in process.args do
	ARGS[a] = true
end
local NO_FIELD = ARGS["--no-field"] == true
local DUMP = nil -- --dump=<file.json>: write every part's world AABB + colour (for a quick top-down preview)
for _, a in process.args do
	local d = string.match(a, "^%-%-dump=(.+)$")
	if d then
		DUMP = d
	end
end
local QUIET = ARGS["--quiet"] == true

local ROOT = string.gsub(process.cwd, "/$", "")
if not fs.isDir(ROOT .. "/src/server/World") then
	print("run from the repository root")
	process.exit(2)
end

----------------------------------------------------------------------------------------------------
-- Roblox shim
----------------------------------------------------------------------------------------------------
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local c = self:FindFirstChild(name)
	if c == nil then
		error(("WaitForChild: %s has no child %q (headless: would wait forever)"):format(self:GetFullName(), name), 2)
	end
	return c
end)

-- the world is built on the server
roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("RunService", "IsClient", function()
	return false
end)

local dm = roblox.Instance.new("DataModel")
local Workspace = dm:GetService("Workspace")
local ReplicatedStorage = dm:GetService("ReplicatedStorage")
local ServerScriptService = dm:GetService("ServerScriptService")
local LightingService = dm:GetService("Lighting")

local CollectionService = {}
function CollectionService.AddTag(_, inst, tag)
	inst:AddTag(tag)
end
function CollectionService.RemoveTag(_, inst, tag)
	inst:RemoveTag(tag)
end
function CollectionService.HasTag(_, inst, tag)
	return inst:HasTag(tag)
end
function CollectionService.GetTags(_, inst)
	return inst:GetTags()
end
function CollectionService.GetTagged(_, tag)
	local out = {}
	for _, d in dm:GetDescendants() do
		if d:HasTag(tag) then
			table.insert(out, d)
		end
	end
	return out
end

local game = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				if name == "CollectionService" then
					return CollectionService
				end
				return dm:GetService(name)
			end
		end
		return dm[k]
	end,
})

-- deterministic stand-in for Roblox's Random (xorshift-ish LCG; values differ from Roblox, shapes do not)
local Random = {}
Random.__index = Random
function Random.new(seed)
	local self = setmetatable({}, Random)
	self.s = (math.floor(seed or os.clock() * 1e6) % 2147483646) + 1
	return self
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

local warnings = {}
local function warnFn(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	local msg = table.concat(parts, " ")
	table.insert(warnings, msg)
	if not QUIET then
		print("  [warn] " .. msg)
	end
end

local taskShim = {
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	delay = function() end,
	wait = function()
		return 0
	end,
}

local baseEnv = {
	game = game,
	workspace = Workspace,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Random = Random,
	task = taskShim,
	warn = warnFn,
	print = function(...)
		if not QUIET then
			print(...)
		end
	end,
	tick = os.clock,
	time = os.clock,
}
for k, v in roblox do
	if type(k) == "string" and string.match(k, "^%u") and baseEnv[k] == nil then
		baseEnv[k] = v
	end
end

-- mount a directory as Folder/ModuleScript instances (Rojo-style: init.luau makes the folder a module).
-- The source path rides on an attribute (Lune userdata wrappers are not stable table keys).
local function setSource(ms, path)
	ms:SetAttribute("__SourcePath", path)
end
local function mount(dir, parent, name, skip)
	local initPath = dir .. "/init.luau"
	local node
	if fs.isFile(initPath) then
		node = roblox.Instance.new("ModuleScript")
		setSource(node, initPath)
	else
		node = roblox.Instance.new("Folder")
	end
	node.Name = name
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if skip and skip[path] then
			continue
		end
		if fs.isDir(path) then
			mount(path, node, entry, skip)
		elseif string.match(entry, "%.luau$") and entry ~= "init.luau" and not string.match(entry, "%.server%.luau$")
			and not string.match(entry, "%.client%.luau$") then
			local ms = roblox.Instance.new("ModuleScript")
			ms.Name = string.gsub(entry, "%.luau$", "")
			setSource(ms, path)
			ms.Parent = node
		end
	end
	node.Parent = parent
	return node
end

local STD = { math = math, string = string, table = table, os = os, utf8 = utf8, bit32 = bit32, buffer = buffer,
	coroutine = coroutine, type = type, typeof = typeof, pairs = pairs, ipairs = ipairs, next = next, select = select,
	tostring = tostring, tonumber = tonumber, error = error, assert = assert, pcall = pcall, xpcall = xpcall,
	setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
	rawlen = rawlen, unpack = unpack, newproxy = newproxy }

local cache = {}
local requireFn
requireFn = function(ms)
	if type(ms) == "string" then
		error("string require not supported headless: " .. ms, 2)
	end
	local path = typeof(ms) == "Instance" and ms:GetAttribute("__SourcePath")
	if not path then
		error("require: not a mounted ModuleScript: " .. tostring(ms), 2)
	end
	if cache[path] ~= nil then
		return cache[path]
	end
	-- a plain table (no __index): Luau resolves imported globals at load time
	local env = { script = ms, require = requireFn }
	for k, v in STD do
		env[k] = v
	end
	for k, v in baseEnv do
		env[k] = v
	end
	local fn = luau.load(fs.readFile(path), { debugName = string.sub(path, #ROOT + 2), environment = env })
	local result = fn()
	cache[path] = result
	return result
end

local skip = {}
if NO_FIELD then
	skip[ROOT .. "/src/server/World/Field.luau"] = true
	skip[ROOT .. "/src/server/World/Zones"] = true
end
local Shared = mount(ROOT .. "/src/shared", ReplicatedStorage, "Shared")
local Server = roblox.Instance.new("Folder")
Server.Name = "Server"
Server.Parent = ServerScriptService
local WorldFolder = mount(ROOT .. "/src/server/World", Server, "World", skip)

local Layout = requireFn(Shared.Config.Layout)
local Zones = requireFn(Shared.Config.Zones)
local WorldBuilder = requireFn(WorldFolder.WorldBuilder)
local WorldCheck = requireFn(WorldFolder.WorldCheck)

----------------------------------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------------------------------
if NO_FIELD then
	WorldBuilder.SkipSteps.Field = true
end
WorldBuilder.RunCheck = false -- we run it below and report it ourselves
-- the client's zone colour grading must survive the server's Lighting.Apply (it adopts effects by name only)
local clientCC = roblox.Instance.new("ColorCorrectionEffect")
clientCC.Name = "ZoneAmbienceCC"
clientCC.Parent = LightingService
local okBuild, map = pcall(WorldBuilder.Build)
if not okBuild then
	print("FATAL: WorldBuilder.Build errored: " .. tostring(map))
	process.exit(1)
end

local failures = {}
local notes = {}
local function fail(msg)
	table.insert(failures, msg)
end
local function note(msg)
	table.insert(notes, msg)
end

local fieldProblems = {}
for _, w in warnings do
	if string.find(w, "Field failed", 1, true) or string.find(w, "zone decorator", 1, true) then
		table.insert(fieldProblems, w)
	elseif string.find(w, "failed", 1, true) then
		fail("build step error: " .. w)
	end
end

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------
local Bounds = WorldCheck.Bounds
local Overlaps = WorldCheck.Overlaps

local function fmt(v)
	return string.format("%.1f", v)
end
local function boxStr(b)
	return ("x %s..%s y %s..%s z %s..%s"):format(fmt(b.MinX), fmt(b.MaxX), fmt(b.MinY), fmt(b.MaxY), fmt(b.MinZ), fmt(b.MaxZ))
end
local function union(a, b)
	if not a then
		return table.clone(b)
	end
	return { MinX = math.min(a.MinX, b.MinX), MaxX = math.max(a.MaxX, b.MaxX), MinY = math.min(a.MinY, b.MinY),
		MaxY = math.max(a.MaxY, b.MaxY), MinZ = math.min(a.MinZ, b.MinZ), MaxZ = math.max(a.MaxZ, b.MaxZ) }
end
local function boundsOf(inst)
	local b = nil
	if inst:IsA("BasePart") then
		b = Bounds(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			b = union(b, Bounds(d))
		end
	end
	return b
end
local function overlapsXZ(a, b, eps)
	local e = eps or 0.02
	return a.MinX < b.MaxX - e and b.MinX < a.MaxX - e and a.MinZ < b.MaxZ - e and b.MinZ < a.MaxZ - e
end
local function insideXZ(inner, outer, eps)
	local e = eps or 0.02
	return inner.MinX >= outer.MinX - e and inner.MaxX <= outer.MaxX + e and inner.MinZ >= outer.MinZ - e
		and inner.MaxZ <= outer.MaxZ + e
end
local function rect(r, y0, y1)
	return { MinX = r.MinX, MaxX = r.MaxX, MinZ = r.MinZ, MaxZ = r.MaxZ, MinY = y0 or -1, MaxY = y1 or 0 }
end
local function isUnder(inst, ancestor)
	return ancestor ~= nil and inst:IsDescendantOf(ancestor)
end
local function pathOf(inst)
	local s = inst.Name
	local cur = inst.Parent
	while cur and cur ~= map do
		s = cur.Name .. "/" .. s
		cur = cur.Parent
	end
	return s
end

local allParts = {}
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(allParts, { Part = d, Box = Bounds(d) })
	end
end

local F = {
	Field = map:FindFirstChild("Field"),
	Walls = map:FindFirstChild("Walls"),
	Platform = map:FindFirstChild("Platform"),
	Plaza = map:FindFirstChild("Plaza"),
	Yards = map:FindFirstChild("Yards"),
	Street = map:FindFirstChild("Street"),
	Outskirts = map:FindFirstChild("Outskirts"),
	Boundaries = map:FindFirstChild("Boundaries"),
	ThrowLine = map:FindFirstChild("ThrowLine"),
}
for k, v in F do
	if v == nil and not (k == "Field" and NO_FIELD) then
		fail("map folder missing: " .. k)
	end
end

----------------------------------------------------------------------------------------------------
-- 1. WorldCheck
----------------------------------------------------------------------------------------------------
if clientCC.Name ~= "ZoneAmbienceCC" or clientCC.Parent ~= LightingService then
	fail("Lighting.Apply renamed or moved the client's ZoneAmbienceCC")
end
if LightingService:FindFirstChildOfClass("Atmosphere") == nil then
	fail("Lighting.Apply created no Atmosphere (haze)")
end

local violations = WorldCheck.Check(map)
for _, v in violations do
	fail("WorldCheck: " .. v)
end

-- World text rule: the only text in the world is on the zone-name arch boards (BoundaryKind "Arch"), the
-- yard owner signs (OwnerLabel) and the kennel count (CountLabel).
for _, d in map:GetDescendants() do
	if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
		local allowed = d.Name == "OwnerLabel" or d.Name == "CountLabel"
		local a = d.Parent
		while not allowed and a and a ~= map do
			if a:GetAttribute("BoundaryKind") == "Arch" then
				allowed = true
			end
			a = a.Parent
		end
		if not allowed then
			fail("world text outside an arch board / yard sign / kennel count: " .. d:GetFullName() .. " = " .. tostring(d.Text))
		end
	end
end

----------------------------------------------------------------------------------------------------
-- 2. Area overlaps
----------------------------------------------------------------------------------------------------
local areas = {}
for i = 1, Layout.Yards.Count do
	local hw, hd = Layout.Yards.Size.X / 2, Layout.Yards.Size.Z / 2
	local cx, cz = Layout.Yards.CentersX[i], Layout.Yards.CenterZ
	areas["Yard" .. i] = { MinX = cx - hw, MaxX = cx + hw, MinZ = cz - hd, MaxZ = cz + hd, MinY = -1, MaxY = 0 }
	local model = F.Yards and F.Yards:FindFirstChild("Yard" .. i)
	if model then
		local b = boundsOf(model)
		if not insideXZ(b, areas["Yard" .. i]) then
			fail(("Yard%d contents (%s) spill outside the yard plot"):format(i, boxStr(b)))
		end
	end
end
areas.Street = rect(Layout.Street)
areas.Plaza = rect(Layout.Plaza)
areas.Field = rect(Layout.Field)
-- floors tile without overlapping
local floorNames = { "Street", "Plaza", "Field" }
for i = 1, Layout.Yards.Count do
	table.insert(floorNames, "Yard" .. i)
end
for i = 1, #floorNames do
	for j = i + 1, #floorNames do
		local a, b = areas[floorNames[i]], areas[floorNames[j]]
		if overlapsXZ(a, b) then
			fail(("floor areas overlap: %s and %s"):format(floorNames[i], floorNames[j]))
		end
	end
end
if Layout.Field.MinZ ~= Layout.ThrowLine.Z then
	fail("Layout.Field.MinZ must equal Layout.ThrowLine.Z")
end

-- plaza features
local feats = {}
local function feat(name, inst)
	if inst == nil then
		fail("missing feature: " .. name)
		return
	end
	feats[name] = { Inst = inst, Box = boundsOf(inst) }
end
local plat = F.Platform
local function find(root, name)
	return root and root:FindFirstChild(name, true)
end
local towerParts = {}
if plat then
	for _, n in { "Tower", "Deck" } do
		local p = plat:FindFirstChild(n)
		if p then
			table.insert(towerParts, p)
		end
	end
end
if #towerParts > 0 then
	local b
	for _, p in towerParts do
		b = union(b, Bounds(p))
	end
	feats.Platform = { Box = b }
else
	fail("missing feature: Platform tower/deck")
end
feat("Ramp", find(plat, "Ramp"))
feat("Shop", find(F.Plaza, "Shop_Balls"))
feat("Training", find(F.Plaza, "TrainingArea"))
feat("RunawayLawn", find(F.Plaza, "RunawayArea"))
feat("Spawn1", find(F.Plaza, "PlazaSpawn1"))
feat("Spawn2", find(F.Plaza, "PlazaSpawn2"))
local featNames = {}
for k in feats do
	table.insert(featNames, k)
end
table.sort(featNames)
for _, n in featNames do
	local b = feats[n].Box
	if not insideXZ(b, areas.Plaza) then
		fail(("%s (%s) is not inside the plaza"):format(n, boxStr(b)))
	end
end
for i = 1, #featNames do
	for j = i + 1, #featNames do
		local a, b = feats[featNames[i]], feats[featNames[j]]
		if overlapsXZ(a.Box, b.Box) then
			fail(("plaza features overlap: %s (%s) and %s (%s)"):format(featNames[i], boxStr(a.Box), featNames[j], boxStr(b.Box)))
		end
	end
end

-- platform geometry vs the Layout contract
do
	local P = Layout.Platform
	local deck = find(plat, "Deck")
	if deck then
		local b = Bounds(deck)
		if math.abs(b.MaxY - Layout.ThrowLine.Y) > 0.02 or math.abs(P.Center.Y - Layout.ThrowLine.Y) > 0.02 then
			fail("deck top / Platform.Center.Y must equal ThrowLine.Y")
		end
		if math.abs(b.MaxZ - Layout.ThrowLine.Z) > 0.02 then
			fail(("deck front edge Z %s ~= ThrowLine.Z %s"):format(fmt(b.MaxZ), fmt(Layout.ThrowLine.Z)))
		end
		if b.MaxY - Layout.GroundY < 40 - 0.02 then
			fail("deck is less than 40 studs above the field")
		end
		-- StandRadius covers the whole deck
		local ts = P.ThrowSpot
		for _, c in { { b.MinX, b.MinZ }, { b.MinX, b.MaxZ }, { b.MaxX, b.MinZ }, { b.MaxX, b.MaxZ } } do
			local d = math.sqrt((c[1] - ts.X) ^ 2 + (c[2] - ts.Z) ^ 2)
			if d > P.StandRadius + 0.01 then
				fail(("StandRadius %s does not cover deck corner (%s, %s) at %s"):format(fmt(P.StandRadius), fmt(c[1]), fmt(c[2]), fmt(d)))
			end
		end
		if ts.Z < b.MaxZ - 6 then
			fail("ThrowSpot is not at the front edge of the deck")
		end
	end
	if #P.QueueSpots ~= 5 then
		fail("Layout.Platform.QueueSpots must hold 5 spots")
	end
	local ramp = find(plat, "Ramp")
	if ramp then
		local slope = math.deg(math.atan((P.RampTop.Y - P.RampBottom.Y) / (P.RampTop.Z - P.RampBottom.Z)))
		note(("ramp slope %.1f deg, run %s, rise %s"):format(slope, fmt(P.RampTop.Z - P.RampBottom.Z), fmt(P.RampTop.Y - P.RampBottom.Y)))
		if slope > 35.01 then
			fail(("ramp slope %.1f deg > 35"):format(slope))
		end
		local rb = Bounds(ramp)
		if math.abs(rb.MaxY - P.RampTop.Y) > 0.05 or math.abs(rb.MinY - P.RampBottom.Y) > 0.05
			or math.abs(rb.MinZ - P.RampBottom.Z) > 0.05 or math.abs(rb.MaxZ - P.RampTop.Z) > 0.05 then
			fail("ramp part does not match Layout.Platform.RampBottom/RampTop: " .. boxStr(rb))
		end
	end
	-- railings: front railing below the launch height (ThrowSpot + 4)
	local launchY = P.ThrowSpot.Y + 4
	if plat then
		for _, d in plat:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local b = Bounds(d)
				if b.MaxZ > Layout.ThrowLine.Z - 3 and b.MinY >= P.Center.Y - 0.1 and b.MaxY > launchY - 0.3 then
					fail(("%s near the deck front tops out at Y %s (launch height %s)"):format(pathOf(d), fmt(b.MaxY), fmt(launchY)))
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- 3. Walls
----------------------------------------------------------------------------------------------------
local wallParts = {}
if F.Walls then
	for _, d in F.Walls:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(wallParts, { Part = d, Box = Bounds(d) })
		end
	end
	note(("walls: %d parts"):format(#wallParts))
	if #wallParts > 1500 then
		fail(("walls use %d parts (> 1500)"):format(#wallParts))
	end
	local margin = 40
	local keepOut = { MinX = Layout.Field.MinX - margin, MaxX = Layout.Field.MaxX + margin, MinZ = Layout.Street.MinZ - 60,
		MaxZ = Layout.Field.MaxZ + 30, MinY = -10, MaxY = 1000 }
	local minInner = math.huge
	for _, w in wallParts do
		if w.Part.CanCollide or w.Part.CanQuery then
			fail("wall part is collidable/queryable: " .. pathOf(w.Part))
		end
		if overlapsXZ(w.Box, keepOut) then
			fail(("wall part %s (%s) is inside the field/plaza keep-out (|x| <= %d)"):format(pathOf(w.Part), boxStr(w.Box),
				Layout.Field.MaxX + margin))
		end
		if w.Box.MinZ < Layout.Field.MaxZ and w.Box.MaxZ > Layout.Street.MinZ then
			minInner = math.min(minInner, math.min(math.abs(w.Box.MinX), math.abs(w.Box.MaxX)))
		end
	end
	note(("walls: closest side-wall face at |x| = %s"):format(fmt(minInner)))
	-- every run must reach >= 200 studs everywhere: check the tallest top in each 40-stud slice of each run
	for _, run in F.Walls:GetChildren() do
		local slices = {}
		local along = (run.Name == "Back" or run.Name == "Far") and "X" or "Z"
		local lo, hi = math.huge, -math.huge
		for _, d in run:GetDescendants() do
			if d:IsA("BasePart") then
				local b = Bounds(d)
				local a0 = if along == "X" then b.MinX else b.MinZ
				local a1 = if along == "X" then b.MaxX else b.MaxZ
				lo, hi = math.min(lo, a0), math.max(hi, a1)
				for s = math.floor(a0 / 40), math.floor(a1 / 40) do
					slices[s] = math.max(slices[s] or 0, b.MaxY)
				end
			end
		end
		local minTop = math.huge
		for s = math.floor(lo / 40) + 1, math.floor(hi / 40) - 1 do
			minTop = math.min(minTop, slices[s] or 0)
		end
		note(("walls/%s: spans %s %s..%s, lowest slice top %s"):format(run.Name, along, fmt(lo), fmt(hi), fmt(minTop)))
		if minTop < 200 then
			fail(("walls/%s has a slice only %s tall (< 200)"):format(run.Name, fmt(minTop)))
		end
	end
	-- enclosure: runs cover the map extents
	local need = {
		Back = { lo = Layout.Street.MinX, hi = Layout.Street.MaxX },
		Far = { lo = Layout.Field.MinX, hi = Layout.Field.MaxX },
		West = { lo = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2, hi = Layout.Field.MaxZ },
		East = { lo = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2, hi = Layout.Field.MaxZ },
	}
	for name, r in need do
		local run = F.Walls:FindFirstChild(name)
		local b = run and boundsOf(run)
		if not b then
			fail("walls: missing run " .. name)
		else
			local lo = if name == "Back" or name == "Far" then b.MinX else b.MinZ
			local hi = if name == "Back" or name == "Far" then b.MaxX else b.MaxZ
			if lo > r.lo or hi < r.hi then
				fail(("walls/%s does not span the map (%s..%s needed, has %s..%s)"):format(name, fmt(r.lo), fmt(r.hi), fmt(lo), fmt(hi)))
			end
		end
	end
	-- the field aprons must run under the walls: sample the apron's outer edge along both sides; every sample
	-- has to sit inside a wall part (else a strip of bare underlay would show between apron and cliff foot)
	if F.Field then
		local apronEdge = 0
		for _, d in F.Field:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "ApronW" or d.Name == "ApronE") then
				local b = Bounds(d)
				apronEdge = math.max(apronEdge, math.abs(b.MinX), math.abs(b.MaxX))
			end
		end
		local function covered(x, z)
			local pt = roblox.Vector3.new(x, Layout.GroundY + 0.5, z)
			for _, w in wallParts do
				local bx = w.Box
				if x >= bx.MinX - 1 and x <= bx.MaxX + 1 and z >= bx.MinZ - 1 and z <= bx.MaxZ + 1 then
					local lp = w.Part.CFrame:PointToObjectSpace(pt)
					local h = w.Part.Size / 2
					if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
						return true
					end
				end
			end
			return false
		end
		local bare = 0
		local firstBare = nil
		local z = Layout.Field.MinZ + 5
		while z < Layout.Field.MaxZ do
			for _, side in { -1, 1 } do
				if not covered(side * (apronEdge - 0.5), z) then
					bare += 1
					firstBare = firstBare or ("x %s z %s"):format(fmt(side * apronEdge), fmt(z))
				end
			end
			z += 10
		end
		note(("walls: apron outer edge |x| = %s (wall inner line %s); %d edge samples not under a wall"):format(
			fmt(apronEdge), fmt(minInner), bare))
		if apronEdge <= minInner then
			fail(("field apron stops at |x| %s, short of the closest wall face %s: a bare strip shows"):format(fmt(apronEdge),
				fmt(minInner)))
		elseif bare > 0 then
			fail(("apron outer edge is not hidden under a wall at %d samples (first: %s)"):format(bare, firstBare))
		end
	end
	-- walls vs everything else (except the ground underlay / clouds of the outskirts)
	local hits = 0
	for _, o in allParts do
		if isUnder(o.Part, F.Walls) or (o.Part.Name == "Underlay") then
			continue
		end
		for _, w in wallParts do
			if Overlaps(w.Box, o.Box, 0.05) then
				hits += 1
				if hits <= 12 then
					local who = if isUnder(o.Part, F.Field) then " [Field-owned]" else ""
					fail(("wall %s overlaps %s%s (%s)"):format(pathOf(w.Part), pathOf(o.Part), who, boxStr(o.Box)))
				end
				break
			end
		end
	end
	if hits > 12 then
		fail(("... %d wall overlaps in total"):format(hits))
	end
end

----------------------------------------------------------------------------------------------------
-- 4. Landing lane + camera box
----------------------------------------------------------------------------------------------------
local lane = { MinX = -56, MaxX = 56, MinY = Layout.GroundY + 0.25, MaxY = 400, MinZ = Layout.Field.MinZ,
	MaxZ = Layout.Field.MaxZ }
local camBox = { MinX = -30, MaxX = 30, MinY = Layout.ThrowLine.Y + 3.4, MaxY = Layout.ThrowLine.Y + 60,
	MinZ = Layout.Platform.Center.Z - Layout.Platform.Size.Z / 2 - 14, MaxZ = Layout.ThrowLine.Z + 260 }
local fieldLane, fieldCam = {}, {}
for _, o in allParts do
	local p = o.Part
	local invisibleGuard = p.Transparency >= 1 and not p.CanQuery
	if invisibleGuard then
		continue
	end
	if Overlaps(o.Box, lane, 0.02) then
		if isUnder(p, F.Field) then
			table.insert(fieldLane, pathOf(p))
		else
			fail(("landing lane: %s (%s) is in |x| <= 56 over the field"):format(pathOf(p), boxStr(o.Box)))
		end
	end
	if Overlaps(o.Box, camBox, 0.02) then
		if isUnder(p, F.Field) then
			table.insert(fieldCam, ("%s (%s)"):format(pathOf(p), boxStr(o.Box)))
		else
			fail(("camera box: %s (%s) is where the platform camera / ball flies"):format(pathOf(p), boxStr(o.Box)))
		end
	end
end

----------------------------------------------------------------------------------------------------
-- 5. Walking paths (grid shortest path at 1-stud cells, 16-neighbour moves; slightly over-estimates)
----------------------------------------------------------------------------------------------------
local walk = {}
do
	local CELL = 1
	local X0, X1 = Layout.Street.MinX - 4, Layout.Street.MaxX + 4
	local Z0, Z1 = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2 - 4, Layout.ThrowLine.Z + 12
	local NX = math.floor((X1 - X0) / CELL) + 1
	local NZ = math.floor((Z1 - Z0) / CELL) + 1
	local blocked = {}
	local R = 1.0 -- character half-width
	local STEP = 2.1 -- humanoids walk over anything lower than this
	local HEAD = 5.5
	local nObst = 0
	for _, o in allParts do
		local p, b = o.Part, o.Box
		if p.CanCollide and b.MinY < Layout.GroundY + HEAD and b.MaxY > Layout.GroundY + STEP then
			nObst += 1
			local ix0 = math.max(0, math.floor((b.MinX - R - X0) / CELL))
			local ix1 = math.min(NX - 1, math.ceil((b.MaxX + R - X0) / CELL))
			local iz0 = math.max(0, math.floor((b.MinZ - R - Z0) / CELL))
			local iz1 = math.min(NZ - 1, math.ceil((b.MaxZ + R - Z0) / CELL))
			for iz = iz0, iz1 do
				local zc = Z0 + iz * CELL
				if zc > b.MinZ - R and zc < b.MaxZ + R then
					for ix = ix0, ix1 do
						local xc = X0 + ix * CELL
						if xc > b.MinX - R and xc < b.MaxX + R then
							blocked[iz * NX + ix] = true
						end
					end
				end
			end
		end
	end
	local function cellOf(x, z)
		return math.floor((z - Z0) / CELL + 0.5) * NX + math.floor((x - X0) / CELL + 0.5)
	end
	local moves = {}
	for dz = -2, 2 do
		for dx = -2, 2 do
			if (dx ~= 0 or dz ~= 0) and (math.abs(dx) + math.abs(dz) <= 3) and not (math.abs(dx) == 2 and math.abs(dz) == 2)
				and not ((math.abs(dx) == 2 and dz == 0) or (dx == 0 and math.abs(dz) == 2)) then
				table.insert(moves, { dx, dz, math.sqrt(dx * dx + dz * dz) * CELL })
			end
		end
	end
	local function dijkstra(src)
		local dist = { [src] = 0 }
		local heap = { { 0, src } }
		local function push(d, c)
			table.insert(heap, { d, c })
			local i = #heap
			while i > 1 do
				local pi = i // 2
				if heap[pi][1] <= heap[i][1] then
					break
				end
				heap[pi], heap[i] = heap[i], heap[pi]
				i = pi
			end
		end
		local function pop()
			local top = heap[1]
			local last = table.remove(heap)
			if #heap > 0 then
				heap[1] = last
				local i = 1
				while true do
					local l, r = i * 2, i * 2 + 1
					local m = i
					if l <= #heap and heap[l][1] < heap[m][1] then
						m = l
					end
					if r <= #heap and heap[r][1] < heap[m][1] then
						m = r
					end
					if m == i then
						break
					end
					heap[m], heap[i] = heap[i], heap[m]
					i = m
				end
			end
			return top
		end
		while #heap > 0 do
			local top = pop()
			local d, c = top[1], top[2]
			if d <= (dist[c] or math.huge) then
				local cx, cz = c % NX, c // NX
				for _, mv in moves do
					local nx, nz = cx + mv[1], cz + mv[2]
					if nx >= 0 and nx < NX and nz >= 0 and nz < NZ then
						local n = nz * NX + nx
						if not blocked[n] then
							-- knight moves: both intermediate cells must be free
							local ok = true
							if math.abs(mv[1]) == 2 then
								ok = not blocked[cz * NX + cx + mv[1] // 2] and not blocked[nz * NX + cx + mv[1] // 2]
							elseif math.abs(mv[2]) == 2 then
								ok = not blocked[(cz + mv[2] // 2) * NX + cx] and not blocked[(cz + mv[2] // 2) * NX + nx]
							elseif mv[1] ~= 0 and mv[2] ~= 0 then
								ok = not blocked[cz * NX + nx] and not blocked[nz * NX + cx]
							end
							if ok then
								local nd = d + mv[3]
								if nd < (dist[n] or math.huge) then
									dist[n] = nd
									push(nd, n)
								end
							end
						end
					end
				end
			end
		end
		return dist
	end

	local P = Layout.Platform
	local rampLen = (P.RampTop - P.RampBottom).Magnitude
	local deckLen = (Vector3.new(P.ThrowSpot.X, 0, P.ThrowSpot.Z) - Vector3.new(P.RampTop.X, 0, P.RampTop.Z)).Magnitude
	local rampFoot = Vector3.new(P.RampBottom.X, 0, P.RampBottom.Z - 1.5)
	local points = {}
	local order = {}
	local function addPoint(name, pos)
		local c = cellOf(pos.X, pos.Z)
		if blocked[c] then
			fail(("walk: start point %s (%s, %s) is inside an obstacle"):format(name, fmt(pos.X), fmt(pos.Z)))
		end
		points[name] = c
		table.insert(order, name)
	end
	for i = 1, Layout.Yards.Count do
		addPoint("Gate" .. i, Vector3.new(Layout.Yards.CentersX[i], 0, Layout.Yards.CenterZ + Layout.Yards.Size.Z / 2 + 1.5))
	end
	addPoint("Shop", Layout.Shop.Center + Vector3.new(0, 0, -3.5))
	addPoint("Training", Layout.Training.Center)
	addPoint("RampFoot", rampFoot)
	local dists = {}
	for _, name in order do
		dists[name] = dijkstra(points[name])
	end
	local function d(a, b)
		local v = dists[a][points[b]]
		return v or math.huge
	end
	local targets = {}
	for _, n in order do
		if n ~= "RampFoot" then
			table.insert(targets, n)
		end
	end
	table.insert(targets, "Platform")
	local platformExtra = 1.5 + rampLen + deckLen
	local worst = 0
	for i = 1, #targets do
		for j = i + 1, #targets do
			local a, b = targets[i], targets[j]
			local len
			if b == "Platform" then
				len = d(a, "RampFoot") + platformExtra
			else
				len = d(a, b)
			end
			table.insert(walk, { a, b, len })
			worst = math.max(worst, len)
			if len > 300 then
				fail(("walk %s -> %s is %s studs (> 300, %.1f s at WalkSpeed 32)"):format(a, b, fmt(len), len / 32))
			end
		end
	end
	note(("walk: %d obstacles rasterised, ramp %s + deck %s studs; worst path %s studs = %.1f s at 32"):format(nObst,
		fmt(rampLen), fmt(deckLen), fmt(worst), worst / 32))
end

if DUMP then
	local serde = require("@lune/serde")
	local rows = {}
	for _, o in allParts do
		local b, c = o.Box, o.Part.Color
		table.insert(rows, { o.Part.Name, b.MinX, b.MaxX, b.MinY, b.MaxY, b.MinZ, b.MaxZ,
			math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255), o.Part.Transparency, pathOf(o.Part) })
	end
	fs.writeFile(DUMP, serde.encode("json", rows))
end

----------------------------------------------------------------------------------------------------
-- Report
----------------------------------------------------------------------------------------------------
print("== worldcheck" .. (if NO_FIELD then " (--no-field)" else "") .. " ==")
local counts = {}
for _, t in WorldCheck.Tags do
	counts[t] = #CollectionService:GetTagged(t)
end
local tagLine = {}
for _, t in WorldCheck.Tags do
	table.insert(tagLine, t .. "=" .. counts[t])
end
print("parts: " .. #allParts .. "   tags: " .. table.concat(tagLine, " "))
print("Layout.ThrowLine = { X = " .. Layout.ThrowLine.X .. ", Z = " .. Layout.ThrowLine.Z .. ", Y = " .. Layout.ThrowLine.Y .. " }")
for _, n in notes do
	print("  " .. n)
end
print("walking paths (studs; <= 300 required):")
for _, w in walk do
	if not QUIET or w[3] > 250 then
		print(("  %-9s -> %-9s %6.1f  (%.1f s)"):format(w[1], w[2], w[3], w[3] / 32))
	end
end
if #fieldProblems > 0 then
	print("FIELD (owned by the zone/field agent) failed to build headlessly:")
	for _, w in fieldProblems do
		print("  " .. w)
	end
end
if #fieldLane > 0 then
	print(("note: %d Field-owned parts stand in the landing lane (zone agent's call), e.g. %s"):format(#fieldLane,
		table.concat({ fieldLane[1], fieldLane[2] or "", fieldLane[3] or "" }, ", ")))
end
if #fieldCam > 0 then
	print(("note: %d Field-owned parts are inside the platform camera box, e.g.:"):format(#fieldCam))
	for i = 1, math.min(5, #fieldCam) do
		print("  " .. fieldCam[i])
	end
end
if #failures == 0 then
	print("PASS")
	process.exit(0)
else
	print(("FAIL (%d):"):format(#failures))
	for _, f in failures do
		print("  - " .. f)
	end
	process.exit(1)
end
