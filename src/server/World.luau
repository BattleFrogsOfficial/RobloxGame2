-- Builds the static map in code: ocean basin, beaches, ramps, cliffs,
-- border walls, decor and lighting. The WATER itself is drawn by each client
-- (see client/Ocean.luau) so a parted sea is only visible to its owner.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voxel = require(Shared.Voxel)

local World = {}

local O = Config.Ocean
local MAP_HALF_X = 215
local MAP_HALF_Z = 265
local BEACH_END = 150 -- beach sand runs from the shore (110) to here

World.PenWidth = Config.Pen.Width
World.PenDepth = Config.Pen.Depth
World.Pens = {} -- { cf: CFrame, side: number }

local SAND = Color3.fromRGB(230, 200, 140)
local SAND_LIGHT = Color3.fromRGB(245, 222, 170)
local SAND_DARK = Color3.fromRGB(221, 190, 130)
local GRASS = Color3.fromRGB(95, 200, 70)
local GRASS_DARK = Color3.fromRGB(86, 188, 62)
local ROCK = Color3.fromRGB(150, 155, 165)

local map: Folder

local function block(name: string, minV: Vector3, maxV: Vector3, color: Color3, material: Enum.Material?, studs: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = maxV - minV
	p.Position = (minV + maxV) / 2
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	if studs then
		p.TopSurface = Enum.SurfaceType.Studs
	else
		p.TopSurface = Enum.SurfaceType.Smooth
	end
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
			block(name, Vector3.new(x, minV.Y, z), Vector3.new(x1, maxV.Y, z1), (ix + iz) % 2 == 0 and colorA or colorB, Enum.Material.SmoothPlastic)
			z = z1
			iz += 1
		end
		x = x1
		ix += 1
	end
end

local function surfaceText(part: BasePart, text: string, face: Enum.NormalId, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
end

local function buildGround()
	-- North and south land (beach + grass). Thick so nothing shows under it.
	for _, s in { 1, -1 } do
		local function zr(a, b)
			return math.min(s * a, s * b), math.max(s * a, s * b)
		end
		local z0, z1 = zr(O.ShoreZ, BEACH_END)
		tiles("Beach", Vector3.new(-MAP_HALF_X, -30, z0), Vector3.new(MAP_HALF_X, 0, z1), SAND, SAND_DARK, 20)
		z0, z1 = zr(BEACH_END, MAP_HALF_Z)
		tiles("Grass", Vector3.new(-MAP_HALF_X, -30, z0), Vector3.new(MAP_HALF_X, 0, z1), GRASS, GRASS_DARK, 23)

		-- Split zone: a lighter sand strip along the shoreline.
		z0, z1 = zr(O.ShoreZ + 1.5, O.ShoreZ + O.SplitZoneDepth)
		local strip = block("SplitZone", Vector3.new(-O.HalfX, 0, z0), Vector3.new(O.HalfX, 0.06, z1), SAND_LIGHT, Enum.Material.SmoothPlastic)
		strip.CanCollide = false
		strip.CanQuery = false

		-- Coral-red lip on the shore edge, like a warning stripe.
		z0, z1 = zr(O.ShoreZ, O.ShoreZ + 1.5)
		block("ShoreLip", Vector3.new(-O.HalfX, 0, z0), Vector3.new(O.HalfX, 0.3, z1), Color3.fromRGB(235, 90, 75), Enum.Material.SmoothPlastic)

		-- Labels painted on the split zone.
		for x = -150, 150, 75 do
			local label = Instance.new("Part")
			label.Name = "SplitLabel"
			label.Anchored = true
			label.CanCollide = false
			label.CanQuery = false
			label.Transparency = 1
			label.Size = Vector3.new(36, 0.1, 7)
			label.CFrame = CFrame.new(x, 0.1, s * (O.ShoreZ + O.SplitZoneDepth / 2)) * CFrame.Angles(0, s > 0 and 0 or math.pi, 0)
			label.Parent = map
			surfaceText(label, "🌊 SPLIT ZONE 🌊", Enum.NormalId.Top, Color3.fromRGB(40, 120, 220))
		end
	end

	-- Seabed
	tiles("Seabed", Vector3.new(-O.HalfX, -30, -O.ShoreZ), Vector3.new(O.HalfX, O.SeabedY, O.ShoreZ), Color3.fromRGB(205, 180, 130), Color3.fromRGB(194, 168, 118), 20)

	-- Ramps from each shore down to the seabed (thin tilted slabs).
	local drop = -O.SeabedY
	local len = math.sqrt(O.RampLength ^ 2 + drop ^ 2)
	local angle = math.atan2(drop, O.RampLength)
	for _, s in { 1, -1 } do
		local midZ = s * (O.ShoreZ - O.RampLength / 2)
		local ramp = Instance.new("Part")
		ramp.Name = "Ramp"
		ramp.Anchored = true
		ramp.Size = Vector3.new(O.HalfX * 2, 1, len)
		-- Tilt so the shore end is high. Positive X-rotation lowers the +Z end.
		ramp.CFrame = CFrame.new(0, O.SeabedY / 2 - 0.5, midZ) * CFrame.Angles(s > 0 and -angle or angle, 0, 0)
		ramp.Color = SAND
		ramp.Material = Enum.Material.Plastic
		ramp.TopSurface = Enum.SurfaceType.Smooth
		ramp.Parent = map
	end

	-- Rocky cliffs capping both ends of the ocean.
	for _, sx in { 1, -1 } do
		local x0, x1 = math.min(sx * O.HalfX, sx * MAP_HALF_X), math.max(sx * O.HalfX, sx * MAP_HALF_X)
		block("Cliff", Vector3.new(x0, -30, -O.ShoreZ), Vector3.new(x1, 4, O.ShoreZ), ROCK, Enum.Material.Slate)
	end

	-- Border walls: blue sides with a green rim, like a toy box.
	local H = 16
	local T = 8
	local walls = {
		{ Vector3.new(-MAP_HALF_X - T, -2, -MAP_HALF_Z - T), Vector3.new(MAP_HALF_X + T, H, -MAP_HALF_Z) },
		{ Vector3.new(-MAP_HALF_X - T, -2, MAP_HALF_Z), Vector3.new(MAP_HALF_X + T, H, MAP_HALF_Z + T) },
		{ Vector3.new(-MAP_HALF_X - T, -2, -MAP_HALF_Z), Vector3.new(-MAP_HALF_X, H, MAP_HALF_Z) },
		{ Vector3.new(MAP_HALF_X, -2, -MAP_HALF_Z), Vector3.new(MAP_HALF_X + T, H, MAP_HALF_Z) },
	}
	for _, w in walls do
		block("Wall", w[1], w[2], Color3.fromRGB(45, 125, 235), Enum.Material.SmoothPlastic)
		block("WallRim", Vector3.new(w[1].X, H, w[1].Z), Vector3.new(w[2].X, H + 2, w[2].Z), Color3.fromRGB(120, 215, 60), Enum.Material.SmoothPlastic)
	end
end

local function buildDecor()
	local rng = Random.new(7)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = map

	-- Palm trees along both beaches (kept away from the split zone).
	for _, s in { 1, -1 } do
		for x = -195, 195, 65 do
			local palm = Voxel.palm(rng:NextInteger(1, 1e6))
			palm:PivotTo(CFrame.new(x + rng:NextNumber(-8, 8), 0, s * (BEACH_END - 6)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
			palm.Parent = decor
		end
	end

	-- Beach umbrellas and towels between the palms.
	local brights = {
		Color3.fromRGB(255, 90, 90),
		Color3.fromRGB(255, 200, 60),
		Color3.fromRGB(80, 180, 255),
		Color3.fromRGB(190, 110, 255),
	}
	local n = 0
	for _, s in { 1, -1 } do
		for x = -162, 162, 65 do
			n += 1
			local m = Instance.new("Model")
			m.Name = "Umbrella"
			local c1 = brights[n % #brights + 1]
			local base = CFrame.new(x + rng:NextNumber(-6, 6), 0, s * (BEACH_END - 9)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			local pole = Voxel.addPart(m, Vector3.new(0.5, 8, 0.5), base * CFrame.new(0, 4, 0), Color3.fromRGB(240, 240, 240))
			pole.CanCollide = true
			for layer, size in { 10, 7, 4 } do
				Voxel.addPart(m, Vector3.new(size, 0.7, size), base * CFrame.new(0, 7.3 + layer * 0.7, 0), layer % 2 == 1 and c1 or Color3.fromRGB(250, 250, 250))
			end
			Voxel.addPart(m, Vector3.new(4, 0.15, 8), base * CFrame.new(4.5, 0.08, 0), brights[(n + 1) % #brights + 1])
			Voxel.addPart(m, Vector3.new(4, 0.16, 1.2), base * CFrame.new(4.5, 0.09, 2), Color3.fromRGB(250, 250, 250))
			m.Parent = decor
		end
	end

	-- A lighthouse on the east cliff.
	do
		local m = Instance.new("Model")
		m.Name = "Lighthouse"
		local base = CFrame.new((O.HalfX + MAP_HALF_X) / 2, 4, 0)
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
		light.Range = 40
		light.Brightness = 2
		light.Parent = lamp
		for _, c in { { 2.5, 2.5 }, { -2.5, 2.5 }, { 2.5, -2.5 }, { -2.5, -2.5 } } do
			Voxel.addPart(m, Vector3.new(0.6, 4, 0.6), base * CFrame.new(c[1], y + 3, c[2]), Color3.fromRGB(60, 60, 70))
		end
		Voxel.addPart(m, Vector3.new(8, 1.5, 8), base * CFrame.new(0, y + 5.75, 0), Color3.fromRGB(235, 70, 60))
		Voxel.addPart(m, Vector3.new(5, 1.5, 5), base * CFrame.new(0, y + 7.25, 0), Color3.fromRGB(235, 70, 60))
		Voxel.addPart(m, Vector3.new(2, 1.5, 2), base * CFrame.new(0, y + 8.75, 0), Color3.fromRGB(235, 70, 60))
		m.Parent = decor
	end

	-- Boulders on the west cliff.
	for _ = 1, 9 do
		local size = rng:NextNumber(4, 10)
		local rock = Voxel.addPart(decor, Vector3.new(size, size * 0.7, size * 0.9), CFrame.new(-(O.HalfX + MAP_HALF_X) / 2 + rng:NextNumber(-10, 10), 4 + size * 0.3, rng:NextNumber(-95, 95)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), ROCK:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0.05, 0.3)))
		rock.CanCollide = true
	end

	-- Seabed: coral, rocks and kelp, only visible inside a parted corridor.
	local coralColors = {
		Color3.fromRGB(255, 110, 130),
		Color3.fromRGB(255, 170, 60),
		Color3.fromRGB(170, 100, 255),
		Color3.fromRGB(90, 220, 200),
	}
	for _ = 1, 90 do
		local x = rng:NextNumber(-O.HalfX + 6, O.HalfX - 6)
		local z = rng:NextNumber(-O.ShoreZ + O.RampLength + 4, O.ShoreZ - O.RampLength - 4)
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

local function buildPensLayout()
	for _, s in { 1, -1 } do
		for _, x in { -153, -51, 51, 153 } do
			local pos = Vector3.new(x, 0, s * 210)
			-- Pen faces the beach: its local -Z (front/gate) points toward the ocean.
			local cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -s))
			table.insert(World.Pens, { cf = cf, side = s })
		end
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
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.25
		atm.Haze = 0.5
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
	-- Template spawns (e.g. the Baseplate one at the origin) sit mid-ocean.
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") and not inst:IsDescendantOf(map) then
			inst:Destroy()
		end
	end

	buildGround()
	buildDecor()
	buildPensLayout()
	setupLighting()

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.Position = Vector3.new(0, 0.2, O.ShoreZ + 30)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = map
end

-- Geometry helpers shared with the split logic.
function World.inOcean(pos: Vector3): boolean
	-- No height test: jumping over the water must not count as dry land.
	return math.abs(pos.X) < O.HalfX and math.abs(pos.Z) < O.ShoreZ
end

function World.inSplitZone(pos: Vector3): boolean
	local az = math.abs(pos.Z)
	return az >= O.ShoreZ and az <= O.ShoreZ + O.SplitZoneDepth + 2 and math.abs(pos.X) <= O.HalfX - 2 and pos.Y > -3
end

return World
