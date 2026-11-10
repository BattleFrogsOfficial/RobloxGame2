-- Everything that makes the inside of a parted sea feel alive. All of it is
-- local to the player who parted the sea, like the corridor itself:
--
--   luck-zone lines   glowing strips across the seabed where each zone
--                     starts, with a sign giving the zone's luck
--   kelp              swaying along both sides; swallowed as the walls close
--   bubble vents      streams of bubbles rising from the floor
--   mist              a low fog rolling along the corridor floor
--   fish              swimming inside the water walls, and every so often
--                     one leaps across the gap over your head
--   falling water     chunks dropping off the tops of the walls
--   tint              the light turns bluer and dimmer the deeper you go

local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local Depths = {}

local O = Config.Ocean
local SHORE = O.ShoreZ
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local WATER = Color3.fromRGB(60, 160, 245)
local FOAM = Color3.fromRGB(235, 250, 255)
local FISH_COLORS = {
	Color3.fromRGB(255, 150, 60),
	Color3.fromRGB(255, 220, 70),
	Color3.fromRGB(240, 90, 120),
	Color3.fromRGB(120, 230, 160),
	Color3.fromRGB(230, 230, 245),
	Color3.fromRGB(170, 110, 240),
}

local folder: Folder
local tint: ColorCorrectionEffect
local rng = Random.new()

local stripes = {} -- { part, zone }
local props = {} -- { model, d, x, shown, sway? }
local fish = {} -- { model, side, d, y, speed, dir, jump? }
local mist: BasePart? = nil
local lastDrop = 0
local nextJump = 0
local lastClock = 0

local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- A model whose pieces are welded to an invisible root at its base, so it
-- can be moved (or swayed) by setting one CFrame.
local function rooted(name: string, at: CFrame): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local root = part(Vector3.new(0.4, 0.4, 0.4), at, Color3.new(), nil)
	root.Name = "Root"
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

local function attach(model: Model, root: Part, p: Part)
	p.Anchored = false
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
end

----------------------------------------------------------------------------
-- Builders
----------------------------------------------------------------------------
local function zoneSign(strip: BasePart, zone)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(16, 5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
	gui.MaxDistance = 260
	gui.LightInfluence = 0
	gui.Adornee = strip
	local function line(text: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, y)
		l.Size = UDim2.fromScale(1, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.Parent = gui
	end
	line(string.upper(zone.name), 0, 0.42, Color3.new(1, 1, 1))
	line("x" .. zone.luck .. " LUCK", 0.42, 0.58, zone.color)
	gui.Parent = strip
end

local function buildKelp(at: CFrame): Model
	local model, root = rooted("Kelp", at)
	local height = rng:NextInteger(3, 6)
	for i = 0, height - 1 do
		local green = Color3.fromRGB(40, 140 + i * 14, 70)
		local seg = part(Vector3.new(0.9, 2.2, 0.9), at * CFrame.new(math.sin(i * 1.3) * 0.5, 1.1 + i * 2.1, 0), green)
		attach(model, root, seg)
		if i % 2 == 1 then
			attach(model, root, part(Vector3.new(2.2, 0.5, 0.9), at * CFrame.new(math.sin(i * 1.3) * 0.5 + 1.1, 1.4 + i * 2.1, 0), green))
		end
	end
	return model
end

local function buildVent(at: CFrame): Model
	local model, root = rooted("Vent", at)
	attach(model, root, part(Vector3.new(2.6, 1.2, 2.6), at * CFrame.new(0, 0.6, 0), Color3.fromRGB(70, 75, 90)))
	attach(model, root, part(Vector3.new(1.4, 0.8, 1.4), at * CFrame.new(0, 1.5, 0), Color3.fromRGB(50, 55, 70)))
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(FOAM)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
	e.Transparency = NumberSequence.new(0.25, 1)
	e.Lifetime = NumberRange.new(1.6, 2.6)
	e.Speed = NumberRange.new(6, 10)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Acceleration = Vector3.new(0, 4, 0)
	e.Rate = 16
	e.LightEmission = 0.4
	e.Parent = root
	return model
end

-- A small blocky fish, built facing its -Z.
local function buildFish(): Model
	local model, root = rooted("Fish", CFrame.new())
	local color = FISH_COLORS[rng:NextInteger(1, #FISH_COLORS)]
	local s = rng:NextNumber(0.8, 1.6)
	attach(model, root, part(Vector3.new(0.6, 1.1, 2) * s, CFrame.new(), color))
	attach(model, root, part(Vector3.new(0.4, 1.4, 0.7) * s, CFrame.new(0, 0, 1.3 * s), color:Lerp(Color3.new(1, 1, 1), 0.3)))
	attach(model, root, part(Vector3.new(0.3, 0.6, 0.8) * s, CFrame.new(0, 0.8 * s, 0.1 * s), color:Lerp(Color3.new(1, 1, 1), 0.3)))
	attach(model, root, part(Vector3.new(0.7, 0.3, 0.3) * s, CFrame.new(0, 0.2 * s, -0.6 * s), Color3.fromRGB(20, 20, 25)))
	return model
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------
function Depths.stop()
	for _, s in stripes do
		s.part:Destroy()
	end
	for _, p in props do
		p.model:Destroy()
	end
	for _, f in fish do
		f.model:Destroy()
	end
	if mist then
		mist:Destroy()
		mist = nil
	end
	table.clear(stripes)
	table.clear(props)
	table.clear(fish)
end

function Depths.start(sp)
	Depths.stop()
	rng = Random.new(math.floor(sp.t0 * 1000) % 100000)
	local full = sp.width / 2
	local floor = O.SeabedY

	-- Luck-zone lines (the first zone starts at the shore and needs none).
	for i = 2, #Config.Zones do
		local zone = Config.Zones[i]
		if zone.from < sp.length - 2 then
			local strip = part(Vector3.new(1, 0.3, 2.4), CFrame.new(sp.cx, floor + 0.2, SHORE - zone.from), zone.color, Enum.Material.Neon)
			strip.Name = "ZoneLine"
			strip.Transparency = 1
			zoneSign(strip, zone)
			strip.Parent = folder
			table.insert(stripes, { part = strip, zone = zone })
		end
	end

	-- Kelp down both sides and bubble vents nearer the middle.
	local side = 1
	local d = O.RampLength + 4
	while d < sp.length - 4 do
		side = -side
		local x = side * full * rng:NextNumber(0.7, 0.94)
		local at = CFrame.new(sp.cx + x, floor, SHORE - d) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		table.insert(props, { model = buildKelp(at), d = d, x = x, at = at, sway = rng:NextNumber(0, 6.28), shown = false })
		d += rng:NextNumber(6, 11)
	end
	d = O.RampLength + 14
	while d < sp.length - 6 do
		local x = rng:NextNumber(-0.45, 0.45) * full
		local at = CFrame.new(sp.cx + x, floor, SHORE - d)
		table.insert(props, { model = buildVent(at), d = d, x = x, at = at, shown = false })
		d += rng:NextNumber(22, 34)
	end

	-- Low mist along the floor.
	local fog = part(Vector3.new(1, 0.2, 1), CFrame.new(sp.cx, floor + 1, SHORE - sp.length / 2), FOAM)
	fog.Name = "Mist"
	fog.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(Color3.fromRGB(225, 240, 255))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.72), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(2.5, 4)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(80, 80)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-12, 12)
	e.Rate = math.clamp(sp.length * 0.45, 12, 70)
	e.LightEmission = 0.25
	e.Enabled = false
	e.Parent = fog
	fog.Parent = folder
	mist = fog

	-- Fish in the walls.
	for _ = 1, math.clamp(math.floor(sp.length / 9), 6, 26) do
		table.insert(fish, {
			model = buildFish(),
			side = rng:NextNumber() < 0.5 and -1 or 1,
			d = rng:NextNumber(8, math.max(9, sp.length - 4)),
			y = rng:NextNumber(floor + 2, O.WaterTopY + 12),
			speed = rng:NextNumber(5, 12),
			dir = rng:NextNumber() < 0.5 and -1 or 1,
			inset = rng:NextNumber(1.2, 3.6),
			shown = false,
		})
	end
	nextJump = os.clock() + Formulas.anim(sp) + 1
	lastClock = os.clock()
end

-- A chunk of water breaks off the top of a wall and falls into the corridor.
local function dropWater(sp, half: number)
	local side = rng:NextNumber() < 0.5 and -1 or 1
	local d = rng:NextNumber(6, sp.length)
	local size = rng:NextNumber(0.6, 1.8)
	local chunk = part(Vector3.new(size, size, size), CFrame.new(sp.cx + side * (half + 0.4), (sp.wallTop or O.WallTopY) - rng:NextNumber(0, 6), SHORE - d), rng:NextNumber() < 0.4 and FOAM or WATER)
	chunk.Name = "Drip"
	chunk.Transparency = 0.25
	chunk.Anchored = false
	chunk.Parent = folder
	chunk.AssemblyLinearVelocity = Vector3.new(-side * rng:NextNumber(2, 7), rng:NextNumber(-4, 4), rng:NextNumber(-3, 3))
	chunk.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
	Debris:AddItem(chunk, 1.5)
end

-- Called every frame by Ocean. `sp` is the active split (or nil), `root` the
-- local character's root part (or nil).
function Depths.update(sp, elapsed: number, root: BasePart?)
	local clock = os.clock()
	local dt = math.min(clock - lastClock, 0.1)
	lastClock = clock

	-- Tint: bluer and dimmer the farther out the player is.
	local depth = 0
	if sp and root and root.Position.Z < SHORE then
		depth = 0.35 + 0.65 * math.clamp((SHORE - root.Position.Z) / O.Reach, 0, 1)
	end
	local goal = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(140, 200, 255), depth * 0.8)
	tint.TintColor = tint.TintColor:Lerp(goal, math.min(1, dt * 4))
	tint.Brightness += (-0.06 * depth - tint.Brightness) * math.min(1, dt * 4)

	if not sp then
		return
	end
	local opening = elapsed < Formulas.anim(sp)
	local half = Formulas.halfWidth(sp, elapsed)
	local floor = O.SeabedY

	-- Zone lines span the gap at their depth.
	for _, s in stripes do
		local hw = Formulas.halfWidthAt(sp, s.zone.from, elapsed)
		if hw > 1 then
			s.part.Transparency = 0.25
			s.part.Size = Vector3.new(hw * 2, 0.3, 2.4)
		else
			s.part.Transparency = 1
		end
	end

	-- Kelp and vents appear as the sea opens over them and are swallowed
	-- when the closing walls reach them.
	for i = #props, 1, -1 do
		local p = props[i]
		local hw = Formulas.halfWidthAt(sp, p.d, elapsed)
		if not p.shown then
			if hw > math.abs(p.x) + 1.2 then
				p.shown = true
				p.model.Parent = folder
			end
		elseif not opening and hw < math.abs(p.x) then
			p.model:Destroy()
			table.remove(props, i)
		elseif p.sway then
			p.model.PrimaryPart.CFrame = p.at * CFrame.Angles(math.sin(clock * 1.4 + p.sway) * 0.12, 0, math.cos(clock * 1.1 + p.sway) * 0.1)
		end
	end

	-- Mist fills the open floor.
	if mist then
		local floorHalf = Formulas.halfWidthAt(sp, sp.length, elapsed)
		local on = floorHalf > 2 and sp.length > O.RampLength + 4
		mist.ParticleEmitter.Enabled = on
		if on then
			mist.Size = Vector3.new(floorHalf * 2, 0.2, sp.length - O.RampLength)
			mist.CFrame = CFrame.new(sp.cx, floor + 1, SHORE - (sp.length + O.RampLength) / 2)
		end
	end

	-- Fish cruise inside the walls; now and then one leaps across the gap.
	if not opening and clock >= nextJump and #fish > 0 and half > 3 then
		nextJump = clock + rng:NextNumber(1.2, 2.6)
		local f = fish[rng:NextInteger(1, #fish)]
		if not f.jump and f.shown then
			f.jump = { t0 = clock, seconds = rng:NextNumber(0.8, 1.1), from = f.side }
		end
	end
	for _, f in fish do
		f.d += f.dir * f.speed * dt
		if f.d < 6 then
			f.d, f.dir = 6, 1
		elseif f.d > sp.length - 3 then
			f.d, f.dir = sp.length - 3, -1
		end
		local hw = Formulas.halfWidthAt(sp, f.d, elapsed)
		if not f.shown and hw > 1 then
			f.shown = true
			f.model.Parent = folder
		end
		if f.shown then
			local z = SHORE - f.d
			local pos, look
			if f.jump then
				local jump = f.jump
				local u = math.clamp((clock - jump.t0) / jump.seconds, 0, 1)
				-- From one wall, up over the gap, into the other.
				local x = sp.cx + jump.from * (hw + f.inset) * (1 - 2 * u)
				pos = Vector3.new(x, f.y + math.sin(math.pi * u) * (7 + hw * 0.35), z)
				look = pos + Vector3.new(-jump.from * 2, math.cos(math.pi * u) * 2, -f.dir * 0.6)
				if u >= 1 then
					f.side = -jump.from
					f.jump = nil
				end
			else
				pos = Vector3.new(sp.cx + f.side * (hw + f.inset), f.y + math.sin(clock * 1.7 + f.speed) * 0.4, z)
				look = pos + Vector3.new(0, 0, -f.dir)
			end
			f.model.PrimaryPart.CFrame = CFrame.lookAt(pos, look)
		end
	end

	-- Water breaking off the wall tops.
	if not opening and half > 2 and clock - lastDrop > 0.16 then
		lastDrop = clock
		dropWater(sp, half)
	end
end

function Depths.init()
	folder = Instance.new("Folder")
	folder.Name = "Depths"
	folder.Parent = workspace
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "SeaTint"
	tint.TintColor = Color3.new(1, 1, 1)
	tint.Brightness = 0
	tint.Parent = Lighting
end

return Depths
