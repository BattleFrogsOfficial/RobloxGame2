--!strict
-- Forest (700-1000): dark grass under a thick litter of leaves, ferns, tiny mushrooms, moss and twigs (dense
-- clumps); dense pines and broadleaf trees, fallen logs, stumps, red mushrooms and mossy rocks; fireflies over
-- the whole band. Boundary: a line of felled logs across the field. Landmark: a giant tree (west).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function giantTree(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.ZoneFolder, "GiantTree")
	local bark, leaf = rgb(105, 70, 42), rgb(58, 140, 64)
	-- buttress roots
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		P.Wedge({ Parent = m, Name = "Root", Size = Vector3.new(4, 10, 9),
			CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 10, 5, math.sin(a) * 10))
				* CFrame.Angles(0, -a - math.pi / 2, 0), Color = bark })
	end
	P.Cylinder(m, "Trunk", base, 84, 16, bark, Enum.Material.Wood)
	P.Block(m, "Branch", Vector3.new(26, 4, 4), CFrame.new(base + Vector3.new(12, 70, 0)) * CFrame.Angles(0, 0, math.rad(25)), bark)
	local canopies = {
		{ Vector3.new(4, 92, 0), Vector3.new(44, 30, 46) },
		{ Vector3.new(-2, 112, 6), Vector3.new(34, 24, 34) },
		{ Vector3.new(14, 80, -12), Vector3.new(26, 18, 26) },
		{ Vector3.new(0, 124, -4), Vector3.new(20, 16, 20) },
	}
	for i, c in canopies do
		P.Ellipsoid(m, "Canopy" .. i, CFrame.new(base + c[1]), c[2], if i % 2 == 0 then leaf:Lerp(Color3.new(1, 1, 1), 0.1) else leaf)
	end
	-- a glowing hollow at the foot (faces the lane)
	P.Block(m, "Hollow", Vector3.new(0.6, 7, 5), CFrame.new(base + Vector3.new(8, 3.5, 0)), rgb(255, 220, 120), Enum.Material.Neon)
	Kit.Landmark(ctx, m, 132, "GiantTree")
	return m
end

local function log(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local yaw = ctx.Rng:NextNumber(0, math.pi)
	Kit.LyingCylinder(P, m, "Log", pos + Vector3.new(0, 1.3, 0), 9, 2.6, yaw, D.Log, Enum.Material.Wood)
	local dir = CFrame.Angles(0, yaw, 0).RightVector
	Kit.LyingCylinder(P, m, "Ring", pos + Vector3.new(0, 1.3, 0) + dir * 4.55, 0.1, 2.2, yaw, rgb(220, 180, 120))
end

local function mushroom(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local sc = ctx.Rng:NextNumber(1, 1.6)
	P.Cylinder(m, "Stem", pos, 2 * sc, 1 * sc, D.MushroomStem)
	P.Ellipsoid(m, "Cap", CFrame.new(pos + Vector3.new(0, 2.2 * sc, 0)), Vector3.new(3.4, 1.8, 3.4) * sc, D.Mushroom)
	P.Ball(m, "Spot", pos + Vector3.new(0.6 * sc, 2.9 * sc, -0.5 * sc), 0.6 * sc, Color3.new(1, 1, 1))
end

local function stump(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Stump", pos, 2.2, 3.2, D.Trunk, Enum.Material.Wood)
	P.Cylinder(m, "Rings", pos + Vector3.new(0, 2.2, 0), 0.05, 2.8, rgb(220, 180, 120))
	P.Ellipsoid(m, "Moss", CFrame.new(pos + Vector3.new(0.8, 2.3, 0.4)), Vector3.new(1.6, 0.5, 1.4), rgb(90, 150, 60))
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- landmark (west edge)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 6
	giantTree(ctx, Vector3.new(Kit.CenterX - 130, Y, lz))

	-- leaf-litter patches across the whole plot (flat dressing)
	for i = 1, 9 do
		local col = (i - 1) % 3 - 1
		local cz = ctx.MinZ + (ctx.MaxZ - ctx.MinZ) * (i - 0.5) / 9
		local cx = Kit.CenterX + col * 78 + rng:NextNumber(-8, 8)
		Kit.Flat(P, g, "LeafLitter", math.max(cx - 30, -Kit.FieldHalf), math.min(cx + 30, Kit.FieldHalf), cz - 14, cz + 14, Y + 0.04,
			if i % 3 == 0 then rgb(110, 80, 45) else rgb(80, 96, 44), Enum.Material.Ground)
	end

	-- props (34): a dense wood with low things in the middle
	Kit.PlaceAll(ctx, {
		{ Name = "Pine", Count = 12, R = 6, Tall = true, Build = function(c, m, pos, i)
			P.Pine(m, pos, rng:NextNumber(1.2, 1.6), if i % 3 == 0 then D.PineDark else D.Pine, D.Trunk)
		end },
		{ Name = "Tree", Count = 4, R = 7, Tall = true, Build = function(c, m, pos)
			P.Tree(m, pos, rng:NextNumber(1, 1.2), D.Trunk, rgb(70, 150, 60))
		end },
		{ Name = "Log", Count = 4, R = 4.5, Build = log },
		{ Name = "MossyRock", Count = 3, R = 3, Build = function(c, m, pos)
			P.Rock(m, pos, rng:NextNumber(0.8, 1.1), rgb(110, 120, 100), rng:NextNumber(0, 6.28))
		end },
		{ Name = "Stump", Count = 4, R = 1.8, Build = stump },
		{ Name = "Mushroom", Count = 3, R = 2.2, Build = mushroom },
		{ Name = "FernClump", Count = 4, R = 2.5, Build = function(c, m, pos)
			for k = 0, 4 do
				local a = k * 1.26 + rng:NextNumber(0, 0.5)
				P.Wedge({ Parent = m, Name = "Frond", Size = Vector3.new(0.6, 2.6, 2.4),
					CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.1, 1.3, math.sin(a) * 1.1)) * CFrame.Angles(0, -a + math.pi / 2, 0),
					Color = if k % 2 == 0 then rgb(50, 130, 55) else rgb(70, 150, 60), Material = Enum.Material.Grass })
			end
		end },
	})

	-- ground cover (dense clumps): leaves, ferns, tiny mushrooms, moss, twigs
	Kit.Cover(ctx, { Count = 380, Mode = "Clumps", Clumps = 16, ClumpRadius = 10, Items = {
		Kit.Weight(Kit.Chip({ rgb(200, 110, 40), rgb(170, 60, 40), rgb(140, 95, 45), rgb(210, 160, 60) }, 1.1, 0.8, 0.08), 5),
		Kit.Weight(Kit.Spike({ rgb(40, 120, 50), rgb(60, 140, 60) }, 1.6, 1.8, Enum.Material.Grass), 4),
		Kit.Weight(Kit.Bead({ rgb(230, 60, 60), rgb(240, 200, 150) }, 0.6, 0.9, 0.25), 1.5),
		Kit.Weight(Kit.Disc({ rgb(70, 130, 50), rgb(90, 140, 60) }, 1.8, 3.2, Enum.Material.Grass), 1.5),
		Kit.Weight(Kit.Chip({ rgb(100, 70, 45) }, 2.2, 0.25, 0.25, Enum.Material.Wood), 1.5),
	} })

	-- fireflies over the whole band (required)
	Kit.Particles(ctx, { Name = "Fireflies", Y0 = 1, Y1 = 12, Rate = 28, Lifetime = { 4, 7 }, Speed = { 0.3, 1.2 },
		Spread = 180, Drag = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 0.2) }),
		Color = rgb(220, 255, 120), LightEmission = 1, Accel = Vector3.new(0, 0.2, 0) })
end
