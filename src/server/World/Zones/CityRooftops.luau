--!strict
-- City Rooftops (1400-1900): AC vents, water tanks, antennas and neon signs on the rooftop bands;
-- a skyline of tall buildings with glowing window strips on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	-- low parapet along both field edges (non-colliding decor)
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * (Kit.FieldHalf - 1.5)
		P.Block(f, "Parapet", Vector3.new(3, 2.5, ctx.MaxZ - ctx.MinZ - 12), CFrame.new(x, Y + 1.25, (ctx.MinZ + ctx.MaxZ) / 2 + 4),
			ctx.Ground:Lerp(Color3.new(1, 1, 1), 0.2))
	end
	for _, s in Kit.Band(ctx, 10, 14, 6) do
		local m = P.Model(f, "Vent")
		P.Block(m, "Box", Vector3.new(6, 4, 6), CFrame.new(s.Pos + Vector3.new(0, 2, 0)), D.Vent)
		P.Part({ Parent = m, Name = "Fan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 4.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(90, 95, 110) })
	end
	for _, s in Kit.Band(ctx, 4, 30, 8) do
		local m = P.Model(f, "WaterTank")
		for _, o in { Vector3.new(-2.5, 0, -2.5), Vector3.new(2.5, 0, -2.5), Vector3.new(-2.5, 0, 2.5), Vector3.new(2.5, 0, 2.5) } do
			P.Cylinder(m, "Leg", s.Pos + o, 6, 0.6, Color3.fromRGB(60, 60, 70))
		end
		P.Cylinder(m, "Tank", s.Pos + Vector3.new(0, 6, 0), 8, 8, D.Tank)
		P.Block(m, "Lid", Vector3.new(6, 2, 6), CFrame.new(s.Pos + Vector3.new(0, 15, 0)) * CFrame.Angles(0, math.rad(45), 0), D.Tank:Lerp(Color3.new(0, 0, 0), 0.2))
	end
	for i, s in Kit.Band(ctx, 4, 30, 4) do
		local c = D.Neon[(i - 1) % #D.Neon + 1]
		local m = P.Model(f, "NeonSign")
		P.Cylinder(m, "Post", s.Pos, 6, 0.6, Color3.fromRGB(60, 60, 70))
		P.Block(m, "Glow", Vector3.new(0.6, 3, 8), CFrame.new(s.Pos + Vector3.new(0, 7.5, 0)), c, Enum.Material.Neon)
	end

	-- skyline
	for i, s in Kit.Apron(ctx, 14, 37, 14) do -- <= 26-wide towers: 37 = 26 * sqrt 2, margin covers window strips
		local m = P.Model(f, "Building")
		local w = ctx.Rng:NextNumber(18, 26)
		local h = ctx.Rng:NextNumber(40, 110)
		local body = D.Building[(i - 1) % #D.Building + 1]
		P.Block(m, "Body", Vector3.new(w, h, w), CFrame.new(s.Pos + Vector3.new(0, h / 2, 0)), body)
		local face = -s.Side -- windows face the field
		for k = 1, 2 do
			P.Block(m, "Windows", Vector3.new(0.4, h * 0.8, w * 0.22),
				CFrame.new(s.Pos + Vector3.new(face * (w / 2 + 0.2), h * 0.5, (k - 1.5) * w * 0.45)), D.Window, Enum.Material.Neon)
		end
		P.Block(m, "Roof", Vector3.new(w + 1, 1.2, w + 1), CFrame.new(s.Pos + Vector3.new(0, h + 0.6, 0)), body:Lerp(Color3.new(0, 0, 0), 0.3))
	end
end
