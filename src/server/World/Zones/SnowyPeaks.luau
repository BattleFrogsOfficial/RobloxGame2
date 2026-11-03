--!strict
-- Snowy Peaks (1000-1400): snow ground with snow lumps, ice chips, frozen puddles and dark rocks over the whole
-- plot; snow-capped pines, snowmen, drifts, ice rocks, sleds, igloos and boulders; snowfall over the band.
-- Boundary: a snow bank with ice shards across the field. Landmark: a low-poly mountain peak (east).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

type Mass = { O: Vector3, W: number, D: number, H: number, Kind: string, Cap: number }

local function mountain(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.ZoneFolder, "MountainPeak")
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

local function snowman(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Ball(m, "Bottom", pos + Vector3.new(0, 2.2, 0), 4.4, D.Snowman, Enum.Material.Snow)
	P.Ball(m, "Middle", pos + Vector3.new(0, 5.4, 0), 3.2, D.Snowman, Enum.Material.Snow)
	P.Ball(m, "Head", pos + Vector3.new(0, 7.8, 0), 2.2, D.Snowman, Enum.Material.Snow)
	P.Block(m, "Nose", Vector3.new(0.4, 0.4, 1.4), CFrame.new(pos + Vector3.new(0, 7.8, -1.4)), D.Carrot)
	P.Block(m, "Scarf", Vector3.new(2.8, 0.6, 2.8), CFrame.new(pos + Vector3.new(0, 6.7, 0)), rgb(220, 60, 60))
	P.Block(m, "Hat", Vector3.new(1.6, 1.2, 1.6), CFrame.new(pos + Vector3.new(0, 9.3, 0)), rgb(40, 40, 50))
end

local function iceRock(ctx: any, m: Model, pos: Vector3)
	local P, D, rng = ctx.Props, ctx.Decor, ctx.Rng
	for _ = 1, 3 do
		local h = rng:NextNumber(3, 6)
		local o = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
		P.Block(m, "Shard", Vector3.new(1.8, h, 1.8), CFrame.new(pos + o + Vector3.new(0, h / 2, 0))
			* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(45), math.rad(rng:NextNumber(-12, 12))),
			D.Ice, Enum.Material.Ice)
	end
end

local function sled(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	for _, dx in { -1, 1 } do
		P.Block(m, "Runner", Vector3.new(0.3, 0.3, 5), CFrame.new(pos + Vector3.new(dx * 1.1, 0.15, 0)), rgb(60, 60, 70), Enum.Material.Metal)
		P.Block(m, "Tip", Vector3.new(0.3, 0.3, 1), CFrame.new(pos + Vector3.new(dx * 1.1, 0.5, -2.7)) * CFrame.Angles(math.rad(45), 0, 0),
			rgb(60, 60, 70), Enum.Material.Metal)
	end
	P.Block(m, "Seat", Vector3.new(2.8, 0.4, 4.2), CFrame.new(pos + Vector3.new(0, 0.8, 0.2)), rgb(220, 60, 50), Enum.Material.Wood)
end

local function igloo(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P = ctx.Props
	P.Ball(m, "Dome", pos, 11, rgb(240, 248, 255), Enum.Material.Ice)
	P.Block(m, "Tunnel", Vector3.new(4, 3.6, 4), CFrame.new(pos + Vector3.new(-side * 5.6, 1.8, 0)), rgb(240, 248, 255), Enum.Material.Ice)
	P.Block(m, "Door", Vector3.new(0.2, 2.6, 2.2), CFrame.new(pos + Vector3.new(-side * 7.65, 1.3, 0)), rgb(60, 80, 110))
end

local function boulder(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local yaw = ctx.Rng:NextNumber(0, 6.28)
	P.Rock(m, pos, ctx.Rng:NextNumber(1.1, 1.4), D.Mountain:Lerp(Color3.new(0, 0, 0), 0.25), yaw)
	P.Block(m, "SnowCap", Vector3.new(5, 0.8, 4), CFrame.new(pos + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, yaw, 0), D.Snow,
		Enum.Material.Snow)
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- landmark: mountain in the east band (x 76..148)
	local lz = ctx.MinZ + 236
	mountain(ctx, Vector3.new(Kit.CenterX + 112, Y, lz))

	-- pale-blue ice sheets / wind-packed snow patches (flat dressing)
	for i = 1, 6 do
		local cz = ctx.MinZ + (ctx.MaxZ - ctx.MinZ) * (i - 0.5) / 6
		local cx = Kit.CenterX + (if i % 2 == 0 then 40 else -50) + rng:NextNumber(-10, 10)
		Kit.Flat(P, g, "IceSheet", cx - 26, cx + 26, cz - 16, cz + 16, Y + 0.04, rgb(200, 228, 250), Enum.Material.Ice)
	end

	-- props (32)
	Kit.PlaceAll(ctx, {
		{ Name = "Pine", Count = 11, R = 6, Tall = true, Build = function(c, m, pos)
			P.Pine(m, pos, rng:NextNumber(1.1, 1.6), D.Pine, rgb(100, 70, 50), D.Snow)
		end },
		{ Name = "Igloo", Count = 2, R = 7, Build = igloo },
		{ Name = "SnowDrift", Count = 5, R = 5, Build = function(c, m, pos)
			P.Ellipsoid(m, "SnowDrift", CFrame.new(pos + Vector3.new(0, 0.6, 0)) * Kit.Yaw(c),
				Vector3.new(rng:NextNumber(8, 11), 3, rng:NextNumber(4, 6)), D.Snow, Enum.Material.Snow)
		end },
		{ Name = "Snowman", Count = 5, R = 2.4, Build = snowman },
		{ Name = "Boulder", Count = 2, R = 3.5, Build = boulder },
		{ Name = "IceRock", Count = 5, R = 3, Build = iceRock },
		{ Name = "Sled", Count = 2, R = 3, Build = sled },
	})

	-- ground cover: snow lumps, ice chips, frozen puddles, dark rocks
	Kit.Cover(ctx, { Count = 380, Mode = "Random", Items = {
		Kit.Weight(Kit.Dome({ rgb(255, 255, 255), rgb(240, 246, 255) }, 1.2, 2.4, Enum.Material.Snow, 0.32), 5),
		Kit.Weight(Kit.Spike({ rgb(170, 220, 255), rgb(140, 200, 245) }, 0.8, 1.2, Enum.Material.Ice), 3),
		Kit.Weight(Kit.Disc({ rgb(175, 215, 245) }, 2, 4, Enum.Material.Ice), 1.5),
		Kit.Weight(Kit.Dome({ rgb(90, 95, 110), rgb(110, 115, 130) }, 0.8, 1.3), 1.5),
	} })

	-- snowfall over the whole band and the mountain (required)
	Kit.Particles(ctx, { Name = "Snowfall", Y0 = 58, Y1 = 62, HalfWidth = Kit.LandmarkMaxAbsX, Rate = 70,
		Lifetime = { 6, 8 }, Speed = { 7, 10 }, Direction = Enum.NormalId.Bottom, Spread = 15,
		Size = NumberSequence.new(0.5, 0.35), Color = rgb(255, 255, 255), Accel = Vector3.new(1.5, 0, 0),
		RotSpeed = { -60, 60 }, Texture = Kit.Textures.Soft,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0),
			NumberSequenceKeypoint.new(0.9, 0), NumberSequenceKeypoint.new(1, 1) }) })
end
