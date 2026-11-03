--!strict
-- Shared helpers for the zone decorators. Each zone plot (the whole field width, |x| <= 120, over the zone's
-- distance band) is filled in three layers:
--   1. Ground cover (Kit.Cover): 200+ tiny one-part items (flowers, tufts, pebbles, shells, snow lumps, leaves,
--      cracks, puddles) scattered over the WHOLE plot. CanCollide/CanQuery/CanTouch/CastShadow all false, so the
--      landing raycast always hits the ZoneBand. Grouped into Atomic "CoverCell" Models (80 x 60 stud cells) so
--      phones stream them per area.
--   2. Mid-size props (Kit.Place): 20-40 per zone (trees, boulders, bales, umbrellas, ...), each its own Atomic
--      Model, non-colliding and non-queryable, at least Kit.PropGap (6) studs apart measured between footprint
--      edges (XZ bounding boxes) and the same distance from the landmark, the boundary line, the arch pillars
--      and the distance-marker signs, so every landing spot has open ground for the dog animation. Inside the
--      ball-POV corridor (|x| <= Kit.Corridor) only low props (<= Kit.CorridorMaxH tall) are allowed.
--   3. One tall landmark per zone at the field edge (Kit.Landmark, Persistent so it is always visible from the
--      platform).
-- The zone boundary (Kit.Boundary) is a low fence line / hedge / terrain step across the FULL field width just
-- past the zone start, plus the side-only name-board gantry (Kit.ZoneArch; nothing crosses the lane).
--
-- Tagging contract (read by tools/worldcheck/zones.luau):
--   <zone>/Ground   Persistent Model: ZoneBand, threshold, aprons, flat dressing
--   <zone>/Cover    Folder of Atomic CoverCell Models (attribute Cover=true); every part is one cover item
--   <zone>/Props    Folder of Atomic prop Models (Prop=true, PropKind, ZoneId)
--   Landmark=true   on the one landmark model per zone (+ LandmarkHeight, LandmarkKind)
--   Boundary=true   on the zone-start arch (BoundaryKind "Arch") and the full-width line (BoundaryKind = style)
--   ParticleVolume  on the invisible, non-colliding, non-queryable parts that carry the zone ParticleEmitters
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any

local Kit = {}

local F = Layout.Field
Kit.FieldHalf = (F.MaxX - F.MinX) / 2 -- 120
Kit.CenterX = (F.MaxX + F.MinX) / 2 -- 0
Kit.LaneHalf = Kit.FieldHalf * 0.5 -- 60 (only used for the arch gantry opening now)
-- 266: themed ground strip outside the field. It runs 30 studs past the scenery walls' inner line (Walls.InnerX
-- = 236) so its outer edge is always hidden under a cliff / hedge tier (tools/worldcheck/run.luau samples it).
Kit.ApronHalf = Kit.FieldHalf + 146
Kit.BackdropHalf = Kit.FieldHalf + 114 -- 234: field-end backdrop stops just inside the walls' inner line (236)
Kit.MarkerX = Kit.LaneHalf + 8 -- 68: distance marker signs
Kit.ArchX = Kit.FieldHalf - 8 -- 112: zone arch pillars
Kit.MarkerEvery = 100
Kit.PlotHalf = Kit.FieldHalf - 2 -- 118: props and cover stay inside the field
Kit.DecorMaxAbsX = Kit.PlotHalf
Kit.LandmarkMaxAbsX = Kit.FieldHalf + 30 -- 150: landmarks may overhang the field edge up to here
Kit.BoundaryOffset = 6 -- the full-width boundary line's centre sits this far past the arch
Kit.PropGap = 6 -- minimum distance between prop footprints (edge to edge)
Kit.Corridor = 30 -- |x| <= 30: the ball-POV camera flies here (~15 studs up), so only low props
Kit.CorridorMaxH = 10
Kit.CoverMaxH = 2.5 -- ground cover limits (checked by tools/worldcheck/zones.luau)
Kit.CoverMaxW = 6
Kit.CoverCell = Vector2.new(80, 60) -- streaming cluster size for ground cover (x, z)

export type Box = { x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, name: string? }

export type Ctx = {
	Zone: any,
	ZoneFolder: Instance,
	Folder: Instance, -- <zone>/Props
	CoverFolder: Instance, -- <zone>/Cover
	GroundModel: Instance, -- <zone>/Ground (flat dressing goes here)
	MinZ: number, -- world Z where the plot starts (band start, or the throw-line wall for the Backyard)
	MaxZ: number, -- band end
	StartZ: number, -- world Z of the band start
	ArchZ: number,
	BoundaryZ: number,
	Rng: Random,
	Decor: any, -- WorldTheme.ZoneDecor[ZoneId]
	Ground: Color3,
	Accent: Color3,
	Props: any,
	Y: number,
	Boxes: { Box }, -- obstacle + placed prop footprints (XZ)
	CoverCells: { [string]: Model },
	CoverItems: number,
	PropCount: number,
}

----------------------------------------------------------------------------------------------------
-- Geometry
----------------------------------------------------------------------------------------------------
local function eachPart(inst: Instance, fn: (BasePart) -> ())
	if inst:IsA("BasePart") then
		fn(inst :: BasePart)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d :: BasePart)
		end
	end
end
Kit.EachPart = eachPart

function Kit.PartBox(p: BasePart): Box
	local cf, s = p.CFrame, p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(l.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
	local c = cf.Position
	return { x0 = c.X - ex, x1 = c.X + ex, y0 = c.Y - ey, y1 = c.Y + ey, z0 = c.Z - ez, z1 = c.Z + ez }
end

function Kit.Bounds(inst: Instance): Box?
	local b: Box? = nil
	eachPart(inst, function(p)
		local a = Kit.PartBox(p)
		local cur = b
		if cur == nil then
			b = a
		else
			cur.x0, cur.x1 = math.min(cur.x0, a.x0), math.max(cur.x1, a.x1)
			cur.y0, cur.y1 = math.min(cur.y0, a.y0), math.max(cur.y1, a.y1)
			cur.z0, cur.z1 = math.min(cur.z0, a.z0), math.max(cur.z1, a.z1)
		end
	end)
	return b
end

-- Edge-to-edge distance between two XZ footprints (0 when they overlap).
function Kit.Gap(a: Box, b: Box): number
	local dx = math.max(0, math.max(a.x0, b.x0) - math.min(a.x1, b.x1))
	local dz = math.max(0, math.max(a.z0, b.z0) - math.min(a.z1, b.z1))
	return math.sqrt(dx * dx + dz * dz)
end

-- Register a footprint that props must keep Kit.PropGap away from (landmark, boundary, signs, fixed dressing).
function Kit.Obstacle(ctx: Ctx, inst: Instance | Box, name: string?)
	local b: Box? = if typeof(inst) == "Instance" then Kit.Bounds(inst :: Instance) else inst :: Box
	if b then
		b.name = name or (if typeof(inst) == "Instance" then (inst :: Instance).Name else "obstacle")
		table.insert(ctx.Boxes, b)
	end
end

local function noShadowLowFlags(p: BasePart, shadow: boolean)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if not shadow then
		p.CastShadow = false
	end
end

local function destroyCounted(ctx: Ctx, inst: Instance)
	local n = 0
	eachPart(inst, function()
		n += 1
	end)
	ctx.Props.PartCount -= n
	inst:Destroy()
end

----------------------------------------------------------------------------------------------------
-- Props (layer 2)
----------------------------------------------------------------------------------------------------
export type PropSpec = {
	Name: string,
	Count: number,
	R: number, -- rough footprint half-extent (used to pick candidate spots; the real footprint is measured)
	Tall: boolean?, -- taller than Kit.CorridorMaxH: kept out of the ball-POV corridor
	MinAbsX: number?, -- optional band limits (|x|)
	MaxAbsX: number?,
	Shadow: boolean?, -- default: Tall props cast shadows, low ones do not
	Build: (ctx: Ctx, m: Model, pos: Vector3, i: number, side: number) -> (),
}

local function fits(ctx: Ctx, b: Box): boolean
	local half = Kit.PlotHalf
	if b.x0 < Kit.CenterX - half - 1e-3 or b.x1 > Kit.CenterX + half + 1e-3 then
		return false
	end
	if b.z0 < ctx.MinZ + 1 or b.z1 > ctx.MaxZ - 1 then
		return false
	end
	local inCorridor = b.x1 > Kit.CenterX - Kit.Corridor and b.x0 < Kit.CenterX + Kit.Corridor
	if inCorridor and b.y1 > ctx.Y + Kit.CorridorMaxH then
		return false
	end
	for _, o in ctx.Boxes do
		if Kit.Gap(o, b) < Kit.PropGap then
			return false
		end
	end
	return true
end

-- Scatter `spec.Count` props of one kind through the plot. Returns the number actually placed.
function Kit.Place(ctx: Ctx, spec: PropSpec): number
	local P, rng = ctx.Props, ctx.Rng
	local placed, tries = 0, 0
	local r = spec.R
	local minAbs = spec.MinAbsX or (if spec.Tall then Kit.Corridor + 1 else 0)
	local maxAbs = spec.MaxAbsX or Kit.PlotHalf
	while placed < spec.Count and tries < spec.Count * 80 do
		tries += 1
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local lo, hi = minAbs + r, maxAbs - r
		if hi <= lo then
			break
		end
		local x = Kit.CenterX + side * rng:NextNumber(lo, hi)
		if minAbs == 0 then
			x = Kit.CenterX + rng:NextNumber(-hi, hi)
			side = if x < Kit.CenterX then -1 else 1
		end
		local z = rng:NextNumber(ctx.MinZ + 1 + r, ctx.MaxZ - 1 - r)
		-- quick reject with the estimated footprint
		local guess: Box = { x0 = x - r * 0.7, x1 = x + r * 0.7, y0 = 0, y1 = 0, z0 = z - r * 0.7, z1 = z + r * 0.7 }
		local ok = true
		for _, o in ctx.Boxes do
			if Kit.Gap(o, guess) < Kit.PropGap then
				ok = false
				break
			end
		end
		if not ok then
			continue
		end
		local m = P.Model(ctx.Folder, spec.Name)
		spec.Build(ctx, m, Vector3.new(x, ctx.Y, z), placed + 1, side)
		local b = Kit.Bounds(m)
		if b == nil or not fits(ctx, b) then
			destroyCounted(ctx, m)
			continue
		end
		b.name = spec.Name
		table.insert(ctx.Boxes, b)
		placed += 1
		ctx.PropCount += 1
		m:SetAttribute("Prop", true)
		m:SetAttribute("PropKind", spec.Name)
		m:SetAttribute("ZoneId", ctx.Zone.Id)
		local shadow = if spec.Shadow ~= nil then spec.Shadow else spec.Tall == true
		eachPart(m, function(p)
			noShadowLowFlags(p, shadow)
		end)
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	return placed
end

-- Place several kinds in order (largest first gives the best packing).
function Kit.PlaceAll(ctx: Ctx, specs: { PropSpec })
	for _, s in specs do
		Kit.Place(ctx, s)
	end
end

----------------------------------------------------------------------------------------------------
-- Ground cover (layer 1): every item is exactly ONE part
----------------------------------------------------------------------------------------------------
export type CoverKind = "Block" | "Ball" | "Disc" | "Wedge" | "Spike"
export type CoverItem = {
	W: number, -- weight
	Make: (ctx: Ctx, x: number, z: number, rng: Random) -> (CoverKind, Vector3, CFrame, Color3, Enum.Material?),
}
export type CoverOpts = {
	Count: number,
	Items: { CoverItem },
	Mode: string?, -- "Random" (default) | "Grid" (tidy, jittered rows) | "Clumps" (dense patches)
	Clumps: number?,
	ClumpShare: number?, -- share of items inside clumps (default 0.65)
	ClumpRadius: number?,
}

local function coverCell(ctx: Ctx, x: number, z: number): Model
	local cx = math.floor((x - (Kit.CenterX - Kit.FieldHalf)) / Kit.CoverCell.X)
	local cz = math.floor((z - ctx.MinZ) / Kit.CoverCell.Y)
	local key = cx .. "_" .. cz
	local m = ctx.CoverCells[key]
	if m == nil then
		local nm = ctx.Props.Model(ctx.CoverFolder, "CoverCell_" .. key)
		nm.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		nm:SetAttribute("Cover", true)
		ctx.CoverCells[key] = nm
		m = nm
	end
	return m :: Model
end

-- One cover part (no SpecialMesh, no children). Disc = flat cylinder lying on the ground (size.X = diameter,
-- size.Y = thickness); Spike = CornerWedgePart (a one-part tuft / shard / shell).
function Kit.CoverPart(ctx: Ctx, parent: Instance, kind: CoverKind, size: Vector3, cf: CFrame, color: Color3,
	material: Enum.Material?): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	elseif kind == "Spike" then
		p = Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		if kind == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif kind == "Disc" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = "Cover"
	p.Anchored = true
	if kind == "Disc" then
		p.Size = Vector3.new(size.Y, size.X, size.X)
		p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	else
		p.Size = size
		p.CFrame = cf
	end
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	ctx.Props.PartCount += 1
	return p
end

local function gauss(rng: Random): number
	local u1 = math.max(1e-6, rng:NextNumber())
	local u2 = rng:NextNumber()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function freeForCover(ctx: Ctx, x: number, z: number): boolean
	for _, o in ctx.Boxes do
		if x > o.x0 - 0.8 and x < o.x1 + 0.8 and z > o.z0 - 0.8 and z < o.z1 + 0.8 then
			return false
		end
	end
	return true
end

function Kit.Cover(ctx: Ctx, o: CoverOpts): number
	local rng = ctx.Rng
	local total = 0
	for _, it in o.Items do
		total += it.W
	end
	local function pickItem(): CoverItem
		local r = rng:NextNumber(0, total)
		for _, it in o.Items do
			r -= it.W
			if r <= 0 then
				return it
			end
		end
		return o.Items[#o.Items]
	end
	local half = Kit.PlotHalf - 1
	local z0, z1 = ctx.MinZ + 2, ctx.MaxZ - 2
	local placed = 0
	local function put(x: number, z: number): boolean
		if x < Kit.CenterX - half or x > Kit.CenterX + half or z < z0 or z > z1 then
			return false
		end
		if not freeForCover(ctx, x, z) then
			return false
		end
		local it = pickItem()
		local kind, size, cf, color, mat = it.Make(ctx, x, z, rng)
		Kit.CoverPart(ctx, coverCell(ctx, x, z), kind, size, cf, color, mat)
		placed += 1
		return true
	end
	local mode = o.Mode or "Random"
	if mode == "Grid" then
		-- tidy: a jittered grid, cells visited in a shuffled order until the count is reached
		local w, d = half * 2, z1 - z0
		local cells = o.Count * 1.4
		local nx = math.max(1, math.floor(math.sqrt(cells * w / d) + 0.5))
		local nz = math.max(1, math.ceil(cells / nx))
		local sx, sz = w / nx, d / nz
		local order = {}
		for i = 0, nx * nz - 1 do
			table.insert(order, i)
		end
		for i = #order, 2, -1 do
			local j = rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		for _, idx in order do
			if placed >= o.Count then
				break
			end
			local ix, iz = idx % nx, idx // nx
			local x = Kit.CenterX - half + (ix + 0.5 + rng:NextNumber(-0.18, 0.18)) * sx
			local z = z0 + (iz + 0.5 + rng:NextNumber(-0.18, 0.18)) * sz
			put(x, z)
		end
	end
	local centres = {}
	if mode == "Clumps" then
		for _ = 1, o.Clumps or 12 do
			table.insert(centres, Vector2.new(rng:NextNumber(-half, half) + Kit.CenterX, rng:NextNumber(z0, z1)))
		end
	end
	local share = o.ClumpShare or 0.65
	local cr = o.ClumpRadius or 9
	local tries = 0
	while placed < o.Count and tries < o.Count * 30 do
		tries += 1
		local x, z
		if #centres > 0 and rng:NextNumber() < share then
			local c = centres[rng:NextInteger(1, #centres)]
			x, z = c.X + gauss(rng) * cr, c.Y + gauss(rng) * cr
		else
			x, z = Kit.CenterX + rng:NextNumber(-half, half), rng:NextNumber(z0, z1)
		end
		put(x, z)
	end
	ctx.CoverItems += placed
	return placed
end

-- Common cover makers -------------------------------------------------------------------------------
-- (each returns kind, size, cframe, colour, material for Kit.CoverPart; yaw is random)
local function yaw(rng: Random): CFrame
	return CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end
Kit.CoverYaw = yaw

local function pickColor(rng: Random, colors: { Color3 }): Color3
	return colors[rng:NextInteger(1, #colors)]
end
Kit.PickColor = pickColor

-- dome sunk into the ground (pebble, snow lump, moss mound): a Ball whose centre sits below the surface
function Kit.Dome(colors: { Color3 }, dmin: number, dmax: number, material: Enum.Material?, sink: number?): CoverItem
	return { W = 1, Make = function(ctx, x, z, rng)
		local d = rng:NextNumber(dmin, dmax)
		return "Ball", Vector3.new(d, d, d), CFrame.new(x, ctx.Y + d * (0.5 - (sink or 0.3)), z), pickColor(rng, colors), material
	end }
end

-- small ball sitting on (or just above) the ground: flower head, berry, tiny mushroom cap
function Kit.Bead(colors: { Color3 }, dmin: number, dmax: number, lift: number, material: Enum.Material?): CoverItem
	return { W = 1, Make = function(ctx, x, z, rng)
		local d = rng:NextNumber(dmin, dmax)
		return "Ball", Vector3.new(d, d, d), CFrame.new(x, ctx.Y + lift + d / 2, z), pickColor(rng, colors), material
	end }
end

-- one-part tuft / shard / shell (CornerWedgePart)
function Kit.Spike(colors: { Color3 }, w: number, h: number, material: Enum.Material?): CoverItem
	return { W = 1, Make = function(ctx, x, z, rng)
		local s = rng:NextNumber(0.75, 1.25)
		local hh = h * s
		return "Spike", Vector3.new(w * s, hh, w * s), CFrame.new(x, ctx.Y + hh / 2, z) * yaw(rng), pickColor(rng, colors),
			material
	end }
end

-- flat disc on the ground: puddle, moss patch, clover, wet sand
function Kit.Disc(colors: { Color3 }, dmin: number, dmax: number, material: Enum.Material?): CoverItem
	return { W = 1, Make = function(ctx, x, z, rng)
		local d = rng:NextNumber(dmin, dmax)
		return "Disc", Vector3.new(d, 0.1, d), CFrame.new(x, ctx.Y + 0.05, z), pickColor(rng, colors), material
	end }
end

-- flat chip / leaf / crack: a thin block lying on the ground, random yaw
function Kit.Chip(colors: { Color3 }, sx: number, sz: number, thick: number, material: Enum.Material?): CoverItem
	return { W = 1, Make = function(ctx, x, z, rng)
		local s = rng:NextNumber(0.7, 1.3)
		return "Block", Vector3.new(sx * s, thick, sz * s), CFrame.new(x, ctx.Y + thick / 2, z) * yaw(rng),
			pickColor(rng, colors), material
	end }
end

-- small chunky block (clod, crate bolt, gravel), slightly tilted
function Kit.Nugget(colors: { Color3 }, size: number, material: Enum.Material?): CoverItem
	return { W = 1, Make = function(ctx, x, z, rng)
		local s = size * rng:NextNumber(0.7, 1.3)
		return "Block", Vector3.new(s, s * 0.6, s * 0.8),
			CFrame.new(x, ctx.Y + s * 0.25, z) * yaw(rng) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3)),
			pickColor(rng, colors), material
	end }
end

function Kit.Weight(item: CoverItem, w: number): CoverItem
	return { W = w, Make = item.Make }
end

----------------------------------------------------------------------------------------------------
-- Tagging
----------------------------------------------------------------------------------------------------
function Kit.Landmark(ctx: Ctx, model: Model, height: number, kind: string): Model
	model:SetAttribute("Landmark", true)
	model:SetAttribute("LandmarkKind", kind)
	model:SetAttribute("LandmarkHeight", height)
	model:SetAttribute("ZoneId", ctx.Zone.Id)
	eachPart(model, function(p)
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end)
	-- always streamed: the landmark is what tells the zones apart from the platform, thousands of studs away
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Kit.Obstacle(ctx, model, "Landmark")
	return model
end

function Kit.Yaw(ctx: Ctx): CFrame
	return CFrame.Angles(0, ctx.Rng:NextNumber(0, math.pi * 2), 0)
end

-- Faces the lane: yaw that turns a model's -Z front toward the field centre.
function Kit.FaceLane(side: number): CFrame
	return CFrame.Angles(0, if side > 0 then math.pi / 2 else -math.pi / 2, 0)
end

----------------------------------------------------------------------------------------------------
-- Shapes
----------------------------------------------------------------------------------------------------
-- Gable prism standing on `cf` (bottom centre): ridge along local X, `w` long, `d` deep, `h` tall.
function Kit.Gable(P: any, parent: Instance, name: string, cf: CFrame, w: number, d: number, h: number,
	color: Color3, material: Enum.Material?)
	P.Wedge({ Parent = parent, Name = name, Size = Vector3.new(w, h, d / 2), CFrame = cf * CFrame.new(0, h / 2, -d / 4),
		Color = color, Material = material })
	P.Wedge({ Parent = parent, Name = name, Size = Vector3.new(w, h, d / 2),
		CFrame = cf * CFrame.new(0, h / 2, d / 4) * CFrame.Angles(0, math.pi, 0), Color = color, Material = material })
end

-- Same, ridge along world Z (wedges rotated 90 degrees; the footprint stays axis-aligned): w along X.
function Kit.GableZ(P: any, parent: Instance, name: string, base: Vector3, w: number, d: number, h: number,
	color: Color3, material: Enum.Material?)
	Kit.Gable(P, parent, name, CFrame.new(base) * CFrame.Angles(0, math.pi / 2, 0), d, w, h, color, material)
end

-- Low-poly peak: a gable along Z crossed by a gable along X (reads as a four-sided pyramid).
function Kit.Peak(P: any, parent: Instance, name: string, base: Vector3, w: number, d: number, h: number,
	color: Color3, material: Enum.Material?)
	Kit.GableZ(P, parent, name, base, w, d, h, color, material)
	Kit.Gable(P, parent, name, CFrame.new(base), w, d, h, color, material)
end

-- Horizontal cylinder centred at `center`, axis along world X (yaw rotates it).
function Kit.LyingCylinder(P: any, parent: Instance, name: string, center: Vector3, length: number, diameter: number,
	yaw: number, color: Color3, material: Enum.Material?): Part
	return P.Part({ Parent = parent, Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter), CFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0),
		Color = color, Material = material })
end

-- Flat ground decal (non-colliding, non-queryable so the landing raycast always hits the ZoneBand).
function Kit.Flat(P: any, parent: Instance, name: string, minX: number, maxX: number, minZ: number, maxZ: number,
	topY: number, color: Color3, material: Enum.Material?): Part
	local p = P.Slab(parent, name, minX, maxX, minZ, maxZ, topY, 0.05, color, material, false)
	p.CanQuery = false
	p.CastShadow = false
	return p
end

----------------------------------------------------------------------------------------------------
-- Zone boundary: a low fence line / hedge / terrain step across the FULL field width (x -120..120) at
-- ctx.BoundaryZ. Visual only (CanCollide/CanQuery/CanTouch false) and low (<= 4 studs in the first three zones,
-- <= 7 after), so it never enters the platform camera's view of the lane or the ball arc, and the ball-POV
-- camera (~15 studs up) flies over it.
----------------------------------------------------------------------------------------------------
export type GateStyle = {
	Kind: string, -- Picket | Hedge | Dune | Rail | Logs | Ice | Parapet | Bulkhead | Crystal
	Color: Color3,
	Trim: Color3,
	Material: Enum.Material?,
	TrimMaterial: Enum.Material?,
	Height: number,
}

function Kit.Boundary(ctx: Ctx, style: GateStyle): Model
	local P = ctx.Props
	local m = P.Model(ctx.ZoneFolder, "Boundary")
	local z, Y = ctx.BoundaryZ, ctx.Y
	local x0, x1 = Kit.CenterX - Kit.FieldHalf, Kit.CenterX + Kit.FieldHalf
	local len = x1 - x0
	local cx = Kit.CenterX
	local h = style.Height
	local kind = style.Kind
	local rng = ctx.Rng
	local function posts(step: number, size: Vector3, color: Color3, material: Enum.Material?, name: string)
		local n = math.floor(len / step + 0.5)
		for i = 0, n do
			local px = x0 + len * i / n
			px = math.clamp(px, x0 + size.X / 2, x1 - size.X / 2)
			P.Block(m, name, size, CFrame.new(px, Y + size.Y / 2, z), color, material)
		end
	end
	if kind == "Picket" then
		-- white picket fence: two rails + posts with caps every 12 studs + a pale base board
		for _, fy in { 0.4, 0.8 } do
			P.Block(m, "Rail", Vector3.new(len, 0.5, 0.35), CFrame.new(cx, Y + h * fy, z), style.Color)
		end
		posts(12, Vector3.new(0.9, h + 0.6, 0.9), style.Trim, style.TrimMaterial, "Post")
		P.Block(m, "Base", Vector3.new(len, 0.5, 0.6), CFrame.new(cx, Y + 0.25, z), style.Color)
	elseif kind == "Hedge" then
		-- one long clipped hedge with pink blossoms every ~10 studs
		P.Block(m, "Hedge", Vector3.new(len, h, 2.6), CFrame.new(cx, Y + h / 2, z), style.Color, style.Material)
		P.Block(m, "Top", Vector3.new(len, 0.5, 2.2), CFrame.new(cx, Y + h + 0.25, z), style.Color:Lerp(Color3.new(1, 1, 1), 0.15),
			style.Material)
		local n = 22
		for i = 0, n do
			local px = x0 + 3 + (len - 6) * i / n
			P.Ball(m, "Blossom", Vector3.new(px, Y + h * rng:NextNumber(0.45, 0.95), z - 1.3), 1.1, style.Trim)
		end
	elseif kind == "Dune" then
		-- terrain step: a sand ridge (two long wedges) topped with dune-grass tufts
		local d = 10
		for _, s in { -1, 1 } do
			P.Wedge({ Parent = m, Name = "Ridge", Size = Vector3.new(len, h, d / 2),
				CFrame = CFrame.new(cx, Y + h / 2, z + s * d / 4) * CFrame.Angles(0, if s > 0 then math.pi else 0, 0),
				Color = style.Color, Material = style.Material })
		end
		for i = 0, 20 do
			local px = x0 + 4 + (len - 8) * i / 20 + rng:NextNumber(-2, 2)
			local th = rng:NextNumber(1.2, 2)
			local tuft = Instance.new("CornerWedgePart")
			tuft.Name = "Grass"
			tuft.Anchored = true
			tuft.Size = Vector3.new(1.4, th, 1.4)
			tuft.CFrame = CFrame.new(px, Y + h - 0.4 + th / 2, z + rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			tuft.Color = style.Trim
			tuft.Material = Enum.Material.Grass
			tuft.Parent = m
			P.PartCount += 1
		end
	elseif kind == "Rail" then
		-- split-rail ranch fence: two log rails + chunky posts every 15 studs
		for _, fy in { 0.4, 0.8 } do
			P.Block(m, "Rail", Vector3.new(len, 0.8, 0.6), CFrame.new(cx, Y + h * fy, z), style.Color, style.Material)
		end
		posts(15, Vector3.new(1.2, h + 0.5, 1.2), style.Trim, style.TrimMaterial or style.Material, "Post")
	elseif kind == "Logs" then
		-- a line of felled logs end to end, a second staggered course on top
		local seg = 24
		local n = math.floor(len / seg)
		for i = 0, n - 1 do
			local px = math.clamp(x0 + seg * (i + 0.5), x0 + seg / 2 + 0.3, x1 - seg / 2 - 0.3)
			Kit.LyingCylinder(P, m, "Log", Vector3.new(px, Y + 1, z), seg + 0.6, 2, 0, style.Color, style.Material)
			if i % 2 == 0 then
				Kit.LyingCylinder(P, m, "LogTop", Vector3.new(px + rng:NextNumber(-3, 3), Y + 2.6, z), seg * 0.6, 1.4, 0,
					style.Trim, style.Material)
			end
		end
	elseif kind == "Ice" then
		-- snow bank with ice shards poking out every ~12 studs
		P.Block(m, "Bank", Vector3.new(len, h * 0.5, 4), CFrame.new(cx, Y + h * 0.25, z), style.Trim, Enum.Material.Snow)
		P.Block(m, "BankTop", Vector3.new(len, h * 0.25, 2.6), CFrame.new(cx, Y + h * 0.625, z), style.Trim, Enum.Material.Snow)
		local n = 20
		for i = 0, n do
			local px = x0 + 3 + (len - 6) * i / n
			local sh = h * (if i % 2 == 0 then 1 else 0.75)
			P.Block(m, "Shard", Vector3.new(1.6, sh, 1.6), CFrame.new(px, Y + sh / 2, z) * CFrame.Angles(0, math.rad(45), math.rad(8)),
				style.Color, style.Material)
		end
	elseif kind == "Parapet" then
		-- roof-edge step: a concrete kerb with a glowing trim line and roof lights every 30 studs
		P.Block(m, "Kerb", Vector3.new(len, h, 2), CFrame.new(cx, Y + h / 2, z), style.Color, Enum.Material.Concrete)
		P.Block(m, "Trim", Vector3.new(len, 0.35, 2.2), CFrame.new(cx, Y + h * 0.7, z), style.Trim, style.TrimMaterial)
		P.Block(m, "Cap", Vector3.new(len, 0.4, 2.4), CFrame.new(cx, Y + h + 0.2, z), style.Color:Lerp(Color3.new(1, 1, 1), 0.2),
			Enum.Material.Concrete)
		posts(30, Vector3.new(1, 1.2, 1), style.Trim, style.TrimMaterial, "RoofLight")
	elseif kind == "Bulkhead" then
		-- low bulkhead wall with a neon band and pylons every 30 studs
		P.Block(m, "Wall", Vector3.new(len, h * 0.6, 1.6), CFrame.new(cx, Y + h * 0.3, z), style.Color, style.Material)
		P.Block(m, "Band", Vector3.new(len, 0.4, 1.8), CFrame.new(cx, Y + h * 0.45, z), style.Trim, style.TrimMaterial)
		posts(30, Vector3.new(2, h, 2), style.Color:Lerp(Color3.new(0, 0, 0), 0.25), style.Material, "Pylon")
		local n = math.floor(len / 30 + 0.5)
		for i = 0, n do
			local px = math.clamp(x0 + len * i / n, x0 + 1, x1 - 1)
			P.Block(m, "PylonLight", Vector3.new(2.1, 0.5, 2.1), CFrame.new(px, Y + h - 0.6, z), style.Trim, style.TrimMaterial)
		end
	else -- Crystal: a glowing rim with a row of shards
		P.Block(m, "Rim", Vector3.new(len, 0.5, 1.4), CFrame.new(cx, Y + 0.25, z), style.Trim, style.TrimMaterial)
		local n = 36
		for i = 0, n do
			local px = x0 + 2 + (len - 4) * i / n
			local sh = h * (if i % 3 == 0 then 1 elseif i % 3 == 1 then 0.6 else 0.4)
			P.Block(m, "Shard", Vector3.new(1.8, sh, 1.8), CFrame.new(px, Y + sh / 2, z) * CFrame.Angles(0, math.rad(45), 0),
				if i % 2 == 0 then style.Color else style.Trim, style.Material)
		end
	end
	m:SetAttribute("Boundary", true)
	m:SetAttribute("BoundaryKind", kind)
	m:SetAttribute("ZoneId", ctx.Zone.Id)
	eachPart(m, function(p)
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
	end)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Kit.Obstacle(ctx, m, "Boundary")
	return m
end

----------------------------------------------------------------------------------------------------
-- Zone arch (the zone-start boundary). Built for the raised throwing platform (deck Y = 40, launch ~44,
-- camera behind and above): NOTHING crosses the centre lane, at any height, so no arch ever enters the
-- platform camera's view down +Z or the ball arc. Each side is a cantilevered sign gantry: a pillar at
-- |x| = width/2 with a beam reaching in over the outer band to |x| = Kit.ArchInnerX, and the zone-name board
-- (the only text in the field besides distance markers) hanging under the beam. Opening: 2 * ArchInnerX
-- wide (140), unlimited height. Visual only: CanQuery/CanCollide off everywhere.
----------------------------------------------------------------------------------------------------
Kit.ArchInnerX = Kit.LaneHalf + 10 -- 70
Kit.ArchBeam = 1.6
Kit.ArchBoard = Vector3.new(34, 8, 1.6)

function Kit.ZoneArch(P: any, parent: Instance, center: Vector3, width: number, height: number, pillar: Color3,
	board: Color3, accent: Color3, text: string): Model
	local m = P.Model(parent, "Arch")
	local beamY = center.Y + height - 3
	local outerX = width / 2
	local beamLen = outerX + 2 - Kit.ArchInnerX
	local first: BasePart? = nil
	for _, side in { -1, 1 } do
		local base = center + Vector3.new(side * outerX, 0, 0)
		local p = P.Block(m, "Pillar", Vector3.new(4, height, 4), CFrame.new(base + Vector3.new(0, height / 2, 0)), pillar)
		first = first or p
		P.Block(m, "PillarTrim", Vector3.new(4.4, 1.2, 4.4), CFrame.new(base + Vector3.new(0, height * 0.4, 0)), accent,
			Enum.Material.Neon)
		P.Ball(m, "Orb", base + Vector3.new(0, height + 2.5, 0), 5, accent, Enum.Material.Neon)
		local bmx = center.X + side * (Kit.ArchInnerX + beamLen / 2)
		P.Block(m, "Beam", Vector3.new(beamLen, Kit.ArchBeam, 2), CFrame.new(bmx, beamY, center.Z), pillar)
		P.Block(m, "BeamTrim", Vector3.new(beamLen - 4, 0.4, 2.3), CFrame.new(bmx - side * 2, beamY - Kit.ArchBeam / 2, center.Z),
			accent, Enum.Material.Neon)
		P.Ball(m, "BeamEnd", Vector3.new(center.X + side * Kit.ArchInnerX, beamY, center.Z), 2.4, accent, Enum.Material.Neon)
		-- name board hanging under the beam
		local bs = Kit.ArchBoard
		local bx = center.X + side * (Kit.ArchInnerX + 2 + bs.X / 2)
		local by = beamY - Kit.ArchBeam / 2 - 0.6 - bs.Y / 2
		local b = P.Block(m, "Board", bs, CFrame.new(bx, by, center.Z), board)
		P.Block(m, "Trim", bs + Vector3.new(1.2, 1.2, -bs.Z * 0.5), CFrame.new(bx, by, center.Z), accent, Enum.Material.Neon)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			P.Label(b, text, { Face = face, PixelsPerStud = 8 })
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
			d.CanCollide = false
		end
	end
	m.PrimaryPart = first
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m:SetAttribute("Boundary", true)
	m:SetAttribute("BoundaryKind", "Arch")
	return m
end

----------------------------------------------------------------------------------------------------
-- Particles: one invisible volume part per effect covering the zone band
----------------------------------------------------------------------------------------------------
export type ParticleOpts = {
	Name: string,
	Y0: number, -- volume bottom (world Y)
	Y1: number, -- volume top
	HalfWidth: number?, -- default FieldHalf
	Rate: number,
	Lifetime: { number },
	Speed: { number },
	Size: NumberSequence | number,
	Color: ColorSequence | Color3,
	Transparency: NumberSequence?,
	Texture: string?,
	Direction: Enum.NormalId?,
	Spread: number?,
	Accel: Vector3?,
	Drag: number?,
	LightEmission: number?,
	RotSpeed: { number }?,
	Squash: NumberSequence?,
}

Kit.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Soft = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

function Kit.Particles(ctx: Ctx, o: ParticleOpts): ParticleEmitter
	local P = ctx.Props
	local half = o.HalfWidth or Kit.FieldHalf
	local z0, z1 = ctx.StartZ, ctx.MaxZ
	local vol = P.Part({ Parent = ctx.ZoneFolder, Name = "ParticleVolume_" .. o.Name,
		Size = Vector3.new(half * 2, math.max(1, o.Y1 - o.Y0), z1 - z0),
		CFrame = CFrame.new(Kit.CenterX, (o.Y0 + o.Y1) / 2, (z0 + z1) / 2),
		Transparency = 1, Collide = false, Query = false, Shadow = false })
	vol:SetAttribute("ParticleVolume", true)
	vol.CastShadow = false
	local e = Instance.new("ParticleEmitter")
	e.Name = o.Name
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = o.Direction or Enum.NormalId.Top
	e.Rate = o.Rate
	e.Lifetime = NumberRange.new(o.Lifetime[1], o.Lifetime[2] or o.Lifetime[1])
	e.Speed = NumberRange.new(o.Speed[1], o.Speed[2] or o.Speed[1])
	local size = o.Size
	e.Size = if typeof(size) == "number" then NumberSequence.new(size :: number) else size :: NumberSequence
	local color = o.Color
	e.Color = if typeof(color) == "Color3" then ColorSequence.new(color :: Color3) else color :: ColorSequence
	e.Transparency = o.Transparency or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 1),
	})
	e.Texture = o.Texture or Kit.Textures.Sparkle
	local spread = o.Spread or 0
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = o.Accel or Vector3.new(0, 0, 0)
	e.Drag = o.Drag or 0
	e.LightEmission = o.LightEmission or 0
	e.LightInfluence = if (o.LightEmission or 0) > 0.5 then 0 else 1
	local rot = o.RotSpeed
	if rot then
		e.RotSpeed = NumberRange.new(rot[1], rot[2] or rot[1])
		e.Rotation = NumberRange.new(0, 360)
	end
	if o.Squash then
		e.Squash = o.Squash
	end
	e.LockedToPart = false
	e.Parent = vol
	return e
end

return Kit
