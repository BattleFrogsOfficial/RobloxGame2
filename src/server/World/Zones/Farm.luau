--!strict
-- Farm (450-700): tilled ground, split-rail fences on the lane edges, a red barn and silo, crop rows, hay bales,
-- scarecrows, a tractor, pumpkins and a water trough. Landmark: a windmill at the east edge, sails facing
-- the throwing platform.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function windmill(ctx: any, base: Vector3): Model
	local P = ctx.Props
	local m = P.Model(ctx.Folder.Parent, "Windmill")
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

local function barn(ctx: any, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "Barn")
	-- long axis along Z, doors facing the lane (+X for a west-side barn)
	P.Block(m, "Body", Vector3.new(22, 16, 30), CFrame.new(pos + Vector3.new(0, 8, 0)), D.Barn)
	Kit.GableZ(P, m, "Roof", pos + Vector3.new(0, 16, 0), 24, 31, 9, D.Barn:Lerp(Color3.new(0, 0, 0), 0.3))
	P.Block(m, "Door", Vector3.new(0.4, 11, 10), CFrame.new(pos + Vector3.new(11.1, 5.5, 0)), D.BarnTrim)
	P.Block(m, "DoorX", Vector3.new(0.5, 14.5, 1), CFrame.new(pos + Vector3.new(11.4, 5.5, 0)) * CFrame.Angles(math.rad(40), 0, 0), D.Barn)
	P.Block(m, "DoorX2", Vector3.new(0.5, 14.5, 1), CFrame.new(pos + Vector3.new(11.4, 5.5, 0)) * CFrame.Angles(math.rad(-40), 0, 0), D.Barn)
	P.Block(m, "Loft", Vector3.new(0.4, 4, 5), CFrame.new(pos + Vector3.new(11.1, 13, 0)), D.BarnTrim)
	Kit.Decor(ctx, m)
end

local function tractor(ctx: any, pos: Vector3)
	local P = ctx.Props
	local m = P.Model(ctx.Folder, "Tractor")
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
	Kit.Decor(ctx, m)
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark (east edge)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 6
	windmill(ctx, Vector3.new(Kit.CenterX + 136, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX + 128, lz, 14)

	-- barn + silo (west side, fixed, between marker lines)
	local bz = ctx.MinZ + 80
	barn(ctx, Vector3.new(Kit.CenterX - 96, Y, bz))
	Kit.Reserve(ctx, Kit.CenterX - 96, bz, 20)
	do
		local m = P.Model(f, "Silo")
		local sb = Vector3.new(Kit.CenterX - 100, Y, bz + 26)
		P.Cylinder(m, "Tower", sb, 30, 11, D.Silo, Enum.Material.Metal)
		P.Ball(m, "Dome", sb + Vector3.new(0, 30, 0), 11, D.Barn)
		for _, y in { 8, 16, 24 } do
			P.Cylinder(m, "Hoop", sb + Vector3.new(0, y, 0), 0.6, 11.4, rgb(150, 150, 160))
		end
		Kit.Decor(ctx, m)
		Kit.Reserve(ctx, sb.X, sb.Z, 7)
	end

	-- split-rail fences just outside the lane edges (2)
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * (Kit.LaneHalf + 1.5)
		Kit.Decor(ctx, P.FenceLine(f, Vector3.new(x, Y, ctx.MinZ + 4), Vector3.new(x, Y, ctx.MaxZ - 6), 20, 3.4, D.Fence, false))
	end
	-- crop patches (4): soil + rows
	for _, s in Kit.Band(ctx, 4, 40, 16) do
		local m = P.Model(f, "CropPatch")
		local cx, cz = s.Pos.X, s.Pos.Z
		P.Slab(m, "Soil", cx - 10, cx + 10, cz - 15, cz + 15, Y + 0.25, 0.25, D.Soil, Enum.Material.Ground, false)
		for r = -1.5, 1.5 do
			P.Block(m, "Crop", Vector3.new(2.2, 1.8, 27), CFrame.new(cx + r * 4.8, Y + 1, cz), D.Crop, Enum.Material.Grass)
		end
		Kit.Decor(ctx, m, true)
	end
	-- hay bales (6)
	for _, s in Kit.Band(ctx, 6, 9, 3) do
		Kit.Decor(ctx, P.Part({ Parent = f, Name = "HayBale", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 3.6, 3.6),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 1.8, 0)) * Kit.Yaw(ctx), Color = D.Hay, Material = Enum.Material.Fabric }), true)
	end
	-- scarecrows (2)
	for _, s in Kit.Band(ctx, 2, 40, 4) do
		local m = P.Model(f, "Scarecrow")
		P.Cylinder(m, "Pole", s.Pos, 7, 0.6, D.Fence)
		P.Block(m, "Arms", Vector3.new(6, 0.6, 0.6), CFrame.new(s.Pos + Vector3.new(0, 5.2, 0)), D.Fence)
		P.Block(m, "Shirt", Vector3.new(2.4, 2.6, 1.2), CFrame.new(s.Pos + Vector3.new(0, 4.6, 0)), rgb(80, 130, 220))
		P.Ball(m, "Head", s.Pos + Vector3.new(0, 7, 0), 1.8, D.Hay)
		P.Block(m, "Hat", Vector3.new(2.6, 0.4, 2.6), CFrame.new(s.Pos + Vector3.new(0, 7.9, 0)), rgb(140, 95, 60))
		Kit.Decor(ctx, m, true)
	end
	-- tractor (1)
	for _, s in Kit.Band(ctx, 1, 10, 6) do
		tractor(ctx, s.Pos)
	end
	-- pumpkins (3)
	for _, s in Kit.Band(ctx, 3, 6, 2) do
		Kit.Decor(ctx, P.Ellipsoid(f, "Pumpkin", CFrame.new(s.Pos + Vector3.new(0, 0.9, 0)), Vector3.new(2.6, 1.8, 2.6),
			rgb(255, 140, 30)), true)
	end
	-- water trough (1)
	for _, s in Kit.Band(ctx, 1, 10, 3) do
		local m = P.Model(f, "Trough")
		P.Block(m, "Tub", Vector3.new(2.4, 1.4, 5), CFrame.new(s.Pos + Vector3.new(0, 0.7, 0)), rgb(150, 150, 160), Enum.Material.Metal)
		P.Block(m, "Water", Vector3.new(2, 0.1, 4.6), CFrame.new(s.Pos + Vector3.new(0, 1.35, 0)), rgb(90, 180, 240))
		Kit.Decor(ctx, m, true)
	end

	-- drifting chaff (light, cheap)
	Kit.Particles(ctx, { Name = "Chaff", Y0 = 1, Y1 = 10, Rate = 5, Lifetime = { 5, 8 }, Speed = { 0.5, 1.5 },
		Size = 0.35, Color = rgb(250, 225, 140), Spread = 180, Accel = Vector3.new(0.8, 0, 0.3), Texture = Kit.Textures.Soft })
end
