--!strict
-- Invisible walls around the playable T (crossbar = yards + street; stem top = plaza + throw apron).
-- The low field wall at ThrowLine.Z + 8 lives in ThrowLine.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared:WaitForChild("Config"):WaitForChild("Layout")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any
local ThrowLine = require((script.Parent :: Instance):WaitForChild("ThrowLine")) :: any

local Boundaries = {}

Boundaries.Height = 80
Boundaries.Thickness = 2

function Boundaries.Build(parent: Instance)
	local f = Props.Folder(parent, "Boundaries")
	local Y, H, t = Layout.GroundY, Boundaries.Height, Boundaries.Thickness
	local s, p = Layout.Street, Layout.Plaza
	local north = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2 -- -200
	local fieldWallZ = Layout.ThrowLine.Z + ThrowLine.WallOffset

	Props.Wall(f, "North", s.MinX - t, s.MaxX + t, north - t, north, Y, H)
	Props.Wall(f, "West", s.MinX - t, s.MinX, north, s.MaxZ, Y, H)
	Props.Wall(f, "East", s.MaxX, s.MaxX + t, north, s.MaxZ, Y, H)
	Props.Wall(f, "StreetSouthW", s.MinX - t, p.MinX, s.MaxZ, s.MaxZ + t, Y, H)
	Props.Wall(f, "StreetSouthE", p.MaxX, s.MaxX + t, s.MaxZ, s.MaxZ + t, Y, H)
	Props.Wall(f, "PlazaWest", p.MinX - t, p.MinX, s.MaxZ, fieldWallZ + 0.5, Y, H)
	Props.Wall(f, "PlazaEast", p.MaxX, p.MaxX + t, s.MaxZ, fieldWallZ + 0.5, Y, H)
end

return Boundaries
