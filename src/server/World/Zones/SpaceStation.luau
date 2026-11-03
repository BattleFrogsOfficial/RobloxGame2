--!strict
-- Space Station (1900-2500): glowing floor strips, domes, antennas, cargo crates and dishes in the
-- bands; huge floating planets over the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	-- glowing cross stripes across the outer bands every 60 studs (decal-thin)
	local z = ctx.MinZ + 30
	while z < ctx.MaxZ - 10 do
		for _, side in { -1, 1 } do
			local a = Kit.CenterX + side * (Kit.LaneHalf + 2)
			local b = Kit.CenterX + side * (Kit.FieldHalf - 2)
			P.Slab(f, "Glow", math.min(a, b), math.max(a, b), z - 0.8, z + 0.8, Y + 0.06, 0.06, D.Glow, Enum.Material.Neon, false)
		end
		z += 60
	end
	for _, s in Kit.Band(ctx, 6, 26, 12) do
		P.Ellipsoid(f, "Dome", CFrame.new(s.Pos), Vector3.new(16, 12, 16), D.Hull, Enum.Material.Glass)
		P.Slab(f, "DomeRing", s.Pos.X - 9, s.Pos.X + 9, s.Pos.Z - 9, s.Pos.Z + 9, Y + 0.5, 0.5, D.Panel, nil, false)
	end
	for _, s in Kit.Band(ctx, 6, 20, 3) do
		local m = P.Model(f, "Antenna")
		P.Cylinder(m, "Mast", s.Pos, 14, 0.6, D.Antenna)
		P.Ball(m, "Beacon", s.Pos + Vector3.new(0, 14.6, 0), 1.6, D.Glow, Enum.Material.Neon)
	end
	for _, s in Kit.Band(ctx, 10, 8, 4) do
		P.Block(f, "Crate", Vector3.new(4, 4, 4), CFrame.new(s.Pos + Vector3.new(0, 2, 0)) * Kit.Yaw(ctx), D.Panel)
	end
	for _, s in Kit.Band(ctx, 3, 40, 8) do
		local m = P.Model(f, "Dish")
		P.Cylinder(m, "Stand", s.Pos, 6, 1.2, D.Antenna)
		P.Part({ Parent = m, Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 10, 10),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(55)), Color = D.Hull })
	end
	-- planets
	for i, s in Kit.Apron(ctx, 5, 70, 30) do
		local d = ctx.Rng:NextNumber(30, 55)
		local center = s.Pos + Vector3.new(0, 60 + ctx.Rng:NextNumber(0, 50), 0)
		P.Ball(f, "Planet", center, d, D.Planet[(i - 1) % #D.Planet + 1])
		if i % 2 == 1 then
			P.Part({ Parent = f, Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, d * 1.7, d * 1.7),
				CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(70)), Color = D.Glow, Transparency = 0.3 })
		end
	end
end
