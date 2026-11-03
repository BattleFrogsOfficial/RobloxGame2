--!strict
-- Forest (700-1000): dark grass with leaf-litter patches, dense pines and broadleaf trees, fallen logs,
-- red mushrooms and mossy rocks; fireflies hover over the whole band. Landmark: a giant tree at the west edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function giantTree(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder.Parent, "GiantTree")
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

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark (west edge)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 6
	giantTree(ctx, Vector3.new(Kit.CenterX - 130, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX - 118, lz, 22)

	-- leaf-litter patches on the outer bands (flat dressing)
	for i = 1, 6 do
		local side = if i % 2 == 0 then 1 else -1
		local cz = ctx.MinZ + (ctx.MaxZ - ctx.MinZ) * (i - 0.5) / 6
		local cx = Kit.CenterX + side * 90
		Kit.Flat(P, f.Parent, "LeafLitter", cx - 24, cx + 24, cz - 14, cz + 14, Y + 0.04,
			if i % 3 == 0 then rgb(110, 80, 45) else rgb(80, 96, 44), Enum.Material.Ground)
	end

	-- dense pines (12) and broadleaf trees (4)
	for i, s in Kit.Band(ctx, 12, 11, 8) do
		Kit.Decor(ctx, P.Pine(f, s.Pos, rng:NextNumber(1.2, 1.6), if i % 3 == 0 then D.PineDark else D.Pine, D.Trunk))
	end
	for _, s in Kit.Band(ctx, 4, 14, 7) do
		Kit.Decor(ctx, P.Tree(f, s.Pos, rng:NextNumber(1, 1.2), D.Trunk, rgb(70, 150, 60)))
	end
	-- fallen logs (3): log + cut end
	for _, s in Kit.Band(ctx, 3, 16, 6) do
		local m = P.Model(f, "Log")
		local yaw = rng:NextNumber(0, math.pi)
		Kit.LyingCylinder(P, m, "Log", s.Pos + Vector3.new(0, 1.3, 0), 9, 2.6, yaw, D.Log, Enum.Material.Wood)
		local dir = CFrame.Angles(0, yaw, 0).RightVector
		Kit.LyingCylinder(P, m, "Ring", s.Pos + Vector3.new(0, 1.3, 0) + dir * 4.55, 0.1, 2.2, yaw, rgb(220, 180, 120))
		Kit.Decor(ctx, m, true)
	end
	-- mushrooms (4): stem + cap + spots
	for _, s in Kit.Band(ctx, 4, 8, 3) do
		local m = P.Model(f, "Mushroom")
		local sc = rng:NextNumber(1, 1.6)
		P.Cylinder(m, "Stem", s.Pos, 2 * sc, 1 * sc, D.MushroomStem)
		P.Ellipsoid(m, "Cap", CFrame.new(s.Pos + Vector3.new(0, 2.2 * sc, 0)), Vector3.new(3.4, 1.8, 3.4) * sc, D.Mushroom)
		P.Ball(m, "Spot", s.Pos + Vector3.new(0.6 * sc, 2.9 * sc, -0.5 * sc), 0.6 * sc, Color3.new(1, 1, 1))
		Kit.Decor(ctx, m, true)
	end
	-- mossy rocks (3)
	for _, s in Kit.Band(ctx, 3, 14, 5) do
		Kit.Decor(ctx, P.Rock(f, s.Pos, rng:NextNumber(0.8, 1.1), rgb(110, 120, 100), rng:NextNumber(0, 6.28)), true)
	end

	-- fireflies over the whole band (required)
	Kit.Particles(ctx, { Name = "Fireflies", Y0 = 1, Y1 = 12, Rate = 28, Lifetime = { 4, 7 }, Speed = { 0.3, 1.2 },
		Spread = 180, Drag = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 0.2) }),
		Color = rgb(220, 255, 120), LightEmission = 1, Accel = Vector3.new(0, 0.2, 0) })
end
