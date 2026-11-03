--!strict
-- Backyard (0-100): the tidy home lawn. Mown stripes across the whole plot, neat rows of flowers / clover /
-- tufts, and a few spaced props: kennels, round trees, bushes, flower beds, gnomes, toys, a sprinkler, a sandpit
-- and a birdbath. Boundary: a white picket fence across the field. Landmark: a stacked doghouse tower (west).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function kennel(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P, D = ctx.Props, ctx.Decor
	local scale = ctx.Rng:NextNumber(0.85, 1)
	local cf = CFrame.new(pos) * Kit.FaceLane(-side)
	P.Block(m, "Body", Vector3.new(7, 5, 7) * scale, cf * CFrame.new(0, 2.5 * scale, 0), D.House)
	Kit.Gable(P, m, "Roof", cf * CFrame.new(0, 5 * scale, 0), 8 * scale, 8 * scale, 3 * scale, D.Roof)
	P.Block(m, "Door", Vector3.new(3, 3.4, 0.3) * scale, cf * CFrame.new(0, 1.7 * scale, -3.55 * scale), rgb(60, 40, 30))
	P.Block(m, "Bowl", Vector3.new(1.6, 0.6, 1.6), cf * CFrame.new(2.4 * scale, 0.3, -4.6 * scale), D.Toy)
end

local function gnome(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Block(m, "Body", Vector3.new(1.8, 2, 1.6), CFrame.new(pos + Vector3.new(0, 1, 0)), rgb(70, 120, 220))
	P.Block(m, "Beard", Vector3.new(1.4, 1.2, 0.5), CFrame.new(pos + Vector3.new(0, 2.2, -0.75)), rgb(250, 250, 250))
	P.Ball(m, "Head", pos + Vector3.new(0, 2.9, 0), 1.4, rgb(255, 210, 170))
	P.Block(m, "Hat", Vector3.new(1.2, 1.6, 1.2), CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(45), 0),
		rgb(230, 50, 50))
end

local function sprinkler(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
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
end

local function flowerBed(ctx: any, m: Model, pos: Vector3, i: number)
	local P, D = ctx.Props, ctx.Decor
	P.Block(m, "Soil", Vector3.new(6, 0.6, 3), CFrame.new(pos + Vector3.new(0, 0.3, 0)), rgb(140, 95, 60))
	P.Ellipsoid(m, "Flowers", CFrame.new(pos + Vector3.new(0, 1.1, 0)), Vector3.new(5.5, 1.4, 2.4),
		({ D.Flower, rgb(255, 220, 80), rgb(190, 120, 255) })[(i - 1) % 3 + 1])
end

local function sandpit(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Block(m, "Frame", Vector3.new(9, 0.8, 9), CFrame.new(pos + Vector3.new(0, 0.4, 0)), rgb(170, 110, 60))
	P.Block(m, "Sand", Vector3.new(7.6, 0.2, 7.6), CFrame.new(pos + Vector3.new(0, 0.85, 0)), rgb(240, 220, 160), Enum.Material.Sand)
	P.Block(m, "Bucket", Vector3.new(1, 1.2, 1), CFrame.new(pos + Vector3.new(2, 1.5, 1.5)), rgb(80, 170, 255))
end

local function birdbath(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local stone = rgb(225, 222, 214)
	P.Cylinder(m, "Foot", pos, 0.6, 2.2, stone)
	P.Cylinder(m, "Column", pos + Vector3.new(0, 0.6, 0), 2.6, 0.8, stone)
	P.Cylinder(m, "Bowl", pos + Vector3.new(0, 3.2, 0), 0.6, 3.2, stone)
	P.Cylinder(m, "Water", pos + Vector3.new(0, 3.8, 0), 0.05, 2.6, rgb(120, 200, 255), Enum.Material.Glass)
end

local function tower(ctx: any, base: Vector3): Model
	-- three stacked doghouses (22 / 16 / 10 wide) with a bone on top: 47 studs
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.ZoneFolder, "DoghouseTower")
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
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- landmark first so everything else keeps clear of it
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 12
	tower(ctx, Vector3.new(Kit.CenterX - 136, Y, lz))

	-- mown-lawn stripes across the whole plot (flat dressing, part of the persistent ground)
	local i = 0
	local z = ctx.MinZ
	while z < ctx.MaxZ do
		if i % 2 == 0 then
			Kit.Flat(P, g, "LawnStripe", Kit.CenterX - Kit.FieldHalf, Kit.CenterX + Kit.FieldHalf, z, math.min(z + 8, ctx.MaxZ), Y + 0.04,
				ctx.Ground:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Grass)
		end
		z += 8
		i += 1
	end

	-- props (20): tidy, well spaced
	Kit.PlaceAll(ctx, {
		{ Name = "Tree", Count = 3, R = 6, Tall = true, MinAbsX = 50,
			Build = function(c, m, pos)
				P.Tree(m, pos, rng:NextNumber(0.9, 1.1), D.Trunk, D.Leaf)
			end },
		{ Name = "Kennel", Count = 3, R = 5, Build = kennel },
		{ Name = "Sandpit", Count = 1, R = 4.5, Build = sandpit },
		{ Name = "FlowerBed", Count = 3, R = 3, Build = flowerBed },
		{ Name = "Bush", Count = 4, R = 3, Build = function(c, m, pos)
			P.Bush(m, pos, rng:NextNumber(0.8, 1.1), D.Leaf:Lerp(Color3.new(0, 0, 0), 0.15))
		end },
		{ Name = "Birdbath", Count = 1, R = 1.6, Build = birdbath },
		{ Name = "Sprinkler", Count = 1, R = 1.2, Build = sprinkler },
		{ Name = "GardenGnome", Count = 2, R = 1, Build = gnome },
		{ Name = "ToyBall", Count = 2, R = 1, Build = function(c, m, pos, n)
			P.Ball(m, "Toy", pos + Vector3.new(0, 1, 0), 2, if n % 2 == 0 then D.Toy else D.Flower)
		end },
	})

	-- ground cover (tidy rows): flowers, clover, grass tufts, stepping stones
	local grass = ctx.Ground
	Kit.Cover(ctx, { Count = 214, Mode = "Grid", Items = {
		Kit.Weight(Kit.Bead({ rgb(255, 120, 180), rgb(255, 230, 90), rgb(255, 255, 255), rgb(255, 90, 90) }, 0.8, 1.1, 0.15), 4),
		Kit.Weight(Kit.Disc({ grass:Lerp(Color3.new(0, 0, 0), 0.25), grass:Lerp(rgb(40, 120, 40), 0.5) }, 1.4, 2.2,
			Enum.Material.Grass), 2),
		Kit.Weight(Kit.Spike({ grass:Lerp(Color3.new(1, 1, 1), 0.2), grass:Lerp(rgb(60, 140, 40), 0.4) }, 0.9, 1.3,
			Enum.Material.Grass), 3),
		Kit.Weight(Kit.Disc({ rgb(205, 200, 190), rgb(185, 180, 172) }, 1.8, 2.4), 0.6),
	} })

	-- butterflies (light, cheap)
	Kit.Particles(ctx, { Name = "Butterflies", Y0 = 1, Y1 = 8, Rate = 3, Lifetime = { 5, 8 }, Speed = { 0.5, 1.5 },
		Size = 0.5, Color = ColorSequence.new(rgb(255, 200, 80), rgb(255, 130, 200)), Spread = 180, Drag = 0.5,
		RotSpeed = { -90, 90 } })
end
