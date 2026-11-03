--!strict
-- City Rooftops (1400-1900): a concrete roof deck with tar seams, raised roof blocks, AC units, water towers,
-- antennas, blank neon billboards (no text), stair huts, skylights and vents; a low skyline along both edges.
-- Landmark: a stepped skyscraper with a spire at the west edge.
local Kit = require((script.Parent :: Instance):WaitForChild("Kit")) :: any

local rgb = Color3.fromRGB

local function skyscraper(ctx: any, base: Vector3): Model
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder.Parent, "Skyscraper")
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

local function waterTower(ctx: any, pos: Vector3)
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "WaterTower")
	for _, o in { Vector3.new(-2.5, 0, -2.5), Vector3.new(2.5, 0, -2.5), Vector3.new(-2.5, 0, 2.5), Vector3.new(2.5, 0, 2.5) } do
		P.Cylinder(m, "Leg", pos + o, 6, 0.6, rgb(60, 60, 70))
	end
	P.Cylinder(m, "Tank", pos + Vector3.new(0, 6, 0), 8, 8, D.Tank, Enum.Material.Wood)
	P.Cylinder(m, "Hoop", pos + Vector3.new(0, 9, 0), 0.5, 8.3, rgb(60, 60, 70), Enum.Material.Metal)
	Kit.Peak(P, m, "Lid", pos + Vector3.new(0, 14, 0), 7, 7, 3, D.Tank:Lerp(Color3.new(0, 0, 0), 0.25))
	Kit.Decor(ctx, m)
end

local function billboard(ctx: any, pos: Vector3, i: number)
	-- blank advert board facing the platform (-Z): colour blocks only, never text or logos
	local P, D = ctx.Props, ctx.Decor
	local m = P.Model(ctx.Folder, "Billboard")
	for _, dx in { -5, 5 } do
		P.Block(m, "Post", Vector3.new(0.8, 9, 0.8), CFrame.new(pos + Vector3.new(dx, 4.5, 0.6)), rgb(60, 60, 70), Enum.Material.Metal)
	end
	local c = D.Neon[(i - 1) % #D.Neon + 1]
	P.Block(m, "Frame", Vector3.new(15, 7.6, 0.6), CFrame.new(pos + Vector3.new(0, 12, 0.3)), c, Enum.Material.Neon)
	P.Block(m, "Panel", Vector3.new(14, 6.6, 0.4), CFrame.new(pos + Vector3.new(0, 12, 0)), rgb(250, 245, 235))
	P.Ball(m, "Dot", pos + Vector3.new(-3.5, 12, -0.1), 3.6, c)
	P.Block(m, "Bar", Vector3.new(6, 1.2, 0.3), CFrame.new(pos + Vector3.new(2.5, 12.6, -0.25)), rgb(60, 60, 80))
	P.Block(m, "Bar2", Vector3.new(4, 1.2, 0.3), CFrame.new(pos + Vector3.new(1.5, 10.8, -0.25)), c)
	Kit.Decor(ctx, m)
end

return function(ctx: any)
	local P, D, f, Y = ctx.Props, ctx.Decor, ctx.Folder, ctx.Y
	local rng = ctx.Rng

	-- landmark (west edge)
	local lz = ctx.MinZ + 250
	skyscraper(ctx, Vector3.new(Kit.CenterX - 135, Y, lz))
	Kit.Reserve(ctx, Kit.CenterX - 124, lz, 14)

	-- tar seams across the outer roof deck (flat dressing) + parapet at the field edge
	for _, side in { -1, 1 } do
		local xa, xb = Kit.CenterX + side * (Kit.LaneHalf + 2), Kit.CenterX + side * Kit.DecorMaxAbsX
		local z = ctx.MinZ + 20
		while z < ctx.MaxZ - 10 do
			Kit.Flat(P, f.Parent, "TarSeam", math.min(xa, xb), math.max(xa, xb), z - 0.4, z + 0.4, Y + 0.04, rgb(50, 52, 60))
			z += 40
		end
		local px = Kit.CenterX + side * (Kit.FieldHalf - 0.75)
		P.Block(f.Parent, "Parapet", Vector3.new(1.5, 3, ctx.MaxZ - ctx.StartZ), CFrame.new(px, Y + 1.5, (ctx.StartZ + ctx.MaxZ) / 2),
			rgb(150, 150, 162), Enum.Material.Concrete)
	end
	-- low skyline just outside the field (dressing), skipping the landmark
	for _, side in { -1, 1 } do
		local z = ctx.StartZ + 30
		local i = 0
		while z < ctx.MaxZ - 20 do
			i += 1
			local w = rng:NextNumber(18, 26)
			if not (side < 0 and math.abs(z - lz) < 30) then
				local h = rng:NextNumber(18, 60)
				local cx = Kit.CenterX + side * (Kit.FieldHalf + 2 + w / 2)
				local b = P.Block(f.Parent, "Building", Vector3.new(w, h, w), CFrame.new(cx, Y + h / 2, z),
					D.Building[(i - 1) % #D.Building + 1])
				b.CanCollide = false
				P.Block(f.Parent, "Windows", Vector3.new(0.4, h * 0.7, w * 0.5), CFrame.new(cx - side * (w / 2 + 0.2), Y + h * 0.5, z),
					D.Window, Enum.Material.Neon)
			end
			z += w + rng:NextNumber(30, 50)
		end
	end

	-- raised roof blocks (3)
	for _, s in Kit.Band(ctx, 3, 50, 12) do
		local m = P.Model(f, "RoofBlock")
		P.Block(m, "Deck", Vector3.new(22, 5, 22), CFrame.new(s.Pos + Vector3.new(0, 2.5, 0)), rgb(132, 134, 146), Enum.Material.Concrete)
		P.Block(m, "Rim", Vector3.new(23, 0.8, 23), CFrame.new(s.Pos + Vector3.new(0, 5.2, 0)), rgb(160, 160, 172))
		P.Block(m, "Hatch", Vector3.new(4, 1.2, 4), CFrame.new(s.Pos + Vector3.new(4, 6, 4)), rgb(90, 95, 110), Enum.Material.Metal)
		Kit.Decor(ctx, m)
	end
	-- AC units (6)
	for _, s in Kit.Band(ctx, 6, 12, 4) do
		local m = P.Model(f, "ACUnit")
		P.Block(m, "Box", Vector3.new(6, 4, 6), CFrame.new(s.Pos + Vector3.new(0, 2, 0)), D.Vent, Enum.Material.Metal)
		P.Part({ Parent = m, Name = "Fan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4),
			CFrame = CFrame.new(s.Pos + Vector3.new(0, 4.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = rgb(90, 95, 110) })
		P.Block(m, "Grille", Vector3.new(0.2, 2.4, 4.6), CFrame.new(s.Pos + Vector3.new(-3.05, 2, 0)), rgb(70, 75, 90))
		Kit.Decor(ctx, m, true)
	end
	-- water towers (3)
	for _, s in Kit.Band(ctx, 3, 30, 5) do
		waterTower(ctx, s.Pos)
	end
	-- antennas (3)
	for _, s in Kit.Band(ctx, 3, 20, 3) do
		local m = P.Model(f, "Antenna")
		local h = rng:NextNumber(14, 20)
		P.Cylinder(m, "Mast", s.Pos, h, 0.5, rgb(200, 200, 210), Enum.Material.Metal)
		for _, y in { h * 0.55, h * 0.8 } do
			P.Block(m, "Bar", Vector3.new(4, 0.3, 0.3), CFrame.new(s.Pos + Vector3.new(0, y, 0)), rgb(200, 200, 210), Enum.Material.Metal)
		end
		P.Ball(m, "Tip", s.Pos + Vector3.new(0, h + 0.4, 0), 0.9, rgb(255, 60, 60), Enum.Material.Neon)
		Kit.Decor(ctx, m, true)
	end
	-- billboards (2), facing the platform
	for i, s in Kit.Band(ctx, 2, 60, 8) do
		billboard(ctx, s.Pos, i)
	end
	-- stair huts (2)
	for _, s in Kit.Band(ctx, 2, 30, 5) do
		local m = P.Model(f, "StairHut")
		P.Block(m, "Hut", Vector3.new(7, 8, 7), CFrame.new(s.Pos + Vector3.new(0, 4, 0)), rgb(150, 130, 170))
		P.Block(m, "Door", Vector3.new(0.3, 5.5, 3), CFrame.new(s.Pos + Vector3.new(-s.Side * 3.6, 2.75, 0)), rgb(60, 60, 80))
		P.Block(m, "Cap", Vector3.new(7.6, 0.6, 7.6), CFrame.new(s.Pos + Vector3.new(0, 8.3, 0)), rgb(110, 115, 140))
		Kit.Decor(ctx, m)
	end
	-- skylights (2)
	for _, s in Kit.Band(ctx, 2, 20, 5) do
		local m = P.Model(f, "Skylight")
		P.Block(m, "Curb", Vector3.new(8, 0.8, 6), CFrame.new(s.Pos + Vector3.new(0, 0.4, 0)), rgb(160, 160, 172))
		P.Block(m, "Glass", Vector3.new(7.2, 0.6, 5.2), CFrame.new(s.Pos + Vector3.new(0, 1, 0)), rgb(150, 210, 255), Enum.Material.Glass)
		Kit.Decor(ctx, m, true)
	end
	-- vent stacks (2)
	for _, s in Kit.Band(ctx, 2, 12, 2) do
		local m = P.Model(f, "VentStack")
		P.Cylinder(m, "Pipe", s.Pos, 5, 1.4, rgb(170, 175, 185), Enum.Material.Metal)
		P.Cylinder(m, "Cap", s.Pos + Vector3.new(0, 5, 0), 0.6, 2.2, rgb(120, 125, 135), Enum.Material.Metal)
		Kit.Decor(ctx, m, true)
	end
end
