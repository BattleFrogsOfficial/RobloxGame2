--!strict
-- The crossbar street: the shared lane every yard gate opens onto. Flat, clear, bold.
-- Dashed centre line, a zebra crossing in front of each gate, and the big title arch where the
-- street meets the plaza (the top of the T's stem).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local Game = require(Config:WaitForChild("Game")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Street = {}

local Y = Layout.GroundY
local T = WorldTheme.Street

function Street.Build(parent: Instance)
	local folder = Props.Folder(parent, "Street")
	local s = Layout.Street
	local midZ = (s.MinZ + s.MaxZ) / 2

	Props.Slab(folder, "Road", s.MinX, s.MaxX, s.MinZ, s.MaxZ, Y, 1, T.Asphalt)

	-- edge stripes (decal-thin)
	Props.Slab(folder, "EdgeLineN", s.MinX, s.MaxX, s.MinZ + 0.5, s.MinZ + 1.5, Y + 0.05, 0.05, T.Curb, nil, false)
	-- the south edge only exists where the street does not open onto the plaza
	Props.Slab(folder, "EdgeLineSW", s.MinX, Layout.Plaza.MinX, s.MaxZ - 1.5, s.MaxZ - 0.5, Y + 0.05, 0.05, T.Curb, nil, false)
	Props.Slab(folder, "EdgeLineSE", Layout.Plaza.MaxX, s.MaxX, s.MaxZ - 1.5, s.MaxZ - 0.5, Y + 0.05, 0.05, T.Curb, nil, false)

	-- dashed centre line
	local dashes = Props.Folder(folder, "CentreLine")
	local x = s.MinX + 6
	while x + 10 <= s.MaxX - 6 do
		Props.Slab(dashes, "Dash", x, x + 10, midZ - 0.6, midZ + 0.6, Y + 0.05, 0.05, T.Line, nil, false)
		x += 20
	end

	-- zebra crossing in front of each gate
	local zebra = Props.Folder(folder, "Crossings")
	for i = 1, Layout.Yards.Count do
		local cx = Layout.Yards.CentersX[i]
		for k = -2, 2 do
			local zx = cx + k * 3.5
			Props.Slab(zebra, "Stripe", zx - 1, zx + 1, s.MinZ + 3, s.MinZ + 13, Y + 0.07, 0.07, T.Curb, nil, false)
		end
	end

	-- title arch over the junction (pillars sit on the street/plaza boundary, well clear of lanes)
	local arch = Props.Arch(folder, "TitleArch", Vector3.new(0, Y, s.MaxZ), 100, 34,
		Color3.fromRGB(255, 255, 255), WorldTheme.Plaza.Leaderboard, Color3.fromRGB(255, 200, 50),
		string.upper(Game.Name))
	arch:SetAttribute("Decor", true)
end

return Street
