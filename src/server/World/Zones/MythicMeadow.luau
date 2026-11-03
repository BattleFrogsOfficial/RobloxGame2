--!strict
-- Mythic Meadow (2500-3200): the densest, glowing plot. Pastel glacier ground with bloom patches, thick clumps of
-- glowing flowers, crystal chips, lavender tufts, petals and sparkle stones; crystal clusters (a few lit),
-- giant flowers, floating islets, standing-stone circles, glowing mushrooms and candy trees; sparkles drift
-- over the band. Boundary: a glowing rim with crystal shards across the field. Landmark: a crystal spire (west).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB
local NEON = Enum.Material.Neon

local function spire(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.ZoneFolder, "CrystalSpire")
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

local lights = 0
local MAX_LIGHTS = 6 -- PointLights sparingly (phones)

local function crystalCluster(ctx: any, m: Model, pos: Vector3, i: number)
	local P, D, rng = ctx.Props, ctx.Decor, ctx.Rng
	local tallest: BasePart? = nil
	local best = 0
	for k = 1, 4 do
		local h = rng:NextNumber(3, 8)
		local o = Vector3.new(rng:NextNumber(-1.8, 1.8), 0, rng:NextNumber(-1.8, 1.8))
		local p = P.Block(m, "Crystal", Vector3.new(1.6, h, 1.6), CFrame.new(pos + o + Vector3.new(0, h / 2, 0))
			* CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), math.rad(45), math.rad(rng:NextNumber(-15, 15))),
			D.Crystal[(k + i) % #D.Crystal + 1], NEON)
		if h > best then
			best, tallest = h, p
		end
	end
	if i % 3 == 1 and lights < MAX_LIGHTS and tallest then
		lights += 1
		local l = Instance.new("PointLight")
		l.Range = 14
		l.Brightness = 1.4
		l.Color = (tallest :: BasePart).Color
		l.Shadows = false
		l.Parent = tallest
	end
end

local function flower(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
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
end

local function islet(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local y = ctx.Rng:NextNumber(18, 32)
	local c = pos + Vector3.new(0, y, 0)
	P.Block(m, "Top", Vector3.new(12, 1.2, 12), CFrame.new(c), D.IslandGrass)
	P.Block(m, "Earth1", Vector3.new(10, 3, 10), CFrame.new(c - Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, math.rad(20), 0), D.Island)
	P.Block(m, "Earth2", Vector3.new(6, 3, 6), CFrame.new(c - Vector3.new(0, 4.8, 0)) * CFrame.Angles(0, math.rad(50), 0), D.Island)
	P.Block(m, "Earth3", Vector3.new(2.6, 3, 2.6), CFrame.new(c - Vector3.new(0, 7.4, 0)) * CFrame.Angles(0, math.rad(10), 0), D.Island)
	P.Block(m, "Crystal", Vector3.new(1.8, 4, 1.8), CFrame.new(c + Vector3.new(2, 2.6, -1)) * CFrame.Angles(0, math.rad(45), 0),
		D.Crystal[ctx.Rng:NextInteger(1, #D.Crystal)], NEON)
	P.Cylinder(m, "Glow", pos, 0.05, 6, D.IslandGrass, NEON)
end

local function stoneCircle(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local stone = rgb(205, 200, 220)
	for k = 0, 5 do
		local a = math.rad(60 * k)
		local h = if k % 2 == 0 then 8 else 6.5
		P.Block(m, "Stone", Vector3.new(2.4, h, 1.6), CFrame.new(pos + Vector3.new(math.cos(a) * 6.5, h / 2, math.sin(a) * 6.5))
			* CFrame.Angles(0, -a, 0), stone, Enum.Material.Slate)
	end
	P.Block(m, "Lintel", Vector3.new(9, 1.4, 2), CFrame.new(pos + Vector3.new(0, 8.7, 0)), stone, Enum.Material.Slate)
	P.Ball(m, "Orb", pos + Vector3.new(0, 2.2, 0), 2.4, D.Crystal[2], NEON)
end

local function glowShroom(ctx: any, m: Model, pos: Vector3, i: number)
	local P, D = ctx.Props, ctx.Decor
	local s = ctx.Rng:NextNumber(0.9, 1.5)
	P.Cylinder(m, "Stem", pos, 2.4 * s, 1 * s, rgb(250, 240, 255))
	P.Ellipsoid(m, "Cap", CFrame.new(pos + Vector3.new(0, 2.6 * s, 0)), Vector3.new(3.6, 1.8, 3.6) * s,
		D.Crystal[(i - 1) % #D.Crystal + 1], NEON)
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel
	lights = 0

	-- landmark (west edge)
	local lz = ctx.MinZ + 330
	spire(ctx, Vector3.new(Kit.CenterX - 130, Y, lz))

	-- pastel bloom patches across the whole plot (flat dressing)
	for i = 1, 12 do
		local col = (i - 1) % 3 - 1
		local cz = ctx.MinZ + (ctx.MaxZ - ctx.MinZ) * (i - 0.5) / 12
		local cx = Kit.CenterX + col * 76 + rng:NextNumber(-10, 10)
		Kit.Flat(P, g, "Bloom", math.max(cx - 28, -Kit.FieldHalf), math.min(cx + 28, Kit.FieldHalf), cz - 18, cz + 18, Y + 0.04,
			({ rgb(255, 190, 235), rgb(190, 230, 255), rgb(255, 240, 180) })[i % 3 + 1], Enum.Material.Grass)
	end

	-- props (40)
	Kit.PlaceAll(ctx, {
		{ Name = "FloatingIslet", Count = 5, R = 6, Tall = true, MinAbsX = 40, Build = islet },
		{ Name = "StandingStones", Count = 3, R = 7.5, Build = stoneCircle },
		{ Name = "CandyTree", Count = 4, R = 6, Tall = true, Build = function(c, m, pos)
			P.Tree(m, pos, rng:NextNumber(1, 1.2), rgb(240, 220, 250), rgb(255, 170, 220))
		end },
		{ Name = "GiantFlower", Count = 8, R = 4, Tall = true, Build = flower },
		{ Name = "CrystalCluster", Count = 10, R = 2.5, Build = crystalCluster },
		{ Name = "GlowShroom", Count = 10, R = 2, Build = glowShroom },
	})

	-- ground cover (densest, glowing clumps): glow flowers, crystal chips, lavender tufts, petals, sparkle stones
	Kit.Cover(ctx, { Count = 520, Mode = "Clumps", Clumps = 22, ClumpRadius = 9, ClumpShare = 0.7, Items = {
		Kit.Weight(Kit.Bead({ rgb(255, 120, 230), rgb(140, 220, 255), rgb(255, 230, 120) }, 0.7, 1.1, 0.3, NEON), 4),
		Kit.Weight(Kit.Spike({ rgb(255, 150, 240), rgb(150, 230, 255) }, 0.7, 1.6, NEON), 3),
		Kit.Weight(Kit.Spike({ rgb(200, 170, 250), rgb(170, 140, 230) }, 1.1, 1.5, Enum.Material.Grass), 3),
		Kit.Weight(Kit.Chip({ rgb(255, 190, 235), rgb(255, 255, 255) }, 0.9, 0.6, 0.06), 2),
		Kit.Weight(Kit.Dome({ rgb(235, 230, 255) }, 0.7, 1.2, Enum.Material.Glass), 1),
	} })

	-- sparkles drifting over the band (required)
	Kit.Particles(ctx, { Name = "Sparkles", Y0 = 1, Y1 = 40, HalfWidth = Kit.LandmarkMaxAbsX, Rate = 40,
		Lifetime = { 2, 4 }, Speed = { 0.3, 1 }, Spread = 180, LightEmission = 1, Accel = Vector3.new(0, 0.6, 0),
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(255, 150, 230)), ColorSequenceKeypoint.new(0.5, rgb(255, 230, 140)),
			ColorSequenceKeypoint.new(1, rgb(150, 220, 255)) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 0) }) })
end
