--!strict
-- WORLD THEME: every colour / material / font the world builder (src/server/World/**) uses.
-- Owned by agent D. Zone ground + accent colours live in Zones.luau (Theme) and are NOT duplicated here;
-- this file only adds the per-zone decoration palettes on top.
-- Look: bright, saturated, chunky low-poly cartoon. SmoothPlastic everywhere, Neon only for accents.
local WorldTheme = {}

local rgb = Color3.fromRGB

WorldTheme.Font = Enum.Font.FredokaOne
WorldTheme.BaseMaterial = Enum.Material.SmoothPlastic
WorldTheme.AccentMaterial = Enum.Material.Neon

-- One bold colour per yard (index 1..6). Used for the sign trim, gate arch and owner glow strip.
WorldTheme.YardColors = {
	rgb(255, 80, 80), -- 1 red
	rgb(255, 160, 40), -- 2 orange
	rgb(255, 220, 50), -- 3 yellow
	rgb(80, 210, 110), -- 4 green
	rgb(70, 160, 255), -- 5 blue
	rgb(190, 100, 255), -- 6 purple
}

WorldTheme.Outskirts = {
	Ground = rgb(98, 180, 82),
	Hill = rgb(120, 196, 96),
	HillDark = rgb(84, 156, 70),
}

WorldTheme.Yard = {
	Grass = rgb(118, 200, 90),
	GrassStripe = rgb(132, 214, 100),
	Path = rgb(236, 214, 168),
	Fence = rgb(255, 255, 255),
	FenceCap = rgb(255, 255, 255),
	DogSpot = rgb(168, 230, 128),
	DogSpotRing = rgb(255, 255, 255),
	KennelWall = rgb(214, 120, 70),
	KennelRoof = rgb(160, 60, 50),
	KennelDoor = rgb(70, 45, 35),
	SignBoard = rgb(40, 40, 60),
	SignText = rgb(255, 255, 255),
	TrophyPlinth = rgb(240, 240, 250),
	TrophyTop = rgb(255, 210, 80),
	GapGround = rgb(98, 180, 82),
	Hedge = rgb(60, 150, 70),
}

WorldTheme.Street = {
	Asphalt = rgb(70, 74, 92),
	Line = rgb(255, 230, 90),
	Curb = rgb(230, 230, 240),
	LampPole = rgb(50, 50, 70),
	LampGlow = rgb(255, 236, 170),
}

WorldTheme.Plaza = {
	Paving = rgb(240, 226, 196),
	PavingTrim = rgb(220, 200, 165),
	Lawn = rgb(126, 210, 96),
	LawnEdge = rgb(96, 176, 80),
	Spawn = rgb(90, 200, 255),
	ShopCounter = rgb(255, 248, 235),
	ShopAwning = { rgb(255, 90, 90), rgb(255, 255, 255) }, -- the one ball shop
	ShopSign = rgb(40, 40, 60),
	Equipment = rgb(80, 85, 110),
	EquipmentAccent = rgb(255, 200, 50),
	TrainingMat = rgb(232, 110, 80),
	TrainingLine = rgb(255, 255, 255),
	TreeTrunk = rgb(130, 85, 50),
	TreeLeaf = rgb(80, 190, 80),
}

WorldTheme.ThrowLine = {
	Line = rgb(255, 255, 255),
}

-- The raised throwing platform (deck at Y = 40), its tower and ramp.
WorldTheme.Platform = {
	Deck = rgb(255, 255, 255),
	DeckTrim = rgb(255, 210, 60),
	Tower = rgb(214, 196, 168),
	TowerBand = rgb(186, 164, 134),
	TowerSign = rgb(40, 40, 60),
	Ramp = rgb(226, 208, 176),
	RampStripe = rgb(255, 210, 60),
	Rail = rgb(255, 255, 255),
	RailPost = rgb(60, 60, 80),
	ThrowSpot = rgb(255, 90, 90),
	ThrowSpotRing = rgb(255, 255, 255),
	QueueSpot = rgb(70, 160, 255),
}

-- World walls (Walls.luau): stepped cliff / hedge faces around the whole map. Each zone's wall is built
-- from its Zones.luau Theme (Ground + Accent); this table only picks the material + how the tiers mix.
-- Top tiers lerp toward SkyFade so the silhouettes melt into the atmosphere.
WorldTheme.Walls = {
	SkyFade = rgb(196, 222, 250),
	Crossbar = { Base = rgb(56, 140, 64), Mid = rgb(74, 164, 78), Top = rgb(104, 186, 98),
		Material = Enum.Material.LeafyGrass, Hedge = true },
	-- per-zone material; Hedge = true gives a softer hedge look (less rock trim)
	Zones = {
		Backyard = { Material = Enum.Material.LeafyGrass, Hedge = true },
		Park = { Material = Enum.Material.LeafyGrass, Hedge = true },
		Beach = { Material = Enum.Material.Sandstone },
		Farm = { Material = Enum.Material.Ground },
		Forest = { Material = Enum.Material.Slate },
		SnowyPeaks = { Material = Enum.Material.Glacier },
		CityRooftops = { Material = Enum.Material.Concrete },
		SpaceStation = { Material = Enum.Material.DiamondPlate },
		MythicMeadow = { Material = Enum.Material.Pebble },
	},
	Rock = Enum.Material.Rock,
}

WorldTheme.Field = {
	DistanceLine = rgb(255, 255, 255),
	MarkerPost = rgb(255, 255, 255),
	MarkerBoard = rgb(40, 40, 60),
	ArchPillar = rgb(255, 255, 255),
	ArchBoard = rgb(40, 40, 60),
	EndWall = rgb(255, 255, 255),
}

-- Decoration palettes per zone (keys = Zones.luau Id). Each decorator reads only its own entry.
WorldTheme.ZoneDecor = {
	Backyard = { Fence = rgb(255, 255, 255), House = rgb(255, 200, 120), Roof = rgb(220, 80, 70),
		Leaf = rgb(90, 200, 90), Trunk = rgb(130, 85, 50), Flower = rgb(255, 120, 180), Toy = rgb(80, 170, 255) },
	Park = { Leaf = rgb(70, 180, 80), Trunk = rgb(120, 80, 50), Pond = rgb(80, 180, 255), Bench = rgb(170, 110, 60),
		Lamp = rgb(50, 50, 70), Bush = rgb(60, 160, 70) },
	Beach = { Water = rgb(60, 180, 240), Palm = rgb(80, 200, 90), PalmTrunk = rgb(190, 140, 80),
		Umbrella = { rgb(255, 90, 90), rgb(255, 220, 60), rgb(80, 170, 255) }, Ball = rgb(255, 255, 255), Rock = rgb(170, 160, 150) },
	Farm = { Barn = rgb(200, 60, 50), BarnTrim = rgb(255, 255, 255), Hay = rgb(240, 200, 90), Crop = rgb(110, 190, 60),
		Soil = rgb(140, 95, 60), Silo = rgb(210, 210, 220), Fence = rgb(170, 120, 70) },
	Forest = { Pine = rgb(40, 130, 70), PineDark = rgb(30, 105, 60), Trunk = rgb(100, 65, 40), Log = rgb(130, 85, 50),
		Mushroom = rgb(230, 60, 60), MushroomStem = rgb(250, 240, 220) },
	SnowyPeaks = { Mountain = rgb(150, 160, 185), Snow = rgb(255, 255, 255), Pine = rgb(60, 130, 100),
		Ice = rgb(170, 220, 255), Snowman = rgb(255, 255, 255), Carrot = rgb(255, 140, 40) },
	CityRooftops = { Building = { rgb(110, 115, 140), rgb(150, 130, 170), rgb(90, 140, 170) }, Window = rgb(255, 220, 110),
		Vent = rgb(190, 195, 205), Tank = rgb(150, 100, 70), Neon = { rgb(255, 80, 180), rgb(80, 220, 255) } },
	SpaceStation = { Hull = rgb(200, 205, 220), Panel = rgb(60, 66, 100), Glow = rgb(120, 220, 255),
		Planet = { rgb(255, 140, 90), rgb(140, 120, 255), rgb(90, 220, 170) }, Antenna = rgb(230, 230, 240) },
	MythicMeadow = { Crystal = { rgb(255, 120, 230), rgb(140, 220, 255), rgb(255, 230, 120) },
		Flower = rgb(255, 160, 220), FlowerCenter = rgb(255, 230, 120), Pillar = rgb(255, 230, 160), Island = rgb(150, 110, 210),
		IslandGrass = rgb(190, 150, 250) },
}

WorldTheme.Lighting = {
	ClockTime = 14.2,
	Brightness = 3,
	Ambient = rgb(120, 120, 140),
	OutdoorAmbient = rgb(150, 150, 165),
	ExposureCompensation = 0.1,
	ColorShiftTop = rgb(255, 245, 225),
	-- near zones (first ~400 studs) stay crisp, the 3,200-stud far end and the walls melt into a blue haze
	Atmosphere = { Density = 0.34, Offset = 0.32, Color = rgb(199, 224, 252), Decay = rgb(112, 150, 205), Glare = 0.12, Haze = 1.8 },
	Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.6 },
	ColorCorrection = { Saturation = 0.18, Contrast = 0.06, Brightness = 0.02, TintColor = rgb(255, 252, 245) },
	SunRays = { Intensity = 0.04, Spread = 0.6 },
}

return WorldTheme
