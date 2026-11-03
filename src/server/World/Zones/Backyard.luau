--!strict
-- Backyard (0-100): mown lawn, white picket fences along the lane edges, kennels, bushes, sprinklers,
-- garden gnome-like figures, flower beds and toys. Landmark: a stacked doghouse tower at the west edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function kennel(ctx: any, pos: Vector3, side: number, scale: number)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "Kennel")
	local cf = CFrame.new(pos) * Kit.FaceLane(side)
	P.Block(m, "Body", Vector3.new(7, 5, 7) * scale, cf * CFrame.new(0, 2.5 * scale, 0), D.House)
	Kit.Gable(P, m, "Roof", cf * CFrame.new(0, 5 * scale, 0), 8 * scale, 8 * scale, 3 * scale, D.Roof)
	P.Block(m, "Door", Vector3.new(3, 3.4, 0.3) * scale, cf * CFrame.new(0, 1.7 * scale, -3.55 * scale), rgb(60, 40, 30))
	P.Block(m, "Bowl", Vector3.new(1.6, 0.6, 1.6), cf * CFrame.new(2.6 * scale, 0.3, -5 * scale), D.Toy)
	Kit.Decor(ctx, m)
end

local function gnome(ctx: any, pos: Vector3)
	local P = ctx.Props
	local m = P.Model(ctx.Folder, "GardenGnome")
	P.Block(m, "Body", Vector3.new(1.8, 2, 1.6), CFrame.new(pos + Vector3.new(0, 1, 0)), rgb(70, 120, 220))
	P.Block(m, "Beard", Vector3.new(1.4, 1.2, 0.5), CFrame.new(pos + Vector3.new(0, 2.2, -0.75)), rgb(250, 250, 250))
	P.Ball(m, "Head", pos + Vector3.new(0, 2.9, 0), 1.4, rgb(255, 210, 170))
	P.Block(m, "HatA", Vector3.new(1.6, 0.8, 1.6), CFrame.new(pos + Vector3.new(0, 3.6, 0)), rgb(230, 50, 50))
	P.Block(m, "HatB", Vector3.new(0.9, 1, 0.9), CFrame.new(pos + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, math.rad(45), 0),
		rgb(230, 50, 50))
	Kit.Decor(ctx, m, true)
end

local function sprinkler(ctx: any, pos: Vector3)
	local P = ctx.Props
	local m = P.Model(ctx.Folder, "Sprinkler")
	P.Cylinder(m, "Base", pos, 0.4, 2.4, rgb(70, 180, 90))
	P.Cylinder(m, "Stem", pos + Vector3.new(0, 0.4, 0), 1.2, 0.5, rgb(200, 200, 210))
	local head = P.Ball(m, "Head", pos + Vector3.new(0, 1.8, 0), 0.9, rgb(230, 230, 240))
	local e = Instance.new("ParticleEmitter")
	e.Name = "Spray"
	e.Texture = Kit.Textures.Soft
	e.Rate = 10
	e.Lifetime = NumberRange.new(0.8, 1.2)
	e.Speed = NumberRange.new(8, 11)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -24, 0)
	e.Size = NumberSequence.new(0.6, 1.4)
	e.Color = ColorSequence.new(rgb(200, 235, 255))
	e.Transparency = NumberSequence.new(0.35, 1)
	e.Parent = head
	Kit.Decor(ctx, m, true)
end

local function tower(ctx: any, base: Vector3): Model
	-- three stacked doghouses (22 / 16 / 10 wide) with a bone on top: 47 studs
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder.Parent, "DoghouseTower")
	local y = 0
	local tiers = { { 22, 13, rgb(255, 196, 110) }, { 16, 10, rgb(130, 200, 255) }, { 10, 7, rgb(255, 150, 190) } }
	for i, t in tiers do
		local w, h, c = t[1], t[2], t[3]
		P.Block(m, "Body" .. i, Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, y + h / 2, 0)), c)
		P.Block(m, "Door" .. i, Vector3.new(w * 0.4, h * 0.55, 0.4),
			CFrame.new(base + Vector3.new(w / 2 + 0.1, y + h * 0.28, 0)) * CFrame.Angles(0, math.pi / 2, 0), rgb(60, 40, 30))
		Kit.Gable(P, m, "Roof" .. i, CFrame.new(base + Vector3.new(0, y + h, 0)), w + 2, w + 2, w * 0.3, D.Roof)
		y += h + w * 0.3 - 2
	end
	-- bone: shaft + four knobs
	local by = y + 3.5
	P.Block(m, "BoneShaft", Vector3.new(1.6, 1.6, 7), CFrame.new(base + Vector3.new(0, by, 0)), rgb(255, 250, 235))
	for _, dz in { -3.6, 3.6 } do
		for _, dx in { -0.9, 0.9 } do
			P.Ball(m, "BoneKnob", base + Vector3.new(dx, by, dz), 2.2, rgb(255, 250, 235))
		end
	end
	Kit.Landmark(ctx, m, by + 1.1, "DoghouseTower")
	return m
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng
	local z0, z1 = ctx.MinZ, ctx.MaxZ - 4

	-- landmark first so the scatter keeps clear of it
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 6
	tower(ctx, Vector3.new(Kit.CenterX - 136, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX - 128, lz, 16)

	-- mown-lawn stripes in the outer bands (flat dressing)
	for _, side in { -1, 1 } do
		local i = 0
		local z = z0
		while z < ctx.MaxZ do
			if i % 2 == 0 then
				local xa, xb = Kit.CenterX + side * (Kit.LaneHalf + 3), Kit.CenterX + side * Kit.DecorMaxAbsX
				Kit.Flat(P, f.Parent, "LawnStripe", math.min(xa, xb), math.max(xa, xb), z, math.min(z + 10, ctx.MaxZ), Y + 0.04,
					ctx.Ground:Lerp(Color3.new(1, 1, 1), 0.1))
			end
			z += 10
			i += 1
		end
	end

	-- picket fence just outside each lane edge (2)
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * (Kit.LaneHalf + 1.5)
		Kit.Decor(ctx, P.FenceLine(f, Vector3.new(x, Y, z0), Vector3.new(x, Y, z1), 10, 3, D.Fence, false))
	end
	-- kennels (3)
	for _, s in Kit.Band(ctx, 3, 22, 7) do
		kennel(ctx, s.Pos, s.Side, rng:NextNumber(0.9, 1.1))
	end
	-- round trees (2)
	for _, s in Kit.Band(ctx, 2, 18, 7) do
		Kit.Decor(ctx, P.Tree(f, s.Pos, rng:NextNumber(0.9, 1.1), D.Trunk, D.Leaf))
	end
	-- bushes (5)
	for _, s in Kit.Band(ctx, 5, 9, 4) do
		Kit.Decor(ctx, P.Bush(f, s.Pos, rng:NextNumber(0.8, 1.2), D.Leaf:Lerp(Color3.new(0, 0, 0), 0.15)), true)
	end
	-- sprinklers (3)
	for _, s in Kit.Band(ctx, 3, 14, 2) do
		sprinkler(ctx, s.Pos)
	end
	-- garden gnomes (3)
	for _, s in Kit.Band(ctx, 3, 8, 2) do
		gnome(ctx, s.Pos)
	end
	-- flower beds (3)
	for _, s in Kit.Band(ctx, 3, 10, 4) do
		local m = P.Model(f, "FlowerBed")
		P.Slab(m, "Soil", s.Pos.X - 3, s.Pos.X + 3, s.Pos.Z - 1.5, s.Pos.Z + 1.5, Y + 0.6, 0.6, rgb(140, 95, 60), nil, false)
		P.Ellipsoid(m, "Flowers", CFrame.new(s.Pos + Vector3.new(0, 1.1, 0)), Vector3.new(5.5, 1.4, 2.4), D.Flower)
		Kit.Decor(ctx, m, true)
	end
	-- toy balls (2) + a sandpit (1)
	for _, s in Kit.Band(ctx, 2, 8, 2) do
		Kit.Decor(ctx, P.Ball(f, "Toy", s.Pos + Vector3.new(0, 1, 0), 2, if rng:NextNumber() < 0.5 then D.Toy else D.Flower), true)
	end
	for _, s in Kit.Band(ctx, 1, 10, 5) do
		local m = P.Model(f, "Sandpit")
		P.Slab(m, "Frame", s.Pos.X - 4.5, s.Pos.X + 4.5, s.Pos.Z - 4.5, s.Pos.Z + 4.5, Y + 0.8, 0.8, rgb(170, 110, 60), nil, false)
		P.Slab(m, "Sand", s.Pos.X - 3.8, s.Pos.X + 3.8, s.Pos.Z - 3.8, s.Pos.Z + 3.8, Y + 0.9, 0.8, rgb(240, 220, 160),
			Enum.Material.Sand, false)
		Kit.Decor(ctx, m, true)
	end

	-- butterflies (light, cheap)
	Kit.Particles(ctx, { Name = "Butterflies", Y0 = 1, Y1 = 8, Rate = 3, Lifetime = { 5, 8 }, Speed = { 0.5, 1.5 },
		Size = 0.5, Color = ColorSequence.new(rgb(255, 200, 80), rgb(255, 130, 200)), Spread = 180, Drag = 0.5,
		RotSpeed = { -90, 90 } })
end
