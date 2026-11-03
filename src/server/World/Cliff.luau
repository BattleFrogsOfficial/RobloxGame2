--!strict
-- The plateau cliff: where the hub plateau (Layout.HubY) ends along the throw line (Layout.ThrowLine.Z) it drops
-- to the fetch field (Layout.GroundY) as a face of layered, stepped rock slabs, never one flat box face.
--
--   * Four strata, top to bottom. Each one is cut along X into irregular chunks (independent seams per layer),
--     and each layer steps further out than the one above it, so the face reads as a weathered stepped cliff:
--       layer 1 (lip, ~30..HubY-1)    front Z = edge - 0..0.7   (tucked just under the plaza paving lip)
--       layer 2 (~19..30)             front Z = edge + 0.6..1.6
--       layer 3 (~9..19)              front Z = edge + 1.8..2.8
--       layer 4 (foot, 0..~9)         front Z = edge + 2.8..3.8 (Cliff.MaxOut)
--     Chunk heights jitter so the ledges are uneven; every lower layer overlaps up into the one above (hidden
--     behind it) so there are no gaps. Ledges get moss caps, and the plateau beyond the plaza gets a grass lip.
--   * The slabs run from deep under the west wall to deep under the east wall (|X| <= Cliff.HalfWidth), so the
--     cliff joins the hub-side walls (which rise from the plateau) and the field walls (which rise from the field)
--     with no gaps. The plateau block itself (Outskirts.Plateau) stops just behind the slabs.
--   * Colours: WorldTheme.Cliff (Backyard tones). Pure scenery: non-colliding, non-queryable, no touch, so it never
--     catches the ball, the cutscene's landing raycast or the camera. The landing lane is unaffected: the shortest
--     throw (Game.Throw.MinDistance = 5) lands at edge + 5, beyond the foot (edge + 3.8), and the arc clears every
--     ledge (tools/worldcheck/run.luau samples the arcs against these slabs).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local World = script.Parent :: Instance
local Props = require(World:WaitForChild("Props")) :: any
local Walls = require(World:WaitForChild("Walls")) :: any

local Cliff = {}

local C = WorldTheme.Cliff

Cliff.EdgeZ = Layout.ThrowLine.Z
Cliff.BackZ = Layout.ThrowLine.Z - 3.5 -- slabs reach 0.5 into the plateau block (which ends at edge - 3)
Cliff.HalfWidth = Walls.InnerX + Walls.Depth + 24 -- well under both side walls
Cliff.MaxOut = 3.8
-- { bottom split (nil = field), top split (nil = plateau lip), front offset min, max }
Cliff.Layers = {
	{ Bottom = 30, Top = nil, OutMin = -0.7, OutMax = 0 },
	{ Bottom = 19, Top = 30, OutMin = 0.6, OutMax = 1.6 },
	{ Bottom = 9, Top = 19, OutMin = 1.8, OutMax = 2.8 },
	{ Bottom = nil, Top = 9, OutMin = 2.8, OutMax = Cliff.MaxOut },
}
Cliff.Overlap = 1.5 -- each layer reaches this far down into the one below it
Cliff.TopJitter = 1.2

local function part(f: Instance, name: string, minX: number, maxX: number, minZ: number, maxZ: number, minY: number,
	maxY: number, color: Color3, material: Enum.Material)
	local p = Props.Part({ Parent = f, Name = name, Size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ),
		CFrame = CFrame.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2), Color = color, Material = material,
		Collide = false, Query = false, Shadow = true })
	return p
end

function Cliff.Build(parent: Instance)
	local f = Props.Folder(parent, "Cliff")
	local rng = Random.new(60606)
	local hub, ground = Layout.HubY, Layout.GroundY
	local lipY = hub - 1 -- the plateau top (Outskirts.Plateau, just under the 1-stud hub floors)
	local edge = Cliff.EdgeZ
	local W = Cliff.HalfWidth
	for k, L in Cliff.Layers do
		local layer = Props.Folder(f, "Layer" .. k)
		local x = -W
		local n = 0
		while x < W do
			n += 1
			local w = math.min(rng:NextNumber(8, 22), W - x)
			local x0, x1 = x - 0.3, x + w + 0.3 -- neighbours overlap: no seams
			local bottom = if L.Bottom then ground + L.Bottom - Cliff.Overlap else ground
			local top = if L.Top then ground + L.Top + rng:NextNumber(-Cliff.TopJitter, Cliff.TopJitter) else lipY
			local front = edge + rng:NextNumber(L.OutMin, L.OutMax)
			local strata = C.Strata[rng:NextInteger(1, #C.Strata)] :: Color3
			local color = strata:Lerp(C.Dark, 0.1 * (k - 1) + rng:NextNumber(0, 0.08))
			part(layer, "Rock", x0, x1, Cliff.BackZ, front, bottom, top, color, C.Material)
			-- a thin darker seam band across some chunks (reads as bedding planes)
			if n % 3 == 0 and top - bottom > 6 then
				local sy = bottom + (top - bottom) * rng:NextNumber(0.35, 0.65)
				part(layer, "Seam", x0 + 0.5, x1 - 0.5, front - 0.6, front + 0.12, sy - 0.4, sy + 0.4,
					color:Lerp(C.Dark, 0.45), C.Material)
			end
			-- moss on the exposed ledge (lower layers only: their top sticks out in front of the layer above)
			if L.Top and rng:NextNumber() < 0.55 then
				part(layer, "Moss", x0 + 0.4, x1 - 0.4, edge - 0.8, front - 0.15, top, top + 0.35, C.Moss, C.MossMaterial)
			end
			x += w
		end
	end
	-- grass lip on the plateau edge outside the plaza (the plaza paving covers the lip in between)
	local pminX, pmaxX = Layout.Plaza.MinX, Layout.Plaza.MaxX
	part(f, "Lip", -W, pminX - 2, Cliff.BackZ, edge - 0.85, lipY, lipY + 0.3, C.Lip, C.MossMaterial)
	part(f, "Lip", pmaxX + 2, W, Cliff.BackZ, edge - 0.85, lipY, lipY + 0.3, C.Lip, C.MossMaterial)
	f:SetAttribute("EdgeZ", edge)
	f:SetAttribute("MaxOut", Cliff.MaxOut)
end

return Cliff
