-- All game tunables in one place. Change numbers here, not in the systems.

local Config = {}

-- Shown in small print at the top of the screen and used in the place
-- file's name, so it is always clear which build is running.
Config.Build = 21

----------------------------------------------------------------------------
-- Rarities
----------------------------------------------------------------------------
Config.Rarities = {
	{ id = "Common", color = Color3.fromRGB(225, 225, 225) },
	{ id = "Uncommon", color = Color3.fromRGB(110, 230, 90) },
	{ id = "Rare", color = Color3.fromRGB(70, 160, 255) },
	{ id = "Epic", color = Color3.fromRGB(190, 95, 255) },
	{ id = "Legendary", color = Color3.fromRGB(255, 185, 40) },
	{ id = "Mythic", color = Color3.fromRGB(255, 70, 110) },
	{ id = "Secret", color = Color3.fromRGB(40, 255, 230) },
}
Config.RarityIndex = {}
for i, r in Config.Rarities do
	Config.RarityIndex[r.id] = i
end

----------------------------------------------------------------------------
-- Eggs (one per rarity tier). `hatch` is seconds in the pen.
-- `value` is the sell price of an unhatched egg.
----------------------------------------------------------------------------
Config.Eggs = {
	{
		id = "Shell",
		name = "Shell Egg",
		rarity = "Common",
		hatch = 15,
		value = 15,
		base = Color3.fromRGB(245, 235, 210),
		spot = Color3.fromRGB(215, 190, 150),
	},
	{
		id = "Coral",
		name = "Coral Egg",
		rarity = "Uncommon",
		hatch = 40,
		value = 80,
		base = Color3.fromRGB(255, 140, 120),
		spot = Color3.fromRGB(255, 220, 90),
	},
	{
		id = "Kelp",
		name = "Kelp Egg",
		rarity = "Rare",
		hatch = 90,
		value = 400,
		base = Color3.fromRGB(80, 170, 90),
		spot = Color3.fromRGB(40, 110, 60),
	},
	{
		id = "Pearl",
		name = "Pearl Egg",
		rarity = "Epic",
		hatch = 180,
		value = 2000,
		base = Color3.fromRGB(235, 225, 255),
		spot = Color3.fromRGB(180, 140, 255),
	},
	{
		id = "Treasure",
		name = "Treasure Egg",
		rarity = "Legendary",
		hatch = 360,
		value = 10000,
		base = Color3.fromRGB(255, 200, 50),
		spot = Color3.fromRGB(200, 90, 30),
	},
	{
		id = "Abyss",
		name = "Abyss Egg",
		rarity = "Mythic",
		hatch = 720,
		value = 60000,
		base = Color3.fromRGB(30, 40, 90),
		spot = Color3.fromRGB(60, 230, 255),
		glow = true,
	},
	{
		id = "Leviathan",
		name = "Leviathan Egg",
		rarity = "Secret",
		hatch = 1200,
		value = 400000,
		base = Color3.fromRGB(25, 25, 30),
		spot = Color3.fromRGB(255, 60, 200),
		glow = true,
	},
}
Config.EggById = {}
for i, e in Config.Eggs do
	e.tier = i
	Config.EggById[e.id] = e
end

----------------------------------------------------------------------------
-- Animals. `income` is $/s for a Normal variant. `model` picks a voxel
-- template in Voxel.luau. `weight` is the hatch weight inside its egg.
----------------------------------------------------------------------------
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Config.Animals = {
	-- Shell Egg
	{ id = "Crab", egg = "Shell", weight = 60, income = 4, model = "crab", p = rgb(235, 80, 55), s = rgb(190, 55, 40), a = rgb(255, 170, 120) },
	{ id = "Seagull", egg = "Shell", weight = 30, income = 6, model = "bird", p = rgb(245, 245, 245), s = rgb(160, 165, 175), a = rgb(255, 180, 40) },
	{ id = "Turtle", egg = "Shell", weight = 10, income = 10, model = "turtle", p = rgb(120, 200, 90), s = rgb(110, 75, 40), a = rgb(80, 55, 30) },
	-- Coral Egg
	{ id = "Pufferfish", egg = "Coral", weight = 60, income = 18, model = "fish", p = rgb(255, 210, 70), s = rgb(230, 150, 40), a = rgb(255, 245, 200), opts = { round = true } },
	{ id = "Seal", egg = "Coral", weight = 30, income = 26, model = "seal", p = rgb(150, 155, 165), s = rgb(110, 115, 125), a = rgb(60, 60, 65) },
	{ id = "Flamingo", egg = "Coral", weight = 10, income = 38, model = "bird", p = rgb(255, 130, 170), s = rgb(235, 90, 140), a = rgb(40, 40, 40), opts = { legs = 7 } },
	-- Kelp Egg
	{ id = "Frog", egg = "Kelp", weight = 60, income = 70, model = "frog", p = rgb(90, 200, 70), s = rgb(220, 240, 150), a = rgb(255, 120, 120) },
	{ id = "Otter", egg = "Kelp", weight = 30, income = 100, model = "quad", p = rgb(140, 95, 60), s = rgb(110, 70, 45), a = rgb(225, 200, 170) },
	{ id = "Pelican", egg = "Kelp", weight = 10, income = 145, model = "bird", p = rgb(240, 240, 235), s = rgb(200, 200, 195), a = rgb(255, 175, 60), opts = { bigBeak = true } },
	-- Pearl Egg
	{ id = "Penguin", egg = "Pearl", weight = 60, income = 280, model = "bird", p = rgb(35, 35, 45), s = rgb(245, 245, 250), a = rgb(255, 170, 40), opts = { upright = true } },
	{ id = "Octopus", egg = "Pearl", weight = 30, income = 400, model = "octo", p = rgb(200, 90, 210), s = rgb(240, 160, 240), a = rgb(255, 255, 255) },
	{ id = "Dolphin", egg = "Pearl", weight = 10, income = 560, model = "fish", p = rgb(110, 160, 220), s = rgb(220, 235, 250), a = rgb(80, 120, 180), opts = { long = true } },
	-- Treasure Egg
	{ id = "Parrot", egg = "Treasure", weight = 60, income = 1200, model = "bird", p = rgb(240, 40, 40), s = rgb(40, 120, 240), a = rgb(255, 220, 40), opts = { crest = true } },
	{ id = "Shark", egg = "Treasure", weight = 30, income = 1700, model = "fish", p = rgb(120, 135, 150), s = rgb(235, 235, 235), a = rgb(255, 255, 255), opts = { long = true, teeth = true } },
	{ id = "Walrus", egg = "Treasure", weight = 10, income = 2400, model = "seal", p = rgb(150, 100, 70), s = rgb(120, 80, 55), a = rgb(250, 250, 235), opts = { tusks = true } },
	-- Abyss Egg
	{ id = "Anglerfish", egg = "Abyss", weight = 60, income = 5500, model = "fish", p = rgb(45, 50, 80), s = rgb(70, 75, 110), a = rgb(120, 255, 240), opts = { lure = true, teeth = true } },
	{ id = "Kraken", egg = "Abyss", weight = 30, income = 7800, model = "octo", p = rgb(150, 30, 45), s = rgb(210, 70, 80), a = rgb(255, 230, 80) },
	{ id = "Narwhal", egg = "Abyss", weight = 10, income = 11000, model = "fish", p = rgb(170, 200, 225), s = rgb(225, 240, 250), a = rgb(255, 250, 220), opts = { long = true, horn = true } },
	-- Leviathan Egg
	{ id = "Sea Dragon", egg = "Leviathan", weight = 60, income = 28000, model = "serpent", p = rgb(40, 170, 160), s = rgb(30, 110, 120), a = rgb(255, 210, 60) },
	{ id = "Ghost Whale", egg = "Leviathan", weight = 30, income = 42000, model = "fish", p = rgb(200, 235, 255), s = rgb(140, 190, 230), a = rgb(120, 255, 255), opts = { long = true, huge = true, ghost = true } },
	{ id = "Golden Kraken", egg = "Leviathan", weight = 10, income = 65000, model = "octo", p = rgb(255, 205, 50), s = rgb(255, 240, 150), a = rgb(255, 80, 80) },
}
Config.AnimalById = {}
Config.AnimalsByEgg = {}
for i, a in Config.Animals do
	a.order = i
	a.name = a.id
	a.rarity = Config.EggById[a.egg].rarity
	Config.AnimalById[a.id] = a
	Config.AnimalsByEgg[a.egg] = Config.AnimalsByEgg[a.egg] or {}
	table.insert(Config.AnimalsByEgg[a.egg], a)
end

----------------------------------------------------------------------------
-- Variants. Chance scales with sqrt(luck), capped.
----------------------------------------------------------------------------
Config.Variants = {
	Normal = { mult = 1 },
	-- `tint` variants recolor the model toward `color`; `shine` is how
	-- reflective it becomes.
	Gold = { mult = 2.5, chance = 0.05, cap = 0.3, color = Color3.fromRGB(255, 205, 50), tint = 0.7, shine = 0.15 },
	Platinum = { mult = 4, chance = 0.018, cap = 0.12, color = Color3.fromRGB(205, 225, 245), tint = 0.8, shine = 0.4 },
	Rainbow = { mult = 6, chance = 0.006, cap = 0.06, color = Color3.fromRGB(255, 120, 255) },
}

----------------------------------------------------------------------------
-- World / ocean geometry (studs). Ground top is y = 0.
-- There is one shore, along the line z = ShoreZ. Land (beach, bases) is on
-- the +z side; the ocean runs off to the horizon on the -z side.
----------------------------------------------------------------------------
Config.Ocean = {
	HalfX = 215, -- the shore spans x in [-HalfX, HalfX]
	ShoreZ = 0,
	RampLength = 20, -- sand slope from the shore down to the seabed
	SeabedY = -12,
	WaterTopY = -1.5,
	WallTopY = 26, -- height the parted water walls rise to (a basic split)
	SplitZoneDepth = 18, -- beach band (from the shoreline) where you can part the sea
	OpenAnim = 4, -- seconds of the parting cutscene before the walls start closing (a basic split)
	SlamAt = 0.32, -- fraction of the cutscene at which the staff slams down and the sea starts to tear
	Reach = 300, -- the deepest a corridor can ever go
	GrabRadius = 6,
	SweepGrace = 2, -- studs of forgiveness at the closing walls (covers network delay)
	MinGap = 1.2, -- once each wall is this close to the corridor center, it's shut
}

Config.World = {
	LandDepth = 190, -- from the shore to the back wall
	BeachDepth = 45,
	WallHeight = 70, -- walls around the land
}

-- The three ways a split can go. Each split rolls one: the rarer casts have
-- a longer, bigger cutscene, taller walls, and multiply your Luck for the
-- eggs in that split.
--   seconds  cutscene length         slam   fraction of it at which the sea tears
--   wallTop  wall height in studs    luck   Luck multiplier for this split
--   chance   odds of rolling it (the basic split takes whatever is left)
Config.Casts = {
	{ key = "Split", tier = 1, seconds = 4, slam = 0.32, wallTop = 26, luck = 1 },
	{ key = "Super", tier = 2, name = "SUPER SPLIT", seconds = 5.2, slam = 0.42, wallTop = 44, luck = 5, chance = 0.12 },
	{ key = "Poseidon", tier = 3, name = "POSEIDON'S WRATH", seconds = 8, slam = 0.56, wallTop = 78, luck = 10, chance = 0.03 },
}
Config.CastByKey = {}
for _, cast in Config.Casts do
	Config.CastByKey[cast.key] = cast
end

Config.MaxPlayers = 5 -- one base each; set the same number in Game Settings

----------------------------------------------------------------------------
-- Splitting. Strength drives how deep the corridor goes. The side walls
-- start closing as soon as it opens and meet after `duration` seconds.
----------------------------------------------------------------------------
Config.Split = {
	BaseLength = 30,
	LengthPerDoubling = 13.2, -- extra studs every time (1 + strength/5) doubles; full depth needs ~7M strength
	MinChargeFactor = 0.45, -- a tap gives 45% of the distance
	BaseDuration = 6, -- seconds until the walls meet...
	DurationPerStud = 0.15, -- ...plus this per stud of depth (a round trip at walk speed is 0.125/stud)
	ChargeOpenBonus = 4, -- full charge = +4s before the walls meet
	ChargeTime = 1.4, -- seconds of holding for a full bar
	BaseWidth = 26,
	WidthPerLevel = 0.9,
	MaxWidth = 44,
	BaseEggs = 2,
	EggsPerStuds = 34,
	MaxEggs = 16,
	BaseCarry = 1,
	GrabHold = 0.35, -- seconds of holding E to pick an egg up
}

-- Animal size multiplier per rarity tier: late-game pets tower over a base.
Config.SizeByTier = { 1, 1.5, 2.2, 3.2, 4.8, 7, 10 }

-- Base hatch weights per rarity tier; luck pushes them toward the right.
Config.RarityWeights = { 1000, 360, 160, 50, 14, 3, 0.4 }
-- Each tier's weight is multiplied by (luck x zone luck)^(LuckPower * (tier-1)).
Config.Odds = { LuckPower = 0.35 }

-- Luck zones: bands of depth, each with a luck multiplier and one more egg
-- tier unlocked than the band before. Shown on the bar at the top of the
-- screen and as glowing lines across the seabed.
Config.Zones = {
	{ name = "Shallows", luck = 1, color = Color3.fromRGB(240, 205, 130) },
	{ name = "Reef", luck = 2, color = Color3.fromRGB(110, 230, 90) },
	{ name = "Kelp Forest", luck = 3.5, color = Color3.fromRGB(60, 215, 235) },
	{ name = "Twilight", luck = 5.5, color = Color3.fromRGB(215, 100, 240) },
	{ name = "Trench", luck = 8, color = Color3.fromRGB(255, 200, 45) },
	{ name = "Abyss", luck = 11, color = Color3.fromRGB(255, 80, 95) },
}
for i, zone in Config.Zones do
	zone.index = i
	zone.from = (i - 1) * Config.Ocean.Reach / 5.4 -- studs out from the shore
	zone.maxTier = math.min(i + 1, #Config.Eggs)
end

----------------------------------------------------------------------------
-- Progression
----------------------------------------------------------------------------
-- Strength gained per rep on the training pad.
Config.Weights = {
	{ name = "Driftwood Dumbbell", cost = 0, gain = 6 },
	{ name = "Shell Barbell", cost = 250, gain = 15 },
	{ name = "Coral Kettlebell", cost = 3000, gain = 42 },
	{ name = "Iron Anchor", cost = 30000, gain = 105 },
	{ name = "Ship Cannon", cost = 300000, gain = 260 },
	{ name = "Pirate Chest", cost = 3000000, gain = 660 },
	{ name = "Kraken Tentacle", cost = 30000000, gain = 1650 },
	{ name = "Trident of Tides", cost = 300000000, gain = 4200 },
}

-- Walk speed, bought at the shop on the beach.
Config.Speed = { Base = 16, PerLevel = 1, MaxLevel = 14, BaseCost = 400, Growth = 2.1 }

Config.Luck = { BaseCost = 120, Growth = 1.45, PerLevel = 0.12, MaxLevel = 150 }
Config.Base = { StartSlots = 4, SlotsPerLevel = 2, MaxSlots = 20, BaseCost = 500, Growth = 2.9 }

Config.Training = { RepTime = 1.4, PadRadius = 7 } -- one rep = one push up and back down

-- Studs; gates face the ocean. Eggs can be placed anywhere in the plot that
-- is PlaceMargin clear of the fence and EggGap from the next egg.
Config.Pen = { Width = 70, Depth = 72, Gate = 9, Spacing = 84, FrontZ = 66, PlaceMargin = 3, EggGap = 5 }

Config.Offline = { Rate = 0.5, MaxSeconds = 4 * 3600, MinSeconds = 60 }
Config.SellAnimalSeconds = 25 -- an animal sells for 25s of its income
Config.MaxStoredAnimals = 60
Config.MaxStoredEggs = 60

----------------------------------------------------------------------------
-- Playtime rewards (reset every session) and daily streak
----------------------------------------------------------------------------
Config.Playtime = {
	{ minutes = 1, kind = "cash", cash = 100, incomeSeconds = 60 },
	{ minutes = 3, kind = "egg", egg = "Coral" },
	{ minutes = 5, kind = "cash", cash = 300, incomeSeconds = 120 },
	{ minutes = 8, kind = "animal", animal = "Seal" },
	{ minutes = 12, kind = "cash", cash = 800, incomeSeconds = 240 },
	{ minutes = 16, kind = "egg", egg = "Kelp" },
	{ minutes = 20, kind = "cash", cash = 2000, incomeSeconds = 420 },
	{ minutes = 25, kind = "animal", animal = "Otter" },
	{ minutes = 30, kind = "cash", cash = 5000, incomeSeconds = 600 },
	{ minutes = 40, kind = "egg", egg = "Pearl" },
	{ minutes = 50, kind = "cash", cash = 12000, incomeSeconds = 900 },
	{ minutes = 60, kind = "animal", animal = "Dolphin" },
}

Config.Daily = {
	{ kind = "cash", cash = 250, incomeSeconds = 120 },
	{ kind = "egg", egg = "Coral" },
	{ kind = "cash", cash = 1000, incomeSeconds = 300 },
	{ kind = "egg", egg = "Kelp" },
	{ kind = "cash", cash = 4000, incomeSeconds = 600 },
	{ kind = "egg", egg = "Pearl" },
	{ kind = "egg", egg = "Treasure" },
}

-- Index: every egg whose three animals have all been discovered, counted
-- separately for each variant, adds this much to all income.
Config.IndexBonusPerEgg = 0.10
Config.VariantOrder = { "Normal", "Gold", "Platinum", "Rainbow" } -- common to rare

----------------------------------------------------------------------------
-- Monetization. Fill in real IDs from the Creator Dashboard. While an ID is
-- 0, purchases are granted for free in Studio (for testing) and disabled live.
----------------------------------------------------------------------------
Config.Passes = {
	{ key = "DoubleStrength", id = 0, price = 99, name = "x2 Strength", desc = "Double Strength from every rep.", icon = "strength" },
	{ key = "DoubleLuck", id = 0, price = 149, name = "x2 Luck", desc = "Permanently doubles your Luck.", icon = "luck" },
	{ key = "DoubleCash", id = 0, price = 199, name = "x2 Cash", desc = "All animals earn double.", icon = "cash" },
	{ key = "ExtraCarry", id = 0, price = 129, name = "Double Carry", desc = "Carry 2 eggs per run.", icon = "egg" },
	{ key = "FastHatch", id = 0, price = 99, name = "Fast Hatch", desc = "Eggs hatch twice as fast.", icon = "hatch" },
}

Config.Products = {
	{ key = "StarterPack", id = 0, price = 10, name = "Starter Pack", desc = "$2,500 + a Treasure Egg!", icon = "gift" },
	{ key = "CashSmall", id = 0, price = 25, name = "Pile of Cash", desc = "10 minutes of income (min $1K).", icon = "cash" },
	{ key = "CashLarge", id = 0, price = 99, name = "Vault of Cash", desc = "1 hour of income (min $10K).", icon = "chest" },
	{ key = "LuckPotion", id = 0, price = 35, name = "Luck Potion", desc = "x2 Luck for 15 minutes.", icon = "potion" },
	{ key = "InstantHatch", id = 0, price = 29, name = "Instant Hatch", desc = "Every egg in your pen is ready now.", icon = "hatch" },
	{ key = "SkipPlaytime", id = 0, price = 95, name = "Skip Playtime", desc = "Unlock every playtime reward.", icon = "clock" },
}

Config.LuckPotionSeconds = 15 * 60

return Config
