--!strict
-- Park (100-250): leafy trees, bushes, benches and lamps in the side bands; ponds on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	for _, s in Kit.Band(ctx, 12, 14, 8) do -- canopy up to 7 wide at scale 1.4
		P.Tree(f, s.Pos, ctx.Rng:NextNumber(1, 1.4), D.Trunk, D.Leaf)
	end
	for _, s in Kit.Band(ctx, 10, 9, 4) do
		P.Bush(f, s.Pos, ctx.Rng:NextNumber(0.8, 1.2), D.Bush)
	end
	for _, s in Kit.Band(ctx, 4, 20, 4) do
		P.Bench(f, s.Pos, if s.Side > 0 then math.pi / 2 else -math.pi / 2, D.Bench, D.Lamp)
	end
	for _, s in Kit.Band(ctx, 4, 24, 2) do
		P.Lamp(f, s.Pos, 12, D.Lamp, Color3.fromRGB(255, 236, 170), false)
	end

	-- ponds + big trees on the apron
	for _, s in Kit.Apron(ctx, 2, 60, 32) do -- rim is 64 long: 32 keeps it inside this zone's apron
		P.Ellipsoid(f, "Pond", CFrame.new(s.Pos + Vector3.new(0, 0.1, 0)), Vector3.new(44, 0.6, 60), D.Pond)
		P.Ellipsoid(f, "PondRim", CFrame.new(s.Pos), Vector3.new(48, 0.4, 64), Color3.fromRGB(200, 190, 160))
	end
	for _, s in Kit.Apron(ctx, 10, 18, 12) do -- canopy reach ~11 at scale 2.2
		P.Tree(f, s.Pos, ctx.Rng:NextNumber(1.6, 2.2), D.Trunk, D.Leaf)
	end
end
