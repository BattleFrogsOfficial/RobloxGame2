--!strict
-- Mythic Meadow (2500-3200): glowing crystals, giant flowers, golden pillars with sparkles;
-- floating islands drifting over the apron. The rarest, flashiest zone.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local function sparkle(part: BasePart, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkle"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = 4
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(1, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.8, 0)
	e.Parent = part
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	for i, s in Kit.Band(ctx, 18, 12, 5) do
		local c = D.Crystal[(i - 1) % #D.Crystal + 1]
		local h = ctx.Rng:NextNumber(6, 12)
		local cr = P.Block(f, "Crystal", Vector3.new(2.6, h, 2.6),
			CFrame.new(s.Pos + Vector3.new(0, h / 2 - 0.5, 0)) * Kit.Yaw(ctx) * CFrame.Angles(math.rad(10), 0, math.rad(6)),
			c, Enum.Material.Neon)
		if i % 6 == 0 then
			sparkle(cr, c)
		end
		P.Block(f, "CrystalSmall", Vector3.new(1.6, h * 0.5, 1.6),
			CFrame.new(s.Pos + Vector3.new(1.8, h * 0.25 - 0.5, 0.8)) * CFrame.Angles(0, 0.6, math.rad(-20)), c, Enum.Material.Neon)
	end
	for _, s in Kit.Band(ctx, 12, 14, 6) do
		local m = P.Model(f, "GiantFlower")
		local h = ctx.Rng:NextNumber(6, 10)
		P.Cylinder(m, "Stem", s.Pos, h, 0.8, Color3.fromRGB(110, 200, 120))
		P.Ellipsoid(m, "Petals", CFrame.new(s.Pos + Vector3.new(0, h, 0)), Vector3.new(7, 1.6, 7), D.Flower)
		P.Ball(m, "Center", s.Pos + Vector3.new(0, h + 0.6, 0), 2.4, D.FlowerCenter, Enum.Material.Neon)
	end
	for i, s in Kit.Band(ctx, 6, 40, 8) do
		local m = P.Model(f, "GoldenPillar")
		P.Block(m, "Pillar", Vector3.new(4, 18, 4), CFrame.new(s.Pos + Vector3.new(0, 9, 0)), D.Pillar)
		local orb = P.Ball(m, "Orb", s.Pos + Vector3.new(0, 20.5, 0), 4, D.FlowerCenter, Enum.Material.Neon)
		if i % 2 == 0 then
			sparkle(orb, D.FlowerCenter)
		end
	end
	-- floating islands
	for _, s in Kit.Apron(ctx, 6, 60, 30) do
		local center = s.Pos + Vector3.new(0, 40 + ctx.Rng:NextNumber(0, 40), 0)
		local w = ctx.Rng:NextNumber(26, 40)
		P.Ellipsoid(f, "Island", CFrame.new(center), Vector3.new(w, w * 0.7, w), D.Island)
		P.Slab(f, "IslandTop", center.X - w * 0.38, center.X + w * 0.38, center.Z - w * 0.38, center.Z + w * 0.38,
			center.Y + w * 0.28, 1.2, D.IslandGrass, nil, false)
		P.Tree(f, Vector3.new(center.X, center.Y + w * 0.28, center.Z), 1.4, Color3.fromRGB(150, 110, 90), D.Flower)
	end
end
