--!strict
-- Snowy Peaks (1000-1400): snow pines, snowmen and ice crystals in the bands; stepped low-poly
-- mountains with snow caps on the apron.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y

	for _, s in Kit.Band(ctx, 16, 12, 8) do
		P.Pine(f, s.Pos, ctx.Rng:NextNumber(1, 1.5), D.Pine, Color3.fromRGB(100, 70, 50), D.Snow)
	end
	for _, s in Kit.Band(ctx, 4, 30, 4) do
		local m = P.Model(f, "Snowman")
		P.Ball(m, "Bottom", s.Pos + Vector3.new(0, 2.2, 0), 4.4, D.Snowman)
		P.Ball(m, "Middle", s.Pos + Vector3.new(0, 5.4, 0), 3.2, D.Snowman)
		P.Ball(m, "Head", s.Pos + Vector3.new(0, 7.8, 0), 2.2, D.Snowman)
		P.Block(m, "Nose", Vector3.new(0.4, 0.4, 1.4), CFrame.new(s.Pos + Vector3.new(0, 7.8, -1.4)), D.Carrot)
	end
	for _, s in Kit.Band(ctx, 8, 10, 3) do
		P.Block(f, "Ice", Vector3.new(2, ctx.Rng:NextNumber(4, 7), 2),
			CFrame.new(s.Pos + Vector3.new(0, 2.5, 0)) * Kit.Yaw(ctx) * CFrame.Angles(math.rad(12), 0, math.rad(8)),
			D.Ice, Enum.Material.Ice)
	end

	-- mountains: three stacked, twisted blocks + snow cap
	for _, s in Kit.Apron(ctx, 7, 74, 38) do -- bottom tier half-diagonal <= 36.2 at scale 1.3
		local m = P.Model(f, "Mountain")
		local scale = ctx.Rng:NextNumber(1, 1.3)
		local yv = 0
		for k = 1, 3 do
			local w = (52 - k * 12) * scale
			local h = 18 * scale
			P.Block(m, "Tier" .. k, Vector3.new(w, h, w),
				CFrame.new(s.Pos + Vector3.new(0, yv + h / 2, 0)) * CFrame.Angles(0, math.rad(45 * k + 10), 0),
				D.Mountain:Lerp(Color3.new(1, 1, 1), k * 0.08))
			yv += h * 0.85
		end
		P.Block(m, "Cap", Vector3.new(14, 8, 14) * scale,
			CFrame.new(s.Pos + Vector3.new(0, yv + 2 * scale, 0)) * CFrame.Angles(0, math.rad(30), 0), D.Snow)
	end
end
