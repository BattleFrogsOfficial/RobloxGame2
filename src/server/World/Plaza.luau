--!strict
-- The plaza between the street and the field. Deliberately simple: ONE ball shop (west), ONE training
-- area (east), two spawn pads beside the ramp foot, and the runaway lawn (with the squirrel loop around it).
-- The ramp + raised throwing platform up the middle are built by Platform.luau.
--
--   x: -60 ............ -8 | ramp | 8 ............. 60
--      z -24  spawn 1        |    |        spawn 2
--      z  -4  BALL SHOP      |    |   TRAINING (z -2..22)
--      z 18..56 runaway lawn | deck + tower (x -18..18, z 34..60)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Plaza = {}

local Y = Layout.GroundY
local T = WorldTheme.Plaza
local P = Layout.Plaza

Plaza.Lawn = { MinX = P.MinX + 4, MaxX = -24, MinZ = 18, MaxZ = P.MaxZ - 4 } -- -56..-24 x 18..56
Plaza.Spawns = { Vector3.new(-20, 0, P.MinZ + 10), Vector3.new(20, 0, P.MinZ + 10) }
Plaza.SpawnSize = 10
Plaza.Shop = { Width = 22, Depth = 12, CounterDepth = 3 } -- counter front faces -Z (the street / spawns)
Plaza.TrainingMat = 24

----------------------------------------------------------------------------------------------------
local function buildShop(parent: Instance)
	local c: Vector3 = Layout.Shop.Center
	local S = Plaza.Shop
	local colors = T.ShopAwning
	local m = Props.Model(parent, "Shop_Balls")
	local halfW = S.Width / 2
	local backZ = c.Z + S.Depth -- back wall line (shop interior is +Z of the counter)

	-- counter (tagged ShopStand: services/client measure range from this part)
	local counter = Props.Block(m, "Counter", Vector3.new(S.Width - 4, 3.5, S.CounterDepth),
		CFrame.new(c.X, Y + 1.75, c.Z), T.ShopCounter, nil, true)
	Props.Block(m, "CounterTop", Vector3.new(S.Width - 3.4, 0.5, S.CounterDepth + 0.6),
		CFrame.new(c.X, Y + 3.75, c.Z), colors[1])
	Props.Tag(counter, "ShopStand", { ShopId = "Balls" })
	m.PrimaryPart = counter

	-- back wall + corner posts
	Props.Block(m, "BackWall", Vector3.new(S.Width, 12, 1.5), CFrame.new(c.X, Y + 6, backZ - 0.75), colors[1], nil, true)
	for _, side in { -1, 1 } do
		Props.Block(m, "Post", Vector3.new(1.2, 9.4, 1.2), CFrame.new(c.X + side * (halfW - 0.6), Y + 4.7, c.Z - 1), colors[2])
		Props.Block(m, "SideWall", Vector3.new(1, 8, S.Depth - 2), CFrame.new(c.X + side * (halfW - 0.5), Y + 4, c.Z + S.Depth / 2),
			colors[2], nil, true)
	end

	-- striped awning sloping down from the back wall to over the counter
	local stripes = 6
	local stripeW = S.Width / stripes
	local depth = S.Depth + 3
	local tilt = math.rad(14)
	for k = 1, stripes do
		local x = c.X - halfW + stripeW * (k - 0.5)
		local cf = CFrame.new(x, Y + 11, c.Z + S.Depth / 2 - 1) * CFrame.Angles(-tilt, 0, 0)
		Props.Block(m, "Awning", Vector3.new(stripeW, 0.6, depth), cf, if k % 2 == 0 then colors[2] else colors[1])
	end

	-- name board above the awning, facing the street (-Z)
	local boardPos = Vector3.new(c.X, Y + 16, backZ - 2)
	local board = Props.Part({ Parent = m, Name = "ShopSign", Size = Vector3.new(S.Width, 5, 1),
		CFrame = CFrame.lookAt(boardPos, boardPos + Vector3.new(0, 0, -1)), Color = T.ShopSign })
	Props.Part({ Parent = m, Name = "ShopSignTrim", Size = Vector3.new(S.Width + 1, 6, 0.5),
		CFrame = CFrame.lookAt(boardPos + Vector3.new(0, 0, 0.4), boardPos + Vector3.new(0, 0, -1)),
		Color = colors[1], Material = WorldTheme.AccentMaterial })
	local _ = board -- blank coloured board (no world text)

	-- display balls on the counter
	local ballColors = { Color3.fromRGB(210, 240, 60), Color3.fromRGB(255, 90, 90), Color3.fromRGB(80, 170, 255),
		Color3.fromRGB(120, 255, 200), Color3.fromRGB(255, 210, 60) }
	for k, col in ballColors do
		Props.Ball(m, "Display", Vector3.new(c.X - 6 + (k - 1) * 3, Y + 4.8, c.Z), 1.6, col,
			if k >= 4 then WorldTheme.AccentMaterial else nil)
	end
end

local function buildTraining(parent: Instance)
	local c: Vector3 = Layout.Training.Center
	local half = Plaza.TrainingMat / 2
	local m = Props.Model(parent, "TrainingArea")
	-- the tagged part is the mat: TrainingService measures range from it (whole area is one station)
	local mat = Props.Slab(m, "TrainingMat", c.X - half, c.X + half, c.Z - half, c.Z + half, Y + 0.2, 0.2,
		T.TrainingMat, nil, false)
	Props.Tag(mat, "TrainingStation", { StationId = "Main" })
	m.PrimaryPart = mat
	-- white border lines (decal-thin)
	for _, side in { -1, 1 } do
		Props.Slab(m, "MatLine", c.X - half, c.X + half, c.Z + side * half - 0.5, c.Z + side * half + 0.5, Y + 0.24, 0.04,
			T.TrainingLine, nil, false)
		Props.Slab(m, "MatLine", c.X + side * half - 0.5, c.X + side * half + 0.5, c.Z - half, c.Z + half, Y + 0.24, 0.04,
			T.TrainingLine, nil, false)
	end

	-- pull-up bar at the back left of the mat
	local px, pz = c.X - 5, c.Z + half - 4
	for _, side in { -1, 1 } do
		Props.Cylinder(m, "Upright", Vector3.new(px + side * 4.5, Y + 0.2, pz), 9, 1, T.EquipmentAccent)
	end
	Props.Part({ Parent = m, Name = "Bar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 0.6, 0.6),
		CFrame = CFrame.new(px, Y + 8.8, pz), Color = Color3.fromRGB(230, 230, 240) })

	-- ball throwing machine at the back right, aimed down the field
	local mx, mz = c.X + 6, c.Z + half - 5
	Props.Block(m, "StationBody", Vector3.new(6, 5, 5), CFrame.new(mx, Y + 2.7, mz), T.Equipment, nil, true)
	Props.Block(m, "Hopper", Vector3.new(5, 2, 4), CFrame.new(mx, Y + 6, mz), T.EquipmentAccent)
	Props.Part({ Parent = m, Name = "Tube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.2, 2.2),
		CFrame = CFrame.new(mx, Y + 4, mz - 3) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(15)),
		Color = T.EquipmentAccent })
	for k = 0, 2 do
		Props.Ball(m, "Ball", Vector3.new(mx + (k - 1) * 1.3, Y + 7.4, mz + (k - 1) * 1.1), 1.1, Color3.fromRGB(210, 240, 60))
	end

	-- three agility cones along the front of the mat
	for k = -1, 1 do
		Props.Cylinder(m, "Cone", Vector3.new(c.X + k * 7, Y + 0.2, c.Z - half + 3), 2, 1.4, Color3.fromRGB(255, 140, 40))
	end

	-- sign across the back edge, facing the street (-Z)
	Props.Sign(m, "TrainingSign", Vector3.new(c.X, Y, c.Z + half + 1), Vector3.new(0, 0, -1), Vector3.new(20, 4, 0.6),
		10, T.ShopSign, T.EquipmentAccent, nil) -- blank board (no world text)
end

local function buildLawn(parent: Instance)
	local l = Plaza.Lawn
	-- dog-park lawn = RunawayArea (thin, so EventService stands runaways on its top surface)
	local lawn = Props.Slab(parent, "RunawayArea", l.MinX, l.MaxX, l.MinZ, l.MaxZ, Y + 0.1, 0.1, T.Lawn, nil, false)
	Props.Tag(lawn, "RunawayArea")
	Props.Slab(parent, "LawnEdge", l.MinX - 1, l.MaxX + 1, l.MinZ - 1, l.MaxZ + 1, Y + 0.05, 0.05, T.LawnEdge, nil, false)
end

local function buildSquirrelPath(parent: Instance)
	local f = Props.Folder(parent, "SquirrelPath")
	local l = Plaza.Lawn
	local x0, x1 = l.MinX - 2.5, l.MaxX + 3
	local z0, z1 = l.MinZ - 3, l.MaxZ + 2
	local zm = (z0 + z1) / 2
	local xm = (x0 + x1) / 2
	-- clockwise loop on the paving just outside the lawn
	local points = {
		Vector3.new(x0, Y, z0), Vector3.new(xm, Y, z0), Vector3.new(x1, Y, z0), Vector3.new(x1, Y, zm),
		Vector3.new(x1, Y, z1), Vector3.new(xm, Y, z1), Vector3.new(x0, Y, z1), Vector3.new(x0, Y, zm),
	}
	for i, p in points do
		local wp = Props.Part({ Parent = f, Name = "Waypoint" .. i, Size = Vector3.new(1, 0.2, 1),
			CFrame = CFrame.new(p + Vector3.new(0, 0.1, 0)), Transparency = 1, Query = false, Shadow = false })
		Props.Tag(wp, "SquirrelPath", { Order = i })
	end
end

local function buildSpawns(parent: Instance)
	local f = Props.Folder(parent, "Spawns")
	local half = Plaza.SpawnSize / 2
	for i, pos in Plaza.Spawns do
		local s = Instance.new("SpawnLocation")
		s.Name = "PlazaSpawn" .. i
		s.Anchored = true
		s.Size = Vector3.new(Plaza.SpawnSize, 0.4, Plaza.SpawnSize)
		s.CFrame = CFrame.new(pos.X, Y + 0.2, pos.Z)
		s.Color = T.Spawn
		s.Material = WorldTheme.AccentMaterial
		s.TopSurface = Enum.SurfaceType.Smooth
		s.BottomSurface = Enum.SurfaceType.Smooth
		s.Neutral = true
		s.AllowTeamChangeOnTouch = false
		s.Duration = 0
		s.Enabled = true
		s.CanCollide = true
		s.Parent = f
		Props.PartCount += 1
		Props.Tag(s, "PlazaSpawn")
		-- white rim
		Props.Slab(f, "SpawnRim", pos.X - half - 0.8, pos.X + half + 0.8, pos.Z - half - 0.8, pos.Z + half + 0.8,
			Y + 0.1, 0.1, Color3.new(1, 1, 1), nil, false)
	end
end

function Plaza.Build(parent: Instance)
	local folder = Props.Folder(parent, "Plaza")
	Props.Slab(folder, "PlazaFloor", P.MinX, P.MaxX, P.MinZ, P.MaxZ, Y, 1, T.Paving)
	buildLawn(folder)
	buildSquirrelPath(folder)
	buildSpawns(folder)
	buildShop(Props.Folder(folder, "Shop"))
	buildTraining(Props.Folder(folder, "Training"))
end

return Plaza
