--!strict
-- Farm (450-700): tilled ground with ploughed furrow stripes, hay tufts, clods, sprouts and stones over the
-- whole plot; a red barn, a silo, crop patches, hay bales, scarecrows, a tractor, pumpkin patches, a water
-- trough and crates. Boundary: a split-rail ranch fence across the field. Landmark: a windmill (east).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function windmill(ctx: any, base: Vector3): Model
	local P = ctx.Props
	local m = P.Model(ctx.ZoneFolder, "Windmill")
	local wall, trim, roof, sail = rgb(245, 238, 220), rgb(170, 120, 70), rgb(200, 60, 50), rgb(255, 250, 240)
	local y = 0
	for i, t in { { 18, 22 }, { 16, 22 }, { 14, 22 }, { 12, 18 } } do
		local w, h = t[1], t[2]
		P.Block(m, "Tier" .. i, Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, y + h / 2, 0)), wall)
		P.Block(m, "Band" .. i, Vector3.new(w + 0.6, 1.2, w + 0.6), CFrame.new(base + Vector3.new(0, y + h, 0)), trim)
		y += h
	end
	P.Block(m, "Door", Vector3.new(0.4, 8, 5), CFrame.new(base + Vector3.new(-9.2, 4, 0)), trim)
	Kit.Gable(P, m, "Cap", CFrame.new(base + Vector3.new(0, y + 0.6, 0)), 14, 14, 7, roof)
	-- sails: an X of four blades on the platform-facing (-Z) side
	local hub = base + Vector3.new(0, y - 2, -7.5)
	P.Part({ Parent = m, Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3.4, 3.4),
		CFrame = CFrame.new(hub) * CFrame.Angles(0, math.pi / 2, 0), Color = trim })
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local rot = CFrame.Angles(0, 0, a)
		P.Block(m, "Spar", Vector3.new(16, 0.8, 0.6), CFrame.new(hub + dir * 8 + Vector3.new(0, 0, -1.6)) * rot, trim)
		P.Block(m, "Sail", Vector3.new(11, 3.4, 0.2), CFrame.new(hub + dir * 9.5 + Vector3.new(0, 0, -1.2)) * rot
			* CFrame.new(0, 1.9, 0), sail)
	end
	Kit.Landmark(ctx, m, y + 7.6, "Windmill")
	return m
end

local function barn(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P, D = ctx.Props, ctx.Decor
	-- long axis along Z, doors facing the field centre
	local f = -side
	P.Block(m, "Body", Vector3.new(18, 13, 24), CFrame.new(pos + Vector3.new(0, 6.5, 0)), D.Barn)
	Kit.GableZ(P, m, "Roof", pos + Vector3.new(0, 13, 0), 20, 25, 7, D.Barn:Lerp(Color3.new(0, 0, 0), 0.3))
	P.Block(m, "Door", Vector3.new(0.4, 9, 8), CFrame.new(pos + Vector3.new(f * 9.1, 4.5, 0)), D.BarnTrim)
	P.Block(m, "DoorX", Vector3.new(0.5, 11.5, 1), CFrame.new(pos + Vector3.new(f * 9.4, 4.5, 0)) * CFrame.Angles(math.rad(40), 0, 0), D.Barn)
	P.Block(m, "DoorX2", Vector3.new(0.5, 11.5, 1), CFrame.new(pos + Vector3.new(f * 9.4, 4.5, 0)) * CFrame.Angles(math.rad(-40), 0, 0), D.Barn)
	P.Block(m, "Loft", Vector3.new(0.4, 3.4, 4), CFrame.new(pos + Vector3.new(f * 9.1, 10.6, 0)), D.BarnTrim)
end

local function silo(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Tower", pos, 26, 10, D.Silo, Enum.Material.Metal)
	P.Ball(m, "Dome", pos + Vector3.new(0, 26, 0), 10, D.Barn)
	for _, y in { 7, 14, 21 } do
		P.Cylinder(m, "Hoop", pos + Vector3.new(0, y, 0), 0.6, 10.4, rgb(150, 150, 160))
	end
end

local function tractor(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local body, dark = rgb(60, 160, 70), rgb(40, 40, 45)
	P.Block(m, "Body", Vector3.new(4, 3, 7), CFrame.new(pos + Vector3.new(0, 2.6, 0)), body)
	P.Block(m, "Cab", Vector3.new(4, 3.4, 3.4), CFrame.new(pos + Vector3.new(0, 5.8, 1.6)), body)
	P.Block(m, "Roof", Vector3.new(4.6, 0.4, 4), CFrame.new(pos + Vector3.new(0, 7.7, 1.6)), rgb(250, 250, 250))
	P.Cylinder(m, "Exhaust", pos + Vector3.new(1.2, 4, -2.4), 3, 0.5, dark)
	for _, w in { { 2.4, 2.2, 5 }, { -2.4, 2.2, 5 }, { 2.3, -2.4, 2.8 }, { -2.3, -2.4, 2.8 } } do
		local d = w[3]
		P.Part({ Parent = m, Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, d, d),
			CFrame = CFrame.new(pos + Vector3.new(w[1], d / 2, w[2])), Color = dark })
	end
end

local function cropPatch(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Block(m, "Soil", Vector3.new(14, 0.3, 18), CFrame.new(pos + Vector3.new(0, 0.15, 0)), D.Soil, Enum.Material.Ground)
	for r = -1.5, 1.5 do
		P.Block(m, "Crop", Vector3.new(2, 1.8, 16), CFrame.new(pos + Vector3.new(r * 3.4, 1, 0)), D.Crop, Enum.Material.Grass)
	end
end

local function scarecrow(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Pole", pos, 7, 0.6, D.Fence)
	P.Block(m, "Arms", Vector3.new(6, 0.6, 0.6), CFrame.new(pos + Vector3.new(0, 5.2, 0)), D.Fence)
	P.Block(m, "Shirt", Vector3.new(2.4, 2.6, 1.2), CFrame.new(pos + Vector3.new(0, 4.6, 0)), rgb(80, 130, 220))
	P.Ball(m, "Head", pos + Vector3.new(0, 7, 0), 1.8, D.Hay)
	P.Block(m, "Hat", Vector3.new(2.6, 0.4, 2.6), CFrame.new(pos + Vector3.new(0, 7.9, 0)), rgb(140, 95, 60))
end

local function pumpkins(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	for k = 1, 3 do
		local o = Vector3.new(ctx.Rng:NextNumber(-1.6, 1.6), 0, ctx.Rng:NextNumber(-1.6, 1.6))
		local s = ctx.Rng:NextNumber(0.8, 1.2)
		P.Ellipsoid(m, "Pumpkin", CFrame.new(pos + o + Vector3.new(0, 0.9 * s, 0)), Vector3.new(2.6, 1.8, 2.6) * s, rgb(255, 140, 30))
	end
end

local function trough(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Block(m, "Tub", Vector3.new(2.4, 1.4, 5), CFrame.new(pos + Vector3.new(0, 0.7, 0)), rgb(150, 150, 160), Enum.Material.Metal)
	P.Block(m, "Water", Vector3.new(2, 0.1, 4.6), CFrame.new(pos + Vector3.new(0, 1.35, 0)), rgb(90, 180, 240))
end

local function crate(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local cf = CFrame.new(pos) * Kit.Yaw(ctx)
	P.Block(m, "Crate", Vector3.new(3, 3, 3), cf * CFrame.new(0, 1.5, 0), rgb(190, 140, 80), Enum.Material.Wood)
	P.Block(m, "Apples", Vector3.new(2.6, 0.5, 2.6), cf * CFrame.new(0, 3.1, 0), rgb(220, 50, 40))
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- landmark (east edge)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 6
	windmill(ctx, Vector3.new(Kit.CenterX + 136, Y, lz))

	-- ploughed furrows across the whole plot (flat dressing, every 12 studs)
	local z = ctx.MinZ + 14
	while z < ctx.MaxZ - 4 do
		Kit.Flat(P, g, "Furrow", Kit.CenterX - Kit.FieldHalf, Kit.CenterX + Kit.FieldHalf, z - 1.2, z + 1.2, Y + 0.04,
			ctx.Ground:Lerp(Color3.new(0, 0, 0), 0.18), Enum.Material.Ground)
		z += 12
	end

	-- props (26)
	Kit.PlaceAll(ctx, {
		{ Name = "Barn", Count = 1, R = 13, Tall = true, MinAbsX = 60, Build = barn },
		{ Name = "Silo", Count = 1, R = 5.5, Tall = true, MinAbsX = 60, Build = silo },
		{ Name = "CropPatch", Count = 4, R = 9, Build = cropPatch },
		{ Name = "Tractor", Count = 1, R = 4, Build = tractor },
		{ Name = "Scarecrow", Count = 3, R = 3, Build = scarecrow },
		{ Name = "HayBale", Count = 8, R = 2, Build = function(c, m, pos)
			P.Part({ Parent = m, Name = "HayBale", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 3.6, 3.6),
				CFrame = CFrame.new(pos + Vector3.new(0, 1.8, 0)) * Kit.Yaw(c), Color = D.Hay, Material = Enum.Material.Fabric })
		end },
		{ Name = "PumpkinPatch", Count = 4, R = 3, Build = pumpkins },
		{ Name = "Crate", Count = 3, R = 2.2, Build = crate },
		{ Name = "Trough", Count = 1, R = 2.6, Build = trough },
	})

	-- ground cover: hay tufts, soil clods, green sprouts, stones, straw
	Kit.Cover(ctx, { Count = 300, Mode = "Random", Items = {
		Kit.Weight(Kit.Spike({ rgb(240, 205, 100), rgb(220, 180, 80) }, 1.1, 1.3, Enum.Material.Grass), 4),
		Kit.Weight(Kit.Nugget({ rgb(120, 85, 55), rgb(100, 70, 45) }, 1.1, Enum.Material.Ground), 3),
		Kit.Weight(Kit.Spike({ rgb(110, 190, 60), rgb(140, 210, 70) }, 0.7, 1.1, Enum.Material.Grass), 3),
		Kit.Weight(Kit.Dome({ rgb(160, 155, 150) }, 0.7, 1.1), 1),
		Kit.Weight(Kit.Chip({ rgb(245, 215, 120) }, 1.8, 0.25, 0.15), 2),
	} })

	-- drifting chaff (light, cheap)
	Kit.Particles(ctx, { Name = "Chaff", Y0 = 1, Y1 = 10, Rate = 5, Lifetime = { 5, 8 }, Speed = { 0.5, 1.5 },
		Size = 0.35, Color = rgb(250, 225, 140), Spread = 180, Accel = Vector3.new(0.8, 0, 0.3), Texture = Kit.Textures.Soft })
end
