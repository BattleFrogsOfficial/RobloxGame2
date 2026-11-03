--!strict
-- Backyard (0-100): white picket fences along the lane edges, doghouses, flower beds, toys,
-- with cosy house silhouettes on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local z0, z1 = ctx.MinZ + 12, ctx.MaxZ - 4

	-- picket fence just outside each lane edge
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * (Kit.LaneHalf + 1.5)
		P.FenceLine(f, Vector3.new(x, Y, z0), Vector3.new(x, Y, z1), 10, 3, D.Fence, false)
	end

	-- doghouses
	for _, s in Kit.Band(ctx, 4, 22, 8) do
		local m = P.Model(f, "Doghouse")
		local cf = CFrame.new(s.Pos) * CFrame.Angles(0, if s.Side > 0 then math.pi / 2 else -math.pi / 2, 0)
		P.Block(m, "Body", Vector3.new(7, 5, 7), cf * CFrame.new(0, 2.5, 0), D.House)
		P.Wedge({ Parent = m, Name = "RoofA", Size = Vector3.new(8, 3, 4), CFrame = cf * CFrame.new(0, 6.5, -2), Color = D.Roof })
		P.Wedge({ Parent = m, Name = "RoofB", Size = Vector3.new(8, 3, 4),
			CFrame = cf * CFrame.new(0, 6.5, 2) * CFrame.Angles(0, math.pi, 0), Color = D.Roof })
		P.Block(m, "Door", Vector3.new(3, 3.4, 0.3), cf * CFrame.new(0, 1.7, -3.55), Color3.fromRGB(60, 40, 30))
	end

	-- round trees and flower beds
	for _, s in Kit.Band(ctx, 6, 14, 6) do
		P.Tree(f, s.Pos, ctx.Rng:NextNumber(0.9, 1.2), D.Trunk, D.Leaf)
	end
	for _, s in Kit.Band(ctx, 8, 10, 6) do -- margin 6: the 6-wide bed stays off the lane fence at 61.5
		P.Slab(f, "FlowerBed", s.Pos.X - 3, s.Pos.X + 3, s.Pos.Z - 1.5, s.Pos.Z + 1.5, Y + 0.6, 0.6,
			Color3.fromRGB(140, 95, 60), nil, false)
		P.Ellipsoid(f, "Flowers", CFrame.new(s.Pos + Vector3.new(0, 1.1, 0)), Vector3.new(5.5, 1.4, 2.4), D.Flower)
	end
	-- toy balls lying around
	for _, s in Kit.Band(ctx, 5, 8, 4) do
		P.Ball(f, "Toy", s.Pos + Vector3.new(0, 1, 0), 2, if ctx.Rng:NextNumber() < 0.5 then D.Toy else D.Flower)
	end

	-- apron houses (big friendly silhouettes)
	for _, s in Kit.Apron(ctx, 4, 40, 22) do
		local m = P.Model(f, "House")
		local cf = CFrame.new(s.Pos) * CFrame.Angles(0, if s.Side > 0 then math.pi / 2 else -math.pi / 2, 0)
		P.Block(m, "Body", Vector3.new(26, 16, 20), cf * CFrame.new(0, 8, 0), D.House)
		P.Wedge({ Parent = m, Name = "RoofA", Size = Vector3.new(28, 9, 11), CFrame = cf * CFrame.new(0, 20.5, -5.5), Color = D.Roof })
		P.Wedge({ Parent = m, Name = "RoofB", Size = Vector3.new(28, 9, 11),
			CFrame = cf * CFrame.new(0, 20.5, 5.5) * CFrame.Angles(0, math.pi, 0), Color = D.Roof })
		P.Block(m, "Window", Vector3.new(6, 5, 0.4), cf * CFrame.new(-6, 9, -10.1), Color3.fromRGB(170, 220, 255))
		P.Block(m, "Window2", Vector3.new(6, 5, 0.4), cf * CFrame.new(6, 9, -10.1), Color3.fromRGB(170, 220, 255))
	end
end
