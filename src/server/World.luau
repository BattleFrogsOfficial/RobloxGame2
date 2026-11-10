-- Builds the static map in code. There is one shore (the line z = ShoreZ):
-- beach and bases on the +z side behind tall walls, and an ocean that runs
-- to the horizon on the -z side, framed by two rocky headlands.
--
-- The WATER itself is drawn by each client (see client/Ocean.luau) so a
-- parted sea is only visible to the player who parted it.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voxel = require(Shared.Voxel)

local World = {}

local O = Config.Ocean
local W = Config.World
local SHORE = O.ShoreZ
local BACK = SHORE + W.LandDepth
local BEACH_END = SHORE + W.BeachDepth
local SEABED_END = SHORE - O.Reach - 40
local WALL_T = 10

World.PenWidth = Config.Pen.Width
World.PenDepth = Config.Pen.Depth
World.Pens = {} -- { cf: CFrame }
World.BoardSpots = {} -- CFrames for the three leaderboards (facing the ocean)
World.ShopSpot = CFrame.new() -- where the Buy button drops you, facing the shop

local SAND = Color3.fromRGB(230, 200, 140)
local SAND_DARK = Color3.fromRGB(221, 190, 130)
local SAND_LIGHT = Color3.fromRGB(245, 222, 170)
local GRASS = Color3.fromRGB(95, 200, 70)
local GRASS_DARK = Color3.fromRGB(86, 188, 62)
local ROCK = Color3.fromRGB(150, 155, 165)

local map: Folder

local function block(name: string, minV: Vector3, maxV: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = maxV - minV
	p.CFrame = CFrame.new((minV + maxV) / 2)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = map
	return p
end

-- Checkerboard of two shades filling a box (Roblox no longer draws stud
-- textures, so the toy-brick look comes from the tile pattern instead).
local function tiles(name: string, minV: Vector3, maxV: Vector3, colorA: Color3, colorB: Color3, tile: number)
	local ix = 0
	local x = minV.X
	while x < maxV.X - 0.01 do
		local x1 = math.min(x + tile, maxV.X)
		local iz = 0
		local z = minV.Z
		while z < maxV.Z - 0.01 do
			local z1 = math.min(z + tile, maxV.Z)
			block(name, Vector3.new(x, minV.Y, z), Vector3.new(x1, maxV.Y, z1), (ix + iz) % 2 == 0 and colorA or colorB)
			z = z1
			iz += 1
		end
		x = x1
		ix += 1
	end
end

local function buildLand()
	local H = O.HalfX
	tiles("Beach", Vector3.new(-H, -30, SHORE), Vector3.new(H, 0, BEACH_END), SAND, SAND_DARK, 20)
	tiles("Grass", Vector3.new(-H, -30, BEACH_END), Vector3.new(H, 0, BACK), GRASS, GRASS_DARK, 23)

	-- Split zone: a lighter sand strip along the shoreline.
	local strip = block("SplitZone", Vector3.new(-H, 0, SHORE + 1.5), Vector3.new(H, 0.06, SHORE + O.SplitZoneDepth), SAND_LIGHT)
	strip.CanCollide = false
	strip.CanQuery = false
	-- Coral-red lip on the shore edge, like a warning stripe.
	block("ShoreLip", Vector3.new(-H, 0, SHORE), Vector3.new(H, 0.3, SHORE + 1.5), Color3.fromRGB(235, 90, 75))
	-- Tall walls on the three land sides. The ocean side stays open.
	local top = W.WallHeight
	local blue, rim = Color3.fromRGB(45, 125, 235), Color3.fromRGB(120, 215, 60)
	local walls = {
		{ Vector3.new(-H - WALL_T, -2, BACK), Vector3.new(H + WALL_T, top, BACK + WALL_T) },
		{ Vector3.new(-H - WALL_T, -2, SHORE), Vector3.new(-H, top, BACK) },
		{ Vector3.new(H, -2, SHORE), Vector3.new(H + WALL_T, top, BACK) },
	}
	for _, w in walls do
		block("Wall", w[1], w[2], blue)
		block("WallRim", Vector3.new(w[1].X, top, w[1].Z), Vector3.new(w[2].X, top + 3, w[2].Z), rim)
	end
end

local function buildSea()
	local H = O.HalfX
	-- Seabed the corridors can reach, then a dark floor far beyond it so the
	-- water has something under it all the way to the horizon.
	tiles("Seabed", Vector3.new(-H, -30, SEABED_END), Vector3.new(H, O.SeabedY, SHORE), Color3.fromRGB(205, 180, 130), Color3.fromRGB(194, 168, 118), 20)
	local deep = Color3.fromRGB(20, 60, 120)
	for iz = 0, 1 do
		local z1 = SEABED_END - iz * 2040
		local floor = block("DeepFloor", Vector3.new(-H, O.SeabedY - 5, z1 - 2040), Vector3.new(H, O.SeabedY - 0.5, z1), deep)
		floor.CanQuery = false
		floor.CastShadow = false
	end

	-- Ramp from the shore down to the seabed (a thin tilted slab).
	local drop = -O.SeabedY
	local len = math.sqrt(O.RampLength ^ 2 + drop ^ 2)
	local angle = math.atan2(drop, O.RampLength)
	local ramp = Instance.new("Part")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.Size = Vector3.new(H * 2, 1, len)
	-- The shore (+Z) end is the high one; a negative X-rotation raises +Z.
	ramp.CFrame = CFrame.new(0, O.SeabedY / 2 - 0.5, SHORE - O.RampLength / 2) * CFrame.Angles(-angle, 0, 0)
	ramp.Color = SAND
	ramp.Material = Enum.Material.SmoothPlastic
	ramp.TopSurface = Enum.SurfaceType.Smooth
	ramp.Parent = map

	-- Sheer rock walls run straight out from both sides of the land, as tall
	-- as the land walls the whole way, so the sea is one long channel and
	-- nothing can be seen past its sides. They start exactly where the blue
	-- walls end (no overlap) and their inner faces are flush with them.
	local rng = Random.new(11)
	local segment = 68
	for _, sx in { 1, -1 } do
		for i = 0, 59 do
			local z1 = SHORE - i * segment
			local z0 = z1 - segment
			local height = W.WallHeight + 3 + rng:NextNumber(-2, 6)
			local depth = WALL_T + 30 + rng:NextNumber(0, 14)
			local x0, x1 = sx * H, sx * (H + depth)
			block("Cliff", Vector3.new(math.min(x0, x1), -30, z0), Vector3.new(math.max(x0, x1), height, z1), ROCK:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.22)), Enum.Material.Slate)
		end
	end
end

local function signText(part: BasePart, title: string, subtitle: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = part
	local function line(text: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.Parent = gui
	end
	if subtitle then
		line(title, 0.04, 0.56, Color3.new(1, 1, 1))
		line(subtitle, 0.6, 0.36, Color3.fromRGB(255, 225, 110))
	else
		line(title, 0.1, 0.8, Color3.new(1, 1, 1))
	end
end
World.signText = signText

-- The shop on the beach: Luck and Speed. Its prompt opens the menu on the
-- client (see the "Menu" attribute).
local function buildShop()
	local pos = Vector3.new(-O.HalfX + 24, 0, SHORE + 30)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)) -- counter faces the middle of the beach
	local stall = Voxel.stall(14, 9, Color3.fromRGB(80, 200, 110))
	stall.Name = "Shop"
	stall:PivotTo(cf)
	signText(stall:FindFirstChild("Sign") :: BasePart, "SHOP", "Luck & Speed")
	-- Wares on the counter.
	for i, name in { "luck", "potion", "clock" } do
		local item = Voxel.icon(name)
		item:ScaleTo(0.7)
		item:PivotTo(cf * CFrame.new(-4.5 + (i - 1) * 4.5, 3.5, -3.5))
		item.Parent = stall
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Shop"
	prompt.ObjectText = "Luck & Speed"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Menu", "Upgrades")
	prompt.Parent = stall:FindFirstChild("Counter")
	stall.Parent = map
	local stand = (cf * CFrame.new(0, 3.5, -13)).Position
	World.ShopSpot = CFrame.lookAt(stand, Vector3.new(pos.X, stand.Y, pos.Z))
end

local function buildDecor()
	local rng = Random.new(7)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = map
	local H = O.HalfX

	-- Palm trees along the back of the beach.
	for x = -H + 20, H - 20, 62 do
		local palm = Voxel.palm(rng:NextInteger(1, 1e6))
		palm:PivotTo(CFrame.new(x + rng:NextNumber(-8, 8), 0, BEACH_END - 5) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
		palm.Parent = decor
	end

	-- Beach umbrellas and towels between the palms.
	local brights = {
		Color3.fromRGB(255, 90, 90),
		Color3.fromRGB(255, 200, 60),
		Color3.fromRGB(80, 180, 255),
		Color3.fromRGB(190, 110, 255),
	}
	local n = 0
	for x = -H + 50, H - 50, 62 do
		n += 1
		local m = Instance.new("Model")
		m.Name = "Umbrella"
		local c1 = brights[n % #brights + 1]
		local base = CFrame.new(x + rng:NextNumber(-6, 6), 0, BEACH_END - 12) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local pole = Voxel.addPart(m, Vector3.new(0.5, 8, 0.5), base * CFrame.new(0, 4, 0), Color3.fromRGB(240, 240, 240))
		pole.CanCollide = true
		for layer, size in { 10, 7, 4 } do
			Voxel.addPart(m, Vector3.new(size, 0.7, size), base * CFrame.new(0, 7.3 + layer * 0.7, 0), layer % 2 == 1 and c1 or Color3.fromRGB(250, 250, 250))
		end
		Voxel.addPart(m, Vector3.new(4, 0.15, 8), base * CFrame.new(4.5, 0.08, 0), brights[(n + 1) % #brights + 1])
		Voxel.addPart(m, Vector3.new(4, 0.16, 1.2), base * CFrame.new(4.5, 0.09, 2), Color3.fromRGB(250, 250, 250))
		m.Parent = decor
	end

	-- A lighthouse on top of the east cliff.
	do
		local m = Instance.new("Model")
		m.Name = "Lighthouse"
		local base = CFrame.new(H + 20, W.WallHeight + 1, SHORE - 34)
		local y = 0
		for i = 1, 7 do
			local w = 13 - i
			local part = Voxel.addPart(m, Vector3.new(w, 5, w), base * CFrame.new(0, y + 2.5, 0), i % 2 == 1 and Color3.fromRGB(235, 70, 60) or Color3.fromRGB(245, 245, 245))
			part.CanCollide = true
			y += 5
		end
		Voxel.addPart(m, Vector3.new(10, 1, 10), base * CFrame.new(0, y + 0.5, 0), Color3.fromRGB(60, 60, 70))
		local lamp = Voxel.addPart(m, Vector3.new(4, 4, 4), base * CFrame.new(0, y + 3, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 240, 170)
		light.Range = 50
		light.Brightness = 2
		light.Parent = lamp
		for _, c in { { 2.5, 2.5 }, { -2.5, 2.5 }, { 2.5, -2.5 }, { -2.5, -2.5 } } do
			Voxel.addPart(m, Vector3.new(0.6, 4, 0.6), base * CFrame.new(c[1], y + 3, c[2]), Color3.fromRGB(60, 60, 70))
		end
		for i, w in { 8, 5, 2 } do
			Voxel.addPart(m, Vector3.new(w, 1.5, w), base * CFrame.new(0, y + 4.25 + i * 1.5, 0), Color3.fromRGB(235, 70, 60))
		end
		m.Parent = decor
	end

	-- Seabed: coral, rocks and kelp, only visible inside a parted corridor.
	local coralColors = {
		Color3.fromRGB(255, 110, 130),
		Color3.fromRGB(255, 170, 60),
		Color3.fromRGB(170, 100, 255),
		Color3.fromRGB(90, 220, 200),
	}
	for _ = 1, 150 do
		local x = rng:NextNumber(-H + 6, H - 6)
		local z = rng:NextNumber(SHORE - O.Reach - 20, SHORE - O.RampLength - 4)
		local base = CFrame.new(x, O.SeabedY, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local kind = rng:NextInteger(1, 3)
		local m = Instance.new("Model")
		m.Name = "SeabedDecor"
		if kind == 1 then
			local c = coralColors[rng:NextInteger(1, #coralColors)]
			for i = 1, rng:NextInteger(3, 5) do
				local h = rng:NextNumber(1.5, 4)
				Voxel.addPart(m, Vector3.new(1, h, 1), base * CFrame.new(rng:NextNumber(-1.5, 1.5), h / 2, rng:NextNumber(-1.5, 1.5)), c)
				if i == 1 then
					Voxel.addPart(m, Vector3.new(2, 1, 2), base * CFrame.new(0, h, 0), c:Lerp(Color3.new(1, 1, 1), 0.3))
				end
			end
		elseif kind == 2 then
			local s = rng:NextNumber(2, 5)
			Voxel.addPart(m, Vector3.new(s, s * 0.6, s * 0.8), base * CFrame.new(0, s * 0.3, 0), ROCK:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.3)))
		else
			for i = 0, rng:NextInteger(2, 4) do
				Voxel.addPart(m, Vector3.new(0.8, 2, 0.8), base * CFrame.new(math.sin(i) * 0.4, 1 + i * 2, 0), Color3.fromRGB(40, 150 + i * 10, 70))
			end
		end
		m.Parent = decor
	end
end

-- One row of bases along the back of the beach, gates facing the ocean.
local function layoutPens()
	local count = Config.MaxPlayers
	local z = SHORE + Config.Pen.FrontZ + Config.Pen.Depth / 2
	for i = 1, count do
		local x = (i - (count + 1) / 2) * Config.Pen.Spacing
		local pos = Vector3.new(x, 0, z)
		-- A pen's local -Z (its front, where the gate is) points at the sea.
		table.insert(World.Pens, { cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)) })
	end
	-- Leaderboards stand against the back wall, facing the ocean.
	for _, x in { -78, 0, 78 } do
		local pos = Vector3.new(x, 0, BACK - 3)
		table.insert(World.BoardSpots, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
	end
end

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		-- Haze blends the far ocean into the sky for an endless horizon.
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.3
		atm.Haze = 1.2
		atm.Color = Color3.fromRGB(200, 230, 255)
		atm.Decay = Color3.fromRGB(120, 180, 230)
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.4
		bloom.Size = 20
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
end

function World.build()
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	-- Template spawns (e.g. the Baseplate one at the origin) sit in the sea.
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") and not inst:IsDescendantOf(map) then
			inst:Destroy()
		end
	end

	buildLand()
	buildSea()
	buildDecor()
	buildShop()
	layoutPens()
	setupLighting()

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(0, 0.2, SHORE + 30)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = map
end

-- Geometry helpers shared with the split logic.

-- Anywhere seaward of the shoreline counts, at any height, so jumping over
-- the water is not "dry land".
function World.inOcean(pos: Vector3): boolean
	return pos.Z < SHORE and math.abs(pos.X) <= O.HalfX
end

function World.inSplitZone(pos: Vector3): boolean
	return pos.Z >= SHORE and pos.Z <= SHORE + O.SplitZoneDepth + 2 and math.abs(pos.X) <= O.HalfX - 24 and pos.Y > -3
end

return World
