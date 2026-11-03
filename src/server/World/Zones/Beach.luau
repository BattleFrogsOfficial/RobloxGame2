--!strict
-- Beach (250-450): sand with shells, pebbles, starfish, seaweed and wet-sand patches over the whole plot; palms,
-- striped umbrellas with towels, sand castles, beach balls, surfboards, rocks and a lifeguard tower; a strip of
-- sea along both field edges. Boundary: a dune ridge across the field. Landmark: a lighthouse (west).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function palm(ctx: any, m: Model, base: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local scale = ctx.Rng:NextNumber(1, 1.25)
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
	P.Ball(m, "Coconuts", top - Vector3.new(0, 0.6, 0), 1.4 * scale, rgb(120, 80, 40))
end

local function lighthouse(ctx: any, base: Vector3): Model
	local P = ctx.Props
	local m = P.Model(ctx.ZoneFolder, "Lighthouse")
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

local function lifeguardTower(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P = ctx.Props
	local wood, cabin, roof = rgb(250, 250, 245), rgb(255, 200, 70), rgb(230, 70, 60)
	for _, o in { Vector3.new(-2.5, 0, -2.5), Vector3.new(2.5, 0, -2.5), Vector3.new(-2.5, 0, 2.5), Vector3.new(2.5, 0, 2.5) } do
		P.Block(m, "Leg", Vector3.new(0.7, 8, 0.7), CFrame.new(pos + o + Vector3.new(0, 4, 0)), wood)
	end
	P.Block(m, "Deck", Vector3.new(7, 0.6, 7), CFrame.new(pos + Vector3.new(0, 8.3, 0)), wood)
	P.Block(m, "Cabin", Vector3.new(5.6, 4, 5.6), CFrame.new(pos + Vector3.new(0, 10.6, 0)), cabin)
	Kit.Gable(P, m, "Roof", CFrame.new(pos + Vector3.new(0, 12.6, 0)), 7, 7, 2.2, roof)
	P.Block(m, "Ramp", Vector3.new(2, 0.4, 9), CFrame.new(pos + Vector3.new(-side * 2, 4.2, -6)) * CFrame.Angles(math.rad(-58), 0, 0), wood)
end

local function umbrella(ctx: any, m: Model, pos: Vector3, i: number)
	local P, D = ctx.Props, ctx.Decor
	P.Cylinder(m, "Pole", pos, 7, 0.4, Color3.new(1, 1, 1))
	P.Part({ Parent = m, Name = "Canopy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 9, 9),
		CFrame = CFrame.new(pos + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = D.Umbrella[(i - 1) % #D.Umbrella + 1] })
	P.Part({ Parent = m, Name = "Stripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 4.5, 4.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 7.05, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.new(1, 1, 1) })
	P.Block(m, "Towel", Vector3.new(3, 0.1, 3.5), CFrame.new(pos + Vector3.new(0, 0.05, 2.8)), D.Umbrella[i % #D.Umbrella + 1])
end

local function towel(ctx: any, m: Model, pos: Vector3, i: number)
	local P = ctx.Props
	local cf = CFrame.new(pos) * Kit.Yaw(ctx)
	P.Block(m, "Cloth", Vector3.new(3, 0.1, 5), cf * CFrame.new(0, 0.05, 0), if i % 2 == 0 then rgb(80, 200, 160) else rgb(255, 140, 60))
	P.Block(m, "Stripe", Vector3.new(3, 0.12, 0.8), cf * CFrame.new(0, 0.06, 0), Color3.new(1, 1, 1))
end

local function sandCastle(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local sand = ctx.Ground:Lerp(Color3.new(0, 0, 0), 0.1)
	P.Block(m, "Base", Vector3.new(6, 3, 6), CFrame.new(pos + Vector3.new(0, 1.5, 0)), sand, Enum.Material.Sand)
	for _, o in { Vector3.new(-2.6, 0, -2.6), Vector3.new(2.6, 0, -2.6), Vector3.new(-2.6, 0, 2.6), Vector3.new(2.6, 0, 2.6) } do
		P.Cylinder(m, "Turret", pos + o, 4.2, 1.8, sand, Enum.Material.Sand)
	end
	P.Block(m, "Keep", Vector3.new(3, 3, 3), CFrame.new(pos + Vector3.new(0, 4.5, 0)), sand, Enum.Material.Sand)
	P.Block(m, "Flag", Vector3.new(0.2, 1, 1.4), CFrame.new(pos + Vector3.new(0, 6.8, 0.7)), rgb(255, 90, 90))
end

local function surfboard(ctx: any, m: Model, pos: Vector3, i: number)
	local P = ctx.Props
	local cf = CFrame.new(pos + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(8))
	P.Ellipsoid(m, "Board", cf, Vector3.new(2, 7, 0.5), if i % 2 == 1 then rgb(80, 200, 255) else rgb(255, 120, 180))
	P.Block(m, "Stripe", Vector3.new(0.3, 6.5, 0.55), cf, Color3.new(1, 1, 1))
end

local function beachBall(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Ball(m, "Ball", pos + Vector3.new(0, 1.3, 0), 2.6, Color3.new(1, 1, 1))
	P.Block(m, "Band", Vector3.new(2.7, 0.8, 0.8), CFrame.new(pos + Vector3.new(0, 1.3, 0)), rgb(255, 90, 90))
	P.Block(m, "Band2", Vector3.new(0.8, 0.8, 2.7), CFrame.new(pos + Vector3.new(0, 1.3, 0)), rgb(80, 170, 255))
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- sea strips along both field edges (outside the field) + surf lines
	for _, side in { -1, 1 } do
		local xa, xb = Kit.CenterX + side * (Kit.FieldHalf + 0.5), Kit.CenterX + side * Kit.LandmarkMaxAbsX
		Kit.Flat(P, g, "Sea", math.min(xa, xb), math.max(xa, xb), ctx.StartZ, ctx.MaxZ, Y + 0.3, D.Water, Enum.Material.Glass)
		local wx = Kit.CenterX + side * (Kit.FieldHalf + 4)
		Kit.Flat(P, g, "Surf", wx - 1, wx + 1, ctx.StartZ, ctx.MaxZ, Y + 0.36, Color3.new(1, 1, 1))
	end
	-- darker wet-sand band along both field edges
	for _, side in { -1, 1 } do
		local xa, xb = Kit.CenterX + side * (Kit.FieldHalf - 10), Kit.CenterX + side * Kit.FieldHalf
		Kit.Flat(P, g, "WetSand", math.min(xa, xb), math.max(xa, xb), ctx.StartZ, ctx.MaxZ, Y + 0.03,
			ctx.Ground:Lerp(rgb(150, 120, 80), 0.35), Enum.Material.Sand)
	end

	-- landmark (west edge, standing in the sea)
	local lz = (ctx.MinZ + ctx.MaxZ) / 2 + 10
	lighthouse(ctx, Vector3.new(Kit.CenterX - 138, Y, lz))

	-- props (25)
	Kit.PlaceAll(ctx, {
		{ Name = "LifeguardTower", Count = 1, R = 6, Tall = true, Build = lifeguardTower },
		{ Name = "Palm", Count = 6, R = 6, Tall = true, Build = palm },
		{ Name = "Umbrella", Count = 6, R = 4.5, Build = umbrella },
		{ Name = "SandCastle", Count = 3, R = 3.5, Build = sandCastle },
		{ Name = "Towel", Count = 3, R = 2.5, Build = towel },
		{ Name = "Rock", Count = 2, R = 3, Build = function(c, m, pos)
			P.Rock(m, pos, rng:NextNumber(0.8, 1.1), D.Rock, rng:NextNumber(0, 6.28))
		end },
		{ Name = "Surfboard", Count = 2, R = 1.5, Build = surfboard },
		{ Name = "BeachBall", Count = 2, R = 1.4, Build = beachBall },
	})

	-- ground cover: shells, pebbles, starfish, seaweed, wet-sand patches
	Kit.Cover(ctx, { Count = 270, Mode = "Random", Items = {
		Kit.Weight(Kit.Spike({ rgb(255, 200, 210), rgb(255, 245, 225), rgb(250, 180, 150) }, 0.9, 0.6), 4),
		Kit.Weight(Kit.Dome({ rgb(170, 160, 150), rgb(200, 190, 175), rgb(130, 125, 120) }, 0.6, 1.1), 3),
		Kit.Weight(Kit.Chip({ rgb(255, 130, 60), rgb(255, 100, 120) }, 1.1, 1.1, 0.15), 2),
		Kit.Weight(Kit.Spike({ rgb(70, 120, 60), rgb(110, 100, 50) }, 0.7, 1.3), 1.5),
		Kit.Weight(Kit.Disc({ ctx.Ground:Lerp(rgb(150, 120, 80), 0.3) }, 3, 5.5, Enum.Material.Sand), 1),
	} })

	-- sun glints on the sand (light, cheap)
	Kit.Particles(ctx, { Name = "Glints", Y0 = 0.5, Y1 = 2, Rate = 6, Lifetime = { 0.6, 1.2 }, Speed = { 0, 0 },
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.8),
			NumberSequenceKeypoint.new(1, 0) }), Color = rgb(255, 255, 230), LightEmission = 1 })
end
