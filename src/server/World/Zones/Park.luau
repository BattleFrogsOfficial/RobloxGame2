--!strict
-- Park (100-250): leafy trees, benches, lamp posts, a duck pond, a fountain, bushes and picnic blankets along
-- paved paths. Landmark: a clock tower (faces without numerals) at the east edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function clockTower(ctx: any, base: Vector3): Model
	local P = ctx.Props
	local m = P.Model(ctx.Folder.Parent, "ClockTower")
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

local function fountain(ctx: any, pos: Vector3)
	local P = ctx.Props
	local m = P.Model(ctx.Folder, "Fountain")
	local stone, water = rgb(225, 220, 210), rgb(90, 190, 255)
	P.Cylinder(m, "Basin", pos, 1.6, 16, stone)
	P.Cylinder(m, "Water", pos + Vector3.new(0, 1.6, 0), 0.1, 14.5, water, Enum.Material.Glass)
	P.Cylinder(m, "Column", pos, 6, 2, stone)
	P.Cylinder(m, "Bowl", pos + Vector3.new(0, 6, 0), 1, 7, stone)
	local top = P.Ball(m, "Spout", pos + Vector3.new(0, 7.6, 0), 1.6, water, Enum.Material.Glass)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Jet"
	e.Texture = Kit.Textures.Soft
	e.Rate = 14
	e.Lifetime = NumberRange.new(0.9, 1.2)
	e.Speed = NumberRange.new(9, 12)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, -26, 0)
	e.Size = NumberSequence.new(0.8, 1.6)
	e.Color = ColorSequence.new(rgb(210, 240, 255))
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Parent = top
	Kit.Decor(ctx, m)
end

local function pond(ctx: any, pos: Vector3)
	local P = ctx.Props
	local m = P.Model(ctx.Folder, "Pond")
	P.Ellipsoid(m, "Rim", CFrame.new(pos + Vector3.new(0, 0.1, 0)), Vector3.new(30, 0.5, 40), rgb(200, 190, 160))
	P.Ellipsoid(m, "Water", CFrame.new(pos + Vector3.new(0, 0.25, 0)), Vector3.new(26, 0.5, 36), ctx.Decor.Pond, Enum.Material.Glass)
	for _, o in { Vector3.new(-5, 0, -8), Vector3.new(4, 0, 6), Vector3.new(6, 0, -3) } do
		P.Part({ Parent = m, Name = "LilyPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 3, 3),
			CFrame = CFrame.new(pos + o + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(70, 170, 70),
			Shadow = false })
	end
	for _, o in { Vector3.new(-2, 0, 2), Vector3.new(1, 0, -10) } do
		local p = pos + o + Vector3.new(0, 0.5, 0)
		P.Ellipsoid(m, "Duck", CFrame.new(p + Vector3.new(0, 0.6, 0)), Vector3.new(1.6, 1.2, 2.4), rgb(255, 255, 255))
		P.Ball(m, "DuckHead", p + Vector3.new(0, 1.6, -0.9), 0.9, rgb(255, 255, 255))
	end
	Kit.Decor(ctx, m, true)
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark (east edge)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 10
	clockTower(ctx, Vector3.new(Kit.CenterX + 137, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX + 128, lz, 13)

	-- paved paths running down each outer band (flat dressing)
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * 88
		Kit.Flat(P, f.Parent, "Path", x - 2.5, x + 2.5, ctx.MinZ, ctx.MaxZ, Y + 0.05, rgb(236, 214, 168))
	end

	-- fixed features: pond (east) and fountain (west), both off the 100-stud marker lines
	local pz = ctx.MinZ + 60
	pond(ctx, Vector3.new(Kit.CenterX + 92, Y, pz))
	Kit.Reserve(ctx, Kit.CenterX + 92, pz, 21)
	local fz = ctx.MinZ + 48
	fountain(ctx, Vector3.new(Kit.CenterX - 90, Y, fz))
	Kit.Reserve(ctx, Kit.CenterX - 90, fz, 10)

	-- trees (8)
	for _, s in Kit.Band(ctx, 8, 16, 7) do
		Kit.Decor(ctx, P.Tree(f, s.Pos, rng:NextNumber(1, 1.3), D.Trunk, D.Leaf))
	end
	-- benches (4), facing the lane
	for _, s in Kit.Band(ctx, 4, 20, 5) do
		Kit.Decor(ctx, P.Bench(f, s.Pos, if s.Side > 0 then math.pi / 2 else -math.pi / 2, D.Bench, D.Lamp), true)
	end
	-- lamp posts (4)
	for _, s in Kit.Band(ctx, 4, 24, 2) do
		Kit.Decor(ctx, P.Lamp(f, s.Pos, 11, D.Lamp, rgb(255, 236, 170), false), true)
	end
	-- bushes (4)
	for _, s in Kit.Band(ctx, 4, 9, 4) do
		Kit.Decor(ctx, P.Bush(f, s.Pos, rng:NextNumber(0.8, 1.2), D.Bush), true)
	end
	-- picnic blankets (2) with a basket
	for i, s in Kit.Band(ctx, 2, 20, 4) do
		local m = P.Model(f, "Picnic")
		Kit.Flat(P, m, "Blanket", s.Pos.X - 3, s.Pos.X + 3, s.Pos.Z - 3, s.Pos.Z + 3, Y + 0.08,
			if i == 1 then rgb(230, 70, 70) else rgb(80, 160, 240))
		P.Block(m, "Basket", Vector3.new(1.6, 1.2, 1.2), CFrame.new(s.Pos + Vector3.new(1, 0.6, 1)), rgb(190, 140, 80))
		Kit.Decor(ctx, m, true)
	end

	-- drifting leaves (light, cheap)
	Kit.Particles(ctx, { Name = "Leaves", Y0 = 6, Y1 = 18, Rate = 4, Lifetime = { 6, 9 }, Speed = { 1, 2 },
		Direction = Enum.NormalId.Bottom, Spread = 40, Size = 0.6, Accel = Vector3.new(0.6, -0.6, 0),
		Color = ColorSequence.new(rgb(120, 200, 80), rgb(240, 180, 60)), RotSpeed = { -120, 120 },
		Texture = Kit.Textures.Soft })
end
