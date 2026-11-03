--!strict
-- The six player yards on the crossbar (north of the street) + the hedge strips between them.
-- Each yard: YardPlot grass base, rounded white fence with a gate on the street side, a big glowing
-- YardSign over the gate facing the street, 12 DogSpots (4x3 grid, spot 1 nearest the gate),
-- a kennel building with a KennelSign, and a TrophySpot plinth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Yards = {}

local Y = Layout.GroundY
local T = WorldTheme.Yard

-- Yard-local design constants (offsets from the yard centre; all well inside the 110 x 120 plot).
Yards.Local = {
	FenceInset = 1,
	FenceHeight = 4,
	GateWidth = 18,
	SignBoard = Vector3.new(38, 10, 1.5),
	SignBottom = 13,
	SpotSize = 7,
	SpotColsX = { -36, -12, 12, 36 },
	SpotRowsZ = { 22, 2, -18 }, -- row 1 (spots 1-4) nearest the gate (+Z = street side)
	PathWidth = 10,
	Kennel = { X = 32, Z = -44, W = 26, D = 18, H = 10 },
	Trophy = { X = -34, Z = -44, Size = 10, H = 1.2 },
}

-- Rectangles (minX, maxX, minZ, maxZ) of the yards, in world space. Used by the bounds check docs.
function Yards.Rect(i: number): (number, number, number, number)
	local cx = Layout.Yards.CentersX[i]
	local hw = Layout.Yards.Size.X / 2
	local hd = Layout.Yards.Size.Z / 2
	local cz = Layout.Yards.CenterZ
	return cx - hw, cx + hw, cz - hd, cz + hd
end

local function buildKennel(model: Model, cx: number, cz: number, index: number)
	local k = Yards.Local.Kennel
	local kx, kz = cx + k.X, cz + k.Z
	local kennel = Props.Model(model, "Kennel")
	Props.Block(kennel, "Body", Vector3.new(k.W, k.H, k.D), CFrame.new(kx, Y + k.H / 2, kz), T.KennelWall, nil, true)
	-- gable roof: two wedges, high edges meeting along the ridge (X axis)
	local roofH = 5
	local half = k.D / 2 + 1
	local roofY = Y + k.H + roofH / 2
	Props.Wedge({ Parent = kennel, Name = "RoofN", Size = Vector3.new(k.W + 2, roofH, half),
		CFrame = CFrame.new(kx, roofY, kz - half / 2), Color = T.KennelRoof })
	Props.Wedge({ Parent = kennel, Name = "RoofS", Size = Vector3.new(k.W + 2, roofH, half),
		CFrame = CFrame.new(kx, roofY, kz + half / 2) * CFrame.Angles(0, math.pi, 0), Color = T.KennelRoof })
	-- arched doorway (dark block + round top) on the street-facing side
	local front = kz + k.D / 2
	Props.Block(kennel, "Door", Vector3.new(6, 4, 0.4), CFrame.new(kx, Y + 2, front + 0.2), T.KennelDoor)
	Props.Part({ Parent = kennel, Name = "DoorTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 6, 6),
		CFrame = CFrame.new(kx, Y + 4, front + 0.2) * CFrame.Angles(0, math.pi / 2, 0), Color = T.KennelDoor })
	-- KennelSign above the door, facing the street
	local signPos = Vector3.new(kx, Y + k.H - 1.4, front + 0.35)
	local sign = Props.Part({ Parent = kennel, Name = "KennelSign", Size = Vector3.new(14, 2.6, 0.5),
		CFrame = CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, 1)), Color = T.SignBoard })
	Props.Label(sign, "Kennel: 0", { LabelName = "CountLabel", PixelsPerStud = 30 })
	Props.Tag(sign, "KennelSign", { YardIndex = index })
	-- chimney-style bone emblem on the roof ridge, yard colour
	Props.Ball(kennel, "RidgeOrb", Vector3.new(kx, Y + k.H + roofH + 0.8, kz), 2.4,
		WorldTheme.YardColors[index], WorldTheme.AccentMaterial)
	kennel.PrimaryPart = sign
end

local function buildYard(parent: Instance, index: number)
	local cx = Layout.Yards.CentersX[index]
	local cz = Layout.Yards.CenterZ
	local minX, maxX, minZ, maxZ = Yards.Rect(index)
	local L = Yards.Local
	local color: Color3 = WorldTheme.YardColors[index]

	local model = Props.Model(parent, "Yard" .. index)
	model:SetAttribute("YardIndex", index)

	-- base
	local plot = Props.Slab(model, "YardPlot", minX, maxX, minZ, maxZ, Y, 1, T.Grass)
	Props.Tag(plot, "YardPlot", { YardIndex = index })

	-- path from the gate to the middle of the spot grid (decal-thin, walkable)
	local pathMinZ = cz + L.SpotRowsZ[2]
	Props.Slab(model, "Path", cx - L.PathWidth / 2, cx + L.PathWidth / 2, pathMinZ, maxZ, Y + 0.06, 0.06, T.Path)

	-- fence (inset so neighbouring fences never touch the 10-stud hedge gap)
	local i0 = L.FenceInset
	local fy = Y
	local nw = Vector3.new(minX + i0, fy, minZ + i0)
	local ne = Vector3.new(maxX - i0, fy, minZ + i0)
	local sw = Vector3.new(minX + i0, fy, maxZ - i0)
	local se = Vector3.new(maxX - i0, fy, maxZ - i0)
	local gw = L.GateWidth / 2
	local gp = gw + 1.2 -- gate pillar centre: its 2.4-wide body ends exactly at the gate edge, fence ends inside it
	Props.FenceLine(model, nw, ne, 9, L.FenceHeight, T.Fence, true)
	Props.FenceLine(model, nw, sw, 10, L.FenceHeight, T.Fence, true)
	Props.FenceLine(model, ne, se, 10, L.FenceHeight, T.Fence, true)
	Props.FenceLine(model, sw, Vector3.new(cx - gp, fy, maxZ - i0), 9, L.FenceHeight, T.Fence, true)
	Props.FenceLine(model, Vector3.new(cx + gp, fy, maxZ - i0), se, 9, L.FenceHeight, T.Fence, true)

	-- gate pillars in the yard colour
	for _, side in { -1, 1 } do
		local base = Vector3.new(cx + side * gp, fy, maxZ - i0)
		Props.Block(model, "GatePillar", Vector3.new(2.4, 7, 2.4), CFrame.new(base + Vector3.new(0, 3.5, 0)), color)
		Props.Ball(model, "GateOrb", base + Vector3.new(0, 8, 0), 3, color, WorldTheme.AccentMaterial)
	end

	-- YardSign over the gate, facing the street (+Z). Big + glowing for readability across the crossbar.
	local board = Props.Sign(model, "YardSignModel", Vector3.new(cx, fy, maxZ - i0), Vector3.new(0, 0, 1),
		L.SignBoard, L.SignBottom, T.SignBoard, color, "Free Yard",
		{ LabelName = "OwnerLabel", PixelsPerStud = 16, TextColor = T.SignText })
	board.Name = "YardSign"
	Props.Tag(board, "YardSign", { YardIndex = index })
	-- yard number medallion on top of the sign
	local medal = Props.Part({ Parent = model, Name = "YardNumber", Size = Vector3.new(5, 5, 1),
		CFrame = CFrame.lookAt(Vector3.new(cx, fy + L.SignBottom + L.SignBoard.Y + 2.8, maxZ - i0),
			Vector3.new(cx, fy + L.SignBottom + L.SignBoard.Y + 2.8, maxZ + 10)),
		Color = color, Material = WorldTheme.AccentMaterial })
	Props.Label(medal, tostring(index), { PixelsPerStud = 30, TextColor = Color3.new(1, 1, 1) })

	-- dog spots: white rim + grass-light pad. Thin (Size.Y <= 4) so DogService stands dogs on top.
	local spots = Props.Folder(model, "DogSpots")
	for row, rz in L.SpotRowsZ do
		for col, rx in L.SpotColsX do
			local spotIndex = (row - 1) * #L.SpotColsX + col
			local px, pz = cx + rx, cz + rz
			Props.Slab(spots, "SpotRim", px - L.SpotSize / 2 - 0.6, px + L.SpotSize / 2 + 0.6,
				pz - L.SpotSize / 2 - 0.6, pz + L.SpotSize / 2 + 0.6, Y + 0.08, 0.08, T.DogSpotRing, nil, false)
			local spot = Props.Slab(spots, "DogSpot" .. spotIndex, px - L.SpotSize / 2, px + L.SpotSize / 2,
				pz - L.SpotSize / 2, pz + L.SpotSize / 2, Y + 0.16, 0.16, T.DogSpot, nil, false)
			Props.Tag(spot, "DogSpot", { YardIndex = index, SpotIndex = spotIndex })
		end
	end

	buildKennel(model, cx, cz, index)

	-- trophy plinth (BookService places statues on its top face)
	local tr = L.Trophy
	local tx, tz = cx + tr.X, cz + tr.Z
	local plinth = Props.Slab(model, "TrophySpot", tx - tr.Size / 2, tx + tr.Size / 2, tz - tr.Size / 2,
		tz + tr.Size / 2, Y + tr.H, tr.H, T.TrophyPlinth)
	Props.Tag(plinth, "TrophySpot", { YardIndex = index })
	Props.Slab(model, "TrophyTrim", tx - tr.Size / 2 - 0.5, tx + tr.Size / 2 + 0.5, tz - tr.Size / 2 - 0.5,
		tz + tr.Size / 2 + 0.5, Y + 0.4, 0.4, T.TrophyTop, WorldTheme.AccentMaterial, false)

	-- a little greenery in the front corners (inside the fence, off the path and grid)
	for _, side in { -1, 1 } do
		Props.Tree(model, Vector3.new(cx + side * 48, Y, maxZ - 9), 0.9, WorldTheme.Plaza.TreeTrunk, WorldTheme.Plaza.TreeLeaf)
		Props.Bush(model, Vector3.new(cx + side * 49, Y, cz + 2), 0.9, T.Hedge) -- clear of spot roam reach (<= 9.5)
	end
	model.PrimaryPart = plot
end

-- Hedge strips filling the gaps between yards (and the street-end margins), with a lamp at each front.
local function buildGaps(parent: Instance)
	local folder = Props.Folder(parent, "YardGaps")
	local edges = {}
	for i = 1, Layout.Yards.Count do
		local minX, maxX = Yards.Rect(i)
		table.insert(edges, minX)
		table.insert(edges, maxX)
	end
	table.sort(edges)
	local intervals = { { Layout.Street.MinX, edges[1] } }
	for i = 2, #edges - 2, 2 do
		table.insert(intervals, { edges[i], edges[i + 1] })
	end
	table.insert(intervals, { edges[#edges], Layout.Street.MaxX })

	local cz = Layout.Yards.CenterZ
	local hd = Layout.Yards.Size.Z / 2
	local minZ, maxZ = cz - hd, cz + hd
	for _, iv in intervals do
		local a, b = iv[1], iv[2]
		if b - a <= 0 then
			continue
		end
		Props.Slab(folder, "GapGround", a, b, minZ, maxZ, Y, 1, T.GapGround)
		local mid = (a + b) / 2
		local hedgeW = math.min(6, b - a - 2)
		Props.Block(folder, "Hedge", Vector3.new(hedgeW, 4.5, (maxZ - minZ) - 10),
			CFrame.new(mid, Y + 2.25, (minZ + maxZ) / 2 - 3), T.Hedge, nil, true)
		Props.Lamp(folder, Vector3.new(mid, Y, maxZ - 3), 14, WorldTheme.Street.LampPole, WorldTheme.Street.LampGlow, false)
	end
end

function Yards.Build(parent: Instance)
	local folder = Props.Folder(parent, "Yards")
	for i = 1, Layout.Yards.Count do
		buildYard(folder, i)
	end
	buildGaps(folder)
end

return Yards
