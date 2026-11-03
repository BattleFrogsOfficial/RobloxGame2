--!strict
-- Farm (450-700): wooden fences on the lane edges, crop rows and hay bales in the bands,
-- red barns and silos on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * (Kit.LaneHalf + 1.5)
		P.FenceLine(f, Vector3.new(x, Y, ctx.MinZ + 14), Vector3.new(x, Y, ctx.MaxZ - 6), 20, 3.4, D.Fence, false)
	end

	-- crop field patches (soil slab + row strips) in the outer band
	for _, s in Kit.Band(ctx, 4, 50, 18) do
		local cx, cz = s.Pos.X, s.Pos.Z
		P.Slab(f, "Soil", cx - 14, cx + 14, cz - 18, cz + 18, Y + 0.2, 0.2, D.Soil, nil, false)
		for r = -2, 2 do
			P.Block(f, "Crop", Vector3.new(2, 1.6, 32), CFrame.new(cx + r * 5.5, Y + 1, cz), D.Crop)
		end
	end
	for _, s in Kit.Band(ctx, 12, 9, 5) do
		P.Part({ Parent = f, Name = "HayBale", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 3.6, 3.6),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 1.8, 0)) * Kit.Yaw(ctx), Color = D.Hay })
	end
	for _, s in Kit.Band(ctx, 2, 40, 6) do
		local m = P.Model(f, "Scarecrow")
		P.Cylinder(m, "Pole", s.Pos, 7, 0.6, D.Fence)
		P.Block(m, "Arms", Vector3.new(6, 0.6, 0.6), CFrame.new(s.Pos + Vector3.new(0, 5.2, 0)), D.Fence)
		P.Block(m, "Shirt", Vector3.new(2.4, 2.6, 1.2), CFrame.new(s.Pos + Vector3.new(0, 4.6, 0)), Color3.fromRGB(80, 130, 220))
		P.Ball(m, "Head", s.Pos + Vector3.new(0, 7, 0), 1.8, D.Hay)
	end

	-- barns + silos on the apron
	for _, s in Kit.Apron(ctx, 4, 60, 28) do -- silo reaches 27 studs from the barn centre
		local m = P.Model(f, "Barn")
		local cf = CFrame.new(s.Pos) * CFrame.Angles(0, if s.Side > 0 then math.pi / 2 else -math.pi / 2, 0)
		P.Block(m, "Body", Vector3.new(30, 18, 24), cf * CFrame.new(0, 9, 0), D.Barn)
		P.Wedge({ Parent = m, Name = "RoofA", Size = Vector3.new(31, 10, 12.5), CFrame = cf * CFrame.new(0, 23, -6.25), Color = D.Barn:Lerp(Color3.new(0, 0, 0), 0.25) })
		P.Wedge({ Parent = m, Name = "RoofB", Size = Vector3.new(31, 10, 12.5),
			CFrame = cf * CFrame.new(0, 23, 6.25) * CFrame.Angles(0, math.pi, 0), Color = D.Barn:Lerp(Color3.new(0, 0, 0), 0.25) })
		P.Block(m, "Door", Vector3.new(10, 12, 0.4), cf * CFrame.new(0, 6, -12.1), D.BarnTrim)
		P.Block(m, "DoorX", Vector3.new(14.5, 1, 0.5), cf * CFrame.new(0, 6, -12.4) * CFrame.Angles(0, 0, math.rad(50)), D.Barn)
		local siloBase = (cf * CFrame.new(22, 0, 0)).Position
		P.Cylinder(m, "Silo", siloBase, 28, 10, D.Silo)
		P.Ball(m, "SiloTop", siloBase + Vector3.new(0, 28, 0), 10, D.Barn)
	end
end
