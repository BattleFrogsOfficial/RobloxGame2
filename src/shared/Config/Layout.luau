--!strict
-- SHARED WORLD LAYOUT CONTRACT. World builder, ThrowService, cutscenes and HUD all read this.
-- Units are studs. Origin (0,0,0) is the centre of the T junction. +Z points down the stem (away from the yards).
-- Ground top surface is Y = 0 everywhere except the throwing platform deck (Y = 40).
--
-- NEW MAP (compact T; every walk between a yard gate, the platform deck, the shop and the training area
-- is <= 300 studs, i.e. under 10 s at WalkSpeed 32; tools/worldcheck/run.luau measures it):
--
--   Z -154 ┌Y1┬Y2┬Y3┬Y4┬Y5┬Y6┐          six 52 x 100 yards side by side, gates face the street (+Z)
--   Z  -54 ├──── STREET ─────┤          X -170..170
--   Z  -34     └─ PLAZA ─┘              X -60..60: ONE ball shop (west), ONE training area (east),
--               │ ramp │                spawns, runaway lawn + squirrel loop; a 30 deg ramp runs up
--   Z   34      [DECK ]                 the middle to the raised throwing platform (deck top Y = 40)
--   Z   60  ====throw line====          front edge of the deck = Layout.ThrowLine (distance 0)
--               │      │
--               │FIELD │                stem X -120..120 (ground Y = 0), 9 zone bands by distance
--   Z 3260      └──────┘
--   Scenery walls (200+ studs tall) enclose everything at |X| >= 236, Z <= -180 and Z >= 3310.
local Layout = {}

Layout.GroundY = 0

Layout.Yards = {
	Count = 6,
	Size = Vector3.new(52, 0, 100), -- X width, Z depth
	CenterZ = -104,
	CentersX = { -140, -84, -28, 28, 84, 140 }, -- 56 apart (4-stud hedge gaps)
	GateSide = "South", -- each yard opens onto the street (+Z)
	MaxRoamingDogs = 12, -- render cap; the rest live in the kennel building
}

Layout.Street = { MinX = -170, MaxX = 170, MinZ = -54, MaxZ = -34 }

Layout.Plaza = { MinX = -60, MaxX = 60, MinZ = -34, MaxZ = 60 }

-- Distance is measured horizontally (Z) from the front edge of the platform deck.
Layout.ThrowLine = { X = 0, Z = 60, Y = 40 }

-- The ONE throwing platform. Deck surface at ThrowLine.Y; the deck part is tagged ThrowPad (PadIndex = 1).
Layout.Platform = {
	Center = Vector3.new(0, 40, 47), -- deck surface centre
	Size = Vector3.new(36, 2, 26), -- deck X -18..18, Z 34..60
	StandRadius = 29, -- XZ radius around ThrowSpot covering the whole deck ("standing on the platform")
	ThrowSpot = Vector3.new(0, 40, 56), -- marked spot at the front edge (deck surface)
	QueueSpots = { -- Order 1..5, beside the throw spot, running back toward the ramp
		Vector3.new(10, 40, 55),
		Vector3.new(10, 40, 50.5),
		Vector3.new(10, 40, 46),
		Vector3.new(10, 40, 41.5),
		Vector3.new(10, 40, 37),
	},
	RampBottom = Vector3.new(0, 0, -34), -- ground end of the ramp (plaza / street edge)
	RampTop = Vector3.new(0, 40, 34), -- deck end of the ramp (back edge of the deck)
	RampWidth = 12,
}

Layout.Shop = { Center = Vector3.new(-34, 0, -4) } -- the ONE ball shop counter (ShopStand, ShopId "Balls")
Layout.Training = { Center = Vector3.new(34, 0, 10) } -- the ONE training area (TrainingStation, StationId "Main")

Layout.Field = { MinX = -120, MaxX = 120, MinZ = 60, MaxZ = 3260 }

-- Distance a ball travelled = (landing.Z - ThrowLine.Z), horizontal. Zone bands live in Zones.luau.
function Layout.DistanceToZ(distance: number): number
	return Layout.ThrowLine.Z + distance
end

return Layout
