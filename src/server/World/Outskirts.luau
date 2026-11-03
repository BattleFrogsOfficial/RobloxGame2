--!strict
-- Everything players see but cannot reach: the grass underlay beneath the whole map, a treeline behind
-- the yards, tree clumps beside the plaza, and a few chunky clouds. The tall scenery walls are Walls.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Outskirts = {}

local Y = Layout.GroundY
local T = WorldTheme.Outskirts

Outskirts.Underlay = { MinX = -720, MaxX = 720, MinZ = -520, MaxZ = Layout.Field.MaxZ + 240, TopY = Y - 0.4 }

function Outskirts.Build(parent: Instance)
	local f = Props.Folder(parent, "Outskirts")
	local u = Outskirts.Underlay
	-- split into <= 2000-stud chunks (Roblox caps a part axis at 2048)
	local z = u.MinZ
	while z < u.MaxZ do
		local z1 = math.min(u.MaxZ, z + 2000)
		Props.Slab(f, "Underlay", u.MinX, u.MaxX, z, z1, u.TopY, 2, T.Ground, nil, true)
		z = z1
	end

	local rng = Random.new(4242)
	local backZ = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2
	-- treeline right behind the yard fences (outside the north boundary, in front of the scenery wall)
	local x = Layout.Street.MinX + 10
	while x < Layout.Street.MaxX do
		Props.Tree(f, Vector3.new(x + rng:NextNumber(-4, 4), Y, backZ - 8 - rng:NextNumber(0, 8)), rng:NextNumber(1.2, 1.7),
			WorldTheme.Plaza.TreeTrunk, WorldTheme.Plaza.TreeLeaf)
		x += 30
	end
	-- tree clumps beside the plaza (outside its side walls, south of the street, north of the field aprons)
	for _, side in { -1, 1 } do
		for k = 0, 7 do
			local px = side * (Layout.Plaza.MaxX + 16 + (k % 4) * 38 + rng:NextNumber(-6, 6))
			local pz = Layout.Street.MaxZ + 14 + (k // 4) * 36 + rng:NextNumber(-6, 6)
			Props.Tree(f, Vector3.new(px, Y, pz), rng:NextNumber(1.3, 1.9), WorldTheme.Plaza.TreeTrunk, WorldTheme.Plaza.TreeLeaf)
		end
	end
	-- street-end caps (the crossbar ends) get a big bush each
	for _, sx in { Layout.Street.MinX - 20, Layout.Street.MaxX + 20 } do
		Props.Bush(f, Vector3.new(sx, Y, (Layout.Street.MinZ + Layout.Street.MaxZ) / 2), 4, T.HillDark)
	end
	-- clouds
	for _ = 1, 14 do
		-- beside the landing lane (|x| >= 62 incl. puffs) and inside the scenery walls
		local cx = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(112, 170)
		local cz = rng:NextNumber(-150, Layout.Field.MaxZ)
		local cy = rng:NextNumber(150, 230)
		local s = rng:NextNumber(0.8, 1.6)
		Props.Ellipsoid(f, "Cloud", CFrame.new(cx, cy, cz), Vector3.new(60, 18, 36) * s, Color3.new(1, 1, 1))
		Props.Ellipsoid(f, "Cloud", CFrame.new(cx + 18 * s, cy + 6 * s, cz), Vector3.new(36, 20, 30) * s, Color3.new(1, 1, 1))
	end
end

return Outskirts
