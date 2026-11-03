--!strict
-- Shared helpers for the zone decorators. Decorations obey two placement rules:
--   * "Band" items sit in the OUTER 25% of the field width on each side (|x| in [LaneHalf, FieldHalf]),
--     so the centre lane (|x| < LaneHalf) stays clear for ball flight and dog runs.
--   * "Apron" items sit outside the field (|x| in [FieldHalf + 6, ApronHalf]) for big silhouettes.
-- Points avoid the DistanceMarker signs (every 100 studs, |x| ~ MarkerX) and the zone arch pillars.
-- Every accepted point is also recorded in ctx.Taken (centre + footprint radius = margin) so later Band/Apron
-- calls of the same zone keep clear of earlier ones (no tree inside a doghouse, no bale inside a crop patch).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any

local Kit = {}

local F = Layout.Field
Kit.FieldHalf = (F.MaxX - F.MinX) / 2 -- 120
Kit.CenterX = (F.MaxX + F.MinX) / 2 -- 0
Kit.LaneHalf = Kit.FieldHalf * 0.5 -- 60: centre 50% clear, outer 25% each side for decor
Kit.ApronHalf = Kit.FieldHalf + 100 -- 220: themed ground strip outside the field
Kit.MarkerX = Kit.LaneHalf + 8 -- 68: distance marker signs
Kit.ArchX = Kit.FieldHalf - 8 -- 112: zone arch pillars
Kit.MarkerEvery = 100

export type Ctx = {
	Zone: any,
	Folder: Instance,
	MinZ: number, -- world Z where the band starts
	MaxZ: number,
	ArchZ: number,
	Rng: Random,
	Decor: any, -- WorldTheme.ZoneDecor[ZoneId]
	Ground: Color3,
	Accent: Color3,
	Props: any,
	Y: number,
	Taken: { { X: number, Z: number, R: number } }?,
}

export type Slot = { Pos: Vector3, Side: number }

local function nearMarker(ctx: Ctx, x: number, z: number, margin: number): boolean
	local d = z - Layout.ThrowLine.Z
	local m = d % Kit.MarkerEvery
	local nearLine = m < margin or m > Kit.MarkerEvery - margin
	if nearLine and math.abs(math.abs(x) - Kit.MarkerX) < 6 + margin then
		return true
	end
	if math.abs(z - ctx.ArchZ) < 6 + margin and math.abs(math.abs(x) - Kit.ArchX) < 6 + margin then
		return true
	end
	return false
end

local function pick(ctx: Ctx, count: number, minAbsX: number, maxAbsX: number, spacing: number,
	zPad: number, radius: number): { Slot }
	local out: { Slot } = {}
	local taken = ctx.Taken
	if taken == nil then
		taken = {}
		ctx.Taken = taken
	end
	local takenList = taken :: { { X: number, Z: number, R: number } }
	local tries = 0
	local z0, z1 = ctx.MinZ + zPad, ctx.MaxZ - zPad
	if ctx.ArchZ > z0 - zPad and ctx.ArchZ < z0 + 10 then
		z0 = math.max(z0, ctx.ArchZ + 8)
	end
	while #out < count and tries < count * 40 do
		tries += 1
		local side = if (#out + tries) % 2 == 0 then 1 else -1
		local x = Kit.CenterX + side * ctx.Rng:NextNumber(minAbsX, maxAbsX)
		local z = ctx.Rng:NextNumber(z0, math.max(z0 + 1, z1))
		if nearMarker(ctx, x, z, math.max(spacing * 0.4, radius)) then
			continue
		end
		local ok = true
		for _, s in out do
			if (Vector2.new(s.Pos.X, s.Pos.Z) - Vector2.new(x, z)).Magnitude < spacing then
				ok = false
				break
			end
		end
		if ok then
			for _, t in takenList do
				if (Vector2.new(t.X, t.Z) - Vector2.new(x, z)).Magnitude < t.R + radius then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(out, { Pos = Vector3.new(x, ctx.Y, z), Side = side })
			table.insert(takenList, { X = x, Z = z, R = radius })
		end
	end
	return out
end

-- Points inside the field's outer 25% band. `margin` keeps the item's footprint off the lane edge.
function Kit.Band(ctx: Ctx, count: number, spacing: number, margin: number?): { Slot }
	local m = margin or 4
	return pick(ctx, count, Kit.LaneHalf + m, Kit.FieldHalf - m, spacing, 6 + m, m)
end

-- Points on the apron outside the field.
function Kit.Apron(ctx: Ctx, count: number, spacing: number, margin: number?): { Slot }
	local m = margin or 8
	return pick(ctx, count, Kit.FieldHalf + m, Kit.ApronHalf - m, spacing, m, m)
end

-- Evenly spaced Z values along the band (for fences/rows), skipping nothing.
function Kit.Every(ctx: Ctx, step: number, pad: number): { number }
	local out = {}
	local z = ctx.MinZ + pad
	while z <= ctx.MaxZ - pad do
		table.insert(out, z)
		z += step
	end
	return out
end

function Kit.Yaw(ctx: Ctx): CFrame
	return CFrame.Angles(0, ctx.Rng:NextNumber(0, math.pi * 2), 0)
end

return Kit
