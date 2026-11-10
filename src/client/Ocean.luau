-- Draws the ocean on this client and runs this player's sea-parting.
--
-- Everyone draws the same closed sea, out to the horizon. When YOU part it,
-- only your client plays the cutscene, carves out the corridor, raises the
-- walls of water and shows your eggs. Anyone watching just sees you walk
-- into the (closed) water.
--
-- The corridor's side walls start closing as soon as it has opened and meet
-- after `duration` seconds. Eggs vanish as the water covers them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Voxel = require(Shared.Voxel)

local State = require(script.Parent.State)
local Depths = require(script.Parent.Depths)
local Poses = require(script.Parent.Poses)

local Ocean = {}

local O = Config.Ocean
local SHORE = O.ShoreZ
local STAFF_NAME = "Sea Staff"
local player = Players.LocalPlayer

local WATER = Color3.fromRGB(35, 135, 235)
local WALL = Color3.fromRGB(60, 160, 245)
local WALL_DARK = Color3.fromRGB(45, 140, 235)
local FOAM = Color3.fromRGB(235, 250, 255)

-- The sea is one long channel between the rock walls. The near part is
-- re-shaped every frame while parted; the rest, out to the horizon, is static.
local NEAR_X = O.HalfX
local NEAR_Z = SHORE - O.Reach - 60
local FAR_Z = SHORE - 4096
local MAX_PART = 2048 -- Roblox's largest part size

local SEG = 15 -- studs per wall segment
local MAX_SEGS = math.ceil(O.Reach / SEG)
local WALL_THICK = 5
local CRESTS = 7

-- Public state read by the HUD and the guide.
Ocean.active = nil :: any -- current split (or nil)
Ocean.cutscene = false -- true while the parting cutscene owns the camera
Ocean.charging = false
Ocean.charge = 0
Ocean.inZone = false
Ocean.canCharge = false
Ocean.handsFull = false
Ocean.carried = 0

local folder: Folder
local parts: { [string]: BasePart } = {}
local baseTransparency: { [BasePart]: number } = {}
local solid: { [BasePart]: boolean } = {} -- collide (for us) whenever visible
local wallSegs = { L = {}, R = {} } -- [side][i] = { base, upper, cap }
local eggModels: { [number]: any } = {}
local chargeStart = 0
local chargeSource: any = nil -- "mouse" or a touch InputObject
local pendingGrab: number? = nil
local pendingAt = 0
local lastFullWarn = 0
local wasInZone = false
local lastTick = -1
local scene: any = nil -- cutscene bookkeeping
local lastBurst = 0

----------------------------------------------------------------------------
-- Water parts
----------------------------------------------------------------------------
local function newPart(name: string, color: Color3, transparency: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Transparency = 1
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.08
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(1, 1, 1)
	p.Parent = folder
	baseTransparency[p] = transparency
	parts[name] = p
	return p
end

local function hide(p: BasePart)
	if p.Transparency ~= 1 then
		p.Transparency = 1
		if solid[p] then
			p.CanCollide = false
			p.CanQuery = false
		end
	end
end

-- Fit a part to an axis-aligned box; hide it if the box is empty.
local function setBox(p: BasePart, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
	if x1 - x0 < 0.05 or y1 - y0 < 0.05 or z1 - z0 < 0.05 then
		hide(p)
		return
	end
	local base = baseTransparency[p]
	if p.Transparency ~= base then
		p.Transparency = base
		if solid[p] then
			p.CanCollide = true
			p.CanQuery = true
		end
	end
	p.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	p.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
end

local function addSpray(p: BasePart, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds" -- soft puffs read as spray
	e.Rotation = NumberRange.new(0, 360)
	e.Color = ColorSequence.new(FOAM)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 3.2) })
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(4, 10)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Acceleration = Vector3.new(0, -25, 0)
	e.Rate = rate
	e.LightInfluence = 0.5
	e.Enabled = false
	e.Parent = p
	return e
end

-- Static water filling a rectangle, in pieces no bigger than a part can be.
local staticCount = 0
local function fillStatic(x0: number, x1: number, z0: number, z1: number)
	if x1 - x0 > MAX_PART then
		local mid = x0 + MAX_PART
		fillStatic(x0, mid, z0, z1)
		fillStatic(mid, x1, z0, z1)
		return
	end
	if z1 - z0 > MAX_PART then
		local mid = z1 - MAX_PART
		fillStatic(x0, x1, z0, mid)
		fillStatic(x0, x1, mid, z1)
		return
	end
	staticCount += 1
	local p = newPart("Sea" .. staticCount, WATER, 0.25)
	setBox(p, x0, x1, O.SeabedY, O.WaterTopY, z0, z1)
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "LocalOcean"
	folder.Parent = workspace

	-- The sea beyond the near box, out to the horizon.
	fillStatic(-NEAR_X, NEAR_X, FAR_Z, NEAR_Z)

	newPart("Main", WATER, 0.25)
	newPart("Left", WATER, 0.25)
	newPart("Right", WATER, 0.25)
	newPart("Far", WATER, 0.25)

	-- Corridor walls are rows of segments, each a wide base with a narrower
	-- upper tier set back from it and a foam crest, so the wall steps back
	-- like a standing wave instead of being one flat slab.
	for _, side in { "L", "R" } do
		for i = 1, MAX_SEGS do
			local base = newPart("Wall" .. side .. i, i % 2 == 0 and WALL or WALL_DARK, 0.12)
			local upper = newPart("Upper" .. side .. i, i % 2 == 0 and WALL_DARK or WALL, 0.18)
			local cap = newPart("Cap" .. side .. i, FOAM, 0.1)
			-- Solid and queryable: you bump into the wall, and the default
			-- camera zooms in instead of ending up behind a sheet of water.
			solid[base] = true
			wallSegs[side][i] = { base = base, upper = upper, cap = cap }
		end
		-- Foam churning along the foot of each wall as it advances.
		addSpray(newPart("Churn" .. side, FOAM, 0.4), 45)
	end
	newPart("WallEnd", WALL, 0.2)
	newPart("CapEnd", FOAM, 0.15)

	-- A fountain of spray that rides the tear as the sea rips open.
	local front = newPart("RipFront", FOAM, 1)
	local burst = addSpray(front, 260)
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 0) })
	burst.Speed = NumberRange.new(45, 85)
	burst.SpreadAngle = Vector2.new(38, 38)
	burst.Lifetime = NumberRange.new(1, 1.8)
	burst.Acceleration = Vector3.new(0, -70, 0)

	-- Wet sand along the corridor floor.
	local wet = newPart("WetSand", Color3.fromRGB(172, 148, 104), 0)
	wet.Reflectance = 0.12

	-- Tall invisible walls above the water so you can't jump out sideways.
	for _, n in { "BarrierL", "BarrierR" } do
		newPart(n, WATER, 1)
	end

	newPart("FoamA", FOAM, 0.35)
	newPart("FoamB", FOAM, 0.35)
	for i = 1, CRESTS do
		newPart("CrestA" .. i, FOAM, 0.5)
		newPart("CrestB" .. i, FOAM, 0.5)
	end
end

local function hideCorridor()
	for _, n in { "Left", "Right", "Far", "WallEnd", "CapEnd", "WetSand", "ChurnL", "ChurnR" } do
		hide(parts[n])
	end
	for _, side in { "L", "R" } do
		for _, seg in wallSegs[side] do
			hide(seg.base)
			hide(seg.upper)
			hide(seg.cap)
		end
		parts["Churn" .. side].ParticleEmitter.Enabled = false
	end
	parts.RipFront.ParticleEmitter.Enabled = false
	parts.BarrierL.CanCollide = false
	parts.BarrierR.CanCollide = false
end

-- Lines of foam drifting toward the shore; they split around the corridor so
-- they never float across the gap.
local function layoutCrests(sp, t: number)
	local y1 = O.WaterTopY
	for i = 1, CRESTS do
		local phase = (t * 0.02 + i / CRESTS) % 1
		local z = SHORE - 620 + phase * 610
		local fade = math.sin(phase * math.pi)
		local a, b = parts["CrestA" .. i], parts["CrestB" .. i]
		if sp and z + 1 >= SHORE - sp.length - WALL_THICK then
			local reach = sp.width / 2 + WALL_THICK
			setBox(a, -NEAR_X, sp.cx - reach, y1, y1 + 0.12, z - 0.8, z + 0.8)
			setBox(b, sp.cx + reach, NEAR_X, y1, y1 + 0.12, z - 0.8, z + 0.8)
		else
			setBox(a, -NEAR_X, NEAR_X, y1, y1 + 0.12, z - 0.8, z + 0.8)
			hide(b)
		end
		for _, p in { a, b } do
			if p.Transparency < 1 then
				p.Transparency = 1 - 0.5 * fade
			end
		end
	end
end

-- Chunks of water flung up and out of the tear as the sea rips open.
local function flingWater(sp, frontD: number, power: number)
	local z = SHORE - frontD
	for _, sx in { -1, 1 } do
		for _ = 1, 2 do
			local size = (1.4 + math.random() * 2.6) * (0.75 + power * 0.25)
			local chunk = Instance.new("Part")
			chunk.Name = "Splash"
			chunk.Size = Vector3.new(size, size, size)
			chunk.Color = math.random() < 0.35 and FOAM or WALL
			chunk.Material = Enum.Material.SmoothPlastic
			chunk.Transparency = 0.2
			chunk.CanCollide = false
			chunk.CanQuery = false
			chunk.CanTouch = false
			chunk.CastShadow = false
			chunk.CFrame = CFrame.new(sp.cx + sx * (1 + math.random() * 3), O.WaterTopY + 1, z + (math.random() - 0.5) * 8)
				* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			chunk.Parent = folder
			chunk.AssemblyLinearVelocity = Vector3.new(sx * (18 + math.random() * 42) * (0.7 + power * 0.3), (70 + math.random() * 60) * (0.6 + power * 0.4), (math.random() - 0.5) * 36)
			chunk.AssemblyAngularVelocity = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5)
			Debris:AddItem(chunk, 2.8)
		end
	end
end

-- Lay out every near-sea part for the current split (or the closed sea).
local function layout(sp, elapsed: number, t: number)
	local y0, y1 = O.SeabedY, O.WaterTopY
	local waterline = SHORE - 2.5 -- where the water surface meets the ramp
	layoutCrests(sp, t)

	if not sp then
		setBox(parts.Main, -NEAR_X, NEAR_X, y0, y1, NEAR_Z, SHORE)
		hideCorridor()
		setBox(parts.FoamA, -NEAR_X, NEAR_X, y1 - 0.05, y1 + 0.15, waterline - 1, waterline + 1)
		hide(parts.FoamB)
		return
	end

	local full = sp.width / 2
	local length = sp.length
	local farZ = SHORE - length
	local opening = elapsed < Formulas.anim(sp)
	local half = Formulas.halfWidth(sp, elapsed) -- at the shore; everywhere once open
	-- The flat sea stops at fixed edges either side of the corridor; the
	-- walls fill from those edges in to wherever the gap currently is, so no
	-- two water faces ever share a plane.
	local edgeL, edgeR = sp.cx - full - WALL_THICK, sp.cx + full + WALL_THICK
	hide(parts.Main)
	setBox(parts.Left, -NEAR_X, edgeL, y0, y1, NEAR_Z, SHORE)
	setBox(parts.Right, edgeR, NEAR_X, y0, y1, NEAR_Z, SHORE)
	setBox(parts.Far, edgeL, edgeR, y0, y1, NEAR_Z, farZ - WALL_THICK)

	-- Once open, the walls lean taller the closer they are to slamming shut.
	local squeeze = opening and 0 or 1 - math.clamp(half / full, 0, 1)
	local peak = (sp.wallTop or O.WallTopY) + squeeze * 10
	for i = 1, MAX_SEGS do
		local d0 = (i - 1) * SEG
		local d1 = math.min(i * SEG, length)
		for _, side in { "L", "R" } do
			local seg = wallSegs[side][i]
			if d1 - d0 < 0.05 then
				hide(seg.base)
				hide(seg.upper)
				hide(seg.cap)
			else
				local za, zb = SHORE - d1, SHORE - d0
				-- This stretch of sea peels open later the farther out it is.
				local hw = Formulas.halfWidthAt(sp, (d0 + d1) / 2, elapsed)
				local openK = math.clamp(hw / full, 0, 1)
				-- While tearing open, the water surges well above its
				-- resting height before settling.
				local riseK = opening and (openK + math.sin(math.pi * openK) * 0.6) or 1
				local wave = math.sin(t * 2.1 + i * 0.9 + (side == "R" and 2 or 0)) * 1.4 * math.min(1, openK * 3)
				local top = y1 + (peak - y1) * riseK + wave
				local inner = side == "L" and sp.cx - hw or sp.cx + hw
				if openK < 0.02 or top - y1 < 0.3 then
					-- Not torn open here yet: still flat sea.
					if side == "L" then
						setBox(seg.base, edgeL, sp.cx, y0, y1, za, zb)
					else
						setBox(seg.base, sp.cx, edgeR, y0, y1, za, zb)
					end
					hide(seg.upper)
					hide(seg.cap)
				else
					local step = y0 + (top - y0) * 0.6
					local back = math.min(2.4, (full + WALL_THICK - hw) * 0.5) -- upper tier sits back from the base
					if side == "L" then
						setBox(seg.base, edgeL, inner, y0, step, za, zb)
						setBox(seg.upper, edgeL, inner - back, step, top, za, zb)
						setBox(seg.cap, edgeL - 0.3, inner - back + 0.6, top, top + 0.9, za, zb)
					else
						setBox(seg.base, inner, edgeR, y0, step, za, zb)
						setBox(seg.upper, inner + back, edgeR, step, top, za, zb)
						setBox(seg.cap, inner + back - 0.6, edgeR + 0.3, top, top + 0.9, za, zb)
					end
				end
			end
		end
	end

	-- The far wall rises once the tear reaches it.
	local endK = math.clamp(Formulas.halfWidthAt(sp, length, elapsed) / full, 0, 1)
	if endK > 0.02 then
		local endTop = y1 + (peak + 1.5 - y1) * math.min(1, endK * 1.5) + math.sin(t * 3) * 0.8
		setBox(parts.WallEnd, edgeL, edgeR, y0, endTop, farZ - WALL_THICK, farZ)
		setBox(parts.CapEnd, edgeL - 0.3, edgeR + 0.3, endTop, endTop + 1, farZ - WALL_THICK - 0.3, farZ + 0.3)
	else
		hide(parts.WallEnd)
		hide(parts.CapEnd)
	end

	-- Spray: a fountain riding the tear while it opens, plus flung chunks of
	-- water; then foam churning at the foot of each wall as they close.
	local xl, xr = sp.cx - half, sp.cx + half
	local frontK = (elapsed / Formulas.anim(sp) - Formulas.slam(sp)) / Formulas.ripSpan(sp) -- 0 at the slam, 1 at the far end
	local ripping = opening and frontK > 0 and frontK < 1.15
	if ripping then
		local frontD = math.min(frontK, 1) * length
		setBox(parts.RipFront, sp.cx - 3, sp.cx + 3, y1, y1 + 1, SHORE - frontD - 2, SHORE - frontD + 2)
		parts.RipFront.Transparency = 1
		if frontK < 1 and t - lastBurst > 0.07 then
			lastBurst = t
			-- Bigger casts throw far more water, and throw it higher.
			local tier = Config.CastByKey[sp.cast or "Split"].tier
			for _ = 1, tier * tier do
				flingWater(sp, frontD, tier)
			end
		end
	end
	parts.RipFront.ParticleEmitter.Enabled = ripping
	setBox(parts.ChurnL, xl, xl + 1.2, y0, y0 + 0.5, farZ, SHORE - O.RampLength)
	setBox(parts.ChurnR, xr - 1.2, xr, y0, y0 + 0.5, farZ, SHORE - O.RampLength)
	parts.ChurnL.ParticleEmitter.Enabled = half > 0.5
	parts.ChurnR.ParticleEmitter.Enabled = half > 0.5

	-- Wet sand on the flat seabed part of the corridor, as wide as the
	-- narrowest point of the gap.
	local floorHalf = Formulas.halfWidthAt(sp, length, elapsed)
	if length > O.RampLength and floorHalf > 0.3 then
		setBox(parts.WetSand, sp.cx - floorHalf, sp.cx + floorHalf, y0, y0 + 0.08, farZ, SHORE - O.RampLength)
	else
		hide(parts.WetSand)
	end

	-- Invisible barriers above the walls (these parts exist only on this client).
	for name, x0 in { BarrierL = xl - 3, BarrierR = xr } do
		local b = parts[name]
		b.Size = Vector3.new(3, 80, math.max(0.1, length))
		b.CFrame = CFrame.new(x0 + 1.5, y0 + 40, SHORE - length / 2)
		b.CanCollide = true
	end

	-- Shore foam, with a gap at the corridor mouth.
	setBox(parts.FoamA, -NEAR_X, edgeL, y1 - 0.05, y1 + 0.15, waterline - 1, waterline + 1)
	setBox(parts.FoamB, edgeR, NEAR_X, y1 - 0.05, y1 + 0.15, waterline - 1, waterline + 1)
end

----------------------------------------------------------------------------
-- Sounds
----------------------------------------------------------------------------
local function playSound(id: string, volume: number?, speed: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
Ocean.playSound = playSound

----------------------------------------------------------------------------
-- Eggs (only on this client)
----------------------------------------------------------------------------
local function clearEggs()
	for _, e in eggModels do
		e.model:Destroy()
	end
	table.clear(eggModels)
end

-- World-sized name tag over an egg (shrinks with distance).
local function eggLabel(root: BasePart, egg: string, variant: string)
	local e = Config.EggById[egg]
	local lines = {}
	if variant ~= "Normal" then
		table.insert(lines, { variant, Config.Variants[variant].color, 18 })
	end
	table.insert(lines, { e.name, Color3.new(1, 1, 1), 24 })
	table.insert(lines, { e.rarity, Config.Rarities[Config.RarityIndex[e.rarity]].color, 20 })
	local total = 0
	for _, l in lines do
		total += l[3]
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(11, total * 0.06)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5 + total * 0.03, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Adornee = root
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	for i, l in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, l[3] / total)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = l[1]
		label.TextColor3 = l[2]
		label.TextStrokeTransparency = 0
		label.LayoutOrder = i
		label.Parent = gui
	end
	gui.Parent = root
end

local function spawnEggs(sp)
	clearEggs()
	local rng = Random.new(math.floor(sp.t0 * 1000) % 100000)
	for _, e in sp.eggs do
		local model = Voxel.egg(e.egg, e.variant, true)
		local pos = Vector3.new(sp.cx + e.x, Formulas.groundY(e.d), SHORE - e.d)
		local yaw = rng:NextNumber(0, math.pi * 2)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
		-- Weld everything to the root so bobbing moves one part, not forty.
		Voxel.weld(model, true)
		eggLabel(model.PrimaryPart, e.egg, e.variant)

		-- Picking an egg up takes a short hold of E (or the on-screen /
		-- gamepad equivalent), not just walking over it.
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Grab"
		prompt.ObjectText = Config.EggById[e.egg].name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = Config.Split.GrabHold
		prompt.MaxActivationDistance = O.GrabRadius + 2
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = model.PrimaryPart
		local id = e.id
		prompt.Triggered:Connect(function()
			if Ocean.active == sp and not pendingGrab and not Ocean.handsFull then
				pendingGrab = id
				pendingAt = os.clock()
				Remotes.get("GrabEgg"):FireServer(id)
			end
		end)
		eggModels[e.id] = { model = model, data = e, pos = pos, yaw = yaw, shown = false, prompt = prompt }
	end
end

----------------------------------------------------------------------------
-- The parting cutscene: the camera circles the player as the staff goes up,
-- swings behind them to watch the sea tear open into the distance, then
-- glides back to exactly where the player's own camera was.
----------------------------------------------------------------------------
local function character()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, root
end

local function beginCutscene(sp)
	local char, root = character()
	local camera = workspace.CurrentCamera
	if not char or not root or not camera then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	scene = {
		camera = camera,
		cameraType = camera.CameraType,
		home = camera.CFrame, -- where the player's own camera is; we end here
		fov = camera.FieldOfView,
		origin = Vector3.new(sp.cx, root.Position.Y, root.Position.Z),
		humanoid = hum,
		walkSpeed = hum and hum.WalkSpeed or 16,
	}
	if hum then
		hum.WalkSpeed = 0 -- hold still while the sea opens
	end
	camera.CameraType = Enum.CameraType.Scriptable
	Ocean.cutscene = true
end

local function endCutscene()
	if not scene then
		return
	end
	local s = scene
	scene = nil
	Ocean.cutscene = false
	-- The camera is already sitting at its old position, so handing control
	-- back is seamless.
	s.camera.CFrame = s.home
	s.camera.CameraType = s.cameraType
	s.camera.FieldOfView = s.fov
	if s.humanoid and s.humanoid.Parent then
		s.humanoid.WalkSpeed = s.walkSpeed
	end
end

local function smoothstep(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Shot 1: a wide, low arc in front of the player for the coil, the leap
-- and the slam. It pulls back and tilts up to keep the leap in frame,
-- however high the cast goes.
local function heroShot(p: Vector3, u: number, height: number, tier: number): CFrame
	local angle = math.rad(50 - 70 * u)
	local radius = 15 + (tier - 1) * 5 + height * 0.9
	local pos = p + Vector3.new(math.sin(angle) * radius, 1.5 + u * 3 + height * 0.25, -math.cos(angle) * radius)
	return CFrame.lookAt(pos, p + Vector3.new(0, 3.6 + height * 0.8, 0))
end

-- Shot 2: behind and above, rising as the tear races away from the shore.
local function seaShot(p: Vector3, v: number, sp): CFrame
	local lift = (sp.wallTop or O.WallTopY) - O.WallTopY -- taller walls, higher camera
	local pos = (p + Vector3.new(0, 9, 15)):Lerp(p + Vector3.new(0, 32 + sp.length * 0.07 + lift * 0.9, 32 + lift * 0.5), v)
	return CFrame.lookAt(pos, p + Vector3.new(0, -5, -(18 + sp.length * 0.6 * v)))
end

local function updateCutscene(sp, elapsed: number)
	if not scene then
		return
	end
	local k = elapsed / Formulas.anim(sp)
	if k >= 1 then
		endCutscene()
		return
	end
	local p = scene.origin
	local slam = Formulas.slam(sp)
	local tier = Config.CastByKey[sp.cast or "Split"].tier
	local height = math.max(0, Poses.castHeight(k, sp.cast))
	local cf
	if k < slam + 0.03 then
		cf = heroShot(p, k / (slam + 0.03), height, tier)
		if k > slam then
			-- The slam jolts the camera; harder for the bigger casts.
			local jolt = 1.6 * tier
			cf *= CFrame.new((math.random() - 0.5) * jolt, (math.random() - 0.5) * jolt, 0)
		end
	elseif k < slam + 0.11 then
		-- Whip around from the hero shot to the view down the sea.
		cf = heroShot(p, 1, 0, tier):Lerp(seaShot(p, 0, sp), smoothstep((k - slam - 0.03) / 0.08))
	elseif k < 0.85 then
		local v = smoothstep((k - slam - 0.11) / (0.85 - slam - 0.11))
		cf = seaShot(p, v, sp)
		local shake = (1 - v) * 0.8 * tier
		cf *= CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
	else
		-- Glide back to the player's own camera.
		cf = seaShot(p, 1, sp):Lerp(scene.home, smoothstep((k - 0.85) / 0.15))
	end
	scene.camera.CFrame = cf
	scene.camera.FieldOfView = scene.fov + (12 + tier * 4) * math.sin(math.pi * math.clamp(k / 0.85, 0, 1))
end

----------------------------------------------------------------------------
-- Split lifecycle
----------------------------------------------------------------------------
local function inZone(pos: Vector3): boolean
	return pos.Z >= SHORE and pos.Z <= SHORE + O.SplitZoneDepth + 2 and math.abs(pos.X) <= O.HalfX - 24 and pos.Y > -3
end

function Ocean.start(sp)
	Ocean.active = sp
	pendingGrab = nil
	lastTick = -1
	spawnEggs(sp)
	Depths.start(sp)
	beginCutscene(sp)
	playSound("rbxasset://sounds/swoosh.wav", 1, 0.5)
	playSound("rbxasset://sounds/swoosh.wav", 0.8, 0.35)
	State.effect:Fire("splitStart", sp)
end

function Ocean.finish()
	endCutscene()
	Ocean.active = nil
	pendingGrab = nil
	clearEggs()
	Depths.stop()
end

function Ocean.close()
	if Ocean.active and not Ocean.cutscene then
		Remotes.get("CloseSplit"):FireServer()
		Ocean.finish()
	end
end

-- For the HUD: phase ("opening" / "closing"), seconds until the walls meet,
-- and how much of the corridor's width is left (1 = fully open, 0 = shut).
function Ocean.timing(): (string?, number, number)
	local sp = Ocean.active
	if not sp then
		return nil, 0, 0
	end
	local elapsed = State.serverNow() - sp.t0
	if elapsed < Formulas.anim(sp) then
		return "opening", sp.duration, 1
	end
	local left = math.max(0, Formulas.totalDuration(sp) - elapsed)
	return "closing", left, Formulas.halfWidth(sp, elapsed) / (sp.width / 2)
end

-- Studs between you and the nearer closing wall, or nil if you're not in
-- the corridor.
function Ocean.wallGap(): number?
	local sp = Ocean.active
	local _, root = character()
	if not sp or not root or root.Position.Z >= SHORE then
		return nil
	end
	local elapsed = State.serverNow() - sp.t0
	return Formulas.halfWidth(sp, elapsed) - math.abs(root.Position.X - sp.cx)
end

-- Positions of this split's eggs that are still on the seabed (for the guide).
function Ocean.eggPositions(): { Vector3 }
	local list = {}
	for _, e in eggModels do
		if e.shown then
			table.insert(list, e.pos)
		end
	end
	return list
end

-- Start / finish charging. `source` identifies what is holding the charge
-- ("mouse" or the touch InputObject) so only it can release.
function Ocean.beginCharge(source: any)
	if Ocean.canCharge and not Ocean.charging then
		Ocean.charging = true
		Ocean.charge = 0
		chargeStart = os.clock()
		chargeSource = source
	end
end

function Ocean.releaseCharge(source: any)
	if not Ocean.charging or (source ~= nil and source ~= chargeSource) then
		return
	end
	Ocean.charging = false
	chargeSource = nil
	local charge = Ocean.charge
	Ocean.charge = 0
	local ok, payload, err = pcall(function()
		return Remotes.get("RequestSplit"):InvokeServer(charge)
	end)
	if ok and type(payload) == "table" then
		Ocean.start(payload)
	elseif ok and err then
		State.toast:Fire(err, Color3.fromRGB(255, 200, 90))
	end
end

local function sourceOf(input: InputObject): any
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return "mouse"
	elseif input.UserInputType == Enum.UserInputType.Touch then
		return input
	end
	return nil
end
Ocean.sourceOf = sourceOf

----------------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------------
local function update()
	local t = os.clock()
	local char, root = character()
	local sp = Ocean.active
	local cap = State.data and State.data.carry or 1
	Ocean.carried = player:GetAttribute("Carrying") or 0
	Ocean.handsFull = Ocean.carried >= cap

	-- Can we charge a split right now?
	local zone = root ~= nil and inZone(root.Position)
	Ocean.inZone = zone
	local training = player:GetAttribute("Training") == true
	local holdingStaff = char ~= nil and char:FindFirstChild(STAFF_NAME) ~= nil
	Ocean.canCharge = zone and holdingStaff and sp == nil and not Ocean.handsFull
	if zone and not wasInZone and char and not holdingStaff and sp == nil and not training then
		-- Walking onto the shore pulls out the staff for you.
		local tool = player.Backpack:FindFirstChild(STAFF_NAME)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if tool and hum and not char:FindFirstChildOfClass("Tool") then
			hum:EquipTool(tool)
		end
	end
	wasInZone = zone
	if Ocean.charging then
		if not Ocean.canCharge then
			Ocean.charging = false
			Ocean.charge = 0
		else
			Ocean.charge = math.clamp((t - chargeStart) / Config.Split.ChargeTime, 0, 1)
		end
	end

	-- Water + corridor.
	local elapsed = 0
	if sp then
		elapsed = State.serverNow() - sp.t0
		if not Formulas.isOpen(sp, elapsed) then
			-- The walls have met.
			playSound("rbxasset://sounds/splat.wav", 0.9, 0.6)
			State.effect:Fire("seaClosed", nil)
			Ocean.finish()
			sp = nil
		else
			updateCutscene(sp, elapsed)
		end
	end
	layout(sp, elapsed, t)
	Depths.update(sp, elapsed, root)

	if sp then
		-- Tick down the last five seconds before the walls meet.
		local phase, left = Ocean.timing()
		local sec = math.ceil(left)
		if phase == "closing" and sec <= 5 and sec ~= lastTick then
			lastTick = sec
			playSound("rbxasset://sounds/electronicpingshort.wav", 0.5, 0.7)
		end

		-- Eggs appear as the corridor tears open past them and are gone the
		-- moment the water covers them.
		for id, e in eggModels do
			if Formulas.eggCovered(sp, e.data, elapsed) then
				e.model:Destroy()
				eggModels[id] = nil
			elseif Formulas.halfWidthAt(sp, e.data.d, elapsed) > math.abs(e.data.x) + 1 then
				local bob = math.sin(t * 2 + id) * 0.25 + 0.25
				e.model.PrimaryPart.CFrame = CFrame.new(e.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, e.yaw + t * 0.6, 0)
				if not e.shown then
					e.shown = true
					e.model.Parent = folder
				end
			end
		end

		-- Egg prompts are live once the cutscene is over and a hand is free.
		if pendingGrab and t - pendingAt > 1.2 then
			pendingGrab = nil
		end
		local canGrab = not Ocean.cutscene and not Ocean.handsFull
		for _, e in eggModels do
			if e.shown and e.prompt.Enabled ~= canGrab then
				e.prompt.Enabled = canGrab
			end
		end
		-- With full hands, standing at an egg explains why there's no prompt.
		if root and Ocean.handsFull and t - lastFullWarn > 2.5 then
			for _, e in eggModels do
				if e.shown then
					local dx, dz = root.Position.X - e.pos.X, root.Position.Z - e.pos.Z
					if dx * dx + dz * dz <= O.GrabRadius * O.GrabRadius then
						lastFullWarn = t
						State.toast:Fire("Hands full! Carry your egg back to your base.", Color3.fromRGB(255, 200, 90))
						break
					end
				end
			end
		end
	end

	-- The staff's gem flares up as the charge builds.
	local staffTool = char and char:FindFirstChild(STAFF_NAME)
	local gem = staffTool and staffTool:FindFirstChild("Gem")
	if gem then
		local light = gem:FindFirstChildOfClass("PointLight")
		if not light then
			light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(120, 255, 255)
			light.Range = 14
			light.Parent = gem
		end
		light.Brightness = (Ocean.charging or Ocean.cutscene) and (1 + math.max(Ocean.charge, Ocean.cutscene and 1 or 0) * 7) or 0.5
	end
end

function Ocean.init()
	build()
	Depths.init()
	RunService.RenderStepped:Connect(update)

	UserInputService.InputBegan:Connect(function(input, processed)
		local source = sourceOf(input)
		if processed or source == nil then
			return
		end
		-- On touch screens a drag on the world moves the camera, so charging
		-- only starts from the on-screen HOLD button.
		if input.UserInputType == Enum.UserInputType.Touch then
			return
		end
		Ocean.beginCharge(source)
	end)
	UserInputService.InputEnded:Connect(function(input)
		local source = sourceOf(input)
		if source ~= nil then
			Ocean.releaseCharge(source)
		end
	end)

	State.effect:Connect(function(kind, payload)
		if kind == "grabbed" then
			local e = eggModels[payload.id]
			if e then
				e.model:Destroy()
				eggModels[payload.id] = nil
			end
			pendingGrab = nil
			playSound("rbxasset://sounds/electronicpingshort.wav", 0.7, 1.3)
		elseif kind == "grabFail" then
			pendingGrab = nil
			if payload.reason == "covered" then
				local e = eggModels[payload.id]
				if e then
					e.model:Destroy()
					eggModels[payload.id] = nil
				end
			end
		elseif kind == "caught" then
			playSound("rbxasset://sounds/splat.wav", 0.9, 0.7)
		elseif kind == "splitEnd" then
			Ocean.finish()
		end
	end)

	player.CharacterAdded:Connect(function()
		Ocean.charging = false
		endCutscene()
	end)
end

return Ocean
