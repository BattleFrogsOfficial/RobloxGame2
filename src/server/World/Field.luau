--!strict
-- The fetch-field stem: 9 ZoneBand floors by distance band (Zones.luau), themed apron strips outside
-- the field, a zone-name arch at each band start, distance lines + DistanceMarker signs every 100
-- studs, and a backdrop at the far end. Each zone's props come from Zones/<ZoneId>.luau.
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

Field.ArchHeight = 44
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

local function buildBand(parent: Instance, zone: any)
	local F = Layout.Field
	local z0, z1 = zoneStartZ(zone), zoneEndZ(zone)
	local band = Props.Slab(parent, "ZoneBand_" .. zone.Id, F.MinX, F.MaxX, z0, z1, Y, 1, zone.Theme.Ground)
	Props.Tag(band, "ZoneBand", { ZoneId = zone.Id, MinDistance = zone.MinDistance, MaxDistance = zone.MaxDistance,
		ZoneName = zone.Name })
	-- slightly darker apron strips either side (outside the field rectangle; no overlap with it)
	local apron = zone.Theme.Ground:Lerp(Color3.new(0, 0, 0), 0.12)
	Props.Slab(parent, "ApronW", Kit.CenterX - Kit.ApronHalf, F.MinX, z0, z1, Y, 1, apron, nil, false)
	Props.Slab(parent, "ApronE", F.MaxX, Kit.CenterX + Kit.ApronHalf, z0, z1, Y, 1, apron, nil, false)
	-- accent stripes marking the clear centre lane edges (decal-thin, non-colliding)
	for _, side in { -1, 1 } do
		local x = Kit.CenterX + side * Kit.LaneHalf
		Props.Slab(parent, "LaneEdge", x - 0.5, x + 0.5, math.max(z0, Layout.ThrowLine.Z + ThrowLine.WallOffset + 1), z1,
			Y + 0.05, 0.05, zone.Theme.Accent, nil, false)
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
		Props.Arch(zf, "Arch", Vector3.new(Kit.CenterX, Y, archZ), Kit.ArchX * 2, Field.ArchHeight,
			T.ArchPillar, T.ArchBoard, zone.Theme.Accent, string.upper(zone.Name))

		local decorModule = ZoneFolder:FindFirstChild(zone.Id)
		if decorModule and decorModule:IsA("ModuleScript") then
			local ctx = {
				Zone = zone,
				Folder = Props.Folder(zf, "Decor"),
				MinZ = math.max(zoneStartZ(zone), wallZ + 4),
				MaxZ = zoneEndZ(zone),
				ArchZ = archZ,
				Rng = Random.new(1000 + zone.Order * 7919),
				Decor = WorldTheme.ZoneDecor[zone.Id],
				Ground = zone.Theme.Ground,
				Accent = zone.Theme.Accent,
				Props = Props,
				Y = Y,
				Taken = {}, -- footprints already placed in this zone (Kit.pick keeps later items clear)
			}
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
