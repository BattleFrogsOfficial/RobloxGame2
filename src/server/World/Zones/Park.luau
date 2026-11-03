--!strict
-- Park (100-250): leafy-grass lawn crossed by paved paths, daisies, dark tufts, fallen leaves and pebbles over
-- the whole plot; round trees, benches, lamp posts, bushes, a duck pond, a fountain, picnic blankets and
-- planters. Boundary: a clipped hedge with blossoms across the field. Landmark: a clock tower (no numerals, east).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function clockTower(ctx: any, base: Vector3): Model
	local P = ctx.Props
	local m = P.Model(ctx.ZoneFolder, "ClockTower")
	local stone, trim, roof = rgb(236, 222, 196), rgb(170, 120, 80), rgb(70, 120, 170)
	P.Block(m, "Plinth", Vector3.new(18, 4, 18), CFrame.new(base + Vector3.new(0, 2, 0)), trim)
	P.Block(m, "Shaft", Vector3.new(13, 44, 13), CFrame.new(base + Vector3.new(0, 26, 0)), stone)
	for _, y in { 14, 30 } do
		P.Block(m, "Band", Vector3.new(14, 1.2, 14), CFrame.new(base + Vector3.new(0, y, 0)), trim)
	end
	P.Block(m, "ClockRoom", Vector3.new(15, 12, 15), CFrame.new(base + Vector3.new(0, 54, 0)), trim)
	-- clock faces on the field side and the platform side: white disc + two hands, no numerals
	for _, face in { { Vector3.new(-7.6, 0, 0), 0 }, { Vector3.new(0, 0, -7.6), math.pi / 2 } } do
		local c = base + Vector3.new(0, 54, 0) + face[1]
		local rot = CFrame.Angles(0, face[2], 0)
		P.Part({ Parent = m, Name = "Face", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 10, 10),
			CFrame = CFrame.new(c) * rot, Color = rgb(255, 252, 240), Material = Enum.Material.Neon })
		local hand = CFrame.new(c + (face[1] :: Vector3).Unit * 0.3) * rot
		P.Block(m, "HourHand", Vector3.new(0.3, 3, 0.6), hand * CFrame.new(0, 1.3, 0), rgb(40, 40, 50))
		P.Block(m, "MinuteHand", Vector3.new(0.3, 0.6, 4.4), hand * CFrame.new(0, 0, 1.9), rgb(40, 40, 50))
	end
	Kit.Peak(P, m, "Roof", base + Vector3.new(0, 60, 0), 17, 17, 12, roof)
	P.Cylinder(m, "Finial", base + Vector3.new(0, 71, 0), 3, 0.6, rgb(255, 210, 80))
	P.Ball(m, "FinialBall", base + Vector3.new(0, 74.5, 0), 1.6, rgb(255, 210, 80), Enum.Material.Neon)
	Kit.Landmark(ctx, m, 75.3, "ClockTower")
	return m
end

local function fountain(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local stone, water = rgb(225, 220, 210), rgb(90, 190, 255)
	P.Cylinder(m, "Basin", pos, 1.6, 14, stone)
	P.Cylinder(m, "Water", pos + Vector3.new(0, 1.6, 0), 0.1, 12.5, water, Enum.Material.Glass)
	P.Cylinder(m, "Column", pos, 5, 2, stone)
	P.Cylinder(m, "Bowl", pos + Vector3.new(0, 5, 0), 1, 6, stone)
	local top = P.Ball(m, "Spout", pos + Vector3.new(0, 6.6, 0), 1.6, water, Enum.Material.Glass)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Jet"
	e.Texture = Kit.Textures.Soft
	e.Rate = 14
	e.Lifetime = NumberRange.new(0.9, 1.2)
	e.Speed = NumberRange.new(8, 10)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, -26, 0)
	e.Size = NumberSequence.new(0.8, 1.6)
	e.Color = ColorSequence.new(rgb(210, 240, 255))
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Parent = top
end

local function pond(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Ellipsoid(m, "Rim", CFrame.new(pos + Vector3.new(0, 0.1, 0)), Vector3.new(22, 0.5, 30), rgb(200, 190, 160))
	P.Ellipsoid(m, "Water", CFrame.new(pos + Vector3.new(0, 0.25, 0)), Vector3.new(19, 0.5, 27), ctx.Decor.Pond, Enum.Material.Glass)
	for _, o in { Vector3.new(-4, 0, -6), Vector3.new(3, 0, 5), Vector3.new(5, 0, -2) } do
		P.Part({ Parent = m, Name = "LilyPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 3, 3),
			CFrame = CFrame.new(pos + o + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(70, 170, 70) })
	end
	for _, o in { Vector3.new(-2, 0, 2), Vector3.new(1, 0, -8) } do
		local p = pos + o + Vector3.new(0, 0.5, 0)
		P.Ellipsoid(m, "Duck", CFrame.new(p + Vector3.new(0, 0.6, 0)), Vector3.new(1.6, 1.2, 2.4), rgb(255, 255, 255))
		P.Ball(m, "DuckHead", p + Vector3.new(0, 1.6, -0.9), 0.9, rgb(255, 255, 255))
	end
end

local function picnic(ctx: any, m: Model, pos: Vector3, i: number)
	local P = ctx.Props
	P.Block(m, "Blanket", Vector3.new(6, 0.1, 6), CFrame.new(pos + Vector3.new(0, 0.05, 0)) * Kit.Yaw(ctx),
		if i % 2 == 1 then rgb(230, 70, 70) else rgb(80, 160, 240))
	P.Block(m, "Basket", Vector3.new(1.6, 1.2, 1.2), CFrame.new(pos + Vector3.new(1, 0.6, 1)), rgb(190, 140, 80))
end

local function planter(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Block(m, "Box", Vector3.new(4, 1.6, 4), CFrame.new(pos + Vector3.new(0, 0.8, 0)), rgb(170, 110, 60), Enum.Material.Wood)
	P.Ellipsoid(m, "Bloom", CFrame.new(pos + Vector3.new(0, 2, 0)), Vector3.new(3.6, 1.6, 3.6), rgb(255, 150, 190))
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- landmark (east edge)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 10
	clockTower(ctx, Vector3.new(Kit.CenterX + 137, Y, lz))

	-- paved paths: two running down the field and one cross path (flat dressing)
	local path = rgb(236, 214, 168)
	for _, x in { -84, 84 } do
		Kit.Flat(P, g, "Path", Kit.CenterX + x - 3, Kit.CenterX + x + 3, ctx.MinZ, ctx.MaxZ, Y + 0.05, path)
	end
	local cz = ctx.MinZ + 95
	Kit.Flat(P, g, "CrossPath", Kit.CenterX - Kit.FieldHalf, Kit.CenterX + Kit.FieldHalf, cz - 3, cz + 3, Y + 0.05, path)

	-- props (22)
	Kit.PlaceAll(ctx, {
		{ Name = "Pond", Count = 1, R = 12, Build = pond },
		{ Name = "Fountain", Count = 1, R = 7, Build = fountain },
		{ Name = "Tree", Count = 7, R = 7, Tall = true, Build = function(c, m, pos)
			P.Tree(m, pos, rng:NextNumber(1, 1.3), D.Trunk, D.Leaf)
		end },
		{ Name = "Lamp", Count = 3, R = 1.4, Tall = true, Build = function(c, m, pos)
			P.Lamp(m, pos, 11, D.Lamp, rgb(255, 236, 170), false)
		end },
		{ Name = "Bench", Count = 4, R = 4, Build = function(c, m, pos, _i, side)
			P.Bench(m, pos, rng:NextNumber(0, math.pi * 2), D.Bench, D.Lamp)
		end },
		{ Name = "Picnic", Count = 2, R = 4, Build = picnic },
		{ Name = "Bush", Count = 3, R = 3, Build = function(c, m, pos)
			P.Bush(m, pos, rng:NextNumber(0.8, 1.2), D.Bush)
		end },
		{ Name = "Planter", Count = 1, R = 2, Build = planter },
	})

	-- ground cover: daisies, dark tufts, fallen leaves, pebbles
	local grass = ctx.Ground
	Kit.Cover(ctx, { Count = 240, Mode = "Random", Items = {
		Kit.Weight(Kit.Bead({ rgb(255, 255, 255), rgb(255, 250, 200) }, 0.7, 0.9, 0.1), 3),
		Kit.Weight(Kit.Spike({ grass:Lerp(Color3.new(0, 0, 0), 0.3), grass:Lerp(rgb(30, 90, 40), 0.5) }, 1, 1.6,
			Enum.Material.LeafyGrass), 4),
		Kit.Weight(Kit.Chip({ rgb(240, 180, 60), rgb(220, 120, 50), rgb(200, 200, 70) }, 1, 0.7, 0.08), 2),
		Kit.Weight(Kit.Dome({ rgb(180, 176, 168), rgb(150, 146, 140) }, 0.7, 1.1), 1),
	} })

	-- drifting leaves (light, cheap)
	Kit.Particles(ctx, { Name = "Leaves", Y0 = 6, Y1 = 18, Rate = 4, Lifetime = { 6, 9 }, Speed = { 1, 2 },
		Direction = Enum.NormalId.Bottom, Spread = 40, Size = 0.6, Accel = Vector3.new(0.6, -0.6, 0),
		Color = ColorSequence.new(rgb(120, 200, 80), rgb(240, 180, 60)), RotSpeed = { -120, 120 },
		Texture = Kit.Textures.Soft })
end
