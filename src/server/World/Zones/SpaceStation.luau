--!strict
-- Space Station (1900-2500): a diamond-plate deck with neon seams, floor lights, bolts, vent grates, cables and
-- moon rocks over the whole plot; station modules, solar arrays, dish antennas, cargo crates, glass domes, fuel
-- tanks, beacons and floating rocks; twinkling stars and slow drifting debris over the band.
-- Boundary: a low bulkhead wall with a neon band across the field. Landmark: a rocket on its pad (east).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function rocket(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.ZoneFolder, "Rocket")
	local hull, red, dark = rgb(240, 240, 248), rgb(225, 60, 55), rgb(60, 66, 100)
	P.Block(m, "Pad", Vector3.new(30, 2, 30), CFrame.new(base + Vector3.new(0, 1, 0)), dark, Enum.Material.DiamondPlate)
	P.Block(m, "PadTrim", Vector3.new(30.4, 0.4, 30.4), CFrame.new(base + Vector3.new(0, 2.1, 0)), D.Glow, Enum.Material.Neon)
	P.Cylinder(m, "Engine", base + Vector3.new(0, 2, 0), 10, 14, rgb(90, 95, 110), Enum.Material.Metal)
	local y = 12
	for i, t in { { 20, 70, hull }, { 20, 3, red }, { 18, 70, hull }, { 18, 3, red }, { 16, 50, hull } } do
		P.Cylinder(m, "Stage" .. i, base + Vector3.new(0, y, 0), t[2], t[1], t[3], Enum.Material.Metal)
		y += t[2]
	end
	-- porthole + flag-free stripe on the platform side
	P.Part({ Parent = m, Name = "Porthole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 6, 6),
		CFrame = CFrame.new(base + Vector3.new(0, y - 20, -8.1)) * CFrame.Angles(0, math.pi / 2, 0), Color = D.Glow,
		Material = Enum.Material.Neon })
	for i, t in { { 13, 10 }, { 9, 9 }, { 5, 8 }, { 2, 6 } } do
		P.Cylinder(m, "Nose" .. i, base + Vector3.new(0, y, 0), t[2], t[1], red, Enum.Material.Metal)
		y += t[2]
	end
	P.Ball(m, "Tip", base + Vector3.new(0, y + 0.8, 0), 2.2, D.Glow, Enum.Material.Neon)
	-- four fins on the diagonals
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		P.Wedge({ Parent = m, Name = "Fin", Size = Vector3.new(1.6, 22, 8),
			CFrame = CFrame.lookAt(base + Vector3.new(0, 23, 0) + dir * 13, base + Vector3.new(0, 23, 0) + dir * 30)
, Color = red })
	end
	Kit.Landmark(ctx, m, y + 1.9, "Rocket")
	return m
end

local function module(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P, D = ctx.Props, ctx.Decor
	local c = pos + Vector3.new(0, 4.5, 0)
	Kit.LyingCylinder(P, m, "Hull", c, 14, 7, math.pi / 2, D.Hull, Enum.Material.Metal)
	P.Ball(m, "CapA", c + Vector3.new(0, 0, -7), 7, D.Hull, Enum.Material.Metal)
	P.Ball(m, "CapB", c + Vector3.new(0, 0, 7), 7, D.Hull, Enum.Material.Metal)
	P.Block(m, "Windows", Vector3.new(0.4, 1.2, 10), CFrame.new(c + Vector3.new(-side * 3.45, 0.6, 0)), D.Glow, Enum.Material.Neon)
	P.Block(m, "Stand", Vector3.new(4, 1.2, 9), CFrame.new(pos + Vector3.new(0, 0.6, 0)), D.Panel, Enum.Material.DiamondPlate)
end

local function solarPanel(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Post", pos, 5, 0.8, D.Antenna, Enum.Material.Metal)
	for _, dz in { -3.4, 3.4 } do
		P.Block(m, "Panel", Vector3.new(8, 0.3, 6), CFrame.new(pos + Vector3.new(0, 5.6, dz)) * CFrame.Angles(0, 0, math.rad(-20)),
			rgb(40, 70, 170), Enum.Material.Glass)
	end
	P.Block(m, "Spine", Vector3.new(0.5, 0.5, 13.6), CFrame.new(pos + Vector3.new(0, 5.5, 0)), D.Glow, Enum.Material.Neon)
end

local function dish(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Mast", pos, 9, 1, D.Antenna, Enum.Material.Metal)
	local c = pos + Vector3.new(0, 10, 0)
	local tilt = CFrame.new(c) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0) * CFrame.Angles(0, 0, math.rad(55))
	P.Part({ Parent = m, Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 9, 9), CFrame = tilt,
		Color = D.Antenna, Material = Enum.Material.Metal })
	P.Block(m, "Feed", Vector3.new(3, 0.4, 0.4), tilt * CFrame.new(1.6, 0, 0), D.Antenna, Enum.Material.Metal)
	P.Ball(m, "Tip", (tilt * CFrame.new(3.2, 0, 0)).Position, 0.9, D.Glow, Enum.Material.Neon)
end

local function crate(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local cf = CFrame.new(pos + Vector3.new(0, 2, 0)) * Kit.Yaw(ctx)
	P.Block(m, "Box", Vector3.new(4, 4, 4), cf, D.Hull, Enum.Material.Metal)
	P.Block(m, "Band", Vector3.new(4.2, 0.6, 4.2), cf, D.Glow, Enum.Material.Neon)
end

local function dome(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Ball(m, "Glass", pos, 14, rgb(150, 220, 255), Enum.Material.Glass).Transparency = 0.35
	P.Cylinder(m, "Ring", pos, 1, 15, D.Panel, Enum.Material.DiamondPlate)
	P.Block(m, "Core", Vector3.new(3, 4, 3), CFrame.new(pos + Vector3.new(0, 2, 0)), D.Glow, Enum.Material.Neon)
end

local function beacon(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Post", pos, 6, 0.6, D.Antenna, Enum.Material.Metal)
	P.Ball(m, "Light", pos + Vector3.new(0, 6.6, 0), 1.6, rgb(255, 80, 80), Enum.Material.Neon)
end

local function fuelTank(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local yaw = ctx.Rng:NextNumber(0, math.pi)
	Kit.LyingCylinder(P, m, "Tank", pos + Vector3.new(0, 2.2, 0), 7, 4, yaw, rgb(240, 150, 60), Enum.Material.Metal)
	Kit.LyingCylinder(P, m, "Band", pos + Vector3.new(0, 2.2, 0), 0.6, 4.2, yaw, D.Glow, Enum.Material.Neon)
	P.Block(m, "Cradle", Vector3.new(3, 0.6, 3), CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, yaw, 0), D.Panel)
end

local function floatingRock(ctx: any, m: Model, pos: Vector3)
	local P, D, rng = ctx.Props, ctx.Decor, ctx.Rng
	local sc = rng:NextNumber(0.9, 1.5)
	P.Block(m, "FloatingRock", Vector3.new(5, 3.6, 4.2) * sc,
		CFrame.new(pos + Vector3.new(0, rng:NextNumber(16, 30), 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)),
		D.Planet[rng:NextInteger(1, #D.Planet)]:Lerp(rgb(120, 110, 120), 0.5), Enum.Material.Slate)
	-- its shadow ring on the deck so the footprint reads from above
	P.Cylinder(m, "Marker", pos, 0.05, 3, D.Glow, Enum.Material.Neon)
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local g = ctx.GroundModel

	-- landmark (east edge)
	local lz = ctx.MinZ + 290
	rocket(ctx, Vector3.new(Kit.CenterX + 134, Y, lz))

	-- neon deck seams across the whole deck + darker panel squares (flat dressing)
	local z = ctx.MinZ + 25
	while z < ctx.MaxZ - 10 do
		Kit.Flat(P, g, "DeckSeam", Kit.CenterX - Kit.FieldHalf, Kit.CenterX + Kit.FieldHalf, z - 0.3, z + 0.3, Y + 0.05, D.Glow,
			Enum.Material.Neon)
		z += 60
	end
	for _, x in { -60, 0, 60 } do
		Kit.Flat(P, g, "DeckPanel", Kit.CenterX + x - 0.3, Kit.CenterX + x + 0.3, ctx.StartZ, ctx.MaxZ, Y + 0.05,
			D.Panel:Lerp(D.Glow, 0.3))
	end

	-- props (34)
	Kit.PlaceAll(ctx, {
		{ Name = "StationModule", Count = 4, R = 10, Build = module },
		{ Name = "Dome", Count = 2, R = 7.5, Build = dome },
		{ Name = "DishAntenna", Count = 3, R = 4.5, Tall = true, Build = dish },
		{ Name = "FloatingRock", Count = 4, R = 3.5, Tall = true, MinAbsX = 40, Build = floatingRock },
		{ Name = "SolarPanel", Count = 6, R = 6, Build = solarPanel },
		{ Name = "FuelTank", Count = 3, R = 4, Build = fuelTank },
		{ Name = "Crate", Count = 8, R = 2.6, Build = crate },
		{ Name = "Beacon", Count = 4, R = 1, Build = beacon },
	})

	-- ground cover: floor lights, bolts, vent grates, cables, moon rocks
	Kit.Cover(ctx, { Count = 400, Mode = "Random", Items = {
		Kit.Weight(Kit.Disc({ D.Glow, rgb(255, 120, 200) }, 0.6, 1, Enum.Material.Neon), 3),
		Kit.Weight(Kit.Nugget({ rgb(170, 176, 196) }, 0.5, Enum.Material.Metal), 3),
		Kit.Weight(Kit.Chip({ rgb(30, 34, 56), rgb(80, 88, 120) }, 2, 1.4, 0.1, Enum.Material.DiamondPlate), 2),
		Kit.Weight(Kit.Chip({ rgb(25, 25, 35), rgb(200, 70, 70) }, 3.6, 0.25, 0.25), 1.5),
		Kit.Weight(Kit.Dome({ rgb(150, 140, 170), rgb(120, 115, 140) }, 0.8, 1.6, Enum.Material.Slate), 2.5),
	} })

	-- twinkling stars high over the band and slow drifting debris (required)
	Kit.Particles(ctx, { Name = "Stars", Y0 = 30, Y1 = 150, HalfWidth = Kit.LandmarkMaxAbsX, Rate = 24,
		Lifetime = { 3, 5 }, Speed = { 0, 0 }, LightEmission = 1, Color = ColorSequence.new(rgb(255, 255, 255), rgb(170, 220, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.4),
			NumberSequenceKeypoint.new(1, 0) }) })
	Kit.Particles(ctx, { Name = "Debris", Y0 = 6, Y1 = 50, Rate = 3, Lifetime = { 14, 20 }, Speed = { 0.4, 1.2 },
		Spread = 180, Size = NumberSequence.new(1.6, 2.6), Color = rgb(150, 145, 160), RotSpeed = { -20, 20 },
		Texture = Kit.Textures.Soft })
end
