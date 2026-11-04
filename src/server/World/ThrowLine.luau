--!strict
-- The cliff edge of the hub plateau along the throw line (Layout.ThrowLine.Z, surface Layout.HubY):
--   * a white throw line across the whole plaza front (the throw zone's front edge is distance 0),
--   * a low visible railing along the whole plaza front (non-colliding; caps below the launch height 44),
--   * ONE invisible collision wall right at the edge, Layout.Edge.GuardHeight tall (well above the railings and any
--     jump), from plaza side wall to plaza side wall, so nobody walks or jumps off the cliff onto the field.
-- The rock cliff face below is Cliff.luau. Nothing here reaches past the edge into the landing lane.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local ThrowLine = {}

local Y = Layout.HubY
local T = WorldTheme.ThrowLine
local TL = Layout.ThrowLine

-- Field.luau keeps its lane stripes / decor this far past the throw line (the cliff foot stands in front of it).
ThrowLine.WallOffset = 8
ThrowLine.LineDepth = 1.2
-- the guard straddles the edge: from Z - 0.4 (inside the throw zone's front strip) to 0.6 over the drop
ThrowLine.GuardMinZ = TL.Z - 0.4
ThrowLine.GuardMaxZ = TL.Z + 0.6

function ThrowLine.Build(parent: Instance)
	local folder = Props.Folder(parent, "ThrowLine")
	local pminX, pmaxX = Layout.Plaza.MinX, Layout.Plaza.MaxX

	-- the throw line: white strip along the edge of the plaza + throw zone (decal-thin, above the zone floor)
	Props.Slab(folder, "Line", pminX, pmaxX, TL.Z - ThrowLine.LineDepth, TL.Z, Y + 0.03, 0.03, T.Line,
		WorldTheme.AccentMaterial, false)

	-- one low railing along the whole plaza front (visual, non-colliding; the guard below does the blocking)
	Props.FenceLine(folder, Vector3.new(pminX + 0.6, Y, TL.Z - 1), Vector3.new(pmaxX - 0.6, Y, TL.Z - 1), 6,
		Layout.Edge.RailHeight, WorldTheme.YardColors[3], false)

	-- the invisible edge wall (Transparency 1, CanQuery false: never blocks the ball, the camera or raycasts).
	-- It overlaps the plaza side walls (Boundaries.luau) at both ends so the corners are sealed.
	local guard = Props.Wall(folder, "EdgeGuard", pminX - 2, pmaxX + 2, ThrowLine.GuardMinZ, ThrowLine.GuardMaxZ, Y,
		Layout.Edge.GuardHeight)
	guard:SetAttribute("EdgeGuard", true)
end

return ThrowLine
