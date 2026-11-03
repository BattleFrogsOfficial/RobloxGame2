--!strict
-- Beach (250-450): palms, striped umbrellas, beach balls, sand castles; sea on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local function palm(ctx: any, base: Vector3, scale: number)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "Palm")
	local lean = ctx.Rng:NextNumber(-0.25, 0.25)
	local top = base
	for i = 1, 3 do
		local seg = Vector3.new(lean * 2 * scale, 4 * scale, 0)
		local mid = top + seg / 2
		P.Block(m, "Trunk" .. i, Vector3.new(1.6 * scale, 4.3 * scale, 1.6 * scale),
			CFrame.lookAt(mid, mid + Vector3.new(0, 0, -1)) * CFrame.Angles(0, 0, -lean * 0.5), D.PalmTrunk)
		top += seg
	end
	for k = 0, 3 do
		local yaw = k * math.pi / 2 + 0.4
		P.Block(m, "Leaf", Vector3.new(1.4 * scale, 0.5 * scale, 8 * scale),
			CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, 0, -3.6 * scale),
			D.Palm)
	end
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	for _, s in Kit.Band(ctx, 10, 16, 12) do -- fronds reach ~12 studs from the trunk
		palm(ctx, s.Pos, ctx.Rng:NextNumber(1, 1.3))
	end
	for i, s in Kit.Band(ctx, 6, 14, 5) do
		local m = P.Model(f, "Umbrella")
		P.Cylinder(m, "Pole", s.Pos, 7, 0.4, Color3.new(1, 1, 1))
		P.Part({ Parent = m, Name = "Canopy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 9, 9),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = D.Umbrella[(i - 1) % #D.Umbrella + 1] })
		P.Slab(m, "Towel", s.Pos.X + 1, s.Pos.X + 4, s.Pos.Z - 3, s.Pos.Z + 3, Y + 0.08, 0.08,
			D.Umbrella[i % #D.Umbrella + 1], nil, false)
	end
	for _, s in Kit.Band(ctx, 6, 8, 3) do
		P.Ball(f, "BeachBall", s.Pos + Vector3.new(0, 1.3, 0), 2.6, D.Ball)
	end
	for _, s in Kit.Band(ctx, 3, 20, 6) do
		local m = P.Model(f, "SandCastle")
		local sand = ctx.Ground:Lerp(Color3.new(0, 0, 0), 0.08)
		P.Block(m, "Base", Vector3.new(6, 3, 6), CFrame.new(s.Pos + Vector3.new(0, 1.5, 0)), sand)
		P.Block(m, "Keep", Vector3.new(3, 3, 3), CFrame.new(s.Pos + Vector3.new(0, 4.5, 0)), sand)
		P.Ball(m, "Flag", s.Pos + Vector3.new(0, 6.6, 0), 1, Color3.fromRGB(255, 90, 90))
	end

	-- the sea on the apron (bright, flat) with a few rocks and white wave stripes
	for _, side in { -1, 1 } do
		local x0 = Kit.CenterX + side * (Kit.FieldHalf + 24)
		local x1 = Kit.CenterX + side * Kit.ApronHalf
		P.Slab(f, "Sea", math.min(x0, x1), math.max(x0, x1), ctx.MinZ, ctx.MaxZ, Y + 0.3, 0.3, D.Water, nil, false)
		for k = 1, 5 do
			local wx = Kit.CenterX + side * (Kit.FieldHalf + 24 + k * 14)
			P.Slab(f, "Wave", wx - 0.8, wx + 0.8, ctx.MinZ + 6, ctx.MaxZ - 6, Y + 0.36, 0.06, Color3.new(1, 1, 1), nil, false)
		end
	end
	for _, s in Kit.Apron(ctx, 6, 30, 30) do
		P.Rock(f, s.Pos, ctx.Rng:NextNumber(1.5, 2.5), D.Rock, ctx.Rng:NextNumber(0, 6.28))
	end
end
