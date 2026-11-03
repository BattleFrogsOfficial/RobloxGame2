--!strict
-- SHARED RARITY + VARIANT CONTRACT. Balance pass may tune numbers but must not rename keys.
local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Rarities.Tiers = {
	Common    = { Odds = 0.75,  Catch = 0.95, IncomeMult = 1,   Color = Color3.fromRGB(200, 200, 200), PerZone = 54 },
	Uncommon  = { Odds = 0.17,  Catch = 0.90, IncomeMult = 2.5, Color = Color3.fromRGB(90, 200, 90),   PerZone = 13 },
	Rare      = { Odds = 0.055, Catch = 0.80, IncomeMult = 6,   Color = Color3.fromRGB(70, 140, 255),  PerZone = 7 },
	Epic      = { Odds = 0.02,  Catch = 0.65, IncomeMult = 15,  Color = Color3.fromRGB(170, 80, 230),  PerZone = 3 },
	Legendary = { Odds = 0.004, Catch = 0.45, IncomeMult = 50,  Color = Color3.fromRGB(255, 170, 30),  PerZone = 2 },
	Mythic    = { Odds = 0.001, Catch = 0.30, IncomeMult = 200, Color = Color3.fromRGB(255, 60, 120),  PerZone = 1 },
}
-- Mythic Meadow is the exception: 53 Common / 2 Mythic (still 80 dogs).

-- Variants roll independently on any NON-Common appearance. Shown as a badge, never as a word in the name.
Rarities.VariantOrder = { "Gold", "Shadow", "Rainbow" }
Rarities.Variants = {
	Gold    = { Chance = 0.05,  IncomeMult = 3 },
	Shadow  = { Chance = 0.015, IncomeMult = 7 },
	Rainbow = { Chance = 0.003, IncomeMult = 15 },
}

-- Visible "Lucky Streak": after this many consecutive Legendary+ misses, the next Legendary+ catch is guaranteed.
Rarities.LuckyStreakMisses = 2

return Rarities
