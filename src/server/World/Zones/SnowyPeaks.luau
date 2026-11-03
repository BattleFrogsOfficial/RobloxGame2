--!strict
-- Snowy Peaks (1000-1400): snow ground, snow-capped pines, snow drifts, ice rocks, a sled and snowmen;
-- snowfall over the whole band. Landmark: a low-poly mountain peak (~170 studs) rising from the east band.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

type Mass = { O: Vector3, W: number, D: number, H: number, Kind: string, Cap: number }

local function mountain(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder.Parent, "MountainPeak")
	local rockA, rockB, snow = D.Mountain, D.Mountain:Lerp(Color3.new(0, 0, 0), 0.15), D.Snow
	-- O offset, W width (x), D depth (z), H height, Kind, Cap = snow cap height
	local masses: { Mass } = {
		{ O = Vector3.new(0, 0, 0), W = 72, D = 120, H = 70, Kind = "Z", Cap = 18 },
		{ O = Vector3.new(-2, 0, -8), W = 64, D = 70, H = 115, Kind = "X", Cap = 30 },
		{ O = Vector3.new(2, 0, 6), W = 46, D = 50, H = 150, Kind = "Peak", Cap = 40 },
		{ O = Vector3.new(2, 0, 0), W = 30, D = 30, H = 170, Kind = "Peak", Cap = 52 },
	}
	for i, ms in masses do
		local w, d, h, kind, cap = ms.W, ms.D, ms.H, ms.Kind, ms.Cap
		local b = base + ms.O
		local col = if i % 2 == 0 then rockB else rockA
		local k = cap / h
		local capBase = b + Vector3.new(0, h - cap + 0.6, 0)
		if kind == "Z" then
			Kit.GableZ(P, m, "Ridge", b, w, d, h, col, Enum.Material.Slate)
			Kit.GableZ(P, m, "Snow", capBase, w * k * 1.06, d * 0.98, cap, snow, Enum.Material.Snow)
		elseif kind == "X" then
			Kit.Gable(P, m, "Ridge", CFrame.new(b), w, d, h, col, Enum.Material.Slate)
			Kit.Gable(P, m, "Snow", CFrame.new(capBase), w * 0.98, d * k * 1.06, cap, snow, Enum.Material.Snow)
		else
			Kit.Peak(P, m, "Peak", b, w, d, h, col, Enum.Material.Slate)
			Kit.Peak(P, m, "Snow", capBase, w * k * 1.06, d * k * 1.06, cap, snow, Enum.Material.Snow)
		end
	end
	Kit.Landmark(ctx, m, 170.6, "MountainPeak")
	return m
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark: mountain in the east band (x 76..148)
	local lz = ctx.MinZ + 236
	mountain(ctx, Vector3.new(Kit.CenterX + 112, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX + 112, lz - 30, 42)
	Kit.Reserve(ctx, Kit.CenterX + 112, lz + 30, 42)

	-- snow-capped pines (12)
	for _, s in Kit.Band(ctx, 12, 12, 8) do
		Kit.Decor(ctx, P.Pine(f, s.Pos, rng:NextNumber(1.1, 1.6), D.Pine, rgb(100, 70, 50), D.Snow))
	end
	-- snow drifts (5)
	for _, s in Kit.Band(ctx, 5, 16, 7) do
		Kit.Decor(ctx, P.Ellipsoid(f, "SnowDrift", CFrame.new(s.Pos + Vector3.new(0, 0.6, 0)) * Kit.Yaw(ctx),
			Vector3.new(rng:NextNumber(8, 11), 3, rng:NextNumber(4, 6)), D.Snow, Enum.Material.Snow), true)
	end
	-- ice rocks (4): clusters of glassy shards
	for _, s in Kit.Band(ctx, 4, 12, 4) do
		local m = P.Model(f, "IceRock")
		for k = 1, 3 do
			local h = rng:NextNumber(3, 6)
			local o = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
			P.Block(m, "Shard", Vector3.new(1.8, h, 1.8), CFrame.new(s.Pos + o + Vector3.new(0, h / 2, 0))
				* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(45), math.rad(rng:NextNumber(-12, 12))),
				D.Ice, Enum.Material.Ice)
		end
		Kit.Decor(ctx, m, true)
	end
	-- sled (1)
	for _, s in Kit.Band(ctx, 1, 10, 4) do
		local m = P.Model(f, "Sled")
		for _, dx in { -1, 1 } do
			P.Block(m, "Runner", Vector3.new(0.3, 0.3, 5), CFrame.new(s.Pos + Vector3.new(dx * 1.1, 0.15, 0)), rgb(60, 60, 70), Enum.Material.Metal)
			P.Block(m, "Tip", Vector3.new(0.3, 0.3, 1), CFrame.new(s.Pos + Vector3.new(dx * 1.1, 0.5, -2.7)) * CFrame.Angles(math.rad(45), 0, 0),
				rgb(60, 60, 70), Enum.Material.Metal)
		end
		P.Block(m, "Seat", Vector3.new(2.8, 0.4, 4.2), CFrame.new(s.Pos + Vector3.new(0, 0.8, 0.2)), rgb(220, 60, 50), Enum.Material.Wood)
		Kit.Decor(ctx, m, true)
	end
	-- snowmen (2)
	for _, s in Kit.Band(ctx, 2, 30, 4) do
		local m = P.Model(f, "Snowman")
		P.Ball(m, "Bottom", s.Pos + Vector3.new(0, 2.2, 0), 4.4, D.Snowman, Enum.Material.Snow)
		P.Ball(m, "Middle", s.Pos + Vector3.new(0, 5.4, 0), 3.2, D.Snowman, Enum.Material.Snow)
		P.Ball(m, "Head", s.Pos + Vector3.new(0, 7.8, 0), 2.2, D.Snowman, Enum.Material.Snow)
		P.Block(m, "Nose", Vector3.new(0.4, 0.4, 1.4), CFrame.new(s.Pos + Vector3.new(0, 7.8, -1.4)), D.Carrot)
		P.Block(m, "Scarf", Vector3.new(2.8, 0.6, 2.8), CFrame.new(s.Pos + Vector3.new(0, 6.7, 0)), rgb(220, 60, 60))
		Kit.Decor(ctx, m, true)
	end

	-- snowfall over the whole band and the mountain (required)
	Kit.Particles(ctx, { Name = "Snowfall", Y0 = 58, Y1 = 62, HalfWidth = Kit.LandmarkMaxAbsX, Rate = 70,
		Lifetime = { 6, 8 }, Speed = { 7, 10 }, Direction = Enum.NormalId.Bottom, Spread = 15,
		Size = NumberSequence.new(0.5, 0.35), Color = rgb(255, 255, 255), Accel = Vector3.new(1.5, 0, 0),
		RotSpeed = { -60, 60 }, Texture = Kit.Textures.Soft,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0),
			NumberSequenceKeypoint.new(0.9, 0), NumberSequenceKeypoint.new(1, 1) }) })
end
