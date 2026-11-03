--!strict
-- Invisible walls around the playable T on the hub plateau (crossbar = yards + street; stem top = plaza), all
-- standing on Layout.HubY. The plaza's cliff edge (Z = ThrowLine.Z, deck included) is closed by the EdgeGuard in
-- ThrowLine.luau, which overlaps the plaza side walls here. The visible scenery walls are Walls.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("Config"):WaitForChild("Layout")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Boundaries = {}

Boundaries.Height = 80
Boundaries.Thickness = 2

function Boundaries.Build(parent: Instance)
	local f = Props.Folder(parent, "Boundaries")
	local Y, H, t = Layout.HubY, Boundaries.Height, Boundaries.Thickness
	local s, p = Layout.Street, Layout.Plaza
	local north = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2
	local plazaEnd = Layout.ThrowLine.Z + 0.6 -- meets the EdgeGuard's outer face

	Props.Wall(f, "North", s.MinX - t, s.MaxX + t, north - t, north, Y, H)
	Props.Wall(f, "West", s.MinX - t, s.MinX, north, s.MaxZ, Y, H)
	Props.Wall(f, "East", s.MaxX, s.MaxX + t, north, s.MaxZ, Y, H)
	Props.Wall(f, "StreetSouthW", s.MinX - t, p.MinX, s.MaxZ, s.MaxZ + t, Y, H)
	Props.Wall(f, "StreetSouthE", p.MaxX, s.MaxX + t, s.MaxZ, s.MaxZ + t, Y, H)
	Props.Wall(f, "PlazaWest", p.MinX - t, p.MinX, s.MaxZ, plazaEnd, Y, H)
	Props.Wall(f, "PlazaEast", p.MaxX, p.MaxX + t, s.MaxZ, plazaEnd, Y, H)
end

return Boundaries
