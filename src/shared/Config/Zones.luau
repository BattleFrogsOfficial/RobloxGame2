--!strict
-- SHARED ZONE CONTRACT. Distances are studs from the throw line. Ids are used by the dog roster.
export type Zone = {
	Id: string,
	Name: string,
	Order: number,
	MinDistance: number,
	MaxDistance: number,
	BaseIncome: number, -- $/s for a Common with rarity mult 1 and no variant
	Theme: { Ground: Color3, Accent: Color3 },
}

local Zones: { Zone } = {
	{ Id = "Backyard", Name = "Backyard", Order = 1, MinDistance = 0, MaxDistance = 100, BaseIncome = 1,
		Theme = { Ground = Color3.fromRGB(106, 170, 72), Accent = Color3.fromRGB(150, 110, 70) } },
	{ Id = "Park", Name = "Park", Order = 2, MinDistance = 100, MaxDistance = 250, BaseIncome = 4,
		Theme = { Ground = Color3.fromRGB(88, 160, 80), Accent = Color3.fromRGB(200, 200, 200) } },
	{ Id = "Beach", Name = "Beach", Order = 3, MinDistance = 250, MaxDistance = 450, BaseIncome = 16,
		Theme = { Ground = Color3.fromRGB(236, 214, 158), Accent = Color3.fromRGB(70, 160, 220) } },
	{ Id = "Farm", Name = "Farm", Order = 4, MinDistance = 450, MaxDistance = 700, BaseIncome = 64,
		Theme = { Ground = Color3.fromRGB(150, 170, 70), Accent = Color3.fromRGB(170, 60, 50) } },
	{ Id = "Forest", Name = "Forest", Order = 5, MinDistance = 700, MaxDistance = 1000, BaseIncome = 256,
		Theme = { Ground = Color3.fromRGB(60, 110, 55), Accent = Color3.fromRGB(90, 65, 40) } },
	{ Id = "SnowyPeaks", Name = "Snowy Peaks", Order = 6, MinDistance = 1000, MaxDistance = 1400, BaseIncome = 1024,
		Theme = { Ground = Color3.fromRGB(235, 242, 250), Accent = Color3.fromRGB(140, 180, 220) } },
	{ Id = "CityRooftops", Name = "City Rooftops", Order = 7, MinDistance = 1400, MaxDistance = 1900, BaseIncome = 4096,
		Theme = { Ground = Color3.fromRGB(90, 92, 100), Accent = Color3.fromRGB(255, 190, 60) } },
	{ Id = "SpaceStation", Name = "Space Station", Order = 8, MinDistance = 1900, MaxDistance = 2500, BaseIncome = 16384,
		Theme = { Ground = Color3.fromRGB(40, 44, 70), Accent = Color3.fromRGB(120, 220, 255) } },
	{ Id = "MythicMeadow", Name = "Mythic Meadow", Order = 9, MinDistance = 2500, MaxDistance = 3200, BaseIncome = 65536,
		Theme = { Ground = Color3.fromRGB(150, 110, 210), Accent = Color3.fromRGB(255, 215, 120) } },
}

return Zones
