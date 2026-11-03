--!strict
-- Mythic Meadow (2500-3200): pastel glacier ground, glowing crystal clusters, giant flowers, floating islets,
-- standing-stone circles, glowing mushrooms and candy-coloured trees; sparkles drift over the band.
-- Landmark: a giant crystal spire (~255 studs) at the west edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

local function spire(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder.Parent, "CrystalSpire")
	local cols = D.Crystal
	local y = 0
	for i, t in { { 26, 80 }, { 22, 60 }, { 17, 45 }, { 12, 35 }, { 7, 25 } } do
		local w, h = t[1], t[2]
		P.Block(m, "Shaft" .. i, Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, math.rad(45), 0),
			cols[(i - 1) % #cols + 1], if i >= 3 then NEON else Enum.Material.Glass)
		y += h
	end
	Kit.Peak(P, m, "Tip", base + Vector3.new(0, y, 0), 7, 7, 12, cols[3], NEON)
	local tip = P.Ball(m, "Glow", base + Vector3.new(0, y + 4, 0), 3, rgb(255, 255, 255), NEON)
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 2
	light.Color = cols[1]
	light.Shadows = false
	light.Parent = tip
	-- foot cluster + orbiting shards
	for k = 0, 3 do
		local a = math.rad(90 * k)
		local o = Vector3.new(math.cos(a) * 12, 0, math.sin(a) * 12)
		local h = 18 + k * 4
		P.Block(m, "FootShard", Vector3.new(6, h, 6), CFrame.new(base + o + Vector3.new(0, h / 2 - 1, 0))
			* CFrame.Angles(math.rad(12) * math.cos(a), math.rad(45), math.rad(12) * math.sin(a)), cols[k % #cols + 1], NEON)
	end
	for k = 0, 5 do
		local a = math.rad(60 * k + 20)
		local o = Vector3.new(math.cos(a) * 15, 70 + k * 26, math.sin(a) * 15)
		P.Block(m, "Orbit", Vector3.new(2.4, 5, 2.4), CFrame.new(base + o) * CFrame.Angles(0.4, a, 0.3), cols[k % #cols + 1], NEON)
	end
	Kit.Landmark(ctx, m, y + 12, "CrystalSpire")
	return m
end

local function flower(ctx: any, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "GiantFlower")
	local h = ctx.Rng:NextNumber(9, 14)
	local petal = ({ D.Flower, rgb(170, 200, 255), rgb(255, 240, 150) })[ctx.Rng:NextInteger(1, 3)]
	P.Cylinder(m, "Stem", pos, h, 0.9, rgb(110, 200, 120))
	P.Ellipsoid(m, "Leaf", CFrame.new(pos + Vector3.new(1.4, h * 0.4, 0)) * CFrame.Angles(0, 0, math.rad(-30)), Vector3.new(3.4, 0.6, 1.6),
		rgb(110, 200, 120))
	local c = pos + Vector3.new(0, h, 0)
	for k = 0, 4 do
		local a = math.rad(72 * k)
		P.Ellipsoid(m, "Petal", CFrame.new(c + Vector3.new(math.cos(a) * 2.2, 0, math.sin(a) * 2.2)) * CFrame.Angles(0, -a, 0),
			Vector3.new(4, 0.8, 2.6), petal)
	end
	P.Ball(m, "Center", c + Vector3.new(0, 0.4, 0), 2.2, D.FlowerCenter, NEON)
	Kit.Decor(ctx, m, true)
end

local function islet(ctx: any, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "FloatingIslet")
	local y = ctx.Rng:NextNumber(18, 32)
	local c = pos + Vector3.new(0, y, 0)
	P.Block(m, "Top", Vector3.new(12, 1.2, 12), CFrame.new(c), D.IslandGrass)
	P.Block(m, "Earth1", Vector3.new(10, 3, 10), CFrame.new(c - Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, math.rad(20), 0), D.Island)
	P.Block(m, "Earth2", Vector3.new(6, 3, 6), CFrame.new(c - Vector3.new(0, 4.8, 0)) * CFrame.Angles(0, math.rad(50), 0), D.Island)
	P.Block(m, "Earth3", Vector3.new(2.6, 3, 2.6), CFrame.new(c - Vector3.new(0, 7.4, 0)) * CFrame.Angles(0, math.rad(10), 0), D.Island)
	P.Block(m, "Crystal", Vector3.new(1.8, 4, 1.8), CFrame.new(c + Vector3.new(2, 2.6, -1)) * CFrame.Angles(0, math.rad(45), 0),
		D.Crystal[ctx.Rng:NextInteger(1, #D.Crystal)], NEON)
	Kit.Decor(ctx, m)
end

local function stoneCircle(ctx: any, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "StandingStones")
	local stone = rgb(205, 200, 220)
	for k = 0, 5 do
		local a = math.rad(60 * k)
		local h = if k % 2 == 0 then 8 else 6.5
		P.Block(m, "Stone", Vector3.new(2.4, h, 1.6), CFrame.new(pos + Vector3.new(math.cos(a) * 6.5, h / 2, math.sin(a) * 6.5))
			* CFrame.Angles(0, -a, 0), stone, Enum.Material.Slate)
	end
	P.Block(m, "Lintel", Vector3.new(9, 1.4, 2), CFrame.new(pos + Vector3.new(0, 8.7, 0)), stone, Enum.Material.Slate)
	P.Ball(m, "Orb", pos + Vector3.new(0, 2.2, 0), 2.4, D.Crystal[2], NEON)
	Kit.Decor(ctx, m)
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark (west edge)
	local lz = ctx.MinZ + 330
	spire(ctx, Vector3.new(Kit.CenterX - 130, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX - 120, lz, 20)

	-- pastel flower-meadow patches (flat dressing)
	for i = 1, 8 do
		local side = if i % 2 == 0 then 1 else -1
		local cz = ctx.MinZ + (ctx.MaxZ - ctx.MinZ) * (i - 0.5) / 8
		local cx = Kit.CenterX + side * 92
		Kit.Flat(P, f.Parent, "Bloom", cx - 22, cx + 22, cz - 16, cz + 16, Y + 0.04,
			({ rgb(255, 190, 235), rgb(190, 230, 255), rgb(255, 240, 180) })[i % 3 + 1], Enum.Material.Grass)
	end

	-- glowing crystal clusters (6)
	for _, s in Kit.Band(ctx, 6, 18, 4) do
		local m = P.Model(f, "CrystalCluster")
		for k = 1, 3 do
			local h = rng:NextNumber(3, 7)
			local o = Vector3.new(rng:NextNumber(-1.4, 1.4), 0, rng:NextNumber(-1.4, 1.4))
			P.Block(m, "Crystal", Vector3.new(1.6, h, 1.6), CFrame.new(s.Pos + o + Vector3.new(0, h / 2, 0))
				* CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), math.rad(45), math.rad(rng:NextNumber(-15, 15))),
				D.Crystal[(k - 1) % #D.Crystal + 1], NEON)
		end
		Kit.Decor(ctx, m, true)
	end
	-- giant flowers (6)
	for _, s in Kit.Band(ctx, 6, 14, 6) do
		flower(ctx, s.Pos)
	end
	-- floating islets (4)
	for _, s in Kit.Band(ctx, 4, 40, 9) do
		islet(ctx, s.Pos)
	end
	-- standing-stone circles (2)
	for _, s in Kit.Band(ctx, 2, 80, 9) do
		stoneCircle(ctx, s.Pos)
	end
	-- glowing mushrooms (3)
	for _, s in Kit.Band(ctx, 3, 10, 3) do
		local m = P.Model(f, "GlowShroom")
		P.Cylinder(m, "Stem", s.Pos, 2.4, 1, rgb(250, 240, 255))
		P.Ellipsoid(m, "Cap", CFrame.new(s.Pos + Vector3.new(0, 2.6, 0)), Vector3.new(3.6, 1.8, 3.6), D.Crystal[2], NEON)
		Kit.Decor(ctx, m, true)
	end
	-- candy-coloured trees (2)
	for _, s in Kit.Band(ctx, 2, 30, 7) do
		Kit.Decor(ctx, P.Tree(f, s.Pos, rng:NextNumber(1, 1.2), rgb(240, 220, 250), rgb(255, 170, 220)))
	end

	-- sparkles drifting over the band (required)
	Kit.Particles(ctx, { Name = "Sparkles", Y0 = 1, Y1 = 40, HalfWidth = Kit.LandmarkMaxAbsX, Rate = 40,
		Lifetime = { 2, 4 }, Speed = { 0.3, 1 }, Spread = 180, LightEmission = 1, Accel = Vector3.new(0, 0.6, 0),
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 150, 230)), ColorSequenceKeypoint.new(0.5, rgb(255, 230, 140)),
			ColorSequenceKeypoint.new(1, rgb(150, 220, 255)) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 0) }) })
end
