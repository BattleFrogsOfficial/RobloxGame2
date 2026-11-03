--!strict
-- DogFactory: builds ANY of the 720 roster dogs on ONE shared procedural quadruped rig.
--
--   DogFactory.Build(dogData, variant?, isPuppy?) -> Model
--   DogFactory.Build(dogData, { Variant = "Gold", IsPuppy = true, NoVfx = false }) -> Model   (server form)
--
-- Rig (Parts + Motor6Ds, no Humanoid, no AnimationController; animated procedurally by DogAnimator):
--   Root (invisible, Anchored, PrimaryPart) --RootJoint--> Torso
--   Torso --Neck--> Head (--EarL/EarR--> ears; snout, nose, eyes welded)      extra heads: Neck2, Neck3
--   Torso --HipFL/HipFR/HipBL/HipBR--> LegFL/LegFR/LegBL/LegBR (paws welded)
--   Torso --TailJoint--> Tail                                                  extra tails: TailJoint2..9
--   Mythic extras: WingL/WingR (Motor6D), Orbit (Motor6D), everything else welded.
-- Built at unit size from BodyTypes proportions, then Model:ScaleTo(dog.Scale x puppy factor).
-- Forward is -Z (LookVector). Every coat part carries attribute Coat = "Primary" | "Secondary" so
-- VariantFX can recolour it; eyes carry Eye = true.
--
-- Rarity visual budget (driven by the roster fields, so data decides what a dog gets):
--   Common: body + coat + simple marking | Uncommon: + pattern | Rare: + accessory
--   Epic: + signature accessory + idle particles (Vfx "sparkle") | Legendary: texture coat + aura
--   Mythic: UniqueParts (extra heads, wings, halo, ...) + full VFX
local Shared = script.Parent.Parent
local BodyTypes = require(script.Parent:WaitForChild("BodyTypes"))
local VariantFX = require(script.Parent:WaitForChild("VariantFX"))
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))

export type BuildOptions = {
	Variant: string?,
	IsPuppy: boolean?,
	Puppy: boolean?,
	NoVfx: boolean?, -- skip particles/lights (e.g. tiny UI previews)
}

local DogFactory = {}

local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"

local BLACK = Color3.fromRGB(25, 20, 20)
local WHITE = Color3.fromRGB(245, 245, 245)

----------------------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------------------
local function hex(v: any, fallback: Color3): Color3
	if type(v) == "string" then
		local ok, c = pcall(Color3.fromHex, v)
		if ok then
			return c
		end
	elseif typeof(v) == "Color3" then
		return v
	end
	return fallback
end

local function hashString(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function lighten(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function darken(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

type Ctx = {
	Model: Model,
	Rng: Random,
	Primary: Color3,
	Secondary: Color3,
	CoatMaterial: Enum.Material,
	Body: BodyTypes.BodyType,
	T: Vector3, -- torso size
	H: Vector3, -- head size
	S: Vector3, -- snout size
	L: number, -- leg length
	Lt: number, -- leg thickness
	Root: BasePart,
	Torso: BasePart,
	Head: BasePart,
	Heads: { BasePart },
	Snout: BasePart,
	Legs: { BasePart },
	Paws: { BasePart },
	Tail: BasePart,
	TailLen: number,
	Ears: { BasePart },
	Rarity: string,
	RarityColor: Color3,
	NoVfx: boolean,
}

local function newPart(ctx: Ctx, name: string, size: Vector3, color: Color3, role: string?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = if role then ctx.CoatMaterial else Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if role then
		p:SetAttribute("Coat", role)
	end
	p.Parent = ctx.Model
	return p
end

-- Weld a new part to `parent` at parent-space `offset`.
local function attach(ctx: Ctx, parent: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3,
	role: string?, shape: Enum.PartType?): Part
	local p = newPart(ctx, name, size, color, role, shape)
	p.CFrame = parent.CFrame * offset
	local w = Instance.new("Weld")
	w.Name = "W_" .. name
	w.Part0 = parent
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	return p
end

-- Motor6D joint; positions part1 so the joint is satisfied without physics (also valid in ViewportFrames).
local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	part1.CFrame = part0.CFrame * c0 * c1:Inverse()
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	return m
end

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = SPARKLE_TEX
	e.LightEmission = 1
	e.Rate = 4
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.3, 1)
	e.SpreadAngle = Vector2.new(180, 180)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function sizeSeq(peak: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.4, peak),
		NumberSequenceKeypoint.new(1, 0),
	})
end

----------------------------------------------------------------------------------------------------
-- Surface plates (decal-less pattern blocks). Thin parts sitting just proud of a body face.
----------------------------------------------------------------------------------------------------
local PLATE = 0.06

-- Torso faces: "Top" | "Left" | "Right" | "Front" | "Back" | "Bottom". u,v in [-0.5,0.5] across the face.
local function torsoPlate(ctx: Ctx, name: string, face: string, u: number, v: number, su: number, sv: number,
	color: Color3, role: string?, material: Enum.Material?, rot: number?): Part
	local T = ctx.T
	local size: Vector3
	local pos: Vector3
	if face == "Top" then
		size = Vector3.new(su * T.X, PLATE, sv * T.Z)
		pos = Vector3.new(u * T.X, T.Y / 2 + PLATE / 2 - 0.01, v * T.Z)
	elseif face == "Bottom" then
		size = Vector3.new(su * T.X, PLATE, sv * T.Z)
		pos = Vector3.new(u * T.X, -T.Y / 2 - PLATE / 2 + 0.01, v * T.Z)
	elseif face == "Left" or face == "Right" then
		local sx = if face == "Left" then -1 else 1
		size = Vector3.new(PLATE, sv * T.Y, su * T.Z)
		pos = Vector3.new(sx * (T.X / 2 + PLATE / 2 - 0.01), v * T.Y, u * T.Z)
	elseif face == "Front" then
		size = Vector3.new(su * T.X, sv * T.Y, PLATE)
		pos = Vector3.new(u * T.X, v * T.Y, -T.Z / 2 - PLATE / 2 + 0.01)
	else
		size = Vector3.new(su * T.X, sv * T.Y, PLATE)
		pos = Vector3.new(u * T.X, v * T.Y, T.Z / 2 + PLATE / 2 - 0.01)
	end
	local cf = CFrame.new(pos)
	if rot then
		local axis = if face == "Top" or face == "Bottom" then CFrame.Angles(0, rot, 0)
			elseif face == "Left" or face == "Right" then CFrame.Angles(rot, 0, 0)
			else CFrame.Angles(0, 0, rot)
		cf *= axis
	end
	local p = attach(ctx, ctx.Torso, name, size, cf, color, role)
	if material then
		p.Material = material
	end
	return p
end

-- A band that wraps over the top and both sides of the torso at length position v (-0.5 back..0.5).
local function torsoBand(ctx: Ctx, name: string, v: number, width: number, color: Color3, role: string?,
	material: Enum.Material?, tilt: number?)
	torsoPlate(ctx, name .. "T", "Top", 0, v, 1.02, width, color, role, material, tilt)
	torsoPlate(ctx, name .. "L", "Left", v, 0.2, width, 0.6, color, role, material, tilt)
	torsoPlate(ctx, name .. "R", "Right", v, 0.2, width, 0.6, color, role, material, tilt)
end

local function headPlate(ctx: Ctx, head: BasePart, name: string, offset: Vector3, size: Vector3, color: Color3,
	role: string?): Part
	return attach(ctx, head, name, size, CFrame.new(offset), color, role)
end

----------------------------------------------------------------------------------------------------
-- Overlay drawers (shared by natural patterns and Legendary textures)
----------------------------------------------------------------------------------------------------
local function spots(ctx: Ctx, count: number, minS: number, maxS: number, color: Color3, role: string?,
	material: Enum.Material?)
	local r = ctx.Rng
	local faces = { "Top", "Left", "Right", "Top" }
	for i = 1, count do
		local face = faces[(i % #faces) + 1]
		local s = r:NextNumber(minS, maxS)
		torsoPlate(ctx, "Spot" .. i, face, r:NextNumber(-0.38, 0.38), r:NextNumber(-0.35, 0.35), s, s * 0.8,
			color, role, material, r:NextNumber(-0.6, 0.6))
	end
end

local function stripes(ctx: Ctx, count: number, width: number, color: Color3, role: string?, material: Enum.Material?,
	tilt: number?)
	for i = 1, count do
		local v = -0.4 + 0.8 * (i - 0.5) / count
		torsoBand(ctx, "Stripe" .. i, v, width, color, role, material, tilt)
	end
end

local function zigzag(ctx: Ctx, count: number, color: Color3, role: string?, material: Enum.Material?)
	for i = 1, count do
		local v = -0.4 + 0.8 * (i - 0.5) / count
		local tilt = if i % 2 == 0 then 0.5 else -0.5
		torsoBand(ctx, "Zig" .. i, v, 0.07, color, role, material, tilt)
	end
end

local function veins(ctx: Ctx, count: number, color: Color3, material: Enum.Material?)
	local r = ctx.Rng
	local faces = { "Top", "Left", "Right" }
	for i = 1, count do
		torsoPlate(ctx, "Vein" .. i, faces[(i % 3) + 1], r:NextNumber(-0.3, 0.3), r:NextNumber(-0.3, 0.3),
			r:NextNumber(0.04, 0.07), r:NextNumber(0.35, 0.7), color, "Secondary", material, r:NextNumber(-1.2, 1.2))
	end
end

local function facets(ctx: Ctx, count: number, color: Color3, material: Enum.Material?)
	local r = ctx.Rng
	for i = 1, count do
		local s = r:NextNumber(0.14, 0.26)
		local face = if i % 3 == 0 then "Left" elseif i % 3 == 1 then "Right" else "Top"
		torsoPlate(ctx, "Facet" .. i, face, r:NextNumber(-0.4, 0.4), r:NextNumber(-0.35, 0.35), s, s,
			color, "Secondary", material, math.rad(45))
	end
end

local function grid(ctx: Ctx, color: Color3, material: Enum.Material?)
	for i = 1, 4 do
		local v = -0.45 + 0.9 * (i - 0.5) / 4
		torsoBand(ctx, "GridZ" .. i, v, 0.03, color, "Secondary", material)
	end
	torsoPlate(ctx, "GridX1", "Top", -0.2, 0, 0.03, 1, color, "Secondary", material)
	torsoPlate(ctx, "GridX2", "Top", 0.2, 0, 0.03, 1, color, "Secondary", material)
	torsoPlate(ctx, "GridL", "Left", 0, 0.1, 1, 0.03, color, "Secondary", material)
	torsoPlate(ctx, "GridR", "Right", 0, 0.1, 1, 0.03, color, "Secondary", material)
end

local function sunburst(ctx: Ctx, color: Color3, material: Enum.Material?)
	for i = 0, 5 do
		torsoPlate(ctx, "Ray" .. i, "Left", 0, 0, 0.06, 0.9, color, "Secondary", material, i * math.pi / 6)
		torsoPlate(ctx, "RayR" .. i, "Right", 0, 0, 0.06, 0.9, color, "Secondary", material, i * math.pi / 6)
	end
	torsoPlate(ctx, "SunCoreL", "Left", 0, 0, 0.22, 0.3, color, "Secondary", material)
	torsoPlate(ctx, "SunCoreR", "Right", 0, 0, 0.22, 0.3, color, "Secondary", material)
end

local function socks(ctx: Ctx, color: Color3)
	for i, leg in ctx.Legs do
		local Lp = leg.Size.Y
		attach(ctx, leg, "Sock" .. i, Vector3.new(ctx.Lt + 0.04, Lp * 0.35, ctx.Lt + 0.04),
			CFrame.new(0, -Lp / 2 + Lp * 0.175, 0), color, "Secondary")
	end
	for _, paw in ctx.Paws do
		paw.Color = color
		paw:SetAttribute("Coat", "Secondary")
	end
end

local function tips(ctx: Ctx, color: Color3, material: Enum.Material?)
	local tail = ctx.Tail
	local tip = attach(ctx, tail, "TailTip", Vector3.new(tail.Size.X + 0.04, ctx.TailLen * 0.3, tail.Size.Z + 0.04),
		CFrame.new(0, ctx.TailLen * 0.35, 0), color, "Secondary")
	if material then
		tip.Material = material
	end
	for i, ear in ctx.Ears do
		local e = attach(ctx, ear, "EarTip" .. i, ear.Size * Vector3.new(1.05, 0.3, 1.05),
			CFrame.new(0, ear.Size.Y * 0.36 * (if ear:GetAttribute("Hangs") then -1 else 1), 0), color, "Secondary")
		if material then
			e.Material = material
		end
	end
end

local function chest(ctx: Ctx, color: Color3, role: string?)
	torsoPlate(ctx, "Chest", "Front", 0, 0, 0.6, 0.75, color, role)
	torsoPlate(ctx, "Belly", "Bottom", 0, -0.15, 0.6, 0.6, color, role)
end

----------------------------------------------------------------------------------------------------
-- Patterns
----------------------------------------------------------------------------------------------------
local Patterns: { [string]: (Ctx) -> () } = {}

Patterns.none = function(_ctx) end
Patterns.socks = function(ctx)
	socks(ctx, ctx.Secondary)
end
Patterns.blaze = function(ctx)
	local H = ctx.H
	headPlate(ctx, ctx.Head, "Blaze", Vector3.new(0, H.Y * 0.2, -H.Z / 2 - 0.02), Vector3.new(H.X * 0.22, H.Y * 0.7, PLATE),
		ctx.Secondary, "Secondary")
	ctx.Snout.Color = ctx.Secondary
	ctx.Snout:SetAttribute("Coat", "Secondary")
end
Patterns.mask = function(ctx)
	local H = ctx.H
	headPlate(ctx, ctx.Head, "Mask", Vector3.new(0, H.Y * 0.05, -H.Z / 2 - 0.02), Vector3.new(H.X * 1.02, H.Y * 0.45, PLATE),
		ctx.Secondary, "Secondary")
	ctx.Snout.Color = ctx.Secondary
	ctx.Snout:SetAttribute("Coat", "Secondary")
end
Patterns.saddle = function(ctx)
	torsoPlate(ctx, "Saddle", "Top", 0, 0.05, 1.04, 0.6, ctx.Secondary, "Secondary")
	torsoPlate(ctx, "SaddleL", "Left", 0.05, 0.3, 0.6, 0.4, ctx.Secondary, "Secondary")
	torsoPlate(ctx, "SaddleR", "Right", 0.05, 0.3, 0.6, 0.4, ctx.Secondary, "Secondary")
end
Patterns.tuxedo = function(ctx)
	chest(ctx, ctx.Secondary, "Secondary")
	socks(ctx, ctx.Secondary)
end
Patterns.tan_points = function(ctx)
	local H = ctx.H
	for i, sx in { -1, 1 } do
		headPlate(ctx, ctx.Head, "Brow" .. i, Vector3.new(sx * H.X * 0.24, H.Y * 0.3, -H.Z / 2 - 0.02),
			Vector3.new(H.X * 0.16, H.Y * 0.1, PLATE), ctx.Secondary, "Secondary")
	end
	ctx.Snout.Color = ctx.Secondary
	ctx.Snout:SetAttribute("Coat", "Secondary")
	socks(ctx, ctx.Secondary)
	torsoPlate(ctx, "Chest", "Front", 0, -0.1, 0.5, 0.5, ctx.Secondary, "Secondary")
end
Patterns.eye_patch = function(ctx)
	local H = ctx.H
	headPlate(ctx, ctx.Head, "EyePatch", Vector3.new(H.X * 0.24, H.Y * 0.12, -H.Z / 2 - 0.02),
		Vector3.new(H.X * 0.4, H.Y * 0.4, PLATE), ctx.Secondary, "Secondary")
end
Patterns.merle = function(ctx)
	spots(ctx, 7, 0.15, 0.3, ctx.Secondary, "Secondary")
	spots(ctx, 4, 0.08, 0.16, darken(ctx.Primary, 0.5), "Secondary")
end
Patterns.brindle = function(ctx)
	stripes(ctx, 7, 0.04, ctx.Secondary, "Secondary", nil, 0.25)
end
Patterns.spotted = function(ctx)
	spots(ctx, 9, 0.12, 0.22, ctx.Secondary, "Secondary")
end
Patterns.ticked = function(ctx)
	spots(ctx, 16, 0.04, 0.08, ctx.Secondary, "Secondary")
end
Patterns.sable = function(ctx)
	torsoPlate(ctx, "SableTop", "Top", 0, 0, 1.04, 1.02, ctx.Secondary, "Secondary")
	torsoPlate(ctx, "SableL", "Left", 0, 0.35, 1.02, 0.3, ctx.Secondary, "Secondary")
	torsoPlate(ctx, "SableR", "Right", 0, 0.35, 1.02, 0.3, ctx.Secondary, "Secondary")
end
Patterns.piebald = function(ctx)
	spots(ctx, 4, 0.35, 0.55, ctx.Secondary, "Secondary")
end
Patterns.roan = function(ctx)
	spots(ctx, 20, 0.04, 0.07, lighten(ctx.Secondary, 0.2), "Secondary")
end
Patterns.dapple = function(ctx)
	spots(ctx, 10, 0.1, 0.18, lighten(ctx.Secondary, 0.1), "Secondary")
end
Patterns.harlequin = function(ctx)
	spots(ctx, 8, 0.18, 0.34, ctx.Secondary, "Secondary")
	torsoPlate(ctx, "HarlequinNeck", "Front", 0, 0.2, 1.02, 0.4, ctx.Secondary, "Secondary")
end
-- fancy (Uncommon+)
Patterns.tiger_stripe = function(ctx)
	stripes(ctx, 6, 0.06, ctx.Secondary, "Secondary", nil, 0.15)
end
Patterns.star_freckles = function(ctx)
	spots(ctx, 10, 0.06, 0.1, ctx.Secondary, "Secondary", Enum.Material.Neon)
end
Patterns.sunburst = function(ctx)
	sunburst(ctx, ctx.Secondary, nil)
end
Patterns.frost_tips = function(ctx)
	tips(ctx, lighten(ctx.Secondary, 0.5), Enum.Material.Ice)
end
Patterns.lightning_streak = function(ctx)
	torsoPlate(ctx, "BoltL1", "Left", -0.15, 0.15, 0.08, 0.6, ctx.Secondary, "Secondary", Enum.Material.Neon, 0.6)
	torsoPlate(ctx, "BoltL2", "Left", 0.1, -0.05, 0.08, 0.6, ctx.Secondary, "Secondary", Enum.Material.Neon, -0.6)
	torsoPlate(ctx, "BoltR1", "Right", -0.15, 0.15, 0.08, 0.6, ctx.Secondary, "Secondary", Enum.Material.Neon, 0.6)
	torsoPlate(ctx, "BoltR2", "Right", 0.1, -0.05, 0.08, 0.6, ctx.Secondary, "Secondary", Enum.Material.Neon, -0.6)
end
Patterns.wave_stripes = function(ctx)
	for i = 1, 4 do
		local tilt = if i % 2 == 0 then 0.35 else -0.35
		torsoBand(ctx, "Wave" .. i, -0.36 + 0.24 * (i - 1), 0.08, ctx.Secondary, "Secondary", nil, tilt)
	end
end
Patterns.leaf_dapple = function(ctx)
	spots(ctx, 8, 0.12, 0.2, ctx.Secondary, "Secondary", Enum.Material.LeafyGrass)
end
Patterns.heart_patch = function(ctx)
	-- two rotated squares + a diamond read as a heart from the side
	for _, face in { "Left", "Right" } do
		torsoPlate(ctx, "Heart" .. face .. "A", face, -0.06, 0.08, 0.16, 0.3, ctx.Secondary, "Secondary", nil, math.rad(45))
		torsoPlate(ctx, "Heart" .. face .. "B", face, 0.06, 0.08, 0.16, 0.3, ctx.Secondary, "Secondary", nil, math.rad(-45))
	end
end
Patterns.checker = function(ctx)
	for i = 1, 4 do
		for j = 1, 2 do
			if (i + j) % 2 == 0 then
				local u = -0.375 + (i - 1) * 0.25
				torsoPlate(ctx, ("CheckT%d%d"):format(i, j), "Top", -0.25 + (j - 1) * 0.5, u, 0.5, 0.25,
					ctx.Secondary, "Secondary")
				torsoPlate(ctx, ("CheckS%d%d"):format(i, j), if j == 1 then "Left" else "Right", u, 0.1, 0.25, 0.5,
					ctx.Secondary, "Secondary")
			end
		end
	end
end
Patterns.polka_dots = function(ctx)
	spots(ctx, 12, 0.1, 0.12, ctx.Secondary, "Secondary")
end
Patterns.ember_tips = function(ctx)
	tips(ctx, ctx.Secondary, Enum.Material.Neon)
end
Patterns.zigzag = function(ctx)
	zigzag(ctx, 6, ctx.Secondary, "Secondary")
end

-- Legendary coat textures: a material for the base coat + an overlay drawn in the secondary colour.
type Texture = { Material: Enum.Material, Overlay: string, Neon: boolean, Reflectance: number? }
local TEXTURES: { [string]: Texture } = {
	galaxy_swirl = { Material = Enum.Material.SmoothPlastic, Overlay = "spots", Neon = true },
	lava_crackle = { Material = Enum.Material.CrackedLava, Overlay = "veins", Neon = true },
	aurora_shimmer = { Material = Enum.Material.Glass, Overlay = "stripes", Neon = true },
	marble_veins = { Material = Enum.Material.Marble, Overlay = "veins", Neon = false },
	crystal_facets = { Material = Enum.Material.Glass, Overlay = "facets", Neon = false, Reflectance = 0.15 },
	stardust = { Material = Enum.Material.SmoothPlastic, Overlay = "dust", Neon = true },
	storm_cloud = { Material = Enum.Material.Slate, Overlay = "zigzag", Neon = true },
	molten_metal = { Material = Enum.Material.Foil, Overlay = "veins", Neon = true },
	opal_sheen = { Material = Enum.Material.Glass, Overlay = "facets", Neon = false, Reflectance = 0.25 },
	coral_reef = { Material = Enum.Material.Pebble, Overlay = "spots", Neon = false },
	bark_rings = { Material = Enum.Material.Wood, Overlay = "stripes", Neon = false },
	circuit_lines = { Material = Enum.Material.SmoothPlastic, Overlay = "grid", Neon = true },
	nebula = { Material = Enum.Material.SmoothPlastic, Overlay = "clouds", Neon = true },
	ice_glaze = { Material = Enum.Material.Ice, Overlay = "facets", Neon = false, Reflectance = 0.1 },
	flame_lick = { Material = Enum.Material.SmoothPlastic, Overlay = "flames", Neon = true },
	moss_velvet = { Material = Enum.Material.Fabric, Overlay = "spots", Neon = false },
	tidal_foam = { Material = Enum.Material.SmoothPlastic, Overlay = "waves", Neon = false },
	rose_vine = { Material = Enum.Material.Fabric, Overlay = "veins", Neon = false },
	sunflare = { Material = Enum.Material.SmoothPlastic, Overlay = "sunburst", Neon = true },
	petal_storm = { Material = Enum.Material.SmoothPlastic, Overlay = "dust", Neon = false },
	neon_grid = { Material = Enum.Material.SmoothPlastic, Overlay = "grid", Neon = true },
	honeycomb = { Material = Enum.Material.SmoothPlastic, Overlay = "facets", Neon = false },
	thunder_scales = { Material = Enum.Material.Slate, Overlay = "zigzag", Neon = true },
	pearl_luster = { Material = Enum.Material.SmoothPlastic, Overlay = "dust", Neon = false, Reflectance = 0.3 },
}

local function applyTexture(ctx: Ctx, tex: Texture)
	for _, d in ctx.Model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Coat") == "Primary" then
			d.Material = tex.Material
			if tex.Reflectance then
				d.Reflectance = tex.Reflectance
			end
		end
	end
	local mat = if tex.Neon then Enum.Material.Neon else nil
	local c = ctx.Secondary
	local o = tex.Overlay
	if o == "spots" then
		spots(ctx, 9, 0.1, 0.24, c, "Secondary", mat)
	elseif o == "dust" then
		spots(ctx, 18, 0.04, 0.08, c, "Secondary", mat)
	elseif o == "clouds" then
		spots(ctx, 5, 0.3, 0.5, c, "Secondary", nil)
		spots(ctx, 8, 0.05, 0.08, WHITE, "Secondary", Enum.Material.Neon)
	elseif o == "veins" then
		veins(ctx, 10, c, mat)
	elseif o == "stripes" then
		stripes(ctx, 5, 0.06, c, "Secondary", mat, 0.2)
	elseif o == "waves" then
		for i = 1, 5 do
			torsoBand(ctx, "Wave" .. i, -0.4 + 0.2 * (i - 1), 0.06, c, "Secondary", mat, if i % 2 == 0 then 0.4 else -0.4)
		end
	elseif o == "zigzag" then
		zigzag(ctx, 7, c, "Secondary", mat)
	elseif o == "facets" then
		facets(ctx, 14, c, mat)
	elseif o == "grid" then
		grid(ctx, c, mat)
	elseif o == "sunburst" then
		sunburst(ctx, c, mat)
	elseif o == "flames" then
		tips(ctx, c, Enum.Material.Neon)
		stripes(ctx, 4, 0.07, c, "Secondary", mat, 0.6)
	end
end

----------------------------------------------------------------------------------------------------
-- Accessories (placeholder parts named Acc_<id>; the real meshes can replace these by name later)
----------------------------------------------------------------------------------------------------
local GOLD = Color3.fromRGB(255, 200, 60)
local SILVER = Color3.fromRGB(200, 205, 215)

type AccSpec = { Builder: string, Color: Color3, Accent: Color3?, [string]: any }
local ACCESSORIES: { [string]: AccSpec } = {
	-- hats
	straw_hat = { Builder = "brim", Color = Color3.fromRGB(230, 200, 120), Accent = Color3.fromRGB(200, 60, 60), Brim = 1.7 },
	ranger_hat = { Builder = "brim", Color = Color3.fromRGB(150, 120, 70), Accent = Color3.fromRGB(80, 60, 40), Brim = 1.5 },
	captain_hat = { Builder = "brim", Color = WHITE, Accent = Color3.fromRGB(30, 40, 80), Brim = 1.15, Badge = GOLD },
	pirate_hat = { Builder = "brim", Color = Color3.fromRGB(30, 28, 30), Accent = GOLD, Brim = 1.5, Upturned = true, Badge = WHITE },
	sailor_cap = { Builder = "cap", Color = WHITE, Accent = Color3.fromRGB(40, 70, 160) },
	baseball_cap = { Builder = "cap", Color = Color3.fromRGB(220, 50, 50), Accent = WHITE, Visor = true },
	beanie = { Builder = "cap", Color = Color3.fromRGB(60, 130, 210), Accent = WHITE, Bobble = true },
	aviator_cap = { Builder = "helmet", Color = Color3.fromRGB(120, 80, 50), Accent = Color3.fromRGB(80, 160, 200) },
	hard_hat = { Builder = "helmet", Color = Color3.fromRGB(255, 200, 30), Accent = Color3.fromRGB(240, 240, 240), Brimmed = true },
	knight_helm = { Builder = "helmet", Color = SILVER, Accent = Color3.fromRGB(200, 40, 40), Plume = true, Metal = true },
	samurai_helm = { Builder = "helmet", Color = Color3.fromRGB(150, 30, 30), Accent = GOLD, Horns = true, Metal = true },
	space_helmet = { Builder = "bubble", Color = Color3.fromRGB(200, 230, 255), Accent = WHITE },
	top_hat = { Builder = "tall", Color = Color3.fromRGB(30, 30, 35), Accent = Color3.fromRGB(180, 40, 40), Height = 0.9 },
	chef_hat = { Builder = "tall", Color = WHITE, Accent = WHITE, Height = 0.8, Puffy = true },
	wizard_hat = { Builder = "cone", Color = Color3.fromRGB(70, 50, 170), Accent = GOLD },
	crown = { Builder = "crown", Color = GOLD, Accent = Color3.fromRGB(220, 40, 60), Metal = true },
	crystal_tiara = { Builder = "crown", Color = Color3.fromRGB(190, 230, 255), Accent = Color3.fromRGB(150, 220, 255), Glass = true },
	laurel_wreath = { Builder = "wreath", Color = Color3.fromRGB(230, 190, 70), Accent = GOLD },
	flower_crown = { Builder = "wreath", Color = Color3.fromRGB(90, 170, 80), Accent = Color3.fromRGB(255, 130, 180), Flowers = true },
	leaf_wreath = { Builder = "wreath", Color = Color3.fromRGB(70, 150, 60), Accent = Color3.fromRGB(110, 190, 80) },
	headphones = { Builder = "muffs", Color = Color3.fromRGB(40, 40, 45), Accent = Color3.fromRGB(80, 200, 255) },
	earmuffs = { Builder = "muffs", Color = Color3.fromRGB(240, 120, 160), Accent = WHITE },
	antenna_headband = { Builder = "antenna", Color = Color3.fromRGB(60, 60, 70), Accent = Color3.fromRGB(120, 255, 120) },
	-- neck
	bandana = { Builder = "collar", Color = Color3.fromRGB(210, 40, 40), Bib = true },
	collar_bell = { Builder = "collar", Color = Color3.fromRGB(200, 40, 40), Accent = GOLD, Bell = 0.28 },
	scarf = { Builder = "collar", Color = Color3.fromRGB(200, 60, 60), Accent = WHITE, Thick = true, Tail = true },
	bow_tie = { Builder = "collar", Color = Color3.fromRGB(40, 40, 160), Bow = true },
	spiked_collar = { Builder = "collar", Color = Color3.fromRGB(30, 30, 30), Accent = SILVER, Spikes = true },
	pearl_necklace = { Builder = "collar", Color = WHITE, Beads = true },
	royal_collar = { Builder = "collar", Color = GOLD, Accent = Color3.fromRGB(200, 30, 60), Thick = true, Gem = true, Metal = true },
	rune_collar = { Builder = "collar", Color = Color3.fromRGB(40, 40, 60), Accent = Color3.fromRGB(90, 200, 255), NeonAccent = true, Gem = true },
	cowbell = { Builder = "collar", Color = Color3.fromRGB(110, 70, 40), Accent = Color3.fromRGB(200, 170, 90), Bell = 0.5 },
	lifeguard_whistle = { Builder = "collar", Color = Color3.fromRGB(230, 40, 40), Accent = Color3.fromRGB(255, 220, 60), Bell = 0.2, Thin = true },
	sheriff_star = { Builder = "collar", Color = Color3.fromRGB(120, 80, 50), Accent = GOLD, Star = true },
	pearl = { Builder = "collar", Color = WHITE, Beads = true },
	-- face
	sunglasses = { Builder = "glasses", Color = Color3.fromRGB(20, 20, 25), Accent = Color3.fromRGB(30, 30, 30) },
	goggles = { Builder = "glasses", Color = Color3.fromRGB(150, 220, 255), Accent = Color3.fromRGB(90, 60, 40), Strap = true, Glass = true },
	monocle = { Builder = "glasses", Color = Color3.fromRGB(200, 230, 255), Accent = GOLD, Single = true, Glass = true },
	binoculars = { Builder = "binoculars", Color = Color3.fromRGB(40, 40, 40), Accent = Color3.fromRGB(120, 180, 220) },
	-- body
	raincoat = { Builder = "coat", Color = Color3.fromRGB(255, 210, 40), Accent = Color3.fromRGB(255, 210, 40) },
	life_vest = { Builder = "coat", Color = Color3.fromRGB(255, 120, 30), Accent = WHITE, Short = true },
	hoodie = { Builder = "coat", Color = Color3.fromRGB(110, 110, 130), Accent = Color3.fromRGB(90, 90, 110), Hood = true },
	astronaut_suit = { Builder = "coat", Color = WHITE, Accent = Color3.fromRGB(60, 120, 220), Bubble = true },
	backpack = { Builder = "pack", Color = Color3.fromRGB(60, 130, 80), Accent = Color3.fromRGB(240, 200, 60) },
	saddlebag = { Builder = "pack", Color = Color3.fromRGB(130, 80, 40), Accent = Color3.fromRGB(200, 160, 90), Sides = true },
	tool_belt = { Builder = "pack", Color = Color3.fromRGB(110, 75, 40), Accent = SILVER, Belt = true },
	jet_pack = { Builder = "pack", Color = SILVER, Accent = Color3.fromRGB(255, 120, 40), Jets = true, Metal = true },
	cape = { Builder = "cape", Color = Color3.fromRGB(200, 30, 40), Accent = GOLD },
	star_cloak = { Builder = "cape", Color = Color3.fromRGB(30, 30, 90), Accent = Color3.fromRGB(255, 240, 150), Stars = true },
	snow_boots = { Builder = "boots", Color = Color3.fromRGB(140, 60, 50), Accent = WHITE },
	-- held in the mouth
	lantern = { Builder = "lantern", Color = Color3.fromRGB(60, 50, 40), Accent = Color3.fromRGB(255, 210, 110) },
	trident = { Builder = "trident", Color = GOLD, Accent = Color3.fromRGB(80, 200, 220) },
}

local function headTop(ctx: Ctx): CFrame
	return CFrame.new(0, ctx.H.Y / 2, 0)
end

local AccBuilders: { [string]: (Ctx, string, AccSpec) -> () } = {}

AccBuilders.brim = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	local b = s.Brim or 1.5
	attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * b, 0.08, H.Z * b), headTop(ctx) * CFrame.new(0, 0.04, 0), s.Color)
	attach(ctx, head, "Acc_" .. id .. "_Crown", Vector3.new(H.X * 0.7, H.Y * 0.38, H.Z * 0.7),
		headTop(ctx) * CFrame.new(0, H.Y * 0.19, 0), s.Color)
	attach(ctx, head, "Acc_" .. id .. "_Band", Vector3.new(H.X * 0.72, H.Y * 0.1, H.Z * 0.72),
		headTop(ctx) * CFrame.new(0, H.Y * 0.07, 0), s.Accent or s.Color)
	if s.Upturned then
		for _, sx in { -1, 1 } do
			attach(ctx, head, "Acc_" .. id .. "_Flap", Vector3.new(0.08, H.Y * 0.35, H.Z * b * 0.9),
				headTop(ctx) * CFrame.new(sx * H.X * b * 0.48, H.Y * 0.15, 0) * CFrame.Angles(0, 0, sx * -0.3), s.Color)
		end
	end
	if s.Badge then
		attach(ctx, head, "Acc_" .. id .. "_Badge", Vector3.new(H.X * 0.2, H.Y * 0.18, 0.05),
			headTop(ctx) * CFrame.new(0, H.Y * 0.2, -H.Z * 0.36), s.Badge).Material = Enum.Material.Neon
	end
end

AccBuilders.cap = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * 0.85, H.Y * 0.3, H.Z * 0.85), headTop(ctx) * CFrame.new(0, H.Y * 0.1, 0), s.Color)
	if s.Visor then
		attach(ctx, head, "Acc_" .. id .. "_Visor", Vector3.new(H.X * 0.7, 0.06, H.Z * 0.45),
			headTop(ctx) * CFrame.new(0, 0.02, -H.Z * 0.6), s.Accent or s.Color)
	else
		attach(ctx, head, "Acc_" .. id .. "_Band", Vector3.new(H.X * 0.88, H.Y * 0.08, H.Z * 0.88),
			headTop(ctx) * CFrame.new(0, 0, 0), s.Accent or s.Color)
	end
	if s.Bobble then
		attach(ctx, head, "Acc_" .. id .. "_Bobble", Vector3.one * H.X * 0.3, headTop(ctx) * CFrame.new(0, H.Y * 0.32, 0),
			s.Accent or WHITE, nil, Enum.PartType.Ball).Material = Enum.Material.Fabric
	end
end

AccBuilders.helmet = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	local p = attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * 1.08, H.Y * 0.55, H.Z * 1.08),
		headTop(ctx) * CFrame.new(0, -H.Y * 0.12, 0.02), s.Color)
	if s.Metal then
		p.Material = Enum.Material.Metal
	end
	if s.Brimmed then
		attach(ctx, head, "Acc_" .. id .. "_Brim", Vector3.new(H.X * 1.3, 0.07, H.Z * 1.3), headTop(ctx) * CFrame.new(0, -H.Y * 0.36, 0),
			s.Color)
	end
	attach(ctx, head, "Acc_" .. id .. "_Trim", Vector3.new(H.X * 1.1, H.Y * 0.08, H.Z * 1.1),
		headTop(ctx) * CFrame.new(0, -H.Y * 0.36, 0.02), s.Accent or s.Color)
	if s.Plume then
		attach(ctx, head, "Acc_" .. id .. "_Plume", Vector3.new(0.12, H.Y * 0.5, H.Z * 0.8),
			headTop(ctx) * CFrame.new(0, H.Y * 0.35, 0.1), s.Accent or s.Color).Material = Enum.Material.Fabric
	end
	if s.Horns then
		for _, sx in { -1, 1 } do
			attach(ctx, head, "Acc_" .. id .. "_Crest", Vector3.new(0.08, H.Y * 0.6, 0.12),
				headTop(ctx) * CFrame.new(sx * H.X * 0.25, H.Y * 0.3, -H.Z * 0.45) * CFrame.Angles(0, 0, sx * -0.45),
				s.Accent or GOLD).Material = Enum.Material.Metal
		end
	end
end

AccBuilders.bubble = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	local d = math.max(H.X, H.Y, H.Z) * 1.7
	local p = attach(ctx, head, "Acc_" .. id, Vector3.one * d, CFrame.new(0, H.Y * 0.05, -H.Z * 0.1), s.Color, nil,
		Enum.PartType.Ball)
	p.Material = Enum.Material.Glass
	p.Transparency = 0.6
	attach(ctx, head, "Acc_" .. id .. "_Ring", Vector3.new(d * 0.75, 0.15, d * 0.75), CFrame.new(0, -H.Y * 0.55, 0.05),
		s.Accent or WHITE)
end

AccBuilders.tall = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	local h = H.Y * (s.Height or 0.9)
	if not s.Puffy then
		attach(ctx, head, "Acc_" .. id .. "_Brim", Vector3.new(H.X * 1.1, 0.07, H.Z * 1.1), headTop(ctx) * CFrame.new(0, 0.03, 0), s.Color)
	end
	attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * 0.62, h, H.Z * 0.62), headTop(ctx) * CFrame.new(0, h / 2, 0), s.Color)
	if s.Puffy then
		attach(ctx, head, "Acc_" .. id .. "_Puff", Vector3.one * H.X * 0.85, headTop(ctx) * CFrame.new(0, h, 0), s.Color, nil,
			Enum.PartType.Ball)
	else
		attach(ctx, head, "Acc_" .. id .. "_Band", Vector3.new(H.X * 0.64, h * 0.18, H.Z * 0.64),
			headTop(ctx) * CFrame.new(0, h * 0.15, 0), s.Accent or s.Color)
	end
end

AccBuilders.cone = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	attach(ctx, head, "Acc_" .. id .. "_Brim", Vector3.new(H.X * 1.4, 0.07, H.Z * 1.4), headTop(ctx) * CFrame.new(0, 0.03, 0), s.Color)
	local y = 0
	for i = 1, 4 do
		local w = H.X * (0.75 - (i - 1) * 0.17)
		local h = H.Y * 0.32
		attach(ctx, head, "Acc_" .. id .. (if i == 1 then "" else "_" .. i), Vector3.new(w, h, w),
			headTop(ctx) * CFrame.new(0, y + h / 2, (i - 1) * 0.06) * CFrame.Angles(-0.08 * i, 0, 0), s.Color)
		y += h * 0.9
	end
	for i = 1, 3 do
		attach(ctx, head, "Acc_" .. id .. "_Star" .. i, Vector3.one * 0.12, headTop(ctx) * CFrame.new((i - 2) * H.X * 0.2, H.Y * 0.2, -H.X * 0.38)
			* CFrame.Angles(0, 0, math.rad(45)), s.Accent or GOLD).Material = Enum.Material.Neon
	end
end

AccBuilders.crown = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	local band = attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * 0.8, H.Y * 0.15, H.Z * 0.8), headTop(ctx) * CFrame.new(0, H.Y * 0.07, 0),
		s.Color)
	band.Material = if s.Glass then Enum.Material.Glass else Enum.Material.Metal
	for i = 0, 7 do
		local a = i * math.pi / 4
		local p = attach(ctx, head, "Acc_" .. id .. "_Point" .. i, Vector3.new(0.12, H.Y * 0.22, 0.12),
			headTop(ctx) * CFrame.new(math.cos(a) * H.X * 0.38, H.Y * 0.25, math.sin(a) * H.Z * 0.38) * CFrame.Angles(0, 0, math.rad(45)),
			s.Color)
		p.Material = band.Material
	end
	attach(ctx, head, "Acc_" .. id .. "_Gem", Vector3.one * 0.16, headTop(ctx) * CFrame.new(0, H.Y * 0.1, -H.Z * 0.41), s.Accent or WHITE)
		.Material = Enum.Material.Neon
end

AccBuilders.wreath = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	for i = 0, 9 do
		local a = i * math.pi / 5
		local p = attach(ctx, head, if i == 0 then "Acc_" .. id else "Acc_" .. id .. "_Leaf" .. i, Vector3.new(0.22, 0.1, 0.12),
			headTop(ctx) * CFrame.new(math.cos(a) * H.X * 0.45, 0.02, math.sin(a) * H.Z * 0.45) * CFrame.Angles(0, -a, 0.4),
			if s.Flowers and i % 2 == 0 then s.Accent or s.Color else s.Color)
		p.Material = if s.Flowers then Enum.Material.SmoothPlastic else Enum.Material.Metal
		if s.Accent == GOLD then
			p.Material = Enum.Material.Metal
		end
	end
end

AccBuilders.muffs = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * 1.1, 0.1, 0.14), headTop(ctx) * CFrame.new(0, 0.06, 0.05), s.Color)
	for _, sx in { -1, 1 } do
		attach(ctx, head, "Acc_" .. id .. "_Cup", Vector3.one * H.Y * 0.42, CFrame.new(sx * H.X * 0.55, H.Y * 0.1, 0.05), s.Accent or s.Color,
			nil, Enum.PartType.Ball).Material = Enum.Material.Fabric
	end
end

AccBuilders.antenna = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	attach(ctx, head, "Acc_" .. id, Vector3.new(H.X * 1.04, 0.08, 0.14), headTop(ctx) * CFrame.new(0, 0.04, 0), s.Color)
	for _, sx in { -1, 1 } do
		attach(ctx, head, "Acc_" .. id .. "_Stalk", Vector3.new(0.05, H.Y * 0.55, 0.05),
			headTop(ctx) * CFrame.new(sx * H.X * 0.25, H.Y * 0.27, 0) * CFrame.Angles(0, 0, sx * -0.3), s.Color)
		attach(ctx, head, "Acc_" .. id .. "_Bulb", Vector3.one * 0.2, headTop(ctx) * CFrame.new(sx * H.X * 0.4, H.Y * 0.55, 0),
			s.Accent or WHITE, nil, Enum.PartType.Ball).Material = Enum.Material.Neon
	end
end

AccBuilders.collar = function(ctx, id, s)
	local T, torso = ctx.T, ctx.Torso
	local y = T.Y * 0.25 + ctx.Body.NeckRaise * 0.5
	local z = -T.Z / 2 + 0.05
	local thick = if s.Thick then 0.32 elseif s.Thin then 0.08 else 0.18
	local ring = attach(ctx, torso, "Acc_" .. id, Vector3.new(ctx.H.X * 0.85, thick, ctx.H.Z * 0.75),
		CFrame.new(0, y, z) * CFrame.Angles(-0.35, 0, 0), s.Color)
	if s.Metal then
		ring.Material = Enum.Material.Metal
	end
	if s.Beads then
		ring.Transparency = 1
		for i = 0, 9 do
			local a = i * math.pi / 5
			attach(ctx, torso, "Acc_" .. id .. "_Pearl" .. i, Vector3.one * 0.14,
				CFrame.new(0, y, z) * CFrame.Angles(-0.35, 0, 0) * CFrame.new(math.cos(a) * ctx.H.X * 0.42, 0, math.sin(a) * ctx.H.Z * 0.37),
				s.Color, nil, Enum.PartType.Ball).Reflectance = 0.3
		end
	end
	local front = CFrame.new(0, y - thick, z - ctx.H.Z * 0.38)
	if s.Bell then
		attach(ctx, torso, "Acc_" .. id .. "_Bell", Vector3.one * s.Bell, front, s.Accent or GOLD, nil, Enum.PartType.Ball).Material =
			Enum.Material.Metal
	end
	if s.Bib then
		attach(ctx, torso, "Acc_" .. id .. "_Bib", Vector3.new(ctx.H.X * 0.6, ctx.H.Y * 0.45, 0.06),
			front * CFrame.new(0, -0.05, -0.02) * CFrame.Angles(0, 0, math.rad(45)), s.Color)
	end
	if s.Bow then
		for _, sx in { -1, 1 } do
			attach(ctx, torso, "Acc_" .. id .. "_Wing", Vector3.new(0.3, 0.22, 0.08), front * CFrame.new(sx * 0.17, 0, 0)
				* CFrame.Angles(0, 0, sx * 0.4), s.Color)
		end
		attach(ctx, torso, "Acc_" .. id .. "_Knot", Vector3.one * 0.12, front, darken(s.Color, 0.3))
	end
	if s.Spikes then
		for i = 0, 5 do
			local a = i * math.pi / 6 - math.pi * 0.25
			attach(ctx, torso, "Acc_" .. id .. "_Spike" .. i, Vector3.one * 0.1, CFrame.new(0, y, z) * CFrame.Angles(-0.35, 0, 0)
				* CFrame.new(math.cos(a + math.pi) * ctx.H.X * 0.43, 0, math.sin(a + math.pi) * ctx.H.Z * 0.39)
				* CFrame.Angles(math.rad(45), 0, math.rad(45)), s.Accent or SILVER).Material = Enum.Material.Metal
		end
	end
	if s.Gem then
		local g = attach(ctx, torso, "Acc_" .. id .. "_Gem", Vector3.one * 0.2, front * CFrame.Angles(0, 0, math.rad(45)), s.Accent or WHITE)
		g.Material = if s.NeonAccent then Enum.Material.Neon else Enum.Material.Glass
	end
	if s.Star then
		for i = 0, 1 do
			attach(ctx, torso, "Acc_" .. id .. "_Star" .. i, Vector3.new(0.26, 0.26, 0.05), front * CFrame.Angles(0, 0, i * math.rad(45)),
				s.Accent or GOLD).Material = Enum.Material.Metal
		end
	end
	if s.Tail then
		attach(ctx, torso, "Acc_" .. id .. "_Tail", Vector3.new(0.25, 0.7, 0.08), CFrame.new(ctx.H.X * 0.3, y - 0.4, z - ctx.H.Z * 0.3)
			* CFrame.Angles(0, 0, 0.15), s.Accent or s.Color)
	end
end

AccBuilders.glasses = function(ctx, id, s)
	local H, head = ctx.H, ctx.Head
	local zf = -H.Z / 2 - 0.06
	local lens = H.X * 0.3
	local sides = if s.Single then { 1 } else { -1, 1 }
	for i, sx in sides do
		local l = attach(ctx, head, if i == 1 then "Acc_" .. id else "Acc_" .. id .. "_Lens" .. i, Vector3.new(lens, lens * 0.75, 0.06),
			CFrame.new(sx * H.X * 0.24, H.Y * 0.12, zf), s.Color)
		if s.Glass then
			l.Material = Enum.Material.Glass
			l.Transparency = 0.3
		end
	end
	if not s.Single then
		attach(ctx, head, "Acc_" .. id .. "_Bridge", Vector3.new(H.X * 0.2, 0.05, 0.05), CFrame.new(0, H.Y * 0.14, zf), s.Accent or s.Color)
	else
		attach(ctx, head, "Acc_" .. id .. "_Chain", Vector3.new(0.03, H.Y * 0.5, 0.03), CFrame.new(H.X * 0.36, -H.Y * 0.12, zf),
			s.Accent or GOLD).Material = Enum.Material.Metal
	end
	if s.Strap then
		attach(ctx, head, "Acc_" .. id .. "_Strap", Vector3.new(H.X * 1.04, 0.1, H.Z * 1.04), CFrame.new(0, H.Y * 0.12, 0), s.Accent or s.Color)
	end
end

AccBuilders.binoculars = function(ctx, id, s)
	local T, torso = ctx.T, ctx.Torso
	local front = CFrame.new(0, T.Y * 0.05, -T.Z / 2 - 0.25)
	for i, sx in { -1, 1 } do
		attach(ctx, torso, if i == 1 then "Acc_" .. id else "Acc_" .. id .. "_Tube", Vector3.new(0.22, 0.22, 0.4), front * CFrame.new(sx * 0.14, 0, 0),
			s.Color)
	end
	attach(ctx, torso, "Acc_" .. id .. "_Strap", Vector3.new(ctx.H.X * 0.8, 0.06, ctx.H.Z * 0.7),
		CFrame.new(0, T.Y * 0.28, -T.Z / 2 + 0.05) * CFrame.Angles(-0.35, 0, 0), s.Accent or s.Color)
end

AccBuilders.coat = function(ctx, id, s)
	local T, torso = ctx.T, ctx.Torso
	local len = if s.Short then 0.55 else 0.85
	attach(ctx, torso, "Acc_" .. id, Vector3.new(T.X + 0.12, T.Y * 0.75, T.Z * len), CFrame.new(0, T.Y * 0.15, -T.Z * (1 - len) / 2 + 0.02),
		s.Color)
	attach(ctx, torso, "Acc_" .. id .. "_Trim", Vector3.new(T.X + 0.16, 0.08, T.Z * len * 0.1), CFrame.new(0, T.Y * 0.2, 0), s.Accent or s.Color)
	if s.Hood then
		attach(ctx, torso, "Acc_" .. id .. "_Hood", Vector3.new(ctx.H.X * 0.9, ctx.H.Y * 0.5, ctx.H.Z * 0.5),
			CFrame.new(0, T.Y * 0.48, -T.Z * 0.32), s.Accent or s.Color)
	end
	if s.Bubble then
		AccBuilders.bubble(ctx, id .. "_Helmet", { Builder = "bubble", Color = Color3.fromRGB(200, 230, 255), Accent = s.Accent })
	end
end

AccBuilders.pack = function(ctx, id, s)
	local T, torso = ctx.T, ctx.Torso
	if s.Sides then
		for _, sx in { -1, 1 } do
			attach(ctx, torso, if sx < 0 then "Acc_" .. id else "Acc_" .. id .. "_R", Vector3.new(0.3, T.Y * 0.5, T.Z * 0.35),
				CFrame.new(sx * (T.X / 2 + 0.15), T.Y * 0.05, T.Z * 0.1), s.Color)
		end
		attach(ctx, torso, "Acc_" .. id .. "_Strap", Vector3.new(T.X + 0.1, 0.08, 0.25), CFrame.new(0, T.Y / 2 + 0.03, T.Z * 0.1), s.Accent or s.Color)
	elseif s.Belt then
		attach(ctx, torso, "Acc_" .. id, Vector3.new(T.X + 0.14, 0.2, 0.35), CFrame.new(0, -T.Y * 0.05, T.Z * 0.05), s.Color)
		for i = -1, 1 do
			attach(ctx, torso, "Acc_" .. id .. "_Tool" .. (i + 2), Vector3.new(0.08, 0.35, 0.08), CFrame.new(T.X / 2 + 0.1, -T.Y * 0.1, T.Z * 0.05 + i * 0.12),
				s.Accent or SILVER).Material = Enum.Material.Metal
		end
	else
		local p = attach(ctx, torso, "Acc_" .. id, Vector3.new(T.X * 0.7, T.Y * 0.45, T.Z * 0.35), CFrame.new(0, T.Y / 2 + T.Y * 0.2, T.Z * 0.05),
			s.Color)
		if s.Metal then
			p.Material = Enum.Material.Metal
		end
		attach(ctx, torso, "Acc_" .. id .. "_Flap", Vector3.new(T.X * 0.72, T.Y * 0.15, T.Z * 0.36), CFrame.new(0, T.Y / 2 + T.Y * 0.38, T.Z * 0.05),
			s.Accent or s.Color)
		if s.Jets then
			for _, sx in { -1, 1 } do
				local jet = attach(ctx, torso, "Acc_" .. id .. "_Jet", Vector3.new(0.25, T.Y * 0.4, 0.25),
					CFrame.new(sx * T.X * 0.28, T.Y / 2 + T.Y * 0.1, T.Z * 0.25), SILVER)
				jet.Material = Enum.Material.Metal
				if not ctx.NoVfx then
					emitter(jet, "JetFlame", {
						Texture = FIRE_TEX,
						Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20)),
						EmissionDirection = Enum.NormalId.Bottom,
						Rate = 18,
						Lifetime = NumberRange.new(0.2, 0.4),
						Speed = NumberRange.new(2, 4),
						SpreadAngle = Vector2.new(10, 10),
						Size = sizeSeq(0.35),
					})
				end
			end
		end
	end
end

AccBuilders.cape = function(ctx, id, s)
	local T, torso = ctx.T, ctx.Torso
	local cape = attach(ctx, torso, "Acc_" .. id, Vector3.new(T.X + 0.2, 0.06, T.Z * 0.95), CFrame.new(0, T.Y / 2 + 0.05, 0.05), s.Color)
	cape.Material = Enum.Material.Fabric
	for _, sx in { -1, 1 } do
		attach(ctx, torso, "Acc_" .. id .. "_Side", Vector3.new(0.06, T.Y * 0.55, T.Z * 0.9), CFrame.new(sx * (T.X / 2 + 0.1), T.Y * 0.22, 0.08),
			s.Color).Material = Enum.Material.Fabric
	end
	attach(ctx, torso, "Acc_" .. id .. "_Clasp", Vector3.one * 0.22, CFrame.new(0, T.Y * 0.3, -T.Z / 2 - 0.05), s.Accent or GOLD).Material =
		Enum.Material.Metal
	if s.Stars then
		for i = 1, 6 do
			attach(ctx, torso, "Acc_" .. id .. "_Star" .. i, Vector3.new(0.12, 0.08, 0.12),
				CFrame.new(ctx.Rng:NextNumber(-0.4, 0.4) * T.X, T.Y / 2 + 0.09, ctx.Rng:NextNumber(-0.4, 0.4) * T.Z) * CFrame.Angles(0, math.rad(45), 0),
				s.Accent or WHITE).Material = Enum.Material.Neon
		end
	end
end

AccBuilders.boots = function(ctx, id, s)
	for i, paw in ctx.Paws do
		attach(ctx, paw, if i == 1 then "Acc_" .. id else "Acc_" .. id .. "_" .. i, paw.Size * Vector3.new(1.25, 2.2, 1.2),
			CFrame.new(0, paw.Size.Y * 0.5, 0), s.Color)
		attach(ctx, paw, "Acc_" .. id .. "_Cuff" .. i, paw.Size * Vector3.new(1.35, 0.6, 1.3), CFrame.new(0, paw.Size.Y * 1.5, 0), s.Accent or WHITE)
			.Material = Enum.Material.Fabric
	end
end

AccBuilders.lantern = function(ctx, id, s)
	local snout = ctx.Snout
	local S = snout.Size
	attach(ctx, snout, "Acc_" .. id .. "_Handle", Vector3.new(0.06, 0.4, 0.06), CFrame.new(0, -S.Y * 0.5 - 0.15, -S.Z * 0.3), s.Color)
	local glass = attach(ctx, snout, "Acc_" .. id, Vector3.new(0.4, 0.5, 0.4), CFrame.new(0, -S.Y * 0.5 - 0.6, -S.Z * 0.3), s.Accent or WHITE)
	glass.Material = Enum.Material.Neon
	glass.Transparency = 0.2
	if not ctx.NoVfx then
		local l = Instance.new("PointLight")
		l.Color = s.Accent or Color3.fromRGB(255, 210, 110)
		l.Range = 10
		l.Brightness = 1.2
		l.Parent = glass
	end
end

AccBuilders.trident = function(ctx, id, s)
	local snout = ctx.Snout
	local S = snout.Size
	local shaft = attach(ctx, snout, "Acc_" .. id, Vector3.new(ctx.H.X * 2.4, 0.08, 0.08), CFrame.new(0, -S.Y * 0.2, -S.Z * 0.15), s.Color)
	shaft.Material = Enum.Material.Metal
	for i = -1, 1 do
		attach(ctx, snout, "Acc_" .. id .. "_Prong" .. (i + 2), Vector3.new(0.35, 0.06, 0.06),
			CFrame.new(ctx.H.X * 1.2 + 0.15, -S.Y * 0.2 + i * 0.14, -S.Z * 0.15), s.Accent or s.Color).Material = Enum.Material.Neon
	end
end

local SIGNATURE: { [string]: boolean } = {
	cape = true, crown = true, captain_hat = true, wizard_hat = true, knight_helm = true, pirate_hat = true,
	laurel_wreath = true, royal_collar = true, rune_collar = true, star_cloak = true, crystal_tiara = true,
	samurai_helm = true, astronaut_suit = true, jet_pack = true, trident = true, sheriff_star = true,
}

local function buildAccessory(ctx: Ctx, id: string)
	if id == "" or id == "none" then
		return
	end
	local spec = ACCESSORIES[id]
	if not spec then
		-- unknown accessory: a labelled placeholder block on the head so data errors are visible
		attach(ctx, ctx.Head, "Acc_" .. id, Vector3.new(ctx.H.X * 0.6, 0.25, ctx.H.Z * 0.6), headTop(ctx) * CFrame.new(0, 0.12, 0),
			Color3.fromRGB(255, 0, 255))
		return
	end
	AccBuilders[spec.Builder](ctx, id, spec)
	if SIGNATURE[id] and not ctx.NoVfx then
		local first = ctx.Model:FindFirstChild("Acc_" .. id, true)
		if first then
			emitter(first, "SignatureGlint", { Color = ColorSequence.new(lighten(ctx.RarityColor, 0.4)), Rate = 2, Size = sizeSeq(0.3) })
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Rig pieces
----------------------------------------------------------------------------------------------------
local function buildEars(ctx: Ctx, head: BasePart, H: Vector3, suffix: string)
	local body = ctx.Body
	local E = body.EarSize * (H.Y / BodyTypes.Get(body.Id).Head.Y)
	for i, sx in { -1, 1 } do
		local name = (if sx < 0 then "EarL" else "EarR") .. suffix
		local ear: Part
		local c0: CFrame
		local c1: CFrame
		local hangs = false
		if body.Ear == "floppy" then
			ear = newPart(ctx, name, Vector3.new(0.14, E, E * 0.55), if body.Poodle then ctx.Primary else darken(ctx.Primary, 0.15), "Primary")
			c0 = CFrame.new(sx * (H.X / 2 + 0.05), H.Y * 0.3, H.Z * 0.05) * CFrame.Angles(0, 0, sx * math.rad(8))
			c1 = CFrame.new(0, E / 2 - 0.06, 0)
			hangs = true
			if body.Poodle then
				ear.Size = Vector3.new(0.3, E, E * 0.6)
				ear.Material = Enum.Material.Fabric
			end
		elseif body.Ear == "folded" then
			ear = newPart(ctx, name, Vector3.new(E * 0.7, E * 0.55, 0.12), darken(ctx.Primary, 0.1), "Primary")
			c0 = CFrame.new(sx * H.X * 0.3, H.Y / 2 - 0.02, -H.Z * 0.05) * CFrame.Angles(-math.rad(75), 0, sx * -math.rad(10))
			c1 = CFrame.new(0, -E * 0.275, 0)
		elseif body.Ear == "round" then
			ear = newPart(ctx, name, Vector3.new(E * 0.85, E * 0.7, 0.14), darken(ctx.Primary, 0.1), "Primary")
			c0 = CFrame.new(sx * H.X * 0.38, H.Y / 2 - 0.05, H.Z * 0.1) * CFrame.Angles(0, 0, sx * -math.rad(25))
			c1 = CFrame.new(0, -E * 0.3, 0)
		else -- pointy
			ear = newPart(ctx, name, Vector3.new(E * 0.55, E, 0.14), ctx.Primary, "Primary")
			c0 = CFrame.new(sx * H.X * 0.3, H.Y / 2 - 0.04, H.Z * 0.1) * CFrame.Angles(0, 0, sx * -math.rad(12))
			c1 = CFrame.new(0, -E / 2 + 0.05, 0)
		end
		if hangs then
			ear:SetAttribute("Hangs", true)
		end
		motor(name, head, ear, c0, c1)
		if body.Ear == "pointy" then
			attach(ctx, ear, "InnerEar" .. i .. suffix, Vector3.new(E * 0.28, E * 0.6, 0.05), CFrame.new(0, -E * 0.08, -0.08),
				lighten(ctx.Secondary, 0.25), "Secondary")
		end
		if suffix == "" then
			table.insert(ctx.Ears, ear)
		end
	end
end

-- Builds a head (with snout, nose, eyes, ears) jointed to the torso. Returns head, snout.
local function buildHead(ctx: Ctx, jointName: string, xOffset: number, yaw: number, suffix: string): (BasePart, BasePart)
	local T, H, S = ctx.T, ctx.H, ctx.S
	local body = ctx.Body
	local head = newPart(ctx, "Head" .. suffix, H, ctx.Primary, "Primary")
	local c0 = CFrame.new(xOffset, T.Y * 0.3 + body.NeckRaise, -T.Z / 2 + H.Z * 0.1) * CFrame.Angles(0, yaw, 0)
	local c1 = CFrame.new(0, -H.Y * 0.3, H.Z * 0.45)
	motor(jointName, ctx.Torso, head, c0, c1)
	-- neck filler (welded to the torso so the head can nod over it)
	attach(ctx, ctx.Torso, "NeckFill" .. suffix, Vector3.new(H.X * 0.68, T.Y * 0.45 + body.NeckRaise, H.Z * 0.6),
		CFrame.new(xOffset, T.Y * 0.22 + body.NeckRaise * 0.5, -T.Z / 2 + H.Z * 0.12), ctx.Primary, "Primary")
	local snout = attach(ctx, head, "Snout" .. suffix, S, CFrame.new(0, -H.Y * 0.18, -H.Z / 2 - S.Z / 2 + 0.06),
		lighten(ctx.Primary, 0.08), "Primary")
	attach(ctx, snout, "Nose" .. suffix, Vector3.new(S.X * 0.5, math.max(S.Y * 0.35, 0.12), 0.14), CFrame.new(0, S.Y * 0.25, -S.Z / 2 - 0.03), BLACK)
	local e = math.min(H.X, H.Y) * 0.18
	for i, sx in { -1, 1 } do
		local eye = attach(ctx, head, "Eye" .. i .. suffix, Vector3.one * e, CFrame.new(sx * H.X * 0.24, H.Y * 0.1, -H.Z / 2 + e * 0.15), BLACK,
			nil, Enum.PartType.Ball)
		eye:SetAttribute("Eye", true)
		attach(ctx, eye, "Glint" .. i .. suffix, Vector3.one * e * 0.35, CFrame.new(e * 0.18, e * 0.18, -e * 0.38), WHITE, nil, Enum.PartType.Ball)
	end
	-- cheeks / fluff
	if body.Fluffy then
		for _, sx in { -1, 1 } do
			attach(ctx, head, "Cheek" .. suffix .. sx, Vector3.new(0.3, H.Y * 0.55, H.Z * 0.6), CFrame.new(sx * H.X * 0.5, -H.Y * 0.15, H.Z * 0.05),
				ctx.Secondary, "Secondary").Material = Enum.Material.Fabric
		end
	end
	if body.Poodle then
		attach(ctx, head, "Topknot" .. suffix, Vector3.one * H.X * 0.85, CFrame.new(0, H.Y * 0.5, H.Z * 0.05), ctx.Primary, "Primary",
			Enum.PartType.Ball).Material = Enum.Material.Fabric
	end
	buildEars(ctx, head, H, suffix)
	return head, snout
end

local function buildTail(ctx: Ctx, jointName: string, xOffset: number, angleOffset: number, yawOffset: number): BasePart
	local T = ctx.T
	local body = ctx.Body
	local len = ctx.TailLen
	local th = math.clamp(ctx.Lt * 0.55, 0.14, 0.5)
	local size: Vector3
	if body.Tail == "whip" then
		size = Vector3.new(th * 0.7, len, th * 0.7)
	elseif body.Tail == "stub" then
		size = Vector3.new(th * 1.4, len, th * 1.4)
	elseif body.Tail == "plume" then
		size = Vector3.new(th * 2, len, th * 2)
	elseif body.Tail == "pom" then
		size = Vector3.new(th * 0.6, len, th * 0.6)
	else
		size = Vector3.new(th, len, th)
	end
	local tail = newPart(ctx, if jointName == "TailJoint" then "Tail" else "Tail" .. string.sub(jointName, 10), size, ctx.Primary, "Primary")
	if body.Tail == "plume" then
		tail.Material = Enum.Material.Fabric
	end
	local c0 = CFrame.new(xOffset, T.Y * 0.3, T.Z / 2 - 0.05) * CFrame.Angles(0, yawOffset, 0)
		* CFrame.Angles(math.rad(body.TailAngle + angleOffset), 0, 0)
	motor(jointName, ctx.Torso, tail, c0, CFrame.new(0, -len / 2, 0))
	if body.Tail == "curled" then
		attach(ctx, tail, "TailCurl", Vector3.one * th * 2, CFrame.new(0, len / 2, -th * 0.6), ctx.Primary, "Primary", Enum.PartType.Ball)
	elseif body.Tail == "pom" then
		attach(ctx, tail, "TailPom", Vector3.one * 0.6, CFrame.new(0, len / 2, 0), ctx.Primary, "Primary", Enum.PartType.Ball).Material =
			Enum.Material.Fabric
	end
	return tail
end

local function buildLegs(ctx: Ctx)
	local T, L, t = ctx.T, ctx.L, ctx.Lt
	local Lp = L + t * 0.4
	local names = { "FL", "FR", "BL", "BR" }
	for i, n in names do
		local sx = if i % 2 == 1 then -1 else 1
		local front = i <= 2
		local z = if front then -(T.Z / 2 - t * 0.8) else (T.Z / 2 - t * 0.8)
		local leg = newPart(ctx, "Leg" .. n, Vector3.new(t, Lp, t), ctx.Primary, "Primary")
		motor("Hip" .. n, ctx.Torso, leg, CFrame.new(sx * (T.X / 2 - t * 0.55), -T.Y / 2 + t * 0.4, z), CFrame.new(0, Lp / 2, 0))
		local pawH = math.min(t * 0.45, L * 0.3)
		local paw = attach(ctx, leg, "Paw" .. n, Vector3.new(t * 1.15, pawH, t * 1.35), CFrame.new(0, -Lp / 2 + pawH / 2, -t * 0.15),
			lighten(ctx.Primary, 0.05), "Primary")
		table.insert(ctx.Legs, leg)
		table.insert(ctx.Paws, paw)
		if ctx.Body.Poodle then
			attach(ctx, leg, "Pom" .. n, Vector3.one * t * 2.1, CFrame.new(0, -Lp / 2 + t * 1.2, 0), ctx.Primary, "Primary", Enum.PartType.Ball)
				.Material = Enum.Material.Fabric
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Mythic unique parts
----------------------------------------------------------------------------------------------------
local Unique: { [string]: (Ctx) -> () } = {}

local function extraHeads(ctx: Ctx, n: number)
	-- shift the main head sideways and add heads beside it
	local H = ctx.H
	local spacing = H.X * 0.95
	local neck = ctx.Torso:FindFirstChild("Neck") :: Motor6D?
	if not neck then
		return
	end
	local positions = if n == 2 then { -spacing / 2, spacing / 2 } else { 0, -spacing, spacing }
	local yaws = if n == 2 then { 0.15, -0.15 } else { 0, 0.3, -0.3 }
	-- move main head
	neck.C0 = CFrame.new(positions[1], neck.C0.Position.Y, neck.C0.Position.Z) * CFrame.Angles(0, yaws[1], 0)
	ctx.Head.CFrame = ctx.Torso.CFrame * neck.C0 * neck.C1:Inverse()
	for i = 2, n do
		if not ctx.Torso:FindFirstChild("Neck" .. i) then
			local h = buildHead(ctx, "Neck" .. i, positions[i], yaws[i], tostring(i))
			table.insert(ctx.Heads, h)
		end
	end
end

-- Children welded to the head follow it automatically via welds, but CFrames set before the move must be
-- recomputed: re-solve every weld below the head once.
local function resolveWelds(model: Model)
	for _ = 1, 4 do
		for _, d in model:GetDescendants() do
			if d:IsA("Weld") and d.Part0 and d.Part1 then
				d.Part1.CFrame = d.Part0.CFrame * d.C0 * d.C1:Inverse()
			elseif d:IsA("Motor6D") and d.Part0 and d.Part1 then
				d.Part1.CFrame = d.Part0.CFrame * d.C0 * d.C1:Inverse()
			end
		end
	end
end

Unique.two_heads = function(ctx)
	extraHeads(ctx, 2)
end
Unique.three_heads = function(ctx)
	extraHeads(ctx, 3)
end

Unique.wings = function(ctx)
	local T = ctx.T
	local span = T.Z * 0.9
	for _, sx in { -1, 1 } do
		local name = if sx < 0 then "WingL" else "WingR"
		local wing = newPart(ctx, name, Vector3.new(span, 0.12, T.Z * 0.55), lighten(ctx.Secondary, 0.3), "Secondary")
		motor(name, ctx.Torso, wing, CFrame.new(sx * T.X * 0.4, T.Y * 0.45, -T.Z * 0.1) * CFrame.Angles(0, 0, sx * -0.35),
			CFrame.new(-sx * span / 2, 0, 0))
		for f = 1, 3 do
			attach(ctx, wing, name .. "Feather" .. f, Vector3.new(span * (1 - f * 0.2), 0.1, T.Z * 0.12),
				CFrame.new(sx * span * f * 0.1, -0.02, T.Z * (0.18 + f * 0.08)), ctx.Secondary, "Secondary")
		end
	end
end

Unique.halo = function(ctx)
	local H = ctx.H
	local r = H.X * 0.55
	for i = 0, 9 do
		local a = i * math.pi / 5
		local p = attach(ctx, ctx.Head, "Halo" .. i, Vector3.new(r * 0.68, 0.1, 0.12),
			CFrame.new(math.cos(a) * r, H.Y * 0.95, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(255, 230, 120))
		p.Material = Enum.Material.Neon
	end
end

local function horn(ctx: Ctx, parent: BasePart, name: string, base: CFrame, length: number, width: number, color: Color3,
	material: Enum.Material?)
	local segs = 3
	for i = 1, segs do
		local w = width * (1 - (i - 1) * 0.28)
		local h = length / segs
		local p = attach(ctx, parent, name .. i, Vector3.new(w, h, w), base * CFrame.new(0, h * (i - 0.5), 0), color)
		if material then
			p.Material = material
		end
	end
end

Unique.horns = function(ctx)
	local H = ctx.H
	for _, head in ctx.Heads do
		for _, sx in { -1, 1 } do
			horn(ctx, head, "Horn" .. sx, CFrame.new(sx * H.X * 0.3, H.Y / 2, H.Z * 0.05) * CFrame.Angles(0.35, 0, sx * -0.5), H.Y * 0.6, 0.22,
				Color3.fromRGB(235, 225, 200))
		end
	end
end

Unique.unicorn_horn = function(ctx)
	local H = ctx.H
	horn(ctx, ctx.Head, "UnicornHorn", CFrame.new(0, H.Y / 2, -H.Z * 0.25) * CFrame.Angles(-0.45, 0, 0), H.Y * 0.9, 0.24,
		Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
end

Unique.antlers = function(ctx)
	local H = ctx.H
	local c = Color3.fromRGB(150, 110, 70)
	for _, sx in { -1, 1 } do
		local base = CFrame.new(sx * H.X * 0.3, H.Y / 2, H.Z * 0.1) * CFrame.Angles(0.2, 0, sx * -0.4)
		attach(ctx, ctx.Head, "Antler" .. sx, Vector3.new(0.12, H.Y * 0.9, 0.12), base * CFrame.new(0, H.Y * 0.45, 0), c)
		for b = 1, 3 do
			attach(ctx, ctx.Head, "AntlerTine" .. sx .. b, Vector3.new(0.08, H.Y * 0.35, 0.08),
				base * CFrame.new(0, H.Y * 0.25 * b, 0) * CFrame.Angles(-0.7, 0, sx * -0.6) * CFrame.new(0, H.Y * 0.17, 0), c)
		end
	end
end

Unique.flame_mane = function(ctx)
	local T = ctx.T
	local col = ctx.Secondary
	for i = 0, 7 do
		local a = i * math.pi / 4
		local p = attach(ctx, ctx.Torso, "Flame" .. i, Vector3.new(0.22, 0.7, 0.22),
			CFrame.new(math.cos(a) * ctx.H.X * 0.5, T.Y * 0.35 + ctx.Body.NeckRaise + math.sin(a) * 0.15, -T.Z / 2 + 0.2 + math.sin(a) * ctx.H.Z * 0.3)
				* CFrame.Angles(0.3, 0, math.cos(a) * -0.6),
			col)
		p.Material = Enum.Material.Neon
		p:SetAttribute("Coat", "Secondary")
	end
	if not ctx.NoVfx then
		emitter(ctx.Torso, "ManeFire", {
			Texture = FIRE_TEX,
			Color = ColorSequence.new(lighten(col, 0.3), Color3.fromRGB(255, 80, 20)),
			Rate = 14,
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(1, 2),
			Acceleration = Vector3.new(0, 3, 0),
			Size = sizeSeq(0.8),
		})
	end
end

Unique.star_tail = function(ctx)
	local tail = ctx.Tail
	for i = 0, 1 do
		attach(ctx, tail, "StarTip" .. i, Vector3.new(0.6, 0.6, 0.12), CFrame.new(0, ctx.TailLen / 2 + 0.2, 0) * CFrame.Angles(0, 0, i * math.rad(45)),
			Color3.fromRGB(255, 235, 120)).Material = Enum.Material.Neon
	end
	if not ctx.NoVfx then
		emitter(tail, "StarDust", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 150)), Rate = 8, Size = sizeSeq(0.3) })
	end
end

Unique.crystal_spikes = function(ctx)
	local T = ctx.T
	for i = 1, 5 do
		local h = 0.35 + 0.12 * (3 - math.abs(3 - i))
		local p = attach(ctx, ctx.Torso, "Crystal" .. i, Vector3.new(0.3, h, 0.3),
			CFrame.new(0, T.Y / 2 + h * 0.3, -T.Z * 0.35 + (i - 1) * T.Z * 0.17) * CFrame.Angles(0, math.rad(45), 0), lighten(ctx.Secondary, 0.3))
		p.Material = Enum.Material.Glass
		p.Reflectance = 0.2
	end
end

Unique.nine_tails = function(ctx)
	for i = 2, 9 do
		local k = i - 5.5
		buildTail(ctx, "TailJoint" .. i, k * 0.05, k * 4, k * 0.12)
	end
end

Unique.third_eye = function(ctx)
	local H = ctx.H
	local e = attach(ctx, ctx.Head, "ThirdEye", Vector3.one * H.X * 0.22, CFrame.new(0, H.Y * 0.33, -H.Z / 2 + 0.02), Color3.fromRGB(120, 255, 230),
		nil, Enum.PartType.Ball)
	e.Material = Enum.Material.Neon
	e:SetAttribute("Eye", true)
end

Unique.fins = function(ctx)
	local T = ctx.T
	attach(ctx, ctx.Torso, "DorsalFin", Vector3.new(0.12, T.Y * 0.6, T.Z * 0.35), CFrame.new(0, T.Y / 2 + T.Y * 0.2, 0) * CFrame.Angles(0.5, 0, 0),
		ctx.Secondary, "Secondary")
	for _, sx in { -1, 1 } do
		attach(ctx, ctx.Torso, "SideFin" .. sx, Vector3.new(T.X * 0.45, 0.1, T.Z * 0.22),
			CFrame.new(sx * T.X * 0.6, -T.Y * 0.1, -T.Z * 0.15) * CFrame.Angles(0, 0, sx * -0.4), ctx.Secondary, "Secondary")
	end
end

Unique.ghost_tail = function(ctx)
	local tail = ctx.Tail
	tail.Material = Enum.Material.ForceField
	tail.Transparency = 0.2
	for i = 1, 3 do
		local w = attach(ctx, tail, "GhostWisp" .. i, Vector3.new(0.4 - i * 0.08, ctx.TailLen * 0.4, 0.4 - i * 0.08),
			CFrame.new(0, ctx.TailLen / 2 + i * ctx.TailLen * 0.25, i * 0.1), lighten(ctx.Secondary, 0.4))
		w.Material = Enum.Material.ForceField
	end
	if not ctx.NoVfx then
		emitter(tail, "GhostMist", { Texture = SMOKE_TEX, Color = ColorSequence.new(Color3.fromRGB(210, 230, 255)), LightEmission = 0.5,
			Rate = 6, Transparency = NumberSequence.new(0.6, 1), Size = sizeSeq(1) })
	end
end

Unique.shell_back = function(ctx)
	local T = ctx.T
	local d = math.min(T.X, T.Z) * 1.15
	attach(ctx, ctx.Torso, "Shell", Vector3.one * d, CFrame.new(0, T.Y * 0.2, 0.05), ctx.Secondary, "Secondary", Enum.PartType.Ball)
	for i = 0, 5 do
		local a = i * math.pi / 3
		attach(ctx, ctx.Torso, "ShellPlate" .. i, Vector3.new(d * 0.28, 0.08, d * 0.28),
			CFrame.new(math.cos(a) * d * 0.22, T.Y * 0.2 + d * 0.44, math.sin(a) * d * 0.22) * CFrame.Angles(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4),
			darken(ctx.Secondary, 0.25), "Secondary")
	end
end

Unique.ring_orbit = function(ctx)
	local T = ctx.T
	local hub = newPart(ctx, "OrbitHub", Vector3.one * 0.2, WHITE)
	hub.Transparency = 1
	motor("Orbit", ctx.Torso, hub, CFrame.new(0, T.Y * 0.1, 0), CFrame.new())
	local r = math.max(T.X, T.Z) * 0.75
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		attach(ctx, hub, "OrbitMoon" .. i, Vector3.one * 0.35, CFrame.new(math.cos(a) * r, math.sin(a * 2) * 0.3, math.sin(a) * r),
			if i == 0 then Color3.fromRGB(120, 220, 255) elseif i == 1 then Color3.fromRGB(255, 200, 90) else Color3.fromRGB(230, 120, 255), nil,
			Enum.PartType.Ball).Material = Enum.Material.Neon
	end
end

Unique.cloud_paws = function(ctx)
	for i, paw in ctx.Paws do
		attach(ctx, paw, "Cloud" .. i, Vector3.one * ctx.Lt * 1.8, CFrame.new(0, 0, 0), WHITE, nil, Enum.PartType.Ball).Material =
			Enum.Material.Fabric
	end
	if not ctx.NoVfx then
		emitter(ctx.Paws[1], "CloudPuff", { Texture = SMOKE_TEX, Color = ColorSequence.new(WHITE), LightEmission = 0.2, Rate = 4,
			Transparency = NumberSequence.new(0.5, 1), Size = sizeSeq(0.7) })
	end
end

Unique.leaf_mane = function(ctx)
	local T = ctx.T
	for i = 0, 9 do
		local a = i * math.pi / 5
		attach(ctx, ctx.Torso, "Leaf" .. i, Vector3.new(0.35, 0.08, 0.6),
			CFrame.new(math.cos(a) * ctx.H.X * 0.48, T.Y * 0.3 + ctx.Body.NeckRaise * 0.5 + math.sin(a) * ctx.H.Y * 0.35, -T.Z / 2 + 0.15)
				* CFrame.Angles(0, 0, a) * CFrame.Angles(0.5, 0, 0),
			if i % 2 == 0 then Color3.fromRGB(80, 170, 70) else Color3.fromRGB(130, 200, 90)).Material = Enum.Material.LeafyGrass
	end
end

----------------------------------------------------------------------------------------------------
-- VFX tiers
----------------------------------------------------------------------------------------------------
local function applyVfx(ctx: Ctx, tier: string)
	if ctx.NoVfx or tier == "none" or tier == "" then
		return
	end
	local col = lighten(ctx.RarityColor, 0.3)
	emitter(ctx.Torso, "IdleSparkle", { Color = ColorSequence.new(col), Rate = if tier == "sparkle" then 3 else 6, Size = sizeSeq(0.35) })
	if tier == "aura" or tier == "full" then
		local light = Instance.new("PointLight")
		light.Name = "AuraLight"
		light.Color = ctx.RarityColor
		light.Brightness = if tier == "full" then 1.5 else 0.9
		light.Range = 10
		light.Parent = ctx.Torso
		local feet = Instance.new("Attachment")
		feet.Name = "AuraFeet"
		feet.Position = Vector3.new(0, -ctx.T.Y / 2 - ctx.L + 0.1, 0)
		feet.Parent = ctx.Torso
		emitter(feet, "AuraRing", {
			Color = ColorSequence.new(ctx.RarityColor),
			Texture = SMOKE_TEX,
			LightEmission = 0.8,
			Rate = if tier == "full" then 14 else 8,
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(0.2, 0.6),
			Acceleration = Vector3.new(0, 1.2, 0),
			Transparency = NumberSequence.new(0.4, 1),
			Size = sizeSeq(1.2),
		})
	end
	if tier == "full" then
		emitter(ctx.Torso, "MythicRise", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), ctx.RarityColor),
			Rate = 10,
			Speed = NumberRange.new(1.5, 3),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(35, 35),
			Size = sizeSeq(0.5),
		})
		local a0 = Instance.new("Attachment")
		a0.Name = "MythicTrail0"
		a0.Position = Vector3.new(0, ctx.T.Y * 0.4, ctx.T.Z * 0.45)
		a0.Parent = ctx.Torso
		local a1 = Instance.new("Attachment")
		a1.Name = "MythicTrail1"
		a1.Position = Vector3.new(0, -ctx.T.Y * 0.4, ctx.T.Z * 0.45)
		a1.Parent = ctx.Torso
		local trail = Instance.new("Trail")
		trail.Name = "MythicTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(ctx.RarityColor)
		trail.LightEmission = 0.7
		trail.Lifetime = 0.4
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Parent = ctx.Torso
	end
end

----------------------------------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------------------------------
function DogFactory.Build(dogData: any, variantOrOpts: any?, isPuppyArg: boolean?): Model
	local opts: BuildOptions = {}
	if type(variantOrOpts) == "table" then
		opts = variantOrOpts
	elseif type(variantOrOpts) == "string" then
		opts.Variant = variantOrOpts
	end
	if isPuppyArg ~= nil then
		opts.IsPuppy = isPuppyArg
	end
	local isPuppy = opts.IsPuppy == true or opts.Puppy == true
	local variant = opts.Variant
	if variant == "" then
		variant = nil
	end

	local def = dogData or {}
	local id = tostring(def.Id or "dog")
	local rarity = if type(def.Rarity) == "string" then def.Rarity else "Common"
	local tier = (Rarities.Tiers :: any)[rarity]
	local base = BodyTypes.Get(def.Body)
	local puppy = BodyTypes.Puppy

	local model = Instance.new("Model")
	model.Name = tostring(def.Name or id)

	local H = base.Head * (if isPuppy then puppy.HeadMult else 1)
	local S = base.Snout * (if isPuppy then Vector3.new(1, 1, puppy.SnoutMult) else Vector3.one)
	local L = base.LegLength * (if isPuppy then puppy.LegMult else 1)
	local body: BodyTypes.BodyType = table.clone(base)
	body.EarSize = base.EarSize * (if isPuppy then puppy.EarMult else 1)

	local primary = hex(def.CoatPrimary, Color3.fromRGB(200, 160, 110))
	local secondary = hex(def.CoatSecondary, Color3.fromRGB(245, 240, 230))

	local ctx: Ctx = {
		Model = model,
		Rng = Random.new(hashString(id)),
		Primary = primary,
		Secondary = secondary,
		CoatMaterial = if base.Fluffy or base.Poodle then Enum.Material.Fabric else Enum.Material.SmoothPlastic,
		Body = body,
		T = base.Torso,
		H = H,
		S = S,
		L = L,
		Lt = base.LegThick,
		Root = nil :: any,
		Torso = nil :: any,
		Head = nil :: any,
		Heads = {},
		Snout = nil :: any,
		Legs = {},
		Paws = {},
		Tail = nil :: any,
		TailLen = base.TailLength,
		Ears = {},
		Rarity = rarity,
		RarityColor = if tier then tier.Color else Color3.new(1, 1, 1),
		NoVfx = opts.NoVfx == true,
	}

	local T = ctx.T
	local root = newPart(ctx, "Root", Vector3.new(T.X * 0.5, T.Y * 0.5, T.Z * 0.5), WHITE)
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = CFrame.new(0, L + T.Y / 2, 0)
	ctx.Root = root
	model.PrimaryPart = root

	local torso = newPart(ctx, "Torso", T, primary, "Primary")
	motor("RootJoint", root, torso, CFrame.new(), CFrame.new())
	ctx.Torso = torso

	buildLegs(ctx)
	local head, snout = buildHead(ctx, "Neck", 0, 0, "")
	ctx.Head = head
	ctx.Snout = snout
	table.insert(ctx.Heads, head)
	ctx.Tail = buildTail(ctx, "TailJoint", 0, 0, 0)

	if base.Fluffy then
		attach(ctx, torso, "ChestRuff", Vector3.new(T.X * 0.85, T.Y * 0.7, 0.45), CFrame.new(0, T.Y * 0.05, -T.Z / 2 - 0.12), secondary,
			"Secondary").Material = Enum.Material.Fabric
		attach(ctx, torso, "BackFluff", Vector3.new(T.X * 0.9, 0.2, T.Z * 0.8), CFrame.new(0, T.Y / 2 + 0.06, 0), primary, "Primary")
			.Material = Enum.Material.Fabric
	end
	if base.Poodle then
		attach(ctx, torso, "ChestPuff", Vector3.one * T.X * 1.15, CFrame.new(0, T.Y * 0.1, -T.Z * 0.3), primary, "Primary", Enum.PartType.Ball)
			.Material = Enum.Material.Fabric
		attach(ctx, torso, "HipPuff", Vector3.one * T.X * 0.95, CFrame.new(0, T.Y * 0.05, T.Z * 0.35), primary, "Primary", Enum.PartType.Ball)
			.Material = Enum.Material.Fabric
	end

	-- Mythic unique parts that restructure the rig first (heads), then the rest
	local uniques: { string } = if type(def.UniqueParts) == "table" then def.UniqueParts else {}
	local hasThree = table.find(uniques, "three_heads") ~= nil
	for _, u in uniques do
		if u == "two_heads" and hasThree then
			continue
		end
		if u == "two_heads" or u == "three_heads" then
			Unique[u](ctx)
		end
	end
	resolveWelds(model)

	-- pattern / texture
	local pattern = if type(def.Pattern) == "string" then def.Pattern else "none"
	local tex = TEXTURES[pattern]
	if tex then
		applyTexture(ctx, tex)
	else
		local fn = Patterns[pattern]
		if fn then
			fn(ctx)
		end
	end

	if type(def.Accessory) == "string" then
		buildAccessory(ctx, def.Accessory)
	end

	for _, u in uniques do
		if u ~= "two_heads" and u ~= "three_heads" then
			local fn = Unique[u]
			if fn then
				fn(ctx)
			end
		end
	end

	applyVfx(ctx, if type(def.Vfx) == "string" then def.Vfx else "none")

	model:SetAttribute("DogId", id)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Body", base.Id)
	model:SetAttribute("IsPuppy", isPuppy)
	model:SetAttribute("RigVersion", 1)

	local scale = (tonumber(def.Scale) or 1) * (if isPuppy then puppy.OverallScale else 1)
	scale = math.clamp(scale, 0.2, 5)
	if math.abs(scale - 1) > 1e-3 then
		model:ScaleTo(scale)
	end

	if variant then
		VariantFX.Apply(model, variant)
	end
	return model
end

-- Convenience: same as Build but with the roster looked up by id (nil if unknown).
function DogFactory.BuildById(dogId: string, variant: string?, isPuppy: boolean?): Model?
	local Util = Shared:FindFirstChild("Util")
	local catalogModule = Util and Util:FindFirstChild("DogCatalog")
	if not catalogModule then
		return nil
	end
	local DogCatalog = (require :: any)(catalogModule)
	local def = DogCatalog.Get(dogId)
	if not def then
		return nil
	end
	return DogFactory.Build(def, variant, isPuppy)
end

DogFactory.Accessories = ACCESSORIES
DogFactory.Textures = TEXTURES
DogFactory.Patterns = Patterns
DogFactory.UniqueParts = Unique

return DogFactory
