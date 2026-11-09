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

local function eye(b, x, y, z)
	local e = b(1, 1, 1, x, y, z, BLACK)
	e:SetAttribute("Keep", true)
	return e
end

----------------------------------------------------------------------------
-- Animal templates. pal = { p = primary, s = secondary, a = accent }
----------------------------------------------------------------------------
local Templates = {}

function Templates.crab(b, pal)
	b(8, 3, 6, 0, 3.5, 0, pal.p)
	b(6, 1, 4, 0, 5.5, 0, pal.s)
	for _, sx in { -1, 1 } do
		b(1, 2, 1, sx * 1.5, 7, -2, pal.p)
		eye(b, sx * 1.5, 8.5, -2)
		b(2, 1, 2, sx * 4.5, 4, -3, pal.p)
		b(3, 3, 2, sx * 5, 4.5, -5, pal.p)
		b(1, 2, 1, sx * 6, 4.5, -6.5, pal.a)
		for _, z in { -1, 1, 3 } do
			b(2, 1, 1, sx * 5, 2.5, z, pal.s)
			b(1, 2, 1, sx * 6.5, 1, z, pal.s)
		end
	end
	b(2, 1, 1, 0, 3, -3.1, BLACK)
end

function Templates.bird(b, pal, o)
	local L = o.legs or (o.upright and 1 or 3)
	for _, sx in { -1, 1 } do
		b(1, L, 1, sx * 1, L / 2, 0, pal.a)
		b(1, 1, 2, sx * 1, 0.5, -0.5, pal.a)
		b(1, 4, 5, sx * 3, L + 3, 0.5, pal.s)
	end
	b(5, 5, 6, 0, L + 2.5, 0, pal.p)
	b(4, o.upright and 4 or 3, 1, 0, L + 2.5, -3, pal.s)
	b(3, 1, 3, 0, L + 3.5, 4, pal.s)
	local hy, hz
	if o.upright then
		hy, hz = L + 7, -0.5
	else
		hy, hz = L + 6.5, -2.5
	end
	b(4, 4, 4, 0, hy, hz, pal.p)
	eye(b, -1.5, hy + 0.5, hz - 2)
	eye(b, 1.5, hy + 0.5, hz - 2)
	if o.bigBeak then
		b(2, 1, 5, 0, hy - 0.5, hz - 4, pal.a)
		b(2, 1, 3, 0, hy - 1.5, hz - 3.5, pal.a)
	else
		b(2, 1, 2, 0, hy - 0.5, hz - 3, pal.a)
	end
	if o.crest then
		b(1, 3, 2, 0, hy + 3, hz + 0.5, pal.a)
		b(1, 2, 1, 0, hy + 3.5, hz + 2, pal.s)
	end
end

function Templates.fish(b, pal, o)
	local w, h, len = 4, 5, 8
	if o.long then
		len = 12
	end
	if o.round then
		w, h, len = 6, 6, 6
	end
	local hy = h / 2 + 2
	b(w, h, len, 0, hy, 0, pal.p)
	b(w + 0.2, 2, len - 2, 0, hy - h / 2 + 1, 0, pal.s)
	b(1, h, 3, 0, hy, len / 2 + 1.5, pal.s)
	b(1, 2, 1, 0, hy + h / 2 + 0.5, len / 2 + 2.5, pal.s)
	b(1, 3, 3, 0, hy + h / 2 + 1.5, 0.5, pal.s)
	for _, sx in { -1, 1 } do
		b(2, 1, 2, sx * (w / 2 + 1), hy - 1, -1, pal.s)
		eye(b, sx * (w / 2), hy + 1, -len / 2 + 1.5)
	end
	if o.teeth then
		b(w - 1, 1, 1, 0, hy - 1, -len / 2 - 0.1, BLACK)
		b(w - 1, 0.5, 0.5, 0, hy - 0.6, -len / 2 - 0.4, WHITE)
	end
	if o.horn then
		b(1, 1, 7, 0, hy + 1, -len / 2 - 3.5, pal.a)
	end
	if o.lure then
		b(1, 4, 1, 0, hy + h / 2 + 2, -len / 2 + 1, pal.s)
		b(1.5, 1.5, 1.5, 0, hy + h / 2 + 4.5, -len / 2 - 0.5, pal.a, Enum.Material.Neon)
	end
	if o.round then
		for _, s in { { 3, 1, 0 }, { -3, 1, 0 }, { 0, 3, 1 }, { 3, -1, 1.5 }, { -3, -1, 1.5 }, { 0, 3, -1.5 }, { 2, 0, -3 }, { -2, 0, -3 } } do
			b(1, 1, 1, s[1], hy + s[2], s[3], pal.a)
		end
	end
end

function Templates.quad(b, pal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			b(2, 3, 2, sx * 2, 1.5, sz * 2.5, pal.s)
		end
		eye(b, sx * 1.5, 8.5, -7.5)
		b(1, 1, 1, sx * 2, 10.5, -5, pal.s)
	end
	b(6, 4, 8, 0, 5, 0, pal.p)
	b(4, 1, 6, 0, 3, 0, pal.a)
	b(5, 5, 4, 0, 7.5, -5.5, pal.p)
	b(3, 2, 2, 0, 6.5, -8, pal.a)
	b(1, 1, 1, 0, 7.5, -9, BLACK)
	b(2, 2, 5, 0, 4.5, 6.5, pal.s)
end

function Templates.seal(b, pal, o)
	b(6, 4, 10, 0, 2, 1, pal.p)
	b(5, 5, 5, 0, 4.5, -5.5, pal.p)
	b(3, 2, 2, 0, 3.5, -8.5, pal.s)
	b(1, 1, 1, 0, 4.5, -9.5, BLACK)
	for _, sx in { -1, 1 } do
		eye(b, sx * 1.5, 5.5, -8)
		b(2, 1, 3, sx * 4, 0.5, -2, pal.s)
		if o.tusks then
			b(1, 3, 1, sx * 1, 1.5, -9, pal.a)
		end
	end
	b(5, 1, 3, 0, 0.5, 7.5, pal.s)
end

function Templates.octo(b, pal, o)
	b(7, 7, 7, 0, 8.5, 0, pal.p)
	b(5, 1, 5, 0, 12.5, 0, pal.p)
	b(1, 1, 1, 3.5, 10, 1, pal.s)
	b(1, 1, 1, -3.5, 9, -1, pal.s)
	b(1, 1, 1, 1, 12.5, 2, pal.s)
	for _, sx in { -1, 1 } do
		local w = b(2, 2, 1, sx * 1.8, 9, -3.5, WHITE)
		w:SetAttribute("Keep", true)
		eye(b, sx * 1.8, 8.6, -4)
	end
	for k = 0, 7 do
		local ang = k * math.pi / 4
		local x, z = math.cos(ang) * 3.2, math.sin(ang) * 3.2
		b(1.5, 5, 1.5, x, 2.5, z, pal.s)
		b(1.5, 1.5, 1.5, x * 1.4, 0.75, z * 1.4, pal.s)
	end
	if o.crown then
		b(5, 1, 5, 0, 13.5, 0, pal.a)
		for _, c in { { 2, 2 }, { -2, 2 }, { 2, -2 }, { -2, -2 } } do
			b(1, 2, 1, c[1], 14.5, c[2], pal.a)
		end
	end
end

function Templates.turtle(b, pal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			b(2, 2, 2, sx * 3, 1, sz * 3, pal.p)
		end
		eye(b, sx * 1, 4, -7)
	end
	b(6, 2, 7, 0, 2.5, 0, pal.p)
	b(7, 3, 8, 0, 4.5, 0, pal.s)
	b(5, 1, 6, 0, 6.5, 0, pal.a)
	b(3, 3, 3, 0, 3.5, -5.5, pal.p)
	b(1, 1, 2, 0, 2, 5, pal.p)
end

function Templates.frog(b, pal)
	for _, sx in { -1, 1 } do
		b(2, 2, 4, sx * 3.5, 1, 1, pal.p)
		b(1, 2, 1, sx * 2, 1, -2.5, pal.p)
		b(2, 2, 2, sx * 2, 5.5, -2, pal.p)
		eye(b, sx * 2, 5.5, -3)
	end
	b(6, 4, 6, 0, 3, 0, pal.p)
	b(4, 3, 1, 0, 2.5, -3, pal.s)
	b(4, 0.5, 0.5, 0, 3.6, -3.2, pal.a)
end

function Templates.serpent(b, pal)
	local segs = { { 3, 9 }, { 5, 5.5 }, { 6, 2 }, { 6.5, -1.5 } }
	for _, s in segs do
		b(4, 4, 4, 0, s[1], s[2], pal.p)
		b(4.2, 1.5, 3.5, 0, s[1] - 1.5, s[2], pal.s)
		b(1, 2, 2, 0, s[1] + 3, s[2], pal.a)
	end
	b(2, 2, 3, 0, 2, 12, pal.s)
	b(5, 5, 6, 0, 8, -5, pal.p)
	b(4, 1, 3, 0, 5.5, -8, pal.s)
	for _, sx in { -1, 1 } do
		eye(b, sx * 2.5, 9, -6.5)
		b(1, 3, 1, sx * 1.5, 11.5, -4, pal.a)
		b(1, 1, 3, sx * 2.5, 6.5, -9, pal.a)
	end
end

local function rarityTier(rarity: string): number
	return Config.RarityIndex[rarity] or 1
end

local function applyVariant(model: Model, variant: string?)
	if variant == "Gold" then
		local gold = Config.Variants.Gold.color
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Root" and not p:GetAttribute("Keep") then
				p.Color = p.Color:Lerp(gold, 0.7)
				p.Reflectance = 0.15
			end
		end
	elseif variant == "Rainbow" then
		local i = 0
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Root" and not p:GetAttribute("Keep") then
				i += 1
				local hue = (p.Position.Y * 0.09 + i * 0.03) % 1
				p.Color = Color3.fromHSV(hue, 0.7, 1)
			end
		end
	end
end

function Voxel.animalScale(animalId: string): number
	local a = Config.AnimalById[animalId]
	local tier = rarityTier(a.rarity)
	-- Rarer animals are much bigger, so a strong base is obvious at a glance.
	local s = 0.32 * (Config.SizeByTier[tier] or 1)
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
local EGG_WIDTHS = { 4, 6, 6, 6, 6, 6, 4, 2 }
local EGG_SPOTS = {
	{ 2, "-z", 1 },
	{ 3, "+x", -1 },
	{ 4, "-x", 1 },
	{ 5, "-z", -1 },
	{ 6, "+z", 0 },
	{ 3, "+z", 1 },
	{ 5, "+x", 1 },
	{ 6, "-x", -1 },
	{ 4, "+z", -1 },
	{ 2, "+x", 0 },
}

function Voxel.eggScale(eggId: string): number
	local e = Config.EggById[eggId]
	return 0.42 * (1 + (e.tier - 1) * 0.08)
end

function Voxel.egg(eggId: string, variant: string?, withNest: boolean?): Model
	local e = Config.EggById[eggId]
	local model = newModel(eggId .. "Egg")
	local P = Voxel.eggScale(eggId)
	local b = pixelBuilder(model, P)
	local baseY = withNest and 0.6 or 0
	local base, spot = e.base, e.spot
	if variant == "Gold" then
		base = base:Lerp(Config.Variants.Gold.color, 0.75)
		spot = spot:Lerp(Color3.fromRGB(255, 240, 160), 0.6)
	end
	for i, w in EGG_WIDTHS do
		local y = baseY + i - 0.5
		local c = base
		if variant == "Rainbow" then
			c = Color3.fromHSV((i / #EGG_WIDTHS) % 1, 0.6, 1)
		end
		if w >= 4 then
			b(w, 1, w - 2, 0, y, 0, c)
			b(w - 2, 1, w, 0, y, 0, c)
		else
			b(w, 1, w, 0, y, 0, c)
		end
	end
	for _, s in EGG_SPOTS do
		local layer, side, t = s[1], s[2], s[3]
		local w = EGG_WIDTHS[layer]
		local y = baseY + layer - 0.5
		local edge = w / 2 - 0.45
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
		b(1, 1, 1, x, y, z, variant == "Rainbow" and WHITE or spot)
	end
	if withNest then
		local browns = { Color3.fromRGB(120, 70, 35), Color3.fromRGB(150, 90, 45) }
		for k = 0, 11 do
			local ang = k * math.pi / 6
			b(2, 1, 2, math.cos(ang) * 3.8, 0.5, math.sin(ang) * 3.8, browns[k % 2 + 1])
		end
		for k = 0, 5 do
			local ang = k * math.pi / 3 + 0.3
			b(3, 0.5, 1, math.cos(ang) * 4.5, 1.1, math.sin(ang) * 4.5, browns[(k + 1) % 2 + 1])
		end
	end
	if e.glow or variant == "Rainbow" then
		local light = Instance.new("PointLight")
		light.Color = variant == "Rainbow" and Color3.fromRGB(255, 150, 255) or e.spot
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
