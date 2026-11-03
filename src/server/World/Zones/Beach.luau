--!strict
-- Beach (250-450): sand, palms, striped umbrellas, towels, sand castles, rocks, a lifeguard tower, beach balls
-- and surfboards; a strip of sea along both field edges. Landmark: a red-and-white lighthouse at the west edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

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
		P.Block(m, "Leaf", Vector3.new(1.4 * scale, 0.5 * scale, 7 * scale),
			CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, 0, -3.1 * scale),
			D.Palm)
	end
	Kit.Decor(ctx, m)
end

local function lighthouse(ctx: any, base: Vector3): Model
	local P = ctx.Props
	local m = P.Model(ctx.Folder.Parent, "Lighthouse")
	local red, white = rgb(225, 60, 55), rgb(250, 250, 250)
	P.Ellipsoid(m, "Rock", CFrame.new(base + Vector3.new(0, 1, 0)), Vector3.new(22, 8, 22), rgb(150, 140, 130))
	local y = 3
	for i = 1, 6 do
		local d = 15 - (i - 1)
		P.Cylinder(m, "Stripe" .. i, base + Vector3.new(0, y, 0), 11, d, if i % 2 == 1 then red else white)
		y += 11
	end
	P.Cylinder(m, "Gallery", base + Vector3.new(0, y, 0), 1.2, 14, rgb(60, 60, 70))
	y += 1.2
	P.Cylinder(m, "LampRoom", base + Vector3.new(0, y, 0), 7, 8, rgb(200, 240, 255), Enum.Material.Glass)
	local lamp = P.Ball(m, "Lamp", base + Vector3.new(0, y + 3.5, 0), 4.5, rgb(255, 240, 160), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 2
	light.Color = rgb(255, 240, 180)
	light.Shadows = false
	light.Parent = lamp
	y += 7
	Kit.Peak(P, m, "Cap", base + Vector3.new(0, y, 0), 9, 9, 5, red)
	P.Ball(m, "Tip", base + Vector3.new(0, y + 5.5, 0), 1.4, red)
	Kit.Landmark(ctx, m, y + 6.2, "Lighthouse")
	return m
end

local function lifeguardTower(ctx: any, pos: Vector3, side: number)
	local P = ctx.Props
	local m = P.Model(ctx.Folder, "LifeguardTower")
	local wood, cabin, roof = rgb(250, 250, 245), rgb(255, 200, 70), rgb(230, 70, 60)
	for _, o in { Vector3.new(-2.5, 0, -2.5), Vector3.new(2.5, 0, -2.5), Vector3.new(-2.5, 0, 2.5), Vector3.new(2.5, 0, 2.5) } do
		P.Block(m, "Leg", Vector3.new(0.7, 8, 0.7), CFrame.new(pos + o + Vector3.new(0, 4, 0)), wood)
	end
	P.Block(m, "Deck", Vector3.new(7, 0.6, 7), CFrame.new(pos + Vector3.new(0, 8.3, 0)), wood)
	P.Block(m, "Cabin", Vector3.new(5.6, 4, 5.6), CFrame.new(pos + Vector3.new(0, 10.6, 0)), cabin)
	Kit.Gable(P, m, "Roof", CFrame.new(pos + Vector3.new(0, 12.6, 0)), 7, 7, 2.2, roof)
	P.Block(m, "Ramp", Vector3.new(2, 0.4, 9), CFrame.new(pos + Vector3.new(-side * 2, 4.2, -6)) * CFrame.Angles(math.rad(-58), 0, 0), wood)
	Kit.Decor(ctx, m)
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- sea strips along both field edges (outside the field), wave lines
	for _, side in { -1, 1 } do
		local xa, xb = Kit.CenterX + side * (Kit.FieldHalf + 0.5), Kit.CenterX + side * Kit.LandmarkMaxAbsX
		Kit.Flat(P, f.Parent, "Sea", math.min(xa, xb), math.max(xa, xb), ctx.StartZ, ctx.MaxZ, Y + 0.3, D.Water,
			Enum.Material.Glass)
		local wx = Kit.CenterX + side * (Kit.FieldHalf + 4)
		Kit.Flat(P, f.Parent, "Surf", math.min(wx - 1, wx + 1), math.max(wx - 1, wx + 1), ctx.StartZ, ctx.MaxZ, Y + 0.36,
			Color3.new(1, 1, 1))
	end

	-- landmark (west edge, standing in the sea)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 10
	lighthouse(ctx, Vector3.new(Kit.CenterX - 138, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX - 128, lz, 12)

	-- lifeguard tower (1), fixed on the east side between marker lines
	local gz = ctx.MinZ + 30
	lifeguardTower(ctx, Vector3.new(Kit.CenterX + 100, Y, gz), 1)
	Kit.Reserve(ctx, Kit.CenterX + 100, gz, 12)

	-- palms (7)
	for _, s in Kit.Band(ctx, 7, 16, 11) do
		palm(ctx, s.Pos, rng:NextNumber(1, 1.25))
	end
	-- umbrellas with towels (5)
	for i, s in Kit.Band(ctx, 5, 14, 5) do
		local m = P.Model(f, "Umbrella")
		P.Cylinder(m, "Pole", s.Pos, 7, 0.4, Color3.new(1, 1, 1))
		P.Part({ Parent = m, Name = "Canopy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 9, 9),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = D.Umbrella[(i - 1) % #D.Umbrella + 1] })
		P.Ball(m, "Top", s.Pos + Vector3.new(0, 7.6, 0), 1, Color3.new(1, 1, 1))
		Kit.Flat(P, m, "Towel", s.Pos.X - 1.5, s.Pos.X + 1.5, s.Pos.Z + 1, s.Pos.Z + 4.5, Y + 0.08, D.Umbrella[i % #D.Umbrella + 1])
		Kit.Decor(ctx, m, true)
	end
	-- loose towels (3)
	for i, s in Kit.Band(ctx, 3, 10, 3) do
		local c = if i % 2 == 0 then rgb(80, 200, 160) else rgb(255, 140, 60)
		local m = P.Model(f, "Towel")
		Kit.Flat(P, m, "Cloth", s.Pos.X - 1.5, s.Pos.X + 1.5, s.Pos.Z - 2.5, s.Pos.Z + 2.5, Y + 0.08, c)
		Kit.Flat(P, m, "Stripe", s.Pos.X - 1.5, s.Pos.X + 1.5, s.Pos.Z - 0.4, s.Pos.Z + 0.4, Y + 0.1, Color3.new(1, 1, 1))
		Kit.Decor(ctx, m, true)
	end
	-- sand castles (3)
	for _, s in Kit.Band(ctx, 3, 18, 5) do
		local m = P.Model(f, "SandCastle")
		local sand = ctx.Ground:Lerp(Color3.new(0, 0, 0), 0.1)
		P.Block(m, "Base", Vector3.new(6, 3, 6), CFrame.new(s.Pos + Vector3.new(0, 1.5, 0)), sand, Enum.Material.Sand)
		for _, o in { Vector3.new(-2.6, 0, -2.6), Vector3.new(2.6, 0, -2.6), Vector3.new(-2.6, 0, 2.6), Vector3.new(2.6, 0, 2.6) } do
			P.Cylinder(m, "Turret", s.Pos + o, 4.2, 1.8, sand, Enum.Material.Sand)
		end
		P.Block(m, "Keep", Vector3.new(3, 3, 3), CFrame.new(s.Pos + Vector3.new(0, 4.5, 0)), sand, Enum.Material.Sand)
		P.Block(m, "Flag", Vector3.new(0.2, 1, 1.4), CFrame.new(s.Pos + Vector3.new(0, 6.8, 0.7)), rgb(255, 90, 90))
		Kit.Decor(ctx, m, true)
	end
	-- rocks (3)
	for _, s in Kit.Band(ctx, 3, 16, 5) do
		Kit.Decor(ctx, P.Rock(f, s.Pos, rng:NextNumber(0.8, 1.1), D.Rock, rng:NextNumber(0, 6.28)), true)
	end
	-- beach balls (2)
	for _, s in Kit.Band(ctx, 2, 10, 2) do
		Kit.Decor(ctx, P.Ball(f, "BeachBall", s.Pos + Vector3.new(0, 1.3, 0), 2.6, D.Ball), true)
	end
	-- surfboards stuck in the sand (2)
	for i, s in Kit.Band(ctx, 2, 12, 3) do
		local m = P.Model(f, "Surfboard")
		P.Ellipsoid(m, "Board", CFrame.new(s.Pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(8)),
			Vector3.new(2, 7, 0.5), if i == 1 then rgb(80, 200, 255) else rgb(255, 120, 180))
		P.Block(m, "Stripe", Vector3.new(0.3, 6.5, 0.55), CFrame.new(s.Pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(8)),
			Color3.new(1, 1, 1))
		Kit.Decor(ctx, m, true)
	end

	-- sun glints on the sand (light, cheap)
	Kit.Particles(ctx, { Name = "Glints", Y0 = 0.5, Y1 = 2, Rate = 6, Lifetime = { 0.6, 1.2 }, Speed = { 0, 0 },
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.8),
			NumberSequenceKeypoint.new(1, 0) }), Color = rgb(255, 255, 230), LightEmission = 1 })
end
