--!strict
-- The ONE throwing platform (Layout.Platform): a white deck set FLUSH into the plaza paving (surface =
-- Layout.ThrowLine.Y = Layout.HubY) with its front edge on the cliff edge (Layout.ThrowLine.Z), so the thrower
-- looks out and down over the whole field. No ramp and no steps: players walk straight on from the plaza.
-- Deck = ThrowPad (PadIndex 1). Throw spot marked at the front edge; 5 QueueSpot markers beside it.
-- The visible front railing is low (caps below the launch height ThrowLine.Y + Game.Throw.LaunchHeight) and
-- non-colliding; the invisible edge wall that stops players walking off the cliff is built by ThrowLine.luau
-- along the whole plaza front.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Platform = {}

local T = WorldTheme.Platform
local PL = Layout.Platform

Platform.RailHeight = 2.4 -- visible railing (caps top out at ~3.15 above the deck, below the +4 launch height)
Platform.SpotSize = 6
Platform.QueueSize = 3.6
Platform.EdgeLine = 1.2 -- the white throw line along the front edge (ThrowLine.luau) is this deep

-- deck rectangle (world XZ) derived from Layout.Platform
function Platform.Rect(): (number, number, number, number)
	local c: Vector3, s: Vector3 = PL.Center, PL.Size
	return c.X - s.X / 2, c.X + s.X / 2, c.Z - s.Z / 2, c.Z + s.Z / 2
end

local function buildDeck(f: Instance)
	local minX, maxX, minZ, maxZ = Platform.Rect()
	local deckTop: number = PL.Center.Y
	local thick: number = PL.Size.Y

	local deck = Props.Slab(f, "Deck", minX, maxX, minZ, maxZ, deckTop, thick, T.Deck, nil, true)
	Props.Tag(deck, "ThrowPad", { PadIndex = 1 })
	deck:SetAttribute("StandRadius", PL.StandRadius)
	deck:SetAttribute("Flush", true)
	-- plank seams running toward the edge (decal-thin, non-colliding) so it reads as a deck, not paving
	local x = minX + 3
	while x < maxX - 2 do
		Props.Slab(f, "Plank", x - 0.15, x + 0.15, minZ + 1, maxZ - Platform.EdgeLine, deckTop + 0.03, 0.03, T.DeckPlank, nil,
			false)
		x += 3
	end
	-- yellow trim on the back and side edges (the front edge carries the white throw line)
	Props.Slab(f, "DeckTrim", minX, maxX, minZ, minZ + 1, deckTop + 0.04, 0.04, T.DeckTrim, WorldTheme.AccentMaterial, false)
	Props.Slab(f, "DeckTrim", minX, minX + 1, minZ + 1, maxZ - Platform.EdgeLine, deckTop + 0.04, 0.04, T.DeckTrim, nil, false)
	Props.Slab(f, "DeckTrim", maxX - 1, maxX, minZ + 1, maxZ - Platform.EdgeLine, deckTop + 0.04, 0.04, T.DeckTrim, nil, false)

	-- throw spot at the front edge
	local ts: Vector3 = PL.ThrowSpot
	local h = Platform.SpotSize / 2
	Props.Slab(f, "ThrowSpotRing", ts.X - h - 0.6, ts.X + h + 0.6, ts.Z - h - 0.6, ts.Z + h + 0.6, deckTop + 0.06, 0.06,
		T.ThrowSpotRing, nil, false)
	Props.Slab(f, "ThrowSpot", ts.X - h, ts.X + h, ts.Z - h, ts.Z + h, deckTop + 0.12, 0.12, T.ThrowSpot,
		WorldTheme.AccentMaterial, false) -- the bright spot + ring mark it; no world text

	-- queue markers
	local q = Platform.QueueSize / 2
	for i, p in PL.QueueSpots do
		local marker = Props.Slab(f, "QueueSpot" .. i, p.X - q, p.X + q, p.Z - q, p.Z + q, deckTop + 0.1, 0.1, T.QueueSpot,
			nil, false)
		Props.Tag(marker, "QueueSpot", { Order = i })
	end

	-- visible low railing along the deck front (the cliff edge); non-colliding (the edge wall stops players)
	local y = deckTop
	Props.FenceLine(f, Vector3.new(minX + 0.6, y, maxZ - 1), Vector3.new(maxX - 0.6, y, maxZ - 1), 4.5, Platform.RailHeight,
		T.Rail, false)
	return deck
end

function Platform.Build(parent: Instance)
	local f = Props.Folder(parent, "Platform")
	local deck = buildDeck(f)
	f:SetAttribute("DeckY", deck.CFrame.Position.Y + deck.Size.Y / 2)
end

return Platform
