--!strict
-- City Rooftops (1400-1900): a concrete roof deck with tar seams, cracks, puddles, gravel, drain grates and
-- paint marks over the whole plot; AC units, vent stacks, water towers, antennas, blank neon billboards (no
-- text), stair huts, skylights, crate stacks and raised roof blocks; a low skyline along both edges.
-- Boundary: a roof-edge kerb with a neon trim line across the field. Landmark: a stepped skyscraper (west).
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function skyscraper(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.ZoneFolder, "Skyscraper")
	local body, glow = rgb(70, 90, 130), D.Window
	local y = 0
	for i, t in { { 28, 110 }, { 22, 50 }, { 14, 25 } } do
		local w, h = t[1], t[2]
		P.Block(m, "Tier" .. i, Vector3.new(w, h, w), CFrame.new(base + Vector3.new(0, y + h / 2, 0)),
			body:Lerp(Color3.new(1, 1, 1), (i - 1) * 0.12), Enum.Material.Glass)
		-- window columns on the field (+X) and platform (-Z) faces
		for k = -1, 1, 2 do
			P.Block(m, "WinX", Vector3.new(0.4, h * 0.86, w * 0.16), CFrame.new(base + Vector3.new(w / 2 + 0.2, y + h / 2, k * w * 0.25)),
				glow, Enum.Material.Neon)
			P.Block(m, "WinZ", Vector3.new(w * 0.16, h * 0.86, 0.4), CFrame.new(base + Vector3.new(k * w * 0.25, y + h / 2, -w / 2 - 0.2)),
				glow, Enum.Material.Neon)
		end
		P.Block(m, "Ledge" .. i, Vector3.new(w + 1, 1.2, w + 1), CFrame.new(base + Vector3.new(0, y + h, 0)), D.Neon[1], Enum.Material.Neon)
		y += h
	end
	P.Cylinder(m, "Spire", base + Vector3.new(0, y, 0), 30, 1.8, rgb(220, 220, 230), Enum.Material.Metal)
	P.Ball(m, "Beacon", base + Vector3.new(0, y + 31, 0), 2.6, rgb(255, 60, 60), Enum.Material.Neon)
	Kit.Landmark(ctx, m, y + 32.3, "Skyscraper")
	return m
end

local function waterTower(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	for _, o in { Vector3.new(-2.5, 0, -2.5), Vector3.new(2.5, 0, -2.5), Vector3.new(-2.5, 0, 2.5), Vector3.new(2.5, 0, 2.5) } do
		P.Cylinder(m, "Leg", pos + o, 6, 0.6, rgb(60, 60, 70))
	end
	P.Cylinder(m, "Tank", pos + Vector3.new(0, 6, 0), 8, 8, D.Tank, Enum.Material.Wood)
	P.Cylinder(m, "Hoop", pos + Vector3.new(0, 9, 0), 0.5, 8.3, rgb(60, 60, 70), Enum.Material.Metal)
	Kit.Peak(P, m, "Lid", pos + Vector3.new(0, 14, 0), 7, 7, 3, D.Tank:Lerp(Color3.new(0, 0, 0), 0.25))
end

local function billboard(ctx: any, m: Model, pos: Vector3, i: number)
	-- blank advert board facing the platform (-Z): colour blocks only, never text or logos
	local P, D = ctx.Props, ctx.Decor
	for _, dx in { -5, 5 } do
		P.Block(m, "Post", Vector3.new(0.8, 9, 0.8), CFrame.new(pos + Vector3.new(dx, 4.5, 0.6)), rgb(60, 60, 70), Enum.Material.Metal)
	end
	local c = D.Neon[(i - 1) % #D.Neon + 1]
	P.Block(m, "Frame", Vector3.new(15, 7.6, 0.6), CFrame.new(pos + Vector3.new(0, 12, 0.3)), c, Enum.Material.Neon)
	P.Block(m, "Panel", Vector3.new(14, 6.6, 0.4), CFrame.new(pos + Vector3.new(0, 12, 0)), rgb(250, 245, 235))
	P.Ball(m, "Dot", pos + Vector3.new(-3.5, 12, -0.1), 3.6, c)
	P.Block(m, "Bar", Vector3.new(6, 1.2, 0.3), CFrame.new(pos + Vector3.new(2.5, 12.6, -0.25)), rgb(60, 60, 80))
	P.Block(m, "Bar2", Vector3.new(4, 1.2, 0.3), CFrame.new(pos + Vector3.new(1.5, 10.8, -0.25)), c)
end

local function acUnit(ctx: any, m: Model, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	P.Block(m, "Box", Vector3.new(6, 4, 6), CFrame.new(pos + Vector3.new(0, 2, 0)), D.Vent, Enum.Material.Metal)
	P.Part({ Parent = m, Name = "Fan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(90, 95, 110) })
	P.Block(m, "Grille", Vector3.new(0.2, 2.4, 4.6), CFrame.new(pos + Vector3.new(-3.05, 2, 0)), rgb(70, 75, 90))
end

local function antenna(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local h = ctx.Rng:NextNumber(14, 20)
	P.Cylinder(m, "Mast", pos, h, 0.5, rgb(200, 200, 210), Enum.Material.Metal)
	for _, y in { h * 0.55, h * 0.8 } do
		P.Block(m, "Bar", Vector3.new(4, 0.3, 0.3), CFrame.new(pos + Vector3.new(0, y, 0)), rgb(200, 200, 210), Enum.Material.Metal)
	end
	P.Ball(m, "Tip", pos + Vector3.new(0, h + 0.4, 0), 0.9, rgb(255, 60, 60), Enum.Material.Neon)
end

local function stairHut(ctx: any, m: Model, pos: Vector3, _i: number, side: number)
	local P = ctx.Props
	P.Block(m, "Hut", Vector3.new(7, 8, 7), CFrame.new(pos + Vector3.new(0, 4, 0)), rgb(150, 130, 170))
	P.Block(m, "Door", Vector3.new(0.3, 5.5, 3), CFrame.new(pos + Vector3.new(-side * 3.6, 2.75, 0)), rgb(60, 60, 80))
	P.Block(m, "Cap", Vector3.new(7.6, 0.6, 7.6), CFrame.new(pos + Vector3.new(0, 8.3, 0)), rgb(110, 115, 140))
end

local function skylight(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Block(m, "Curb", Vector3.new(8, 0.8, 6), CFrame.new(pos + Vector3.new(0, 0.4, 0)), rgb(160, 160, 172))
	P.Block(m, "Glass", Vector3.new(7.2, 0.6, 5.2), CFrame.new(pos + Vector3.new(0, 1, 0)), rgb(150, 210, 255), Enum.Material.Glass)
end

local function ventStack(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Cylinder(m, "Pipe", pos, 5, 1.4, rgb(170, 175, 185), Enum.Material.Metal)
	P.Cylinder(m, "Cap", pos + Vector3.new(0, 5, 0), 0.6, 2.2, rgb(120, 125, 135), Enum.Material.Metal)
	P.Cylinder(m, "Pipe2", pos + Vector3.new(1.8, 0, 0.6), 3, 1, rgb(170, 175, 185), Enum.Material.Metal)
end

local function crateStack(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	local cf = CFrame.new(pos) * Kit.Yaw(ctx)
	P.Block(m, "Crate", Vector3.new(3.4, 3, 3.4), cf * CFrame.new(-1, 1.5, 0), rgb(200, 150, 90), Enum.Material.Wood)
	P.Block(m, "Crate2", Vector3.new(3, 2.6, 3), cf * CFrame.new(1.8, 1.3, 0.6), rgb(90, 130, 200))
	P.Block(m, "Crate3", Vector3.new(2.6, 2.4, 2.6), cf * CFrame.new(-0.6, 4.2, 0.2) * CFrame.Angles(0, 0.4, 0), rgb(220, 90, 70))
end

local function roofBlock(ctx: any, m: Model, pos: Vector3)
	local P = ctx.Props
	P.Block(m, "Deck", Vector3.new(16, 5, 16), CFrame.new(pos + Vector3.new(0, 2.5, 0)), rgb(132, 134, 146), Enum.Material.Concrete)
	P.Block(m, "Rim", Vector3.new(17, 0.8, 17), CFrame.new(pos + Vector3.new(0, 5.2, 0)), rgb(160, 160, 172))
	P.Block(m, "Hatch", Vector3.new(4, 1.2, 4), CFrame.new(pos + Vector3.new(3, 6, 3)), rgb(90, 95, 110), Enum.Material.Metal)
	P.Block(m, "Helipad", Vector3.new(6, 0.1, 1.2), CFrame.new(pos + Vector3.new(-3, 5.65, -3)), rgb(255, 196, 60))
end

return function(ctx: any)
	local P, D, Y = ctx.Props, ctx.Decor, ctx.Y
	local rng = ctx.Rng
	local g = ctx.GroundModel

	-- landmark (west edge)
	local lz = ctx.MinZ + 250
	skyscraper(ctx, Vector3.new(Kit.CenterX - 135, Y, lz))

	-- tar seams across the whole roof deck + a yellow service walkway down each side (flat dressing)
	local z = ctx.MinZ + 20
	while z < ctx.MaxZ - 10 do
		Kit.Flat(P, g, "TarSeam", Kit.CenterX - Kit.FieldHalf, Kit.CenterX + Kit.FieldHalf, z - 0.4, z + 0.4, Y + 0.04, rgb(50, 52, 60))
		z += 40
	end
	for _, x in { -70, 70 } do
		Kit.Flat(P, g, "Walkway", Kit.CenterX + x - 0.4, Kit.CenterX + x + 0.4, ctx.StartZ, ctx.MaxZ, Y + 0.05, rgb(255, 196, 60))
	end
	-- parapets along both field edges + a low skyline just outside the field
	for _, side in { -1, 1 } do
		local px = Kit.CenterX + side * (Kit.FieldHalf - 0.75)
		local pp = P.Block(g, "Parapet", Vector3.new(1.5, 3, ctx.MaxZ - ctx.StartZ), CFrame.new(px, Y + 1.5, (ctx.StartZ + ctx.MaxZ) / 2),
			rgb(150, 150, 162), Enum.Material.Concrete)
		pp.CanQuery = false
		Kit.Obstacle(ctx, pp, "Parapet")
		local bz = ctx.StartZ + 30
		local i = 0
		while bz < ctx.MaxZ - 20 do
			i += 1
			local w = rng:NextNumber(18, 26)
			if not (side < 0 and math.abs(bz - lz) < 30) then
				local h = rng:NextNumber(18, 60)
				local cx = Kit.CenterX + side * (Kit.FieldHalf + 2 + w / 2)
				P.Block(g, "Building", Vector3.new(w, h, w), CFrame.new(cx, Y + h / 2, bz), D.Building[(i - 1) % #D.Building + 1])
				P.Block(g, "Windows", Vector3.new(0.4, h * 0.7, w * 0.5), CFrame.new(cx - side * (w / 2 + 0.2), Y + h * 0.5, bz),
					D.Window, Enum.Material.Neon)
			end
			bz += w + rng:NextNumber(30, 50)
		end
	end

	-- props (34)
	Kit.PlaceAll(ctx, {
		{ Name = "RoofBlock", Count = 2, R = 8.5, Build = roofBlock },
		{ Name = "Billboard", Count = 2, R = 7.5, Tall = true, MinAbsX = 50, Build = billboard },
		{ Name = "WaterTower", Count = 3, R = 4.2, Tall = true, Build = waterTower },
		{ Name = "Antenna", Count = 3, R = 2, Tall = true, Build = antenna },
		{ Name = "StairHut", Count = 3, R = 4, Build = stairHut },
		{ Name = "ACUnit", Count = 7, R = 3.2, Build = acUnit },
		{ Name = "Skylight", Count = 4, R = 4, Build = skylight },
		{ Name = "CrateStack", Count = 5, R = 3, Build = crateStack },
		{ Name = "VentStack", Count = 5, R = 1.8, Build = ventStack },
	})

	-- ground cover: cracks, puddles, gravel, drain grates, paint marks, bolts
	Kit.Cover(ctx, { Count = 380, Mode = "Random", Items = {
		Kit.Weight(Kit.Chip({ rgb(55, 56, 64), rgb(70, 72, 80) }, 3.2, 0.25, 0.06), 4),
		Kit.Weight(Kit.Disc({ rgb(110, 150, 190), rgb(90, 130, 175) }, 2, 4.5, Enum.Material.Glass), 2),
		Kit.Weight(Kit.Nugget({ rgb(150, 150, 158), rgb(120, 120, 128) }, 0.7, Enum.Material.Concrete), 3),
		Kit.Weight(Kit.Chip({ rgb(45, 46, 52) }, 1.6, 1.6, 0.08, Enum.Material.DiamondPlate), 1),
		Kit.Weight(Kit.Chip({ rgb(255, 196, 60), rgb(240, 240, 240) }, 2.2, 0.4, 0.06), 1.5),
		Kit.Weight(Kit.Nugget({ rgb(180, 185, 195) }, 0.45, Enum.Material.Metal), 1),
	} })
end
