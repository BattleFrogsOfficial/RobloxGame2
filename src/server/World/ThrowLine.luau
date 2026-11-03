--!strict
-- Throw line at ground level: the white line across the field start (Layout.ThrowLine.Z, right in front
-- of the platform tower) and the low fence + invisible wall along the plaza's field edge either side of
-- the tower. The raised deck / ThrowPad itself is built by Platform.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local ThrowLine = {}

local Y = Layout.GroundY
local T = WorldTheme.ThrowLine
local TL = Layout.ThrowLine

ThrowLine.WallOffset = 8 -- clear apron in front of the tower; Field.luau starts lane stripes / decor past it
ThrowLine.WallHeight = 12 -- taller than a default jump (~7.2 studs)

function ThrowLine.Build(parent: Instance)
	local folder = Props.Folder(parent, "ThrowLine")
	local minX, maxX = Layout.Field.MinX, Layout.Field.MaxX

	-- starts exactly at the tower's front face so it never overlaps the platform
	Props.Slab(folder, "Line", minX, maxX, TL.Z, TL.Z + 1.5, Y + 0.06, 0.06, T.Line, WorldTheme.AccentMaterial, false)

	-- the plaza ends at the throw line: a low fence + invisible wall either side of the tower keeps ground
	-- walkers out of the field without putting anything into the landing lane (Z > ThrowLine.Z)
	local pminX, pmaxX = Layout.Plaza.MinX, Layout.Plaza.MaxX
	local towerHalf = Layout.Platform.Size.X / 2
	for _, side in { -1, 1 } do
		local a = side * (towerHalf + 0.6)
		local b = if side < 0 then pminX + 0.6 else pmaxX - 0.6
		Props.FenceLine(folder, Vector3.new(a, Y, TL.Z - 1), Vector3.new(b, Y, TL.Z - 1), 6, 2.6,
			WorldTheme.YardColors[3], false)
		local edge = if side < 0 then pminX else pmaxX
		Props.Wall(folder, "PlazaEndWall", math.min(side * towerHalf, edge), math.max(side * towerHalf, edge),
			TL.Z - 0.6, TL.Z, Y, ThrowLine.WallHeight)
	end
end

return ThrowLine
