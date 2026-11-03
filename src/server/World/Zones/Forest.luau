--!strict
-- Forest (700-1000): dense pines, fallen logs and red mushrooms; a tall treeline on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	for i, s in Kit.Band(ctx, 24, 10, 8) do -- twisted bottom tier half-diagonal up to ~7.7
		P.Pine(f, s.Pos, ctx.Rng:NextNumber(1.1, 1.6), if i % 3 == 0 then D.PineDark else D.Pine, D.Trunk)
	end
	for _, s in Kit.Band(ctx, 6, 16, 5) do
		P.Part({ Parent = f, Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 2.4, 2.4),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 1.2, 0)) * Kit.Yaw(ctx), Color = D.Log })
	end
	for _, s in Kit.Band(ctx, 8, 8, 3) do
		local m = P.Model(f, "Mushroom")
		P.Cylinder(m, "Stem", s.Pos, 2, 1, D.MushroomStem)
		P.Ellipsoid(m, "Cap", CFrame.new(s.Pos + Vector3.new(0, 2.2, 0)), Vector3.new(3.4, 1.8, 3.4), D.Mushroom)
	end
	for i, s in Kit.Apron(ctx, 18, 30, 15) do -- scale-3 pine tier half-diagonal ~14.4
		P.Pine(f, s.Pos, ctx.Rng:NextNumber(2, 3), if i % 2 == 0 then D.PineDark else D.Pine, D.Trunk)
	end
end
