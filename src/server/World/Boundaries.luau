--!strict
-- Invisible walls around the playable T (crossbar = yards + street; stem top = plaza). The plaza's field
-- edge (Z = ThrowLine.Z, either side of the tower) is closed in ThrowLine.luau and the deck / ramp guards
-- live in Platform.luau. The visible scenery walls far outside all this are Walls.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("Config"):WaitForChild("Layout")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Boundaries = {}

Boundaries.Height = 80
Boundaries.Thickness = 2

function Boundaries.Build(parent: Instance)
	local f = Props.Folder(parent, "Boundaries")
	local Y, H, t = Layout.GroundY, Boundaries.Height, Boundaries.Thickness
	local s, p = Layout.Street, Layout.Plaza
	local north = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2
	local plazaEnd = Layout.ThrowLine.Z

	Props.Wall(f, "North", s.MinX - t, s.MaxX + t, north - t, north, Y, H)
	Props.Wall(f, "West", s.MinX - t, s.MinX, north, s.MaxZ, Y, H)
	Props.Wall(f, "East", s.MaxX, s.MaxX + t, north, s.MaxZ, Y, H)
	Props.Wall(f, "StreetSouthW", s.MinX - t, p.MinX, s.MaxZ, s.MaxZ + t, Y, H)
	Props.Wall(f, "StreetSouthE", p.MaxX, s.MaxX + t, s.MaxZ, s.MaxZ + t, Y, H)
	Props.Wall(f, "PlazaWest", p.MinX - t, p.MinX, s.MaxZ, plazaEnd + t, Y, H)
	Props.Wall(f, "PlazaEast", p.MaxX, p.MaxX + t, s.MaxZ, plazaEnd + t, Y, H)
end

return Boundaries
