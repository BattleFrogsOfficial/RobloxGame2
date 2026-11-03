--!strict
-- Space Station (1900-2500): a diamond-plate deck with neon trim, station modules, solar panel arrays,
-- dish antennas, floating rocks, cargo crates, glass domes and beacons; twinkling stars and slow drifting
-- debris over the band. Landmark: a rocket on its launch pad at the east edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function rocket(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder.Parent, "Rocket")
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

local function module(ctx: any, pos: Vector3, side: number)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "StationModule")
	local c = pos + Vector3.new(0, 4.5, 0)
	Kit.LyingCylinder(P, m, "Hull", c, 16, 7, math.pi / 2, D.Hull, Enum.Material.Metal)
	P.Ball(m, "CapA", c + Vector3.new(0, 0, -8), 7, D.Hull, Enum.Material.Metal)
	P.Ball(m, "CapB", c + Vector3.new(0, 0, 8), 7, D.Hull, Enum.Material.Metal)
	P.Block(m, "Windows", Vector3.new(0.4, 1.2, 12), CFrame.new(c + Vector3.new(-side * 3.45, 0.6, 0)), D.Glow, Enum.Material.Neon)
	P.Block(m, "Stand", Vector3.new(4, 1.2, 10), CFrame.new(pos + Vector3.new(0, 0.6, 0)), D.Panel, Enum.Material.DiamondPlate)
	Kit.Decor(ctx, m)
end

local function solarPanel(ctx: any, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "SolarPanel")
	P.Cylinder(m, "Post", pos, 5, 0.8, D.Antenna, Enum.Material.Metal)
	for _, dz in { -3.4, 3.4 } do
		P.Block(m, "Panel", Vector3.new(8, 0.3, 6), CFrame.new(pos + Vector3.new(0, 5.6, dz)) * CFrame.Angles(0, 0, math.rad(-20)),
			rgb(40, 70, 170), Enum.Material.Glass)
	end
	P.Block(m, "Spine", Vector3.new(0.5, 0.5, 13.6), CFrame.new(pos + Vector3.new(0, 5.5, 0)), D.Glow, Enum.Material.Neon)
	Kit.Decor(ctx, m, true)
end

local function dish(ctx: any, pos: Vector3, side: number)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "DishAntenna")
	P.Cylinder(m, "Mast", pos, 9, 1, D.Antenna, Enum.Material.Metal)
	local c = pos + Vector3.new(0, 10, 0)
	local tilt = CFrame.new(c) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0) * CFrame.Angles(0, 0, math.rad(55))
	P.Part({ Parent = m, Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 9, 9), CFrame = tilt,
		Color = D.Antenna, Material = Enum.Material.Metal })
	P.Block(m, "Feed", Vector3.new(3, 0.4, 0.4), tilt * CFrame.new(1.6, 0, 0), D.Antenna, Enum.Material.Metal)
	P.Ball(m, "Tip", (tilt * CFrame.new(3.2, 0, 0)).Position, 0.9, D.Glow, Enum.Material.Neon)
	Kit.Decor(ctx, m)
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark (east edge)
	local lz = ctx.MinZ + 290
	rocket(ctx, Vector3.new(Kit.CenterX + 134, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX + 124, lz, 16)

	-- neon deck seams across the outer bands (flat dressing)
	for _, side in { -1, 1 } do
		local xa, xb = Kit.CenterX + side * (Kit.LaneHalf + 2), Kit.CenterX + side * Kit.DecorMaxAbsX
		local z = ctx.MinZ + 25
		while z < ctx.MaxZ - 10 do
			Kit.Flat(P, f.Parent, "DeckSeam", math.min(xa, xb), math.max(xa, xb), z - 0.3, z + 0.3, Y + 0.05, D.Glow, Enum.Material.Neon)
			z += 60
		end
	end

	-- station modules (4)
	for _, s in Kit.Band(ctx, 4, 40, 12) do
		module(ctx, s.Pos, s.Side)
	end
	-- solar panel arrays (5)
	for _, s in Kit.Band(ctx, 5, 18, 8) do
		solarPanel(ctx, s.Pos)
	end
	-- dish antennas (3)
	for _, s in Kit.Band(ctx, 3, 30, 7) do
		dish(ctx, s.Pos, s.Side)
	end
	-- floating rocks (5)
	for _, s in Kit.Band(ctx, 5, 20, 5) do
		local sc = rng:NextNumber(0.9, 1.5)
		local r = P.Block(f, "FloatingRock", Vector3.new(5, 3.6, 4.2) * sc,
			CFrame.new(s.Pos + Vector3.new(0, rng:NextNumber(14, 30), 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)),
			D.Planet[rng:NextInteger(1, #D.Planet)]:Lerp(rgb(120, 110, 120), 0.5), Enum.Material.Slate)
		Kit.Decor(ctx, r)
	end
	-- cargo crates (3)
	for _, s in Kit.Band(ctx, 3, 12, 4) do
		local m = P.Model(f, "Crate")
		P.Block(m, "Box", Vector3.new(4, 4, 4), CFrame.new(s.Pos + Vector3.new(0, 2, 0)) * Kit.Yaw(ctx), D.Hull, Enum.Material.Metal)
		P.Block(m, "Band", Vector3.new(4.2, 0.6, 4.2), CFrame.new(s.Pos + Vector3.new(0, 2, 0)), D.Glow, Enum.Material.Neon)
		Kit.Decor(ctx, m, true)
	end
	-- glass domes (2)
	for _, s in Kit.Band(ctx, 2, 40, 9) do
		local m = P.Model(f, "Dome")
		P.Ball(m, "Glass", s.Pos, 15, rgb(150, 220, 255), Enum.Material.Glass).Transparency = 0.35
		P.Cylinder(m, "Ring", s.Pos, 1, 16, D.Panel, Enum.Material.DiamondPlate)
		P.Block(m, "Core", Vector3.new(3, 4, 3), CFrame.new(s.Pos + Vector3.new(0, 2, 0)), D.Glow, Enum.Material.Neon)
		Kit.Decor(ctx, m)
	end
	-- beacons (2)
	for _, s in Kit.Band(ctx, 2, 30, 2) do
		local m = P.Model(f, "Beacon")
		P.Cylinder(m, "Post", s.Pos, 6, 0.6, D.Antenna, Enum.Material.Metal)
		P.Ball(m, "Light", s.Pos + Vector3.new(0, 6.6, 0), 1.6, rgb(255, 80, 80), Enum.Material.Neon)
		Kit.Decor(ctx, m, true)
	end

	-- twinkling stars high over the band and slow drifting debris (required)
	Kit.Particles(ctx, { Name = "Stars", Y0 = 30, Y1 = 150, HalfWidth = Kit.LandmarkMaxAbsX, Rate = 24,
		Lifetime = { 3, 5 }, Speed = { 0, 0 }, LightEmission = 1, Color = ColorSequence.new(rgb(255, 255, 255), rgb(170, 220, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.4),
			NumberSequenceKeypoint.new(1, 0) }) })
	Kit.Particles(ctx, { Name = "Debris", Y0 = 6, Y1 = 50, Rate = 3, Lifetime = { 14, 20 }, Speed = { 0.4, 1.2 },
		Spread = 180, Size = NumberSequence.new(1.6, 2.6), Color = rgb(150, 145, 160), RotSpeed = { -20, 20 },
		Texture = Kit.Textures.Soft })
end
