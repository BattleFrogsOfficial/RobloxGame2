--!strict
-- The fetch-field stem: 9 ZoneBand floors by distance band (Zones.luau), each with its own ground material
-- and colour, themed apron strips outside the field, a zone-name arch + a themed gate (Kit.Gate) at each band
-- start, distance lines + DistanceMarker signs every 100 studs, and a backdrop at the far end. Each zone's
-- decorations, landmark and particles come from Zones/<ZoneId>.luau. The centre lane (|x| <= Kit.LaneHalf)
-- only ever holds flat (<= 1 stud), non-colliding dressing; the arch spans it with a 220 x 34 opening.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local ZonesCfg = require(Config:WaitForChild("Zones")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local World = script.Parent :: Instance
local Props = require(World:WaitForChild("Props")) :: any
local ThrowLine = require(World:WaitForChild("ThrowLine")) :: any
local ZoneFolder = World:WaitForChild("Zones")
local Kit = require(ZoneFolder:WaitForChild("Kit")) :: any

local Field = {}

local Y = Layout.GroundY
local T = WorldTheme.Field

-- The throwing platform is raised to Y = 40 (eye ~45): the arch beam sits above eye level so no arch ever
-- hides the field ground or the zones behind it (see Kit.ZoneArch).
Field.ArchHeight = 56
Field.FirstArchOffset = 12 -- the Backyard arch sits just past the throw-line wall

local function zoneStartZ(zone: any): number
	return Layout.DistanceToZ(zone.MinDistance)
end

local function zoneEndZ(zone: any): number
	return Layout.DistanceToZ(zone.MaxDistance)
end

function Field.ArchZ(zone: any): number
	local z = zoneStartZ(zone)
	if zone.Order == 1 then
		z += Field.FirstArchOffset
	end
	return z
end

local rgb = Color3.fromRGB
local M = Enum.Material

-- Ground look per zone: material, colour (distinct neighbours, readable from the platform), lane-edge
-- trim colour/material and the themed gate at the zone start.
export type GroundStyle = { Material: Enum.Material, Color: Color3, Trim: Color3, TrimMaterial: Enum.Material?,
	Gate: any }
Field.Ground = {
	Backyard = { Material = M.Grass, Color = rgb(112, 186, 70), Trim = rgb(255, 255, 255),
		Gate = { Kind = "Picket", Color = rgb(255, 255, 255), Trim = rgb(255, 255, 255), Height = 4 } },
	Park = { Material = M.LeafyGrass, Color = rgb(72, 150, 92), Trim = rgb(236, 214, 168),
		Gate = { Kind = "Hedge", Color = rgb(46, 128, 60), Trim = rgb(255, 150, 190), Material = M.LeafyGrass, Height = 5 } },
	Beach = { Material = M.Sand, Color = rgb(238, 214, 156), Trim = rgb(70, 170, 230),
		Gate = { Kind = "Dune", Color = rgb(224, 196, 136), Trim = rgb(120, 190, 90), Material = M.Sand, Height = 3.5 } },
	Farm = { Material = M.Ground, Color = rgb(150, 112, 70), Trim = rgb(240, 200, 90),
		Gate = { Kind = "Rail", Color = rgb(170, 120, 70), Trim = rgb(200, 60, 50), Material = M.Wood, Height = 4.5 } },
	Forest = { Material = M.Grass, Color = rgb(52, 98, 50), Trim = rgb(120, 84, 50),
		Gate = { Kind = "Logs", Color = rgb(120, 82, 48), Trim = rgb(90, 62, 38), Material = M.Wood, Height = 4 } },
	SnowyPeaks = { Material = M.Snow, Color = rgb(238, 245, 252), Trim = rgb(140, 190, 235),
		Gate = { Kind = "Ice", Color = rgb(170, 215, 250), Trim = rgb(255, 255, 255), Material = M.Ice, Height = 5 } },
	CityRooftops = { Material = M.Concrete, Color = rgb(112, 114, 124), Trim = rgb(255, 196, 60),
		Gate = { Kind = "Parapet", Color = rgb(150, 150, 162), Trim = rgb(255, 196, 60), TrimMaterial = M.Neon, Height = 4 } },
	SpaceStation = { Material = M.DiamondPlate, Color = rgb(58, 64, 92), Trim = rgb(120, 220, 255), TrimMaterial = M.Neon,
		Gate = { Kind = "Bulkhead", Color = rgb(190, 196, 214), Trim = rgb(120, 220, 255), Material = M.Metal,
			TrimMaterial = M.Neon, Height = 6 } },
	MythicMeadow = { Material = M.Glacier, Color = rgb(196, 168, 240), Trim = rgb(255, 215, 120), TrimMaterial = M.Neon,
		Gate = { Kind = "Crystal", Color = rgb(255, 130, 230), Trim = rgb(140, 220, 255), Material = M.Neon, Height = 7 } },
} :: { [string]: GroundStyle }

local function buildBand(parent: Instance, zone: any)
	local F = Layout.Field
	local z0, z1 = zoneStartZ(zone), zoneEndZ(zone)
	local g = Field.Ground[zone.Id]
	local band = Props.Slab(parent, "ZoneBand_" .. zone.Id, F.MinX, F.MaxX, z0, z1, Y, 1,
		if g then g.Color else zone.Theme.Ground, if g then g.Material else nil)
	Props.Tag(band, "ZoneBand", { ZoneId = zone.Id, MinDistance = zone.MinDistance, MaxDistance = zone.MaxDistance,
		ZoneName = zone.Name })
	-- threshold stripe across the whole width at the band start (flat, so the lane stays clear): the colour
	-- change reads as a line from the platform
	if zone.Order > 1 then
		local t = Props.Slab(parent, "Threshold", F.MinX, F.MaxX, z0 + 1, z0 + 4, Y + 0.06, 0.06,
			if g then g.Trim else zone.Theme.Accent, if g and g.TrimMaterial then g.TrimMaterial else nil, false)
		t.CanQuery = false
		t.CastShadow = false
	end
	-- slightly darker apron strips either side (outside the field rectangle; no overlap with it)
	local apron = (if g then g.Color else zone.Theme.Ground):Lerp(Color3.new(0, 0, 0), 0.12)
	Props.Slab(parent, "ApronW", Kit.CenterX - Kit.ApronHalf, F.MinX, z0, z1, Y, 1, apron, nil, false)
	Props.Slab(parent, "ApronE", F.MaxX, Kit.CenterX + Kit.ApronHalf, z0, z1, Y, 1, apron, nil, false)
	-- accent stripes marking the clear centre lane edges (decal-thin, non-colliding)
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * Kit.LaneHalf
		local edge = Props.Slab(parent, "LaneEdge", x - 0.5, x + 0.5,
			math.max(z0, Layout.ThrowLine.Z + ThrowLine.WallOffset + 1), z1, Y + 0.05, 0.05,
			if g then g.Trim else zone.Theme.Accent, if g and g.TrimMaterial then g.TrimMaterial else nil, false)
		edge.CanQuery = false
		edge.CastShadow = false
	end
	return band
end

local function buildMarkers(parent: Instance)
	local folder = Props.Folder(parent, "DistanceMarkers")
	local F = Layout.Field
	local maxD = Layout.Field.MaxZ - Layout.ThrowLine.Z
	local d = Kit.MarkerEvery
	while d < maxD do -- the final distance is marked by the end backdrop
		local z = Layout.DistanceToZ(d)
		Props.Slab(folder, "Line" .. d, F.MinX, F.MaxX, z - 0.6, z + 0.6, Y + 0.05, 0.05, T.DistanceLine, nil, false)
		for _, side in { -1, 1 } do
			local board = Props.Sign(folder, "Marker" .. d, Vector3.new(Kit.CenterX + side * Kit.MarkerX, Y, z),
				Vector3.new(0, 0, -1), Vector3.new(10, 5, 0.8), 2.5, T.MarkerBoard, T.MarkerPost, tostring(d),
				{ PixelsPerStud = 20, TextColor = T.MarkerText })
			Props.Tag(board, "DistanceMarker", { Distance = d })
		end
		d += Kit.MarkerEvery
	end
end

local function buildEnd(parent: Instance)
	local F = Layout.Field
	local m = Props.Model(parent, "FieldEnd")
	local z = F.MaxZ
	local width = Kit.ApronHalf * 2
	local wall = Props.Block(m, "Backdrop", Vector3.new(width, 36, 4), CFrame.new(Kit.CenterX, Y + 18, z + 2), T.EndWall)
	Props.Block(m, "BackdropTrim", Vector3.new(width, 3, 4.4), CFrame.new(Kit.CenterX, Y + 36, z + 2),
		ZonesCfg[#ZonesCfg].Theme.Accent, WorldTheme.AccentMaterial)
	local label = Props.Label(wall, tostring(math.floor(Layout.Field.MaxZ - Layout.ThrowLine.Z)) .. "! THE EDGE OF THE MAP ... FOR NOW", { PixelsPerStud = 4,
		TextColor = Color3.fromRGB(150, 110, 210), StrokeColor = Color3.new(1, 1, 1) })
	label.Size = UDim2.fromScale(0.5, 0.5)
	label.Position = UDim2.fromScale(0.25, 0.25)
end

function Field.Build(parent: Instance)
	local folder = Props.Folder(parent, "Field")
	local wallZ = Layout.ThrowLine.Z + ThrowLine.WallOffset
	for _, zone in ZonesCfg do
		local zf = Props.Folder(folder, zone.Id)
		buildBand(zf, zone)

		local archZ = Field.ArchZ(zone)
		local arch = Kit.ZoneArch(Props, zf, Vector3.new(Kit.CenterX, Y, archZ), Kit.ArchX * 2, Field.ArchHeight,
			T.ArchPillar, T.ArchBoard, zone.Theme.Accent, string.upper(zone.Name))
		arch:SetAttribute("ZoneId", zone.Id)

		local ctx = {
			Zone = zone,
			Folder = Props.Folder(zf, "Decor"),
			MinZ = math.max(archZ + Kit.DecorStartOffset, wallZ + 4),
			MaxZ = zoneEndZ(zone),
			StartZ = math.max(zoneStartZ(zone), wallZ),
			ArchZ = archZ,
			Rng = Random.new(1000 + zone.Order * 7919),
			Decor = WorldTheme.ZoneDecor[zone.Id],
			Ground = if Field.Ground[zone.Id] then Field.Ground[zone.Id].Color else zone.Theme.Ground,
			Accent = zone.Theme.Accent,
			Props = Props,
			Y = Y,
			Taken = {}, -- footprints already placed in this zone (Kit.pick keeps later items clear)
		}
		local style = Field.Ground[zone.Id]
		if style then
			Kit.Gate(ctx, style.Gate)
		end

		local decorModule = ZoneFolder:FindFirstChild(zone.Id)
		if decorModule and decorModule:IsA("ModuleScript") then
			local ok, err = pcall(function()
				local decorate = require(decorModule) :: any
				decorate(ctx)
			end)
			if not ok then
				warn(("[World] zone decorator %s failed: %s"):format(zone.Id, tostring(err)))
			end
		end
	end
	buildMarkers(folder)
	buildEnd(folder)
end

return Field
