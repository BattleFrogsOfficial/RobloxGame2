--!strict
-- The fetch-field stem: 9 ZoneBand floors by distance band (Zones.luau), each with its own ground material
-- and colour, themed apron strips outside the field, a side-only zone-name gantry (Kit.ZoneArch) plus a low
-- full-width boundary line (Kit.Boundary) at each band start, distance lines + blank DistanceMarker boards every
-- 100 studs, and a backdrop at the far end. Each zone's plot is FILLED by Zones/<ZoneId>.luau: ground cover over
-- the whole plot, 20-40 spaced props and one landmark (see Kit.luau for the rules). Nothing in the field
-- collides except the ZoneBand floors, and nothing but the ZoneBand answers queries in the landing area.
--
-- Streaming (Workspace.StreamingEnabled, default.project.json): each zone's Ground model, arch, boundary line
-- and landmark are Persistent (the platform always sees the whole field's silhouette); props and ground-cover
-- cells are Atomic models that stream in around the player / the cutscene's RequestStreamAroundAsync.
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

-- The throwing platform is raised to Y = 40: arches are side-only sign gantries (Kit.ZoneArch), nothing
-- crosses the lane, so they never enter the platform camera's view or the ball arc.
Field.ArchHeight = 34
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
		Gate = { Kind = "Picket", Color = rgb(255, 255, 255), Trim = rgb(255, 255, 255), Height = 3 } },
	Park = { Material = M.LeafyGrass, Color = rgb(72, 150, 92), Trim = rgb(236, 214, 168),
		Gate = { Kind = "Hedge", Color = rgb(46, 128, 60), Trim = rgb(255, 150, 190), Material = M.LeafyGrass, Height = 3 } },
	Beach = { Material = M.Sand, Color = rgb(238, 214, 156), Trim = rgb(70, 170, 230),
		Gate = { Kind = "Dune", Color = rgb(224, 196, 136), Trim = rgb(120, 190, 90), Material = M.Sand, Height = 3 } },
	Farm = { Material = M.Ground, Color = rgb(150, 112, 70), Trim = rgb(240, 200, 90),
		Gate = { Kind = "Rail", Color = rgb(170, 120, 70), Trim = rgb(200, 60, 50), Material = M.Wood, Height = 4 } },
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

-- Same layout on every server: the per-zone seed comes from the zone Id.
function Field.Seed(id: string): number
	local h = 7
	for i = 1, #id do
		h = (h * 131 + string.byte(id, i)) % 2147483629
	end
	return h
end

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
	return band
end

local function buildMarkers(parent: Instance): { any }
	local folder = Props.Folder(parent, "DistanceMarkers")
	local boxes = {}
	local F = Layout.Field
	local maxD = Layout.Field.MaxZ - Layout.ThrowLine.Z
	local d = Kit.MarkerEvery
	while d < maxD do -- the final distance is marked by the end backdrop
		local z = Layout.DistanceToZ(d)
		Props.Slab(folder, "Line" .. d, F.MinX, F.MaxX, z - 0.6, z + 0.6, Y + 0.05, 0.05, T.DistanceLine, nil, false)
		for _, side in { -1, 1 } do
			local board = Props.Sign(folder, "Marker" .. d, Vector3.new(Kit.CenterX + side * Kit.MarkerX, Y, z),
				Vector3.new(0, 0, -1), Vector3.new(10, 5, 0.8), 2.5, T.MarkerBoard, T.MarkerPost, nil) -- no world text
			Props.Tag(board, "DistanceMarker", { Distance = d })
			local model = board.Parent :: Model
			model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.CanQuery = false
				end
			end
			local bx = Kit.Bounds(model)
			if bx then
				table.insert(boxes, bx)
			end
		end
		d += Kit.MarkerEvery
	end
	return boxes
end

local function buildEnd(parent: Instance)
	local F = Layout.Field
	local m = Props.Model(parent, "FieldEnd")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local z = F.MaxZ
	local width = Kit.BackdropHalf * 2
	Props.Block(m, "Backdrop", Vector3.new(width, 36, 4), CFrame.new(Kit.CenterX, Y + 18, z + 2), T.EndWall)
	Props.Block(m, "BackdropTrim", Vector3.new(width, 3, 4), CFrame.new(Kit.CenterX, Y + 36, z + 2),
		ZonesCfg[#ZonesCfg].Theme.Accent, WorldTheme.AccentMaterial)
	-- no text on the backdrop (world text rule: only the zone arch boards, yard owner signs and kennel count)
end

function Field.Build(parent: Instance)
	local folder = Props.Folder(parent, "Field")
	local wallZ = Layout.ThrowLine.Z + ThrowLine.WallOffset
	local markerBoxes = buildMarkers(folder)
	for zi, zone in ZonesCfg do
		local zf = Props.Folder(folder, zone.Id)
		local ground = Props.Model(zf, "Ground")
		ground.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		buildBand(ground, zone)

		local archZ = Field.ArchZ(zone)
		local arch = Kit.ZoneArch(Props, zf, Vector3.new(Kit.CenterX, Y, archZ), Kit.ArchX * 2, Field.ArchHeight,
			T.ArchPillar, T.ArchBoard, zone.Theme.Accent, string.upper(zone.Name))
		arch:SetAttribute("ZoneId", zone.Id)

		local z0, z1 = zoneStartZ(zone), zoneEndZ(zone)
		local ctx = {
			Zone = zone,
			ZoneFolder = zf,
			Folder = Props.Folder(zf, "Props"),
			CoverFolder = Props.Folder(zf, "Cover"),
			GroundModel = ground,
			MinZ = math.max(z0, wallZ + 1),
			MaxZ = z1,
			StartZ = math.max(z0, wallZ),
			ArchZ = archZ,
			BoundaryZ = archZ + Kit.BoundaryOffset,
			Rng = Random.new(Field.Seed(zone.Id)),
			Decor = WorldTheme.ZoneDecor[zone.Id],
			Ground = if Field.Ground[zone.Id] then Field.Ground[zone.Id].Color else zone.Theme.Ground,
			Accent = zone.Theme.Accent,
			Props = Props,
			Y = Y,
			Boxes = {},
			CoverCells = {},
			CoverItems = 0,
			PropCount = 0,
		}
		-- fixed obstacles props keep clear of: marker signs, arch pillars, the next zone's boundary / the end wall
		for _, b in markerBoxes do
			if b.z1 > z0 - 10 and b.z0 < z1 + 10 then
				Kit.Obstacle(ctx, b, "DistanceMarker")
			end
		end
		for _, p in arch:GetDescendants() do
			if p:IsA("BasePart") then
				local pb = Kit.PartBox(p :: BasePart)
				if pb.y0 <= Y + 1 then
					Kit.Obstacle(ctx, pb, "ArchPillar")
				end
			end
		end
		local nextZ = if zi < #ZonesCfg then z1 + Kit.BoundaryOffset - 5 else z1
		Kit.Obstacle(ctx, { x0 = Layout.Field.MinX, x1 = Layout.Field.MaxX, y0 = Y, y1 = Y + 8, z0 = nextZ, z1 = nextZ + 10 },
			"NextBoundary")

		local style = Field.Ground[zone.Id]
		if style then
			Kit.Boundary(ctx, style.Gate)
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
		zf:SetAttribute("CoverItems", ctx.CoverItems)
		zf:SetAttribute("PropCount", ctx.PropCount)
	end
	buildEnd(folder)
end

return Field
