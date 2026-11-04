--!strict
-- THE THROW ZONE (Layout.ThrowZone): a big brown dirt strip set FLUSH into the plaza paving at the cliff edge
-- (surface = Layout.ThrowZone.Y = Layout.HubY), its front edge on the throw line (Layout.ThrowLine.Z). Walking into it
-- is all it takes to throw: there is no pad, no spot and no queue. A bold light-tan border runs round the back and
-- the sides and just behind the white throw line (ThrowLine.luau), so it reads as "the throw zone" from anywhere in
-- the plaza. The floor part is tagged "ThrowZone" and, for compatibility, "ThrowPad" (PadIndex 1).
-- Nothing collidable stands on it: the border and patches are decal-thin and non-colliding, the railing and the
-- invisible edge wall along the edge are ThrowLine.luau's (tools/worldcheck checks the zone is clear).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local ThrowZone = {}

local T = WorldTheme.ThrowZone
local Z = Layout.ThrowZone

ThrowZone.Border = 1.6 -- border width (studs)
ThrowZone.FrontGap = 1.2 -- the white throw line (ThrowLine.LineDepth) sits in front of the front border

-- darker / lighter dirt patches (offsets from the zone centre; decal-thin), so the strip reads as dirt, not paint
ThrowZone.Patches = {
	{ -36, -3, 9, 5, "DirtPatch" }, { -14, 4, 12, 4, "DirtLight" }, { 6, -4, 10, 6, "DirtPatch" },
	{ 27, 3, 13, 5, "DirtLight" }, { 40, -5, 6, 4, "DirtPatch" }, { -25, 6, 7, 3, "DirtPatch" },
}

function ThrowZone.Rect(): (number, number, number, number)
	return Z.MinX, Z.MaxX, Z.MinZ, Z.MaxZ
end

function ThrowZone.Build(parent: Instance)
	local f = Props.Folder(parent, "ThrowZone")
	local minX, maxX, minZ, maxZ = ThrowZone.Rect()
	local y: number = Z.Y

	-- the floor itself (collidable, top = the plateau surface): part of the plaza floor
	local floor = Props.Slab(f, "ThrowZone", minX, maxX, minZ, maxZ, y, 1, T.Dirt, T.Material, true)
	Props.Tag(floor, "ThrowZone")
	Props.Tag(floor, "ThrowPad", { PadIndex = 1 }) -- compatibility: the old platform tag
	floor:SetAttribute("Flush", true)

	-- bold lighter border: back, both sides, and a front strip just behind the white throw line
	local b = ThrowZone.Border
	local fz = maxZ - ThrowZone.FrontGap
	Props.Slab(f, "ZoneBorder", minX, maxX, minZ, minZ + b, y + 0.05, 0.05, T.Border, nil, false)
	Props.Slab(f, "ZoneBorder", minX, maxX, fz - b, fz, y + 0.05, 0.05, T.Border, nil, false)
	Props.Slab(f, "ZoneBorder", minX, minX + b, minZ + b, fz - b, y + 0.05, 0.05, T.Border, nil, false)
	Props.Slab(f, "ZoneBorder", maxX - b, maxX, minZ + b, fz - b, y + 0.05, 0.05, T.Border, nil, false)

	-- dirt patches inside the border
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	for _, p in ThrowZone.Patches do
		local px, pz, w, d = cx + p[1], cz + p[2], p[3] / 2, p[4] / 2
		Props.Slab(f, "Dirt", math.max(minX + b, px - w), math.min(maxX - b, px + w), math.max(minZ + b, pz - d),
			math.min(fz - b, pz + d), y + 0.03, 0.03, T[p[5]], T.Material, false)
	end
	f:SetAttribute("SurfaceY", y)
end

return ThrowZone
