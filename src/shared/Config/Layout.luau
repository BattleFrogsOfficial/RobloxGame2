--!strict
-- SHARED WORLD LAYOUT CONTRACT. World builder, ThrowService, cutscenes and HUD all read this.
-- Units are studs. Origin (0,0,0) is the centre of the T junction. +Z points down the stem (away from the yards).
-- Ground top surface is Y = 0.
--
--   Z -200 ┌──Y1──┬──Y2──┬──Y3──┬──Y4──┬──Y5──┬──Y6──┐   <- six player yards (crossbar, north side)
--   Z  -80 ├──────────────── STREET ─────────────────┤   <- crossbar street
--   Z  -40       └──── PLAZA / DOG PARK HUB ────┘         <- shop, training, leaderboard, spawn
--   Z   60             [ THROW LINE: 6 pads ]
--                      │                    │
--                      │   FETCH FIELD      │            <- stem, 9 zones in bands by distance
--   Z 3260             └────────────────────┘
local Layout = {}

Layout.GroundY = 0

Layout.Yards = {
	Count = 6,
	Size = Vector3.new(110, 0, 120), -- X width, Z depth
	CenterZ = -140,
	CentersX = { -300, -180, -60, 60, 180, 300 },
	GateSide = "South", -- each yard opens onto the street
	MaxRoamingDogs = 12, -- render cap; the rest live in the kennel building
}

Layout.Street = { MinX = -380, MaxX = 380, MinZ = -80, MaxZ = -40 }

Layout.Plaza = { MinX = -120, MaxX = 120, MinZ = -40, MaxZ = 60 }

Layout.ThrowLine = {
	Z = 60,
	PadsX = { -75, -45, -15, 15, 45, 75 }, -- pad i belongs to yard i's owner
	PadSize = Vector3.new(20, 1, 12),
}

Layout.Field = { MinX = -120, MaxX = 120, MinZ = 60, MaxZ = 3260 }

-- Distance a ball travelled = (landing.Z - ThrowLine.Z). Zone bands live in Zones.luau.
function Layout.DistanceToZ(distance: number): number
	return Layout.ThrowLine.Z + distance
end

return Layout
