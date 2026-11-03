--!strict
-- World walls: a ring of tall, stepped cliff / hedge faces around the WHOLE map (yards, street, plaza,
-- platform and the full fetch field) so the horizon is never flat ground.
--
--   * Inner line: |X| = Walls.InnerX (well outside the field |x| <= 120 and the zone aprons), Z = Walls.BackZ
--     behind the yards and Z = Walls.FarZ past the end of Mythic Meadow.
--   * Each run is cut into irregular chunks; each chunk is three set-back tiers (low / mid / high) with
--     small yaw + height jitter, a scree wedge at the foot (cliffs) and a lighter band at the top that
--     lerps toward the sky colour so the silhouette melts into the atmosphere.
--   * Colours come from the zone the chunk borders (Zones.luau Theme Ground/Accent); the crossbar
--     (yards / street / plaza) gets green hedge tiers. Materials from WorldTheme.Walls.
--   * Pure scenery: CanCollide / CanQuery / CanTouch / CastShadow all off (never blocks the ball, the
--     camera, raycasts, or throws long shadows over the field). Players are kept in by Boundaries.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Layout = require(Config:WaitForChild("Layout")) :: any
local ZonesCfg = require(Config:WaitForChild("Zones")) :: any
local WorldTheme = require(Config:WaitForChild("WorldTheme")) :: any
local Props = require((script.Parent :: Instance):WaitForChild("Props")) :: any

local Walls = {}

Walls.InnerX = 236 -- nothing of the wall comes closer to the centre line than this
Walls.BackZ = Layout.Yards.CenterZ - Layout.Yards.Size.Z / 2 - 26 -- behind the yard treeline
Walls.FarZ = Layout.Field.MaxZ + 50 -- past the field-end backdrop
Walls.MinHeight = 200
Walls.Depth = 90 -- total thickness of a run (inner face to back)

local W = WorldTheme.Walls
local BLACK = Color3.new(0, 0, 0)

type Palette = { Base: Color3, Mid: Color3, Top: Color3, Band: Color3, Strata: Color3, Material: Enum.Material,
	Hedge: boolean }

local function zonePalette(zone: any): Palette
	local g: Color3, a: Color3 = zone.Theme.Ground, zone.Theme.Accent
	local z = W.Zones[zone.Id] or {}
	local hedge = z.Hedge == true
	return {
		Base = g:Lerp(a, if hedge then 0.05 else 0.3):Lerp(BLACK, if hedge then 0.38 else 0.32),
		Mid = g:Lerp(BLACK, if hedge then 0.22 else 0.16),
		Top = g:Lerp(W.SkyFade, 0.3),
		Band = g:Lerp(W.SkyFade, 0.68),
		Strata = a:Lerp(g, 0.35),
		Material = z.Material or W.Rock,
		Hedge = hedge,
	}
end

local CROSSBAR: Palette = {
	Base = W.Crossbar.Base,
	Mid = W.Crossbar.Mid,
	Top = W.Crossbar.Top:Lerp(W.SkyFade, 0.2),
	Band = W.Crossbar.Top:Lerp(W.SkyFade, 0.65),
	Strata = W.Crossbar.Top,
	Material = W.Crossbar.Material,
	Hedge = true,
}

local palettes: { [string]: Palette } = {}
for _, zone in ZonesCfg do
	palettes[zone.Id] = zonePalette(zone)
end

-- palette for a point along the side walls (world Z)
local function paletteAtZ(z: number): Palette
	if z < Layout.ThrowLine.Z then
		return CROSSBAR
	end
	local d = z - Layout.ThrowLine.Z
	for _, zone in ZonesCfg do
		if d < zone.MaxDistance then
			return palettes[zone.Id]
		end
	end
	return palettes[ZonesCfg[#ZonesCfg].Id]
end

local function part(f: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
	return Props.Part({ Parent = f, Name = name, Size = size, CFrame = cf, Color = color, Material = material,
		Collide = false, Query = false, Shadow = false })
end

-- One run of wall: from `origin` along unit `u` for `length` studs; `n` = outward unit (away from the map).
local function buildRun(f: Instance, name: string, origin: Vector3, u: Vector3, n: Vector3, length: number,
	rng: Random, paletteAt: (Vector3) -> Palette, tall: number)
	local run = Props.Folder(f, name)
	local t = 0
	local k = 0
	while t < length do
		k += 1
		local mid0 = origin + u * t
		local far = math.abs(mid0.Z) > 900
		local w = math.min(if far then rng:NextNumber(70, 110) else rng:NextNumber(38, 68), length - t + 4)
		local center = origin + u * (t + w / 2)
		local pal = paletteAt(center)
		local yaw = math.rad(rng:NextNumber(-4, 4))
		local ww = w + 6 -- overlap neighbours so the face never shows gaps

		-- tier: inner offset (from the inner line), depth, height
		local function tier(tname: string, inner: number, depth: number, height: number, color: Color3, bottom: number?)
			local b = bottom or 0
			local p = center + n * (inner + depth / 2)
			local cf = CFrame.lookAt(Vector3.new(p.X, Layout.GroundY + b + height / 2, p.Z),
				Vector3.new(p.X, Layout.GroundY + b + height / 2, p.Z) + n) * CFrame.Angles(0, yaw, 0)
			return part(run, tname, Vector3.new(ww, height, depth), cf, color, pal.Material)
		end

		-- the yaw swings a chunk's ends inward by up to (ww / 2) * sin(4 deg) ~ 4 studs; keep that clear
		local base = 14 + rng:NextNumber(0, 6)
		local h1 = rng:NextNumber(46, 90)
		local h2 = rng:NextNumber(110, 160) * tall
		local h3 = rng:NextNumber(Walls.MinHeight + 8, Walls.MinHeight + 60) * tall
		local band = rng:NextNumber(34, 50)

		tier("Low", base, rng:NextNumber(18, 26), h1, pal.Base)
		tier("Mid", base + rng:NextNumber(14, 22), 30, h2, pal.Mid)
		local backInner = base + rng:NextNumber(36, 46)
		tier("High", backInner, 34, h3 - band, pal.Top)
		tier("Band", backInner + rng:NextNumber(-2, 3), 34, band, pal.Band, h3 - band)

		if pal.Hedge then
			-- clipped-hedge ledge: a lighter cap slab overhanging the low tier
			if k % 2 == 0 then
				tier("HedgeCap", base - 1.5, 22, 6, pal.Top, h1 - 3)
			end
		else
			-- scree wedge at the foot, rising toward the cliff (tall face at local +Z = outward)
			local sh = rng:NextNumber(12, 22)
			local sd = rng:NextNumber(8, 12)
			local p = center + n * (base - sd / 2 + 1)
			local cf = CFrame.lookAt(Vector3.new(p.X, Layout.GroundY + sh / 2, p.Z),
				Vector3.new(p.X, Layout.GroundY + sh / 2, p.Z) - n) * CFrame.Angles(0, -yaw, 0)
			local wedge = Props.Wedge({ Parent = run, Name = "Scree", Size = Vector3.new(w * 0.8, sh, sd), CFrame = cf,
				Color = pal.Base:Lerp(BLACK, 0.1), Material = pal.Material, Collide = false, Query = false, Shadow = false })
			wedge.CanTouch = false
			-- accent strata stripe on every other mid tier
			if k % 2 == 1 then
				tier("Strata", base + rng:NextNumber(13, 15), 30, 3, pal.Strata, h2 * rng:NextNumber(0.45, 0.7))
			end
		end
		t += w
	end
	return run
end

function Walls.Build(parent: Instance)
	local f = Props.Folder(parent, "Walls")
	local rng = Random.new(31337)
	local X = Walls.InnerX
	local D = Walls.Depth
	local backZ, farZ = Walls.BackZ, Walls.FarZ
	local sideLen = farZ - backZ + 2 * D -- sides run past both ends so the corners close

	local function crossbar(_: Vector3): Palette
		return CROSSBAR
	end
	local lastPal = palettes[ZonesCfg[#ZonesCfg].Id]
	local function farEnd(_: Vector3): Palette
		return lastPal
	end

	-- behind the yards (outward = -Z); spans the corners
	buildRun(f, "Back", Vector3.new(-X - D, 0, backZ), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), 2 * (X + D), rng,
		crossbar, 1)
	-- the two long sides (outward = -X / +X), colour follows the zone they border
	buildRun(f, "West", Vector3.new(-X, 0, backZ - D), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), sideLen, rng,
		function(p: Vector3): Palette
			return paletteAtZ(p.Z)
		end, 1)
	buildRun(f, "East", Vector3.new(X, 0, backZ - D), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), sideLen, rng,
		function(p: Vector3): Palette
			return paletteAtZ(p.Z)
		end, 1)
	-- far end behind Mythic Meadow (outward = +Z), a little taller so it reads across 3,200 studs of haze
	buildRun(f, "Far", Vector3.new(-X - D, 0, farZ), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), 2 * (X + D), rng,
		farEnd, 1.25)
end

return Walls
