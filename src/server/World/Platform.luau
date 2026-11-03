--!strict
-- The ONE raised throwing platform (Layout.Platform): a stone tower whose deck surface sits at
-- Layout.ThrowLine.Y (40) with its front edge on the throw line, and a 30-degree ramp up from the plaza.
-- Deck = ThrowPad (PadIndex 1). Throw spot marked at the front edge; 5 QueueSpot markers beside it.
-- Visible railings are low (top < launch height ThrowSpot.Y + 4) and non-colliding; invisible,
-- non-queryable colliders stop players falling off without catching the camera or anything else.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Platform = {}

local T = WorldTheme.Platform
local PL = Layout.Platform

Platform.RailHeight = 2.4 -- visible railing (caps top out at ~3.2 above the deck, below the +4 launch height)
Platform.ColliderHeight = 12 -- invisible fall guard above the deck / beside the ramp
Platform.SpotSize = 6
Platform.QueueSize = 3.6

-- deck rectangle (world XZ) derived from Layout.Platform
function Platform.Rect(): (number, number, number, number)
	local c: Vector3, s: Vector3 = PL.Center, PL.Size
	return c.X - s.X / 2, c.X + s.X / 2, c.Z - s.Z / 2, c.Z + s.Z / 2
end

local function buildTower(f: Instance, minX: number, maxX: number, minZ: number, maxZ: number, deckBottom: number)
	local tower = Props.Block(f, "Tower", Vector3.new(maxX - minX, deckBottom - Layout.GroundY, maxZ - minZ),
		CFrame.new((minX + maxX) / 2, (deckBottom + Layout.GroundY) / 2, (minZ + maxZ) / 2), T.Tower, nil, true)
	tower:SetAttribute("Walkable", false)
	-- decorative bands (slightly proud of the side/back faces, flush with the front so nothing pokes into the field)
	for _, y in { 10, 22, 34 } do
		Props.Slab(f, "TowerBand", minX - 0.3, maxX + 0.3, minZ - 0.3, maxZ, y + 0.6, 1.2, T.TowerBand, nil, false)
	end
	-- coloured panel on both side faces (no world text)
	for _, side in { -1, 1 } do
		local x = if side < 0 then minX - 0.45 else maxX + 0.45
		local pos = Vector3.new(x, 27.5, (minZ + maxZ) / 2)
		Props.Part({ Parent = f, Name = "TitleBoard", Size = Vector3.new(maxZ - minZ - 4, 7, 0.4),
			CFrame = CFrame.lookAt(pos, pos + Vector3.new(side, 0, 0)), Color = T.TowerSign })
	end
end

local function buildRamp(f: Instance)
	local bottom: Vector3, top: Vector3 = PL.RampBottom, PL.RampTop
	local w = PL.RampWidth
	local run = top.Z - bottom.Z
	local rise = top.Y - bottom.Y
	-- WedgePart: tall face at local +Z (the deck end), slope rising from local -Z
	local ramp = Props.Wedge({ Parent = f, Name = "Ramp", Size = Vector3.new(w, rise, run),
		CFrame = CFrame.new(bottom.X, bottom.Y + rise / 2, (bottom.Z + top.Z) / 2), Color = T.Ramp, Collide = true })
	ramp:SetAttribute("Walkable", true)
	ramp:SetAttribute("SlopeDeg", math.deg(math.atan(rise / run)))

	-- painted stripes on the slope (non-colliding, decal-thin, aligned with the surface)
	local angle = math.atan(rise / run)
	local slopeLen = math.sqrt(run * run + rise * rise)
	local dir = (top - bottom).Unit
	local n = math.floor(slopeLen / 9)
	for k = 1, n - 1 do
		local p = bottom + dir * (slopeLen * k / n)
		local cf = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(-angle, 0, 0) * CFrame.new(0, 0.04, 0)
		Props.Part({ Parent = f, Name = "RampStripe", Size = Vector3.new(w - 3, 0.06, 1.2), CFrame = cf,
			Color = T.RampStripe, Query = false, Shadow = false })
	end

	-- railings on both sides (visual) + invisible guards
	local railX = w / 2 - 0.6
	for _, side in { -1, 1 } do
		Props.FenceLine(f, Vector3.new(bottom.X + side * railX, bottom.Y, bottom.Z + 0.6),
			Vector3.new(top.X + side * railX, top.Y, top.Z), 5, Platform.RailHeight, T.Rail, false)
		local x0 = bottom.X + side * (w / 2)
		Props.Wall(f, "RampGuard", math.min(x0, x0 + side), math.max(x0, x0 + side), bottom.Z, top.Z,
			bottom.Y, rise + Platform.ColliderHeight)
	end
	return ramp
end

local function buildDeck(f: Instance)
	local minX, maxX, minZ, maxZ = Platform.Rect()
	local deckTop: number = PL.Center.Y
	local thick: number = PL.Size.Y
	buildTower(f, minX, maxX, minZ, maxZ, deckTop - thick)

	local deck = Props.Slab(f, "Deck", minX, maxX, minZ, maxZ, deckTop, thick, T.Deck, nil, true)
	Props.Tag(deck, "ThrowPad", { PadIndex = 1 })
	deck:SetAttribute("StandRadius", PL.StandRadius)
	-- yellow edge trim (decal-thin)
	Props.Slab(f, "DeckTrim", minX, maxX, maxZ - 1, maxZ, deckTop + 0.04, 0.04, T.DeckTrim, WorldTheme.AccentMaterial, false)
	Props.Slab(f, "DeckTrim", minX, minX + 1, minZ, maxZ - 1, deckTop + 0.04, 0.04, T.DeckTrim, nil, false)
	Props.Slab(f, "DeckTrim", maxX - 1, maxX, minZ, maxZ - 1, deckTop + 0.04, 0.04, T.DeckTrim, nil, false)

	-- throw spot at the front edge
	local ts: Vector3 = PL.ThrowSpot
	local h = Platform.SpotSize / 2
	Props.Slab(f, "ThrowSpotRing", ts.X - h - 0.6, ts.X + h + 0.6, ts.Z - h - 0.6, ts.Z + h + 0.6, deckTop + 0.06, 0.06,
		T.ThrowSpotRing, nil, false)
	local spot = Props.Slab(f, "ThrowSpot", ts.X - h, ts.X + h, ts.Z - h, ts.Z + h, deckTop + 0.12, 0.12, T.ThrowSpot,
		WorldTheme.AccentMaterial, false)
	local _ = spot -- the bright spot + ring mark it; no world text

	-- queue markers
	local q = Platform.QueueSize / 2
	for i, p in PL.QueueSpots do
		local marker = Props.Slab(f, "QueueSpot" .. i, p.X - q, p.X + q, p.Z - q, p.Z + q, deckTop + 0.1, 0.1, T.QueueSpot,
			nil, false)
		Props.Tag(marker, "QueueSpot", { Order = i })
	end

	-- visible low railings (front, sides, back beside the ramp opening)
	local inset = 1.0 -- rail caps stay behind the deck front edge (= throw line)
	local rh = Platform.RailHeight
	local y = deckTop
	local gap = PL.RampWidth / 2 + 0.6
	local rails = {
		{ Vector3.new(minX + inset, y, maxZ - inset), Vector3.new(maxX - inset, y, maxZ - inset) }, -- front
		{ Vector3.new(minX + inset, y, minZ + inset), Vector3.new(minX + inset, y, maxZ - inset) }, -- west
		{ Vector3.new(maxX - inset, y, minZ + inset), Vector3.new(maxX - inset, y, maxZ - inset) }, -- east
		{ Vector3.new(minX + inset, y, minZ + inset), Vector3.new(-gap, y, minZ + inset) }, -- back west
		{ Vector3.new(gap, y, minZ + inset), Vector3.new(maxX - inset, y, minZ + inset) }, -- back east
	}
	for _, r in rails do
		Props.FenceLine(f, r[1], r[2], 4.5, rh, T.Rail, false)
	end

	-- invisible fall guards just inside the deck edges (Transparency 1, CanQuery false: never block the
	-- ball, the camera or raycasts)
	local ch = Platform.ColliderHeight
	Props.Wall(f, "DeckGuardFront", minX, maxX, maxZ - 1, maxZ, deckTop, ch)
	Props.Wall(f, "DeckGuardW", minX, minX + 1, minZ, maxZ - 1, deckTop, ch)
	Props.Wall(f, "DeckGuardE", maxX - 1, maxX, minZ, maxZ - 1, deckTop, ch)
	Props.Wall(f, "DeckGuardBW", minX + 1, -PL.RampWidth / 2, minZ, minZ + 1, deckTop, ch)
	Props.Wall(f, "DeckGuardBE", PL.RampWidth / 2, maxX - 1, minZ, minZ + 1, deckTop, ch)
	return deck
end

function Platform.Build(parent: Instance)
	local f = Props.Folder(parent, "Platform")
	local deck = buildDeck(f)
	buildRamp(f)
	f:SetAttribute("DeckY", deck.CFrame.Position.Y + deck.Size.Y / 2)
end

return Platform
