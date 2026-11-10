-- Builds every pixel-art (voxel) model in the game out of plain Parts:
-- eggs, animals, the sea staff, barbells and palm trees.
-- Models are built at the origin, feet on y = 0, facing -Z, all anchored.
-- Call Voxel.weld(model) to make one movable by its Root.

local Config = require(script.Parent.Config)

local Voxel = {}

local BLACK = Color3.fromRGB(20, 20, 25)
local WHITE = Color3.fromRGB(250, 250, 250)

local function newModel(name: string): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = m
	m.PrimaryPart = root
	return m, root
end

local function addPart(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = model
	return p
end
Voxel.addPart = addPart

-- Returns a function b(sx, sy, sz, x, y, z, color, material?) that adds a box
-- measured in "pixels" of size P studs, positioned by its center.
local function pixelBuilder(model: Model, P: number)
	return function(sx, sy, sz, x, y, z, color, material)
		return addPart(model, Vector3.new(sx, sy, sz) * P, CFrame.new(x * P, y * P, z * P), color, material)
	end
end

local function shade(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount or 0.25)
end

-- A rounded lump (body, head, shell) sx x sy x sz pixels, centered at
-- (cx, cy, cz). It is stacked from one-pixel layers whose width follows a
-- rounded profile, each layer a plus-shaped pair of boxes so the corners are
-- clipped too. Layers of equal size are merged into one taller box.
-- `power` sets the shape: 2 is a ball, higher is boxier.
local function blob(b, sx: number, sy: number, sz: number, cx: number, cy: number, cz: number, color: Color3, power: number?)
	local n = power or 3
	local function flush(y0: number, y1: number, w: number, d: number)
		local h = y1 - y0
		local y = cy - sy / 2 + y0 + h / 2
		if w >= 4 and d >= 4 then
			b(w, h, d - 2, cx, y, cz, color)
			b(w - 2, h, d, cx, y, cz, color)
		else
			b(w, h, d, cx, y, cz, color)
		end
	end
	local start, lastW, lastD = 0, nil, nil
	for i = 0, sy - 1 do
		local t = math.abs(((i + 0.5) / sy) * 2 - 1)
		local k = (1 - t ^ n) ^ (1 / n)
		-- Even sizes keep every layer centered on the pixel grid.
		local w = math.max(2, math.floor(sx * k / 2 + 0.5) * 2)
		local d = math.max(2, math.floor(sz * k / 2 + 0.5) * 2)
		if lastW and (w ~= lastW or d ~= lastD) then
			flush(start, i, lastW, lastD)
			start = i
		end
		lastW, lastD = w, d
	end
	flush(start, sy, lastW :: number, lastD :: number)
end

local function keep(part: BasePart): BasePart
	part:SetAttribute("Keep", true) -- eyes etc. keep their color in Gold / Rainbow variants
	return part
end

-- A 2x2 black eye with a white highlight pixel, on a face pointing along
-- (dx, dz) (one of them is -1 or 1, the other 0).
local function eye(b, x: number, y: number, z: number, dx: number, dz: number)
	keep(b(2, 2, 2, x, y, z, BLACK))
	local sideways = dz ~= 0
	keep(b(1, 1, 1, x + dx * 0.7 + (sideways and 0.5 or 0), y + 0.5, z + dz * 0.7 + (sideways and 0 or -0.5), WHITE))
end

----------------------------------------------------------------------------
-- Animal templates. pal = { p = primary, s = secondary, a = accent }
-- Coordinates are in pixels; models stand on y = 0 and face -Z.
----------------------------------------------------------------------------
local Templates = {}

function Templates.crab(b, pal)
	blob(b, 18, 7, 13, 0, 7.5, 0, pal.p)
	blob(b, 12, 3, 8, 0, 11.5, 0, pal.s, 2)
	b(2, 1, 2, -3, 13.1, -1, pal.a)
	b(2, 1, 2, 3, 13.1, 1, pal.a)
	b(2, 1, 2, 0, 13.1, -2.5, pal.a)
	keep(b(4, 1, 1, 0, 6, -6.6, BLACK))
	for _, sx in { -1, 1 } do
		b(2, 4, 2, sx * 4, 13, -5, pal.p)
		keep(b(3, 3, 3, sx * 4, 16.5, -5, WHITE))
		keep(b(2, 2, 1, sx * 4, 16.5, -6.6, BLACK))
		b(2, 2, 1, sx * 5.5, 8, -6.6, pal.a)
		b(4, 3, 4, sx * 10, 8, -6, pal.p)
		blob(b, 7, 7, 5, sx * 12, 9.5, -10, pal.p, 2)
		b(2, 2, 4, sx * 13.5, 11.5, -13.5, pal.a)
		b(2, 2, 4, sx * 10.5, 8, -13.5, pal.a)
		for _, z in { -2, 2, 6 } do
			b(5, 2, 2, sx * 11, 5.5, z, pal.s)
			b(2, 5, 2, sx * 14, 2.5, z, pal.s)
			b(3, 1, 2, sx * 14.5, 0.5, z, shade(pal.s))
		end
	end
end

function Templates.bird(b, pal, o)
	local L = 2 * (o.legs or (o.upright and 1 or 3))
	local dark = shade(pal.s)
	for _, sx in { -1, 1 } do
		b(2, L, 2, sx * 2.5, L / 2, 0, pal.a)
		b(4, 1, 5, sx * 2.5, 0.5, -1.5, pal.a)
		b(1, 1, 2, sx * 2.5 - 1.5, 0.5, -4.5, pal.a)
		b(1, 1, 2, sx * 2.5 + 1.5, 0.5, -4.5, pal.a)
		-- wing with darker feather tips
		b(2, 8, 9, sx * 6, L + 6.5, 0.5, pal.s)
		b(2, 5, 3, sx * 6, L + 5, 6, pal.s)
		b(2, 3, 2, sx * 6, L + 4, 8.5, dark)
		b(1, 1, 7, sx * 6.6, L + 8, 0.5, dark)
	end
	blob(b, 11, 11, 13, 0, L + 5.5, 0, pal.p)
	b(8, o.upright and 9 or 7, 2, 0, L + 5, -6, pal.s)
	b(6, o.upright and 7 or 5, 1, 0, L + 5, -7, pal.s)
	for _, x in { -2.5, 0, 2.5 } do
		b(2, 2, 6, x, L + 7, 8.5, pal.s)
		b(2, 1, 2, x, L + 7, 12, dark)
	end
	local hy, hz
	if o.upright then
		hy, hz = L + 14.5, -1
	else
		hy, hz = L + 13.5, -5
	end
	blob(b, 9, 9, 9, 0, hy, hz, pal.p)
	eye(b, -2.5, hy + 1, hz - 4, 0, -1)
	eye(b, 2.5, hy + 1, hz - 4, 0, -1)
	if o.bigBeak then
		b(4, 2, 10, 0, hy - 1, hz - 9, pal.a)
		blob(b, 4, 4, 8, 0, hy - 3.5, hz - 8, pal.a:Lerp(Color3.new(1, 1, 1), 0.25), 2)
	else
		b(4, 2, 4, 0, hy - 0.5, hz - 6.5, pal.a)
		b(2, 1, 2, 0, hy - 0.5, hz - 9, pal.a)
		b(3, 1, 3, 0, hy - 2, hz - 6, shade(pal.a))
	end
	if o.crest then
		b(2, 5, 2, 0, hy + 6, hz + 1, pal.a)
		b(2, 4, 2, 0, hy + 5.5, hz + 3, pal.s)
		b(2, 3, 2, 0, hy + 5, hz - 1, pal.a)
	end
end

function Templates.fish(b, pal, o)
	local w, h, len = 8, 10, 16
	if o.long then
		len = 24
	end
	if o.round then
		w, h, len = 12, 12, 12
	end
	local hy = h / 2 + 4
	local dark = shade(pal.p)
	blob(b, w, h, len, 0, hy, 0, pal.p)
	b(w - 2, 2, len - 6, 0, hy - h / 2 + 1, 0, pal.s)
	b(w + 0.3, 1, len - 10, 0, hy, 0, pal.s)
	-- forked tail
	b(2, 6, 3, 0, hy, len / 2 + 1, pal.s)
	b(2, 4, 3, 0, hy + 3.5, len / 2 + 3.5, pal.s)
	b(2, 4, 3, 0, hy - 3.5, len / 2 + 3.5, pal.s)
	-- dorsal fin
	b(2, 3, 7, 0, hy + h / 2 + 1, 1, pal.s)
	b(2, 2, 4, 0, hy + h / 2 + 3, 2, pal.s)
	for _, sx in { -1, 1 } do
		b(3, 1, 4, sx * (w / 2 + 1), hy - 2, -2, pal.s)
		b(2, 1, 2, sx * (w / 2 + 2.5), hy - 2, -0.5, pal.s)
		eye(b, sx * (w / 2 - 0.6), hy + 1.5, -len / 2 + 4, sx, 0)
		b(1, 3, 1, sx * (w / 2 - 0.3), hy, -len / 2 + 7, dark)
	end
	if o.teeth then
		keep(b(w - 2, 1, 1, 0, hy - 2, -len / 2 + 0.4, BLACK))
		for _, x in { -2, 0, 2 } do
			keep(b(1, 1, 1, x, hy - 1.4, -len / 2, WHITE))
		end
	end
	if o.horn then
		b(2, 2, 6, 0, hy + 2, -len / 2 - 3, pal.a)
		b(1, 1, 6, 0, hy + 2, -len / 2 - 8, pal.a)
	end
	if o.lure then
		b(1, 6, 1, 0, hy + h / 2 + 3, -len / 2 + 3, pal.s)
		b(1, 1, 3, 0, hy + h / 2 + 6, -len / 2 + 1.5, pal.s)
		b(3, 3, 3, 0, hy + h / 2 + 5, -len / 2 - 1, pal.a, Enum.Material.Neon)
	end
	if o.round then
		for _, sp in { { 6.4, 2, 0 }, { -6.4, 2, 0 }, { 6.4, -2, 2 }, { -6.4, -2, 2 }, { 0, 6.4, 2 }, { 0, 6.4, -2 }, { 3, 5.4, 0 }, { -3, 5.4, 0 }, { 4, 0, -5.4 }, { -4, 0, -5.4 }, { 4, 0, 5.4 }, { -4, 0, 5.4 } } do
			b(1, 1, 1, sp[1], hy + sp[2], sp[3], pal.a)
		end
	end
end

function Templates.quad(b, pal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			b(3, 5, 3, sx * 3.5, 2.5, sz * 5, pal.s)
			b(4, 1, 4, sx * 3.5, 0.5, sz * 5 - 0.5, shade(pal.s))
		end
		eye(b, sx * 3, 16.5, -14.2, 0, -1)
		b(2, 2, 2, sx * 4, 20.5, -9, pal.s)
		b(1, 1, 1, sx * 4, 20.5, -10.1, pal.a)
		keep(b(1, 1, 1, sx * 2, 12.5, -17.1, BLACK))
	end
	blob(b, 12, 9, 17, 0, 9.5, 0, pal.p)
	b(8, 2, 12, 0, 5.4, 0, pal.a)
	blob(b, 10, 10, 9, 0, 15, -10, pal.p)
	blob(b, 6, 4, 4, 0, 13, -15, pal.a, 2)
	keep(b(2, 1, 1, 0, 14.5, -17, BLACK))
	blob(b, 4, 4, 10, 0, 9, 13, pal.s, 2)
end

function Templates.seal(b, pal, o)
	blob(b, 12, 8, 20, 0, 4, 2, pal.p)
	blob(b, 10, 9, 10, 0, 9, -11, pal.p)
	blob(b, 6, 4, 4, 0, 7.5, -16.5, pal.s, 2)
	keep(b(2, 1, 1, 0, 9, -18.6, BLACK))
	b(2, 1, 2, -2, 8.1, 3, pal.s)
	b(2, 1, 2, 2.5, 8.1, 7, pal.s)
	b(2, 1, 2, 0, 8.1, -2, pal.s)
	for _, sx in { -1, 1 } do
		eye(b, sx * 3, 10.5, -15.6, 0, -1)
		keep(b(1, 1, 1, sx * 2, 7, -18.6, BLACK))
		b(5, 1, 6, sx * 7.5, 0.5, -4, pal.s)
		b(3, 1, 3, sx * 9.5, 0.5, -1, pal.s)
		b(4, 1, 5, sx * 3, 0.5, 14, pal.s)
		if o.tusks then
			keep(b(1, 6, 1, sx * 2, 3.5, -17.5, pal.a))
		end
	end
	b(6, 2, 3, 0, 1.5, 11.5, pal.s)
end

function Templates.octo(b, pal, o)
	blob(b, 14, 14, 14, 0, 17, 0, pal.p)
	b(2, 2, 2, 6.2, 20, 2, pal.s)
	b(2, 2, 2, -6.2, 18, -2, pal.s)
	b(2, 2, 2, 2, 23.2, 3, pal.s)
	b(2, 2, 2, -3, 23.2, -2, pal.s)
	keep(b(2, 1, 1, 0, 13.5, -6.9, BLACK))
	for _, sx in { -1, 1 } do
		keep(b(4, 4, 2, sx * 3.6, 18, -6.4, WHITE))
		keep(b(2, 2, 1, sx * 3.6, 17.4, -7.7, BLACK))
		keep(b(1, 1, 1, sx * 3.6 + 0.5, 18.6, -7.9, WHITE))
	end
	for k = 0, 7 do
		local ang = k * math.pi / 4 + math.pi / 8
		local x, z = math.cos(ang) * 6, math.sin(ang) * 6
		b(3, 6, 3, x, 8, z, pal.p)
		b(3, 4, 3, x * 1.3, 3.5, z * 1.3, pal.s)
		b(2, 2, 2, x * 1.7, 1, z * 1.7, pal.s)
		b(1, 1, 1, x * 1.3, 1, z * 1.3, shade(pal.s))
	end
	if o.crown then
		b(10, 2, 10, 0, 25, 0, pal.a)
		for _, c in { { 4, 4 }, { -4, 4 }, { 4, -4 }, { -4, -4 } } do
			b(2, 4, 2, c[1], 28, c[2], pal.a)
			keep(b(1, 1, 1, c[1], 30.5, c[2], WHITE))
		end
	end
end

function Templates.turtle(b, pal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			b(4, 4, 4, sx * 6, 2, sz * 6, pal.p)
			b(4, 1, 1, sx * 6, 0.5, sz * 6 - 2.4, shade(pal.p))
		end
		eye(b, sx * 2, 8, -13.6, 0, -1)
		b(3, 1, 3, sx * 3, 12.6, 0, pal.a)
	end
	b(12, 3, 14, 0, 4.5, 0, pal.p)
	blob(b, 14, 8, 16, 0, 9, 0, pal.s, 2.5)
	b(4, 1, 4, 0, 13.1, 0, pal.a)
	b(3, 1, 3, 0, 12.6, 4.5, pal.a)
	b(3, 1, 3, 0, 12.6, -4.5, pal.a)
	blob(b, 6, 6, 6, 0, 7, -11, pal.p)
	b(2, 2, 3, 0, 4, 9, pal.p)
end

function Templates.frog(b, pal)
	local dark = shade(pal.p)
	for _, sx in { -1, 1 } do
		blob(b, 5, 5, 8, sx * 7, 2.5, 2, pal.p, 2)
		b(6, 1, 3, sx * 7.5, 0.5, -3, dark)
		b(2, 5, 2, sx * 4, 2.5, -5, pal.p)
		b(3, 1, 3, sx * 4, 0.5, -6, dark)
		blob(b, 4, 4, 4, sx * 4, 12, -3.5, pal.p, 2)
		eye(b, sx * 4, 12.2, -5, 0, -1)
		b(2, 1, 2, sx * 2.5, 11.1, 2, dark)
		keep(b(1, 1, 1, sx * 1, 9, -6.1, BLACK))
	end
	blob(b, 12, 9, 12, 0, 6.5, 0, pal.p)
	b(8, 5, 2, 0, 5, -5.4, pal.s)
	b(8, 1, 1, 0, 7.5, -6.2, pal.a)
	b(2, 1, 2, 0, 11.1, -1, dark)
end

function Templates.serpent(b, pal)
	local segs = { { 6, 18 }, { 10, 11 }, { 12, 4 }, { 13, -3 } }
	for _, sgm in segs do
		blob(b, 8, 8, 8, 0, sgm[1], sgm[2], pal.p)
		b(6, 2, 6, 0, sgm[1] - 3.5, sgm[2], pal.s)
		b(2, 3, 3, 0, sgm[1] + 5, sgm[2], pal.a)
		b(2, 2, 2, 0, sgm[1] + 4.5, sgm[2] + 3, pal.a)
	end
	blob(b, 4, 4, 6, 0, 4, 24, pal.s, 2)
	b(2, 5, 3, 0, 5, 27.5, pal.a)
	blob(b, 10, 10, 12, 0, 16, -10, pal.p)
	b(8, 2, 7, 0, 11, -15, pal.s)
	for _, x in { -3, -1, 1, 3 } do
		keep(b(1, 1, 1, x, 12.3, -18.2, WHITE))
	end
	for _, sx in { -1, 1 } do
		eye(b, sx * 4.4, 18, -13, sx, 0)
		b(2, 5, 2, sx * 3, 23, -8, pal.a)
		b(1, 3, 1, sx * 3, 26.5, -7, pal.a)
		b(1, 1, 6, sx * 5, 13, -18, pal.a)
		b(1, 3, 1, sx * 5, 11.5, -21, pal.a)
		keep(b(1, 1, 1, sx * 2, 15, -16.1, BLACK))
	end
end

local function rarityTier(rarity: string): number
	return Config.RarityIndex[rarity] or 1
end

local function applyVariant(model: Model, variant: string?)
	local v = variant and Config.Variants[variant]
	if v and v.tint then
		-- Gold, Platinum: wash every part toward the metal's color.
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Root" and not p:GetAttribute("Keep") then
				p.Color = p.Color:Lerp(v.color, v.tint)
				p.Reflectance = v.shine
			end
		end
	elseif variant == "Rainbow" then
		local i = 0
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Root" and not p:GetAttribute("Keep") then
				i += 1
				local hue = (p.CFrame.Position.Y * 0.09 + i * 0.03) % 1
				p.Color = Color3.fromHSV(hue, 0.7, 1)
			end
		end
	end
end

function Voxel.animalScale(animalId: string): number
	local a = Config.AnimalById[animalId]
	local tier = rarityTier(a.rarity)
	-- Rarer animals are much bigger, so a strong base is obvious at a glance.
	-- 0.16 studs per pixel for a Common pet: half the old pixel size, with
	-- twice as many pixels in each direction.
	local s = 0.16 * (Config.SizeByTier[tier] or 1)
	if a.opts and a.opts.huge then
		s *= 1.3
	end
	return s
end

function Voxel.animal(animalId: string, variant: string?): Model
	local a = Config.AnimalById[animalId]
	local model = newModel(animalId)
	local o = table.clone(a.opts or {})
	if a.model == "octo" and rarityTier(a.rarity) >= 6 then
		o.crown = true
	end
	local b = pixelBuilder(model, Voxel.animalScale(animalId))
	local template = Templates[a.model] or Templates.quad
	template(b, { p = a.p, s = a.s, a = a.a }, o)
	if o.ghost then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.Name ~= "Root" and not p:GetAttribute("Keep") then
				p.Transparency = 0.3
			end
		end
	end
	applyVariant(model, variant)
	return model
end

----------------------------------------------------------------------------
-- Eggs
----------------------------------------------------------------------------
-- Width of the egg at each one-pixel layer, bottom to top.
local EGG_WIDTHS = { 6, 8, 10, 12, 12, 12, 12, 12, 12, 12, 10, 10, 8, 8, 6, 4 }
-- Speckles: { layer, face, sideways offset, size }
local EGG_SPOTS = {
	{ 3, "-z", 2, 2 },
	{ 4, "+x", -2, 1 },
	{ 5, "-x", 1, 2 },
	{ 6, "-z", -3, 1 },
	{ 6, "+z", 2, 2 },
	{ 7, "+x", 2, 2 },
	{ 8, "-z", 1, 1 },
	{ 8, "-x", -3, 1 },
	{ 9, "+z", -2, 2 },
	{ 10, "-z", -1, 2 },
	{ 10, "+x", -1, 1 },
	{ 11, "-x", 2, 1 },
	{ 12, "+z", 1, 1 },
	{ 13, "-z", 1, 1 },
	{ 13, "+x", 0, 1 },
	{ 14, "-x", 0, 1 },
}

function Voxel.eggScale(eggId: string): number
	local e = Config.EggById[eggId]
	return 0.21 * (1 + (e.tier - 1) * 0.08)
end

function Voxel.egg(eggId: string, variant: string?, withNest: boolean?): Model
	local e = Config.EggById[eggId]
	local model = newModel(eggId .. "Egg")
	local P = Voxel.eggScale(eggId)
	local b = pixelBuilder(model, P)
	local baseY = withNest and 1.4 or 0
	local base, spot = e.base, e.spot
	local v = variant and Config.Variants[variant]
	local metal = v ~= nil and v.tint ~= nil
	if metal then
		-- Gold, Platinum: a metal shell with pale speckles.
		base = base:Lerp(v.color, 0.75)
		spot = spot:Lerp(v.color:Lerp(Color3.new(1, 1, 1), 0.6), 0.6)
	end
	local rainbow = variant == "Rainbow"

	-- Shell: layers of equal width are merged into one taller box (Rainbow
	-- eggs keep every layer separate so each can have its own color).
	local function layerBox(first: number, last: number, w: number)
		local h = last - first + 1
		local y = baseY + first - 1 + h / 2
		local c = rainbow and Color3.fromHSV(((first - 1) / #EGG_WIDTHS) % 1, 0.6, 1) or base
		b(w, h, w - 2, 0, y, 0, c)
		b(w - 2, h, w, 0, y, 0, c)
	end
	local first = 1
	for i = 2, #EGG_WIDTHS + 1 do
		if rainbow or EGG_WIDTHS[i] ~= EGG_WIDTHS[first] then
			layerBox(first, i - 1, EGG_WIDTHS[first])
			first = i
		end
	end
	-- A lighter shine patch up one side.
	b(1, 4, 2, EGG_WIDTHS[9] / 2 - 0.42, baseY + 9, -3, base:Lerp(Color3.new(1, 1, 1), 0.55))
	b(1, 1, 1, EGG_WIDTHS[12] / 2 - 0.42, baseY + 11.5, -3, base:Lerp(Color3.new(1, 1, 1), 0.55))

	for _, sp in EGG_SPOTS do
		local layer, side, t, size = sp[1], sp[2], sp[3], sp[4]
		local w = EGG_WIDTHS[layer]
		local y = baseY + layer - 1 + size / 2
		local edge = w / 2 - size / 2 + 0.12
		local x, z = 0, 0
		if side == "+x" then
			x, z = edge, t
		elseif side == "-x" then
			x, z = -edge, t
		elseif side == "+z" then
			x, z = t, edge
		else
			x, z = t, -edge
		end
		b(size, size, size, x, y, z, rainbow and WHITE or spot)
	end

	if metal then -- shine the shell (before the nest is added)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.Name ~= "Root" then
				p.Reflectance = v.shine
			end
		end
	end
	if withNest then
		local browns = { Color3.fromRGB(120, 70, 35), Color3.fromRGB(150, 90, 45), Color3.fromRGB(100, 58, 30) }
		b(10, 1, 10, 0, 0.5, 0, browns[3])
		for k = 0, 15 do
			local ang = k * math.pi / 8
			b(3, 1.4, 3, math.cos(ang) * 7.2, 0.7, math.sin(ang) * 7.2, browns[k % 3 + 1])
		end
		for k = 0, 11 do
			local ang = k * math.pi / 6 + 0.2
			b(3, 1.2, 2, math.cos(ang) * 8.6, 1.8, math.sin(ang) * 8.6, browns[(k + 1) % 3 + 1])
		end
		for k = 0, 5 do
			local ang = k * math.pi / 3 + 0.5
			b(4, 0.6, 1, math.cos(ang) * 9.6, 2.6, math.sin(ang) * 9.6, browns[k % 2 + 1])
		end
	end
	if e.glow or rainbow then
		local light = Instance.new("PointLight")
		light.Color = rainbow and Color3.fromRGB(255, 150, 255) or e.spot
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = model.PrimaryPart
	end
	return model
end

----------------------------------------------------------------------------
-- Props
----------------------------------------------------------------------------

-- The sea staff. The part named "Handle" is where the hand grips.
function Voxel.staff(): Model
	local model = Instance.new("Model")
	model.Name = "Staff"
	local woodA = Color3.fromRGB(150, 90, 45)
	local woodB = Color3.fromRGB(120, 70, 35)
	local teal = Color3.fromRGB(40, 200, 200)
	local handle = addPart(model, Vector3.new(0.35, 1.2, 0.35), CFrame.new(), woodA)
	handle.Name = "Handle"
	addPart(model, Vector3.new(0.45, 0.4, 0.45), CFrame.new(0, -0.8, 0), woodB)
	for i = 1, 3 do
		addPart(model, Vector3.new(0.35, 1.2, 0.35), CFrame.new(0, i * 1.2, 0), i % 2 == 0 and woodA or woodB)
	end
	addPart(model, Vector3.new(1.7, 0.3, 0.3), CFrame.new(0, 4.35, 0), teal)
	for _, x in { -0.7, 0.7 } do
		addPart(model, Vector3.new(0.3, 0.9, 0.3), CFrame.new(x, 4.95, 0), teal)
	end
	addPart(model, Vector3.new(0.3, 1.3, 0.3), CFrame.new(0, 5.15, 0), teal)
	local gem = addPart(model, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 3.95, -0.1), Color3.fromRGB(120, 255, 255), Enum.Material.Neon)
	gem.Name = "Gem"
	return model
end

-- A market stall, built at the origin with its counter facing -Z. The part
-- named "Counter" is where customers stand; "Sign" is the board on top.
function Voxel.stall(width: number, depth: number, stripe: Color3): Model
	local model = newModel("Stall")
	local wood, dark = Color3.fromRGB(165, 110, 60), Color3.fromRGB(120, 75, 40)
	local function solid(size: Vector3, at: CFrame, color: Color3): Part
		local p = addPart(model, size, at, color)
		p.CanCollide = true
		return p
	end
	local counter = solid(Vector3.new(width, 3, 2), CFrame.new(0, 1.5, -depth / 2 + 1), wood)
	counter.Name = "Counter"
	solid(Vector3.new(width + 0.6, 0.5, 2.6), CFrame.new(0, 3.2, -depth / 2 + 1), dark)
	solid(Vector3.new(width, 7, 0.6), CFrame.new(0, 3.5, depth / 2 - 0.3), wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			solid(Vector3.new(0.8, 9.4, 0.8), CFrame.new(sx * (width / 2 - 0.4), 4.7, sz * (depth / 2 - 0.4)), dark)
		end
		solid(Vector3.new(0.6, 5, depth - 1.6), CFrame.new(sx * (width / 2 - 0.3), 2.5, 0), wood)
	end
	-- Striped awning with a hanging front lip.
	local n = math.max(3, math.floor(width / 1.6))
	local w = (width + 2) / n
	for i = 1, n do
		local x = -(width + 2) / 2 + (i - 0.5) * w
		local color = i % 2 == 0 and stripe or Color3.fromRGB(250, 250, 250)
		addPart(model, Vector3.new(w, 0.6, depth + 3), CFrame.new(x, 9.7, -0.8), color)
		addPart(model, Vector3.new(w, 1.3, 0.6), CFrame.new(x, 8.9, -depth / 2 - 2), color)
	end
	local sign = addPart(model, Vector3.new(width * 0.8, 2.6, 0.5), CFrame.new(0, 11.6, -depth / 2 - 1), dark)
	sign.Name = "Sign"
	return model
end

function Voxel.barbell(tier: number): Model
	local model = newModel("Barbell")
	local hue = ((tier - 1) * 0.13) % 1
	local plate = Color3.fromHSV(hue, 0.25 + math.min(0.5, tier * 0.06), 0.35 + math.min(0.4, tier * 0.05))
	addPart(model, Vector3.new(6, 0.3, 0.3), CFrame.new(), Color3.fromRGB(200, 200, 210), Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		addPart(model, Vector3.new(0.6, 2.2, 2.2), CFrame.new(sx * 2.4, 0, 0), plate)
		addPart(model, Vector3.new(0.4, 1.6, 1.6), CFrame.new(sx * 1.95, 0, 0), plate:Lerp(Color3.new(1, 1, 1), 0.25))
		addPart(model, Vector3.new(0.3, 0.6, 0.6), CFrame.new(sx * 2.85, 0, 0), Color3.fromRGB(200, 200, 210))
	end
	return model
end

function Voxel.palm(seed: number): Model
	local rng = Random.new(seed)
	local model = newModel("Palm")
	local bark = { Color3.fromRGB(150, 105, 60), Color3.fromRGB(125, 85, 45) }
	local lean = rng:NextNumber(-0.4, 0.4)
	local top = Vector3.new()
	for i = 0, 6 do
		top = Vector3.new(lean * i * i * 0.15, 1 + i * 2, 0)
		addPart(model, Vector3.new(1.6, 2, 1.6), CFrame.new(top), bark[i % 2 + 1])
	end
	top += Vector3.new(0, 1.2, 0)
	local greens = { Color3.fromRGB(70, 175, 60), Color3.fromRGB(50, 145, 50) }
	for k = 0, 6 do
		local yaw = k * math.pi * 2 / 7 + rng:NextNumber(0, 0.4)
		local cf = CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-0.35, 0, 0) * CFrame.new(0, 0, -3)
		addPart(model, Vector3.new(1.4, 0.5, 6), cf, greens[k % 2 + 1])
		addPart(model, Vector3.new(1, 0.5, 2.5), cf * CFrame.new(0, -0.6, -3.6) * CFrame.Angles(-0.5, 0, 0), greens[(k + 1) % 2 + 1])
	end
	for k = 0, 2 do
		local yaw = k * math.pi * 2 / 3
		addPart(model, Vector3.new(0.8, 0.8, 0.8), CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, -1, -0.9), Color3.fromRGB(110, 70, 35))
	end
	return model
end

----------------------------------------------------------------------------
-- Icons: small models shown in ViewportFrames wherever the UI needs a picture.
----------------------------------------------------------------------------
local Icons = {}

function Icons.cash(b)
	local green, light, band = Color3.fromRGB(70, 190, 80), Color3.fromRGB(150, 235, 140), Color3.fromRGB(245, 240, 200)
	for i = 0, 2 do
		b(8, 1.6, 4, i * 0.6 - 0.6, 0.8 + i * 1.7, i * 0.5 - 0.5, i % 2 == 0 and green or light)
		b(1.6, 1.7, 4.1, i * 0.6 - 0.6, 0.8 + i * 1.7, i * 0.5 - 0.5, band)
	end
end

function Icons.luck(b)
	local g, dark = Color3.fromRGB(80, 210, 90), Color3.fromRGB(45, 150, 60)
	for _, c in { { -1.6, 6.6 }, { 1.6, 6.6 }, { -1.6, 3.4 }, { 1.6, 3.4 } } do
		b(3, 3, 1.2, c[1], c[2], 0, g)
		b(1, 1, 1.3, c[1], c[2], 0, dark)
	end
	b(1, 1, 1.2, 0, 5, 0, dark)
	b(1, 3, 1, 0.6, 1.5, 0, dark)
end

function Icons.book(b)
	local cover, page = Color3.fromRGB(60, 130, 235), Color3.fromRGB(250, 250, 245)
	b(7, 9, 1, 0, 4.5, 0.8, cover)
	b(7, 9, 1, 0, 4.5, -0.8, cover)
	b(6, 8, 1.2, 0.3, 4.5, 0, page)
	b(1, 9, 2.6, -3.5, 4.5, 0, Color3.fromRGB(40, 95, 190))
	b(3, 1, 0.3, 0.5, 6.5, -1.4, Color3.fromRGB(255, 215, 80))
end

function Icons.chest(b)
	local wood, dark, gold = Color3.fromRGB(150, 95, 50), Color3.fromRGB(105, 65, 35), Color3.fromRGB(255, 205, 60)
	b(9, 4, 6, 0, 2, 0, wood)
	b(9, 2, 6, 0, 5, 0, dark)
	b(9.2, 1, 6.2, 0, 4, 0, gold)
	b(1.6, 2, 0.6, 0, 3.6, -3.1, gold)
	for _, c in { { -2, 6.3, 0 }, { 0.5, 6.6, 1 }, { 2.2, 6.3, -0.6 }, { -0.4, 7.2, -0.5 } } do
		b(1.6, 0.6, 1.6, c[1], c[2], c[3], gold)
	end
end

function Icons.gift(b)
	local red, ribbon = Color3.fromRGB(235, 65, 70), Color3.fromRGB(255, 215, 70)
	b(7, 5, 7, 0, 2.5, 0, red)
	b(7.6, 1.6, 7.6, 0, 5.8, 0, Color3.fromRGB(250, 95, 100))
	b(1.4, 6.8, 7.8, 0, 3.4, 0, ribbon)
	b(7.8, 6.8, 1.4, 0, 3.4, 0, ribbon)
	b(2.2, 1.6, 1.2, -1.4, 7.6, 0, ribbon)
	b(2.2, 1.6, 1.2, 1.4, 7.6, 0, ribbon)
end

function Icons.calendar(b)
	local page, red, ink = Color3.fromRGB(250, 250, 250), Color3.fromRGB(230, 70, 70), Color3.fromRGB(70, 75, 90)
	b(8, 8, 1, 0, 4, 0, page)
	b(8, 2.4, 1.1, 0, 7.6, 0, red)
	b(0.8, 1.6, 1.4, -2.2, 8.8, 0, ink)
	b(0.8, 1.6, 1.4, 2.2, 8.8, 0, ink)
	for row = 0, 1 do
		for col = 0, 2 do
			b(1.2, 1.2, 0.3, -2.2 + col * 2.2, 4.6 - row * 2.2, -0.6, ink)
		end
	end
end

function Icons.potion(b)
	local glass, liquid = Color3.fromRGB(215, 235, 250), Color3.fromRGB(175, 90, 240)
	b(6, 5, 6, 0, 2.5, 0, liquid)
	b(4, 1, 4, 0, 5.5, 0, liquid)
	b(2, 2.4, 2, 0, 7.2, 0, glass)
	b(2.6, 1, 2.6, 0, 8.8, 0, Color3.fromRGB(160, 110, 60))
	b(1.2, 1.2, 0.4, -1.4, 3.6, -3, Color3.fromRGB(235, 200, 255))
end

function Icons.clock(b)
	local rim, face, ink = Color3.fromRGB(70, 75, 90), Color3.fromRGB(250, 250, 250), Color3.fromRGB(230, 70, 70)
	b(9, 9, 1, 0, 4.5, 0.2, rim)
	b(7.4, 7.4, 1.2, 0, 4.5, 0, face)
	b(0.9, 3.2, 0.4, 0, 5.8, -0.7, rim)
	b(2.6, 0.9, 0.4, 1, 4.5, -0.7, ink)
	b(1, 1, 0.5, 0, 4.5, -0.75, rim)
end

function Icons.wave(b)
	local blue, light = Color3.fromRGB(45, 140, 235), Color3.fromRGB(235, 250, 255)
	b(10, 2, 2, 0, 1, 0, blue)
	b(8, 2, 2, 0.5, 3, 0, blue)
	b(5, 2, 2, 1.5, 5, 0, blue)
	b(3, 1.6, 2, -0.5, 6.6, 0, light)
	b(2, 1.4, 2, -2.2, 5.4, 0, light)
end

-- Builds the icon model called `name`. Some icons reuse game models.
function Voxel.icon(name: string): Model
	local eggId = string.match(name, "^egg:(.+)$")
	if eggId and Config.EggById[eggId] then
		return Voxel.egg(eggId, "Normal", false)
	end
	if name == "strength" then
		return Voxel.barbell(3)
	elseif name == "egg" then
		return Voxel.egg("Shell", "Normal", false)
	elseif name == "hatch" then
		return Voxel.egg("Treasure", "Normal", false)
	elseif name == "pets" then
		return Voxel.animal("Turtle", "Normal")
	elseif name == "staff" then
		local staff = Voxel.staff()
		staff.PrimaryPart = staff:FindFirstChild("Handle") :: BasePart
		return staff
	end
	local model = newModel("Icon_" .. name)
	local build = Icons[name] or Icons.gift
	build(pixelBuilder(model, 0.4))
	return model
end

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

-- Unanchors every part and welds it to Root so tweening Root moves the model.
function Voxel.weld(model: Model, anchorRoot: boolean?)
	local root = model.PrimaryPart
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
			p.Anchored = false
			p.Massless = true
		end
	end
	root.Anchored = anchorRoot ~= false
end

-- Paints the model as a dark silhouette (used for undiscovered Index entries).
function Voxel.silhouette(model: Model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Color = Color3.fromRGB(25, 25, 35)
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0
		elseif p:IsA("Light") then
			p:Destroy()
		end
	end
end

return Voxel
