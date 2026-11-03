--!strict
-- The plaza / dog-park hub between the street and the throw line.
--
--   x: -120 ........ -104 | -54 ...... 54 | 98 ........ 120
--      SHOP COLUMN (4)    |  running track |  TRAINING (2) + LEADERBOARD
--      Balls/Boosts/      |  around the    |  PullUpBar, ThrowingMachine
--      Yard/Cosmetics     |  RunawayArea   |  (Sprint gate sits on the track)
--   Spawns just south of the street, benches/trees only in the margins.
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

-- All plaza rectangles derive from the Layout.Plaza bounds (mirrored by tools/world_bounds.py).
Plaza.Lawn = { MinX = -40, MaxX = 40, MinZ = P.MinZ + 28, MaxZ = P.MinZ + 72 } -- -12..32
Plaza.TrackOuter = { MinX = -54, MaxX = 54, MinZ = P.MinZ + 18, MaxZ = P.MinZ + 82 } -- -22..42
Plaza.TrackWidth = 8
Plaza.Spawns = { Vector3.new(-16, 0, P.MinZ + 9), Vector3.new(16, 0, P.MinZ + 9) }
Plaza.SpawnSize = 10
Plaza.ShopIds = { "Balls", "Boosts", "Yard", "Cosmetics" }
Plaza.ShopNames = { Balls = "BALLS", Boosts = "BOOSTS", Yard = "YARD UPGRADES", Cosmetics = "BONE SHOP" }
Plaza.ShopColumn = { MinX = P.MinX, MaxX = P.MinX + 16, CentersZ = { -26, -4, 18, 40 }, Width = 18 }
Plaza.Stations = {
	PullUpBar = Vector3.new(P.MaxX - 10, 0, -26),
	ThrowingMachine = Vector3.new(P.MaxX - 10, 0, 2),
}
Plaza.StationMat = 12
Plaza.SprintGateZ = 10
Plaza.Leaderboard = { X = P.MaxX - 4, Z = 30, Width = 28, Height = 18, Bottom = 3 }

local function trackCenterX(): number
	return Plaza.TrackOuter.MaxX - Plaza.TrackWidth / 2
end

----------------------------------------------------------------------------------------------------
local function buildShop(parent: Instance, id: string, cz: number)
	local col = Plaza.ShopColumn
	local m = Props.Model(parent, "Shop_" .. id)
	local halfW = col.Width / 2
	local colors = T.ShopAwnings[id]
	local inner = col.MaxX -- counter front edge (faces +X, into the plaza)

	-- back wall + side posts
	Props.Block(m, "BackWall", Vector3.new(1.5, 12, col.Width), CFrame.new(col.MinX + 1.5, Y + 6, cz), colors[1], nil, true)
	for _, side in { -1, 1 } do
		Props.Block(m, "Post", Vector3.new(1.2, 9.4, 1.2), CFrame.new(inner - 1, Y + 4.7, cz + side * (halfW - 0.6)), colors[2])
	end
	-- counter (tagged ShopStand: services/client measure range from this part)
	local counter = Props.Block(m, "Counter", Vector3.new(4, 3.5, col.Width - 3), CFrame.new(inner - 2.5, Y + 1.75, cz),
		T.ShopCounter, nil, true)
	Props.Block(m, "CounterTop", Vector3.new(4.6, 0.5, col.Width - 2.4), CFrame.new(inner - 2.5, Y + 3.75, cz), colors[1])
	Props.Tag(counter, "ShopStand", { ShopId = id })
	m.PrimaryPart = counter

	-- striped, sloped awning (6 alternating stripes), high at the wall, low over the counter
	local stripes = 6
	local stripeW = col.Width / stripes
	local depth = 16
	local tilt = math.rad(14)
	for k = 1, stripes do
		local z = cz - halfW + stripeW * (k - 0.5)
		local cf = CFrame.new(col.MinX + depth / 2 + 1, Y + 11, z) * CFrame.Angles(0, 0, -tilt)
		Props.Block(m, "Awning", Vector3.new(depth + 2, 0.6, stripeW), cf, if k % 2 == 0 then colors[2] else colors[1])
	end

	-- name board above the awning, facing into the plaza (+X)
	local boardPos = Vector3.new(col.MinX + 3, Y + 16, cz)
	local board = Props.Part({ Parent = m, Name = "ShopSign", Size = Vector3.new(col.Width, 5, 1),
		CFrame = CFrame.lookAt(boardPos, boardPos + Vector3.new(1, 0, 0)), Color = T.ShopSign })
	Props.Part({ Parent = m, Name = "ShopSignTrim", Size = Vector3.new(col.Width + 1, 6, 0.5),
		CFrame = CFrame.lookAt(boardPos - Vector3.new(0.4, 0, 0), boardPos + Vector3.new(1, 0, 0)),
		Color = colors[1], Material = WorldTheme.AccentMaterial })
	Props.Label(board, Plaza.ShopNames[id] or id, { PixelsPerStud = 20 })

	-- a few display props on the counter
	if id == "Balls" then
		local ballColors = { Color3.fromRGB(210, 240, 60), Color3.fromRGB(255, 90, 90), Color3.fromRGB(80, 170, 255),
			Color3.fromRGB(120, 255, 200), Color3.fromRGB(255, 210, 60) }
		for k, c in ballColors do
			Props.Ball(m, "Display", Vector3.new(inner - 2.5, Y + 4.8, cz - 6 + (k - 1) * 3), 1.6, c,
				if k >= 4 then WorldTheme.AccentMaterial else nil)
		end
	elseif id == "Boosts" then
		for k = 0, 2 do
			Props.Cylinder(m, "Potion", Vector3.new(inner - 2.5, Y + 4, cz - 4 + k * 4), 2, 1.4,
				Color3.fromRGB(120, 230, 255), WorldTheme.AccentMaterial)
		end
	elseif id == "Yard" then
		Props.Block(m, "MiniFence", Vector3.new(0.6, 1.2, 8), CFrame.new(inner - 2.5, Y + 4.6, cz), Color3.new(1, 1, 1))
	else
		for k = 0, 2 do
			Props.Block(m, "Bone", Vector3.new(0.8, 0.8, 2.6), CFrame.new(inner - 2.5, Y + 4.4, cz - 4 + k * 4)
				* CFrame.Angles(0, math.rad(30), 0), Color3.fromRGB(255, 250, 235))
		end
	end
end

local function buildPullUpBar(parent: Instance, pos: Vector3)
	local m = Props.Model(parent, "PullUpBar")
	local half = Plaza.StationMat / 2
	local mat = Props.Slab(m, "StationMat", pos.X - half, pos.X + half, pos.Z - half, pos.Z + half, Y + 0.2, 0.2,
		T.Equipment, nil, false)
	Props.Tag(mat, "TrainingStation", { StationId = "PullUpBar" })
	m.PrimaryPart = mat
	for _, side in { -1, 1 } do
		Props.Cylinder(m, "Upright", Vector3.new(pos.X + 2, Y, pos.Z + side * 4.5), 9, 1, T.EquipmentAccent)
	end
	Props.Part({ Parent = m, Name = "Bar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 0.6, 0.6),
		CFrame = CFrame.new(pos.X + 2, Y + 8.6, pos.Z) * CFrame.Angles(0, math.pi / 2, 0), Color = Color3.fromRGB(230, 230, 240) })
	local sign = Props.Sign(m, "StationSign", Vector3.new(pos.X + 4.5, Y, pos.Z), Vector3.new(-1, 0, 0),
		Vector3.new(10, 3, 0.6), 9.8, T.ShopSign, T.EquipmentAccent, "PULL-UP BAR", { PixelsPerStud = 24 })
	sign.Name = "StationSignBoard"
end

local function buildThrowingMachine(parent: Instance, pos: Vector3)
	local m = Props.Model(parent, "ThrowingMachine")
	local half = Plaza.StationMat / 2
	local mat = Props.Slab(m, "StationMat", pos.X - half, pos.X + half, pos.Z - half, pos.Z + half, Y + 0.2, 0.2,
		T.Equipment, nil, false)
	Props.Tag(mat, "TrainingStation", { StationId = "ThrowingMachine" })
	m.PrimaryPart = mat
	Props.Block(m, "Body", Vector3.new(5, 5, 6), CFrame.new(pos.X + 3, Y + 2.7, pos.Z), T.Equipment, nil, true)
	Props.Block(m, "Hopper", Vector3.new(4, 2, 5), CFrame.new(pos.X + 3, Y + 6, pos.Z), T.EquipmentAccent)
	Props.Part({ Parent = m, Name = "Tube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 2.2, 2.2),
		CFrame = CFrame.new(pos.X - 0.5, Y + 4, pos.Z) * CFrame.Angles(0, 0, math.rad(-15)), Color = T.EquipmentAccent })
	for k = 0, 2 do
		Props.Ball(m, "Ball", Vector3.new(pos.X + 3 + (k - 1) * 1.2, Y + 7.4, pos.Z + (k - 1) * 1.3), 1.1,
			Color3.fromRGB(210, 240, 60))
	end
	Props.Sign(m, "StationSign", Vector3.new(pos.X + 4.5, Y, pos.Z), Vector3.new(-1, 0, 0),
		Vector3.new(12, 3, 0.6), 9.8, T.ShopSign, T.EquipmentAccent, "THROWING MACHINE", { PixelsPerStud = 24 })
end

local function buildTrack(parent: Instance)
	local f = Props.Folder(parent, "Track")
	local o, w = Plaza.TrackOuter, Plaza.TrackWidth
	local top = Y + 0.08
	Props.Slab(f, "TrackN", o.MinX, o.MaxX, o.MinZ, o.MinZ + w, top, 0.08, T.Track, nil, false)
	Props.Slab(f, "TrackS", o.MinX, o.MaxX, o.MaxZ - w, o.MaxZ, top, 0.08, T.Track, nil, false)
	Props.Slab(f, "TrackW", o.MinX, o.MinX + w, o.MinZ + w, o.MaxZ - w, top, 0.08, T.Track, nil, false)
	Props.Slab(f, "TrackE", o.MaxX - w, o.MaxX, o.MinZ + w, o.MaxZ - w, top, 0.08, T.Track, nil, false)

	-- Sprint start gate across the east straight. The tagged part is the start line on the track.
	local gx = trackCenterX()
	local gz = Plaza.SprintGateZ
	local m = Props.Model(f, "SprintGate")
	local line = Props.Slab(m, "SprintStart", o.MaxX - w, o.MaxX, gz - 1, gz + 1, Y + 0.12, 0.04, T.TrackLine, nil, false)
	Props.Tag(line, "TrainingStation", { StationId = "Sprint" })
	m.PrimaryPart = line
	for _, side in { -1, 1 } do
		Props.Block(m, "GatePillar", Vector3.new(1.4, 12, 1.4), CFrame.new(gx + side * (w / 2 + 2), Y + 6, gz), T.EquipmentAccent)
	end
	local boardPos = Vector3.new(gx, Y + 13, gz)
	local board = Props.Part({ Parent = m, Name = "SprintSign", Size = Vector3.new(w + 6, 3, 0.6),
		CFrame = CFrame.lookAt(boardPos, boardPos + Vector3.new(0, 0, -1)), Color = T.ShopSign })
	Props.Label(board, "SPRINT: RUN A LAP", { PixelsPerStud = 24 })
	Props.Label(board, "SPRINT: RUN A LAP", { Face = Enum.NormalId.Back, PixelsPerStud = 24 })
end

local function buildSquirrelPath(parent: Instance)
	local f = Props.Folder(parent, "SquirrelPath")
	local o, w = Plaza.TrackOuter, Plaza.TrackWidth
	local x0, x1 = o.MinX + w / 2, o.MaxX - w / 2
	local z0, z1 = o.MinZ + w / 2, o.MaxZ - w / 2
	local zm = (z0 + z1) / 2
	local third = (x1 - x0) / 3
	-- clockwise loop around the lawn, on the running track's centreline
	local points = {
		Vector3.new(x0, Y, z0), Vector3.new(x0 + third, Y, z0), Vector3.new(x1 - third, Y, z0), Vector3.new(x1, Y, z0),
		Vector3.new(x1, Y, zm), Vector3.new(x1, Y, z1), Vector3.new(x1 - third, Y, z1), Vector3.new(x0 + third, Y, z1),
		Vector3.new(x0, Y, z1), Vector3.new(x0, Y, zm),
	}
	for i, p in points do
		local wp = Props.Part({ Parent = f, Name = "Waypoint" .. i, Size = Vector3.new(1, 0.2, 1),
			CFrame = CFrame.new(p + Vector3.new(0, 0.1, 0)), Transparency = 1, Query = false, Shadow = false })
		Props.Tag(wp, "SquirrelPath", { Order = i })
	end
end

local function buildLeaderboard(parent: Instance)
	local lb = Plaza.Leaderboard
	local m = Props.Model(parent, "LeaderboardBoard")
	local center = Vector3.new(lb.X, Y + lb.Bottom + lb.Height / 2, lb.Z)
	local board = Props.Part({ Parent = m, Name = "Leaderboard", Size = Vector3.new(lb.Width, lb.Height, 1.5),
		CFrame = CFrame.lookAt(center, center + Vector3.new(-1, 0, 0)), Color = T.Leaderboard })
	Props.Part({ Parent = m, Name = "Trim", Size = Vector3.new(lb.Width + 1.4, lb.Height + 1.4, 0.8),
		CFrame = CFrame.lookAt(center + Vector3.new(0.6, 0, 0), center + Vector3.new(-1, 0, 0)),
		Color = T.LeaderboardTrim, Material = WorldTheme.AccentMaterial })
	for _, side in { -1, 1 } do
		Props.Block(m, "Leg", Vector3.new(1.4, lb.Bottom + 2, 1.4),
			CFrame.new(lb.X + 1.2, Y + (lb.Bottom + 2) / 2, lb.Z + side * (lb.Width / 2 - 2)), Color3.fromRGB(60, 60, 75))
	end
	m.PrimaryPart = board

	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.16)
	title.Font = WorldTheme.Font
	title.TextScaled = true
	title.TextColor3 = T.LeaderboardTrim
	title.Text = "TOP EARNERS ($/s)"
	title.Parent = gui

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromScale(0.03, 0.18)
	list.Size = UDim2.fromScale(0.94, 0.79)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = gui

	Props.Tag(board, "Leaderboard")
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

local function buildMargins(parent: Instance)
	local f = Props.Folder(parent, "Decor")
	-- benches between the track and the side columns, facing the lawn
	for _, side in { -1, 1 } do
		for _, z in { -6, 24 } do
			Props.Bench(f, Vector3.new(side * 72, Y, z), side * math.pi / 2, T.Bench, T.BenchLeg)
		end
	end
	-- trees in the four plaza corners (clear of pads, shops, stations, and the street opening)
	for _, side in { -1, 1 } do
		for _, z in { P.MaxZ - 8, P.MinZ + 8 } do
			local base = Vector3.new(side * 94, Y, z)
			Props.Slab(f, "Planter", base.X - 3, base.X + 3, base.Z - 3, base.Z + 3, Y + 1, 1, T.Planter, nil, false)
			Props.Tree(f, base + Vector3.new(0, 1, 0), 1.1, T.TreeTrunk, T.TreeLeaf)
		end
	end
	-- lawn corner bushes (inside the lawn rim, tiny)
	local l = Plaza.Lawn
	-- 2 studs in from the rim: EventService roams runaway dogs 4 studs inside the lawn, so the bushes stay out of it
	for _, c in { { l.MinX + 2, l.MinZ + 2 }, { l.MaxX - 2, l.MinZ + 2 }, { l.MinX + 2, l.MaxZ - 2 }, { l.MaxX - 2, l.MaxZ - 2 } } do
		Props.Bush(f, Vector3.new(c[1], Y, c[2]), 0.6, WorldTheme.Yard.Hedge)
	end
end

function Plaza.Build(parent: Instance)
	local folder = Props.Folder(parent, "Plaza")
	Props.Slab(folder, "PlazaFloor", P.MinX, P.MaxX, P.MinZ, P.MaxZ, Y, 1, T.Paving)

	-- dog-park lawn = RunawayArea (thin, so EventService stands runaways on its top surface)
	local l = Plaza.Lawn
	local lawn = Props.Slab(folder, "RunawayArea", l.MinX, l.MaxX, l.MinZ, l.MaxZ, Y + 0.1, 0.1, T.Lawn, nil, false)
	Props.Tag(lawn, "RunawayArea")

	buildTrack(folder)
	buildSquirrelPath(folder)
	buildSpawns(folder)

	local shops = Props.Folder(folder, "Shops")
	for i, id in Plaza.ShopIds do
		buildShop(shops, id, Plaza.ShopColumn.CentersZ[i])
	end

	local training = Props.Folder(folder, "Training")
	buildPullUpBar(training, Plaza.Stations.PullUpBar)
	buildThrowingMachine(training, Plaza.Stations.ThrowingMachine)

	buildLeaderboard(folder)
	buildMargins(folder)
end

return Plaza
