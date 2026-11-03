--!strict
-- Shared helpers for the zone decorators. Decorations obey these placement rules:
--   * "Band" items sit in the OUTER 25% of the field width on each side (|x| in [LaneHalf, DecorMaxAbsX]),
--     so the centre lane (|x| < LaneHalf) stays clear for ball flight and dog runs.
--   * The zone landmark sits at the outer edge of the field, |x| <= LandmarkMaxAbsX (the scenery walls of the
--     outskirts start beyond that).
-- Points avoid the DistanceMarker signs (every 100 studs, |x| ~ MarkerX) and the zone arch pillars.
-- Every accepted point is also recorded in ctx.Taken (centre + footprint radius = margin) so later Band
-- calls of the same zone keep clear of earlier ones (no tree inside a doghouse, no bale inside a crop patch).
--
-- Tagging contract (read by tools/worldcheck/zones.luau):
--   Decor=true      on every placed decoration (one top-level Model/Part in ctx.Folder), 15-30 per zone
--   Landmark=true   on the one landmark model per zone (+ LandmarkHeight)
--   Boundary=true   on the zone-start arch (BoundaryKind "Arch") and the themed gate (BoundaryKind = style)
--   ParticleVolume  on the invisible, non-colliding, non-queryable parts that carry the zone ParticleEmitters
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any

local Kit = {}

local F = Layout.Field
Kit.FieldHalf = (F.MaxX - F.MinX) / 2 -- 120
Kit.CenterX = (F.MaxX + F.MinX) / 2 -- 0
Kit.LaneHalf = Kit.FieldHalf * 0.5 -- 60: centre 50% clear, outer 25% each side for decor
Kit.ApronHalf = Kit.FieldHalf + 100 -- 220: themed ground strip outside the field
Kit.MarkerX = Kit.LaneHalf + 8 -- 68: distance marker signs
Kit.ArchX = Kit.FieldHalf - 8 -- 112: zone arch pillars
Kit.MarkerEvery = 100
Kit.DecorMaxAbsX = Kit.FieldHalf - 2 -- 118: decorations stay inside the field
Kit.LandmarkMaxAbsX = Kit.FieldHalf + 30 -- 150: landmarks may overhang the field edge up to here
Kit.GateOffset = 5 -- themed gate sits this far past the zone arch
Kit.DecorStartOffset = 9 -- decorations start this far past the arch (clear of the gate)

export type Ctx = {
	Zone: any,
	Folder: Instance,
	MinZ: number, -- world Z where decorations may start
	MaxZ: number,
	StartZ: number, -- world Z of the band start
	ArchZ: number,
	Rng: Random,
	Decor: any, -- WorldTheme.ZoneDecor[ZoneId]
	Ground: Color3,
	Accent: Color3,
	Props: any,
	Y: number,
	Taken: { { X: number, Z: number, R: number } }?,
}

export type Slot = { Pos: Vector3, Side: number }

local function nearMarker(ctx: Ctx, x: number, z: number, margin: number): boolean
	local d = z - Layout.ThrowLine.Z
	local m = d % Kit.MarkerEvery
	local nearLine = m < margin or m > Kit.MarkerEvery - margin
	if nearLine and math.abs(math.abs(x) - Kit.MarkerX) < 6 + margin then
		return true
	end
	if math.abs(z - ctx.ArchZ) < 6 + margin and math.abs(math.abs(x) - Kit.ArchX) < 6 + margin then
		return true
	end
	return false
end

local function takenList(ctx: Ctx): { { X: number, Z: number, R: number } }
	local taken = ctx.Taken
	if taken == nil then
		taken = {}
		ctx.Taken = taken
	end
	return taken :: { { X: number, Z: number, R: number } }
end

local function pick(ctx: Ctx, count: number, minAbsX: number, maxAbsX: number, spacing: number,
	zPad: number, radius: number): { Slot }
	local out: { Slot } = {}
	local takenList = takenList(ctx)
	local tries = 0
	local z0, z1 = ctx.MinZ + zPad, ctx.MaxZ - zPad
	if ctx.ArchZ > z0 - zPad and ctx.ArchZ < z0 + 10 then
		z0 = math.max(z0, ctx.ArchZ + 8)
	end
	while #out < count and tries < count * 60 do
		tries += 1
		local side = if (#out + tries) % 2 == 0 then 1 else -1
		local x = Kit.CenterX + side * ctx.Rng:NextNumber(minAbsX, math.max(minAbsX, maxAbsX))
		local z = ctx.Rng:NextNumber(z0, math.max(z0 + 1, z1))
		if nearMarker(ctx, x, z, math.max(spacing * 0.4, radius)) then
			continue
		end
		local ok = true
		for _, s in out do
			if (Vector2.new(s.Pos.X, s.Pos.Z) - Vector2.new(x, z)).Magnitude < spacing then
				ok = false
				break
			end
		end
		if ok then
			for _, t in takenList do
				if (Vector2.new(t.X, t.Z) - Vector2.new(x, z)).Magnitude < t.R + radius then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(out, { Pos = Vector3.new(x, ctx.Y, z), Side = side })
			table.insert(takenList, { X = x, Z = z, R = radius })
		end
	end
	return out
end

-- Points inside the field's outer 25% band. `margin` (>= the item's footprint half-extent) keeps the item
-- off the lane edge, the field edge (DecorMaxAbsX) and the zone ends.
function Kit.Band(ctx: Ctx, count: number, spacing: number, margin: number?): { Slot }
	local m = margin or 4
	return pick(ctx, count, Kit.LaneHalf + m, Kit.DecorMaxAbsX - m, spacing, 6 + m, m)
end

-- Reserve a circular footprint (fixed placements, landmarks) so later Band calls avoid it.
function Kit.Reserve(ctx: Ctx, x: number, z: number, r: number)
	table.insert(takenList(ctx), { X = x, Z = z, R = r })
end

-- Evenly spaced Z values along the band (for fences/rows).
function Kit.Every(ctx: Ctx, step: number, pad: number): { number }
	local out = {}
	local z = ctx.MinZ + pad
	while z <= ctx.MaxZ - pad do
		table.insert(out, z)
		z += step
	end
	return out
end

function Kit.Yaw(ctx: Ctx): CFrame
	return CFrame.Angles(0, ctx.Rng:NextNumber(0, math.pi * 2), 0)
end

-- Faces the lane: yaw that turns a model's -Z front toward the field centre.
function Kit.FaceLane(side: number): CFrame
	return CFrame.Angles(0, if side > 0 then math.pi / 2 else -math.pi / 2, 0)
end

----------------------------------------------------------------------------------------------------
-- Tagging
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

-- Marks one placed decoration. Decorations never collide; small props cast no shadow.
function Kit.Decor<T>(ctx: Ctx, inst: T, small: boolean?): T
	local i = (inst :: any) :: Instance
	i:SetAttribute("Decor", true)
	i:SetAttribute("ZoneId", ctx.Zone.Id)
	eachPart(i, function(p)
		p.CanCollide = false
		p.CanTouch = false
		if small then
			p.CastShadow = false
		end
	end)
	return inst
end

function Kit.Landmark(ctx: Ctx, model: Model, height: number, kind: string): Model
	model:SetAttribute("Landmark", true)
	model:SetAttribute("LandmarkKind", kind)
	model:SetAttribute("LandmarkHeight", height)
	model:SetAttribute("ZoneId", ctx.Zone.Id)
	eachPart(model, function(p)
		p.CanCollide = false
		p.CanTouch = false
	end)
	return model
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
-- Zone gate (themed boundary across the outer bands at the zone start; the lane stays open)
----------------------------------------------------------------------------------------------------
export type GateStyle = {
	Kind: string, -- Hedge | Picket | Dune | Rail | Logs | Ice | Parapet | Bulkhead | Crystal
	Color: Color3,
	Trim: Color3,
	Material: Enum.Material?,
	TrimMaterial: Enum.Material?,
	Height: number,
}

function Kit.Gate(ctx: Ctx, style: GateStyle): Model
	local P = ctx.Props
	local m = P.Model(ctx.Folder.Parent :: Instance, "Gate")
	local z = ctx.ArchZ + Kit.GateOffset
	local x0, x1 = Kit.LaneHalf + 2, Kit.ArchX - 4 -- 62 .. 108: clear of the lane and the arch pillar
	local len = x1 - x0
	local h = style.Height
	for _, side in { -1, 1 } do
		local cx = Kit.CenterX + side * (x0 + x1) / 2
		local kind = style.Kind
		if kind == "Hedge" or kind == "Ice" or kind == "Dune" then
			P.Block(m, "Wall", Vector3.new(len, h, 3), CFrame.new(cx, ctx.Y + h / 2, z), style.Color, style.Material)
			P.Block(m, "Cap", Vector3.new(len + 0.4, 0.8, 3.4), CFrame.new(cx, ctx.Y + h + 0.1, z), style.Trim, style.TrimMaterial)
		elseif kind == "Picket" or kind == "Rail" or kind == "Logs" then
			local n = 6
			for i = 0, n do
				local px = Kit.CenterX + side * (x0 + len * i / n)
				P.Block(m, "Post", Vector3.new(1.4, h + 1, 1.4), CFrame.new(px, ctx.Y + (h + 1) / 2, z), style.Trim, style.TrimMaterial)
			end
			for _, frac in { 0.35, 0.8 } do
				P.Block(m, "Rail", Vector3.new(len, if kind == "Logs" then 1.6 else 0.8, 0.8),
					CFrame.new(cx, ctx.Y + h * frac, z), style.Color, style.Material)
			end
		elseif kind == "Parapet" or kind == "Bulkhead" then
			P.Block(m, "Wall", Vector3.new(len, h, 2), CFrame.new(cx, ctx.Y + h / 2, z), style.Color, style.Material)
			P.Block(m, "Trim", Vector3.new(len + 0.2, 0.6, 2.3), CFrame.new(cx, ctx.Y + h * 0.7, z), style.Trim, style.TrimMaterial)
			P.Block(m, "Pylon", Vector3.new(3, h + 3, 3), CFrame.new(Kit.CenterX + side * (x0 + 1.5), ctx.Y + (h + 3) / 2, z),
				style.Color:Lerp(Color3.new(0, 0, 0), 0.25), style.Material)
		else -- Crystal: a row of glowing shards
			for i = 0, 7 do
				local px = Kit.CenterX + side * (x0 + 2 + (len - 4) * i / 7)
				local sh = h * (if i % 2 == 0 then 1 else 0.65)
				P.Block(m, "Shard", Vector3.new(2.2, sh, 2.2), CFrame.new(px, ctx.Y + sh / 2, z) * CFrame.Angles(0, math.rad(45), 0),
					if i % 2 == 0 then style.Color else style.Trim, style.Material)
			end
		end
	end
	m:SetAttribute("Boundary", true)
	m:SetAttribute("BoundaryKind", style.Kind)
	m:SetAttribute("ZoneId", ctx.Zone.Id)
	eachPart(m, function(p)
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end)
	return m
end

----------------------------------------------------------------------------------------------------
-- Zone arch (the zone-start boundary across the whole field). Built for the raised throwing platform
-- (top Y = 40, eye ~45): only a thin beam crosses the lane, ABOVE eye level, so it never hides the field
-- ground; the zone-name boards (the only text in the field besides distance markers) hang under the
-- beam over the outer bands. Opening: (width - 4) wide x (height - beam) tall. Visual only: CanQuery off
-- everywhere so the cutscene landing raycast never stops on it.
----------------------------------------------------------------------------------------------------
Kit.ArchBeam = 1.6
Kit.ArchBoard = Vector3.new(26, 8, 1.6)

function Kit.ZoneArch(P: any, parent: Instance, center: Vector3, width: number, height: number, pillar: Color3,
	board: Color3, accent: Color3, text: string): Model
	local m = P.Model(parent, "Arch")
	local beamY = center.Y + height - Kit.ArchBeam / 2
	for _, side in { -1, 1 } do
		local base = center + Vector3.new(side * width / 2, 0, 0)
		P.Block(m, "Pillar", Vector3.new(4, height, 4), CFrame.new(base + Vector3.new(0, height / 2, 0)), pillar)
		P.Block(m, "PillarTrim", Vector3.new(4.4, 1.2, 4.4), CFrame.new(base + Vector3.new(0, height * 0.55, 0)), accent,
			Enum.Material.Neon)
		P.Ball(m, "Orb", base + Vector3.new(0, height + 2.5, 0), 5, accent, Enum.Material.Neon)
		-- name board hanging under the beam, next to the pillar (outside the centre lane)
		local bs = Kit.ArchBoard
		local bx = center.X + side * (width / 2 - 2 - 1 - bs.X / 2)
		local by = beamY - Kit.ArchBeam / 2 - 0.4 - bs.Y / 2
		local b = P.Block(m, "Board", bs, CFrame.new(bx, by, center.Z), board)
		P.Block(m, "Trim", bs + Vector3.new(1.2, 1.2, -bs.Z * 0.5), CFrame.new(bx, by, center.Z), accent, Enum.Material.Neon)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			P.Label(b, text, { Face = face, PixelsPerStud = 8 })
		end
		P.Block(m, "Hanger", Vector3.new(0.6, 0.6, 0.6), CFrame.new(bx, beamY - Kit.ArchBeam / 2 - 0.2, center.Z), pillar)
	end
	local beam = P.Block(m, "Beam", Vector3.new(width + 4, Kit.ArchBeam, 2), CFrame.new(center.X, beamY, center.Z), pillar)
	P.Block(m, "BeamTrim", Vector3.new(width, 0.4, 2.3), CFrame.new(center.X, beamY - Kit.ArchBeam / 2, center.Z), accent,
		Enum.Material.Neon)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
			d.CanCollide = false
		end
	end
	m.PrimaryPart = beam
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
	local vol = P.Part({ Parent = ctx.Folder.Parent :: Instance, Name = "ParticleVolume_" .. o.Name,
		Size = Vector3.new(half * 2, math.max(1, o.Y1 - o.Y0), z1 - z0),
		CFrame = CFrame.new(Kit.CenterX, (o.Y0 + o.Y1) / 2, (z0 + z1) / 2),
		Transparency = 1, Collide = false, Query = false, Shadow = false })
	vol:SetAttribute("ParticleVolume", true)
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
