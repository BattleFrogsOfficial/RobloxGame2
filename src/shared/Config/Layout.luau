--!strict
-- SHARED WORLD LAYOUT CONTRACT. World builder, ThrowService, cutscenes and HUD all read this.
-- Units are studs. Origin (0,0,0) is the centre of the T junction. +Z points down the stem (away from the yards).
--
-- TWO LEVELS. The whole hub (six yards, street, plaza with the ball shop, training area and the brown throw
-- zone) sits on a plateau whose walking surface is Layout.HubY (40). The fetch field is 40 studs below
-- at Layout.GroundY (0). The plateau's front edge runs along Z = Layout.ThrowLine.Z: a stepped rock cliff
-- (World/Cliff.luau) drops from it to the field. Players never go down: an invisible wall + railings close
-- the edge, and the field is scenery the ball is thrown into.
--
-- MAP (compact T; every walk between a yard gate, the throw zone, the shop and the training area
-- is <= 300 studs, i.e. under 10 s at WalkSpeed 32; tools/worldcheck/run.luau measures it):
--
--   Z -154 ┌Y1┬Y2┬Y3┬Y4┬Y5┬Y6┐          six 52 x 100 yards side by side, gates face the street (+Z)   } plateau
--   Z  -54 ├──── STREET ─────┤          X -170..170                                                   } Y = HubY
--   Z  -34     └─ PLAZA ─┘              X -60..60: ONE ball shop (west), ONE training area (east),     } (40)
--   Z   40   [##THROW ZONE##]           spawns, runaway lawn + squirrel loop; the brown throw zone is }
--   Z   60  ====throw line==== cliff    flush with the paving, its front edge = the cliff edge = distance 0
--               │      │
--               │FIELD │                stem X -120..120 (ground Y = GroundY = 0), 9 zone bands by distance
--   Z 3260      └──────┘
--   Scenery walls (200+ studs tall) enclose everything at |X| >= 236, Z <= -180 and Z >= 3310; the hub-side
--   walls rise from the plateau, the field walls from the field.
local Layout = {}

Layout.GroundY = 0 -- the fetch field (zone bands, distance markers, landing spots)
Layout.HubY = 40 -- the plateau: yards, street, plaza, shop, training, throw zone, spawns

Layout.Yards = {
	Count = 6,
	Size = Vector3.new(52, 0, 100), -- X width, Z depth
	CenterZ = -104,
	CentersX = { -140, -84, -28, 28, 84, 140 }, -- 56 apart (4-stud hedge gaps)
	Y = Layout.HubY, -- yard plot top surface
	GateSide = "South", -- each yard opens onto the street (+Z)
	MaxRoamingDogs = 12, -- render cap; the rest live in the kennel building
}

Layout.Street = { MinX = -170, MaxX = 170, MinZ = -54, MaxZ = -34, Y = Layout.HubY }

Layout.Plaza = { MinX = -60, MaxX = 60, MinZ = -34, MaxZ = 60, Y = Layout.HubY }

-- Distance is measured horizontally (Z) from the throw line (= the throw zone's front edge = the cliff edge).
-- Y = the plateau surface.
Layout.ThrowLine = { X = 0, Z = 60, Y = Layout.HubY }

-- THE THROW ZONE: a big brown dirt strip set flush into the plaza paving along the cliff edge (World/ThrowZone.luau,
-- floor part tagged "ThrowZone" + "ThrowPad" PadIndex 1). Walking into it is all it takes: there are no turns and
-- no queue; everyone inside can throw at once (one ball in flight each). MaxZ is the throw line (distance 0).
-- "In the zone" = HumanoidRootPart XZ inside this rectangle grown by Game.ThrowZone.EdgeMargin, and
-- Y >= Y - Game.ThrowZone.YTolerance (server attribute "InThrowZone", ~4x per second).
-- Each throw leaves from the cliff edge in front of the thrower: LaunchPos = (root X clamped to MinX..MaxX,
-- Y + Game.Throw.LaunchHeight, ThrowLine.Z).
Layout.ThrowZone = { MinX = -50, MaxX = 50, MinZ = 40, MaxZ = 60, Y = Layout.HubY }

-- DEPRECATED (the old platform deck + queue): only ThrowSpot is kept, for older code that reads it. It is the centre
-- of the throw zone at Y = HubY. Center / Size mirror the zone rectangle.
Layout.Platform = {
	Center = Vector3.new(0, Layout.HubY, 50),
	Size = Vector3.new(100, 1, 20),
	ThrowSpot = Vector3.new(0, Layout.HubY, 50),
}

-- The cliff edge (World/ThrowLine.luau + World/Cliff.luau): visible railings along the whole plaza front and an
-- invisible collision wall right at the edge, taller than any jump.
Layout.Edge = {
	RailHeight = 2.6, -- visible railing posts (caps top out below the launch height)
	GuardHeight = 20, -- invisible wall above the plateau surface (a WalkSpeed 32 / JumpPower 60 jump is ~9.2)
}

Layout.Shop = { Center = Vector3.new(-34, Layout.HubY, -4) } -- the ONE ball shop counter (ShopStand, ShopId "Balls")
Layout.Training = { Center = Vector3.new(34, Layout.HubY, 2) } -- the ONE training area (TrainingStation, StationId "Main");
-- its sign stands at Z 15, clear of the view over the throwers' shoulders

Layout.Field = { MinX = -120, MaxX = 120, MinZ = 60, MaxZ = 3260, Y = Layout.GroundY } -- 40 studs below the hub

-- Distance a ball travelled = (landing.Z - ThrowLine.Z), horizontal, landing on the field at GroundY.
-- Zone bands live in Zones.luau.
function Layout.DistanceToZ(distance: number): number
	return Layout.ThrowLine.Z + distance
end

return Layout
