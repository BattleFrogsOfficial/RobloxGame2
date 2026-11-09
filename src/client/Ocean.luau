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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Voxel = require(Shared.Voxel)

local State = require(script.Parent.State)

local Ocean = {}

local O = Config.Ocean
local SHORE = O.ShoreZ
local STAFF_NAME = "Sea Staff"
local player = Players.LocalPlayer

local WATER = Color3.fromRGB(35, 135, 235)
local WALL = Color3.fromRGB(60, 160, 245)
local WALL_DARK = Color3.fromRGB(45, 140, 235)
local FOAM = Color3.fromRGB(235, 250, 255)

-- The near sea (re-shaped every frame while parted) covers this box; the
-- rest of the ocean, out to the horizon, is static.
local NEAR_X = O.HalfX + 45
local NEAR_Z = SHORE - O.Reach - 60
local FAR_X = 3072
local FAR_Z = SHORE - 4096
local MAX_PART = 2048 -- Roblox's largest part size

local SEG = 10 -- studs per wall segment
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
local wallSegs = { L = {}, R = {} } -- [side][i] = { wall, cap }
local eggModels: { [number]: any } = {}
local chargeStart = 0
local chargeSource: any = nil -- "mouse" or a touch InputObject
local pendingGrab: number? = nil
local pendingAt = 0
local lastFullWarn = 0
local wasInZone = false
local lastTick = -1
local scene: any = nil -- cutscene bookkeeping

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
	e.Color = ColorSequence.new(FOAM)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
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

	-- The endless sea around the near box.
	fillStatic(-FAR_X, -NEAR_X, FAR_Z, SHORE)
	fillStatic(NEAR_X, FAR_X, FAR_Z, SHORE)
	fillStatic(-NEAR_X, NEAR_X, FAR_Z, NEAR_Z)

	newPart("Main", WATER, 0.25)
	newPart("Left", WATER, 0.25)
	newPart("Right", WATER, 0.25)
	newPart("Far", WATER, 0.25)

	-- Corridor walls are rows of segments so their tops can roll like waves.
	for _, side in { "L", "R" } do
		for i = 1, MAX_SEGS do
			local wall = newPart("Wall" .. side .. i, i % 2 == 0 and WALL or WALL_DARK, 0.12)
			local cap = newPart("Cap" .. side .. i, FOAM, 0.1)
			-- Solid and queryable: you bump into the wall, and the default
			-- camera zooms in instead of ending up behind a sheet of water.
			solid[wall] = true
			wallSegs[side][i] = { wall = wall, cap = cap }
		end
		-- Foam churning along the foot of each wall as it advances.
		addSpray(newPart("Churn" .. side, FOAM, 0.4), 45)
	end
	newPart("WallEnd", WALL, 0.2)
	newPart("CapEnd", FOAM, 0.15)

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
			hide(seg.wall)
			hide(seg.cap)
		end
		parts["Churn" .. side].ParticleEmitter.Enabled = false
	end
	parts.BarrierL.CanCollide = false
	parts.BarrierR.CanCollide = false
end

-- Lines of foam drifting toward the shore; they split around the corridor so
-- they never float across the gap.
local function layoutCrests(sp, half: number, length: number, t: number)
	local y1 = O.WaterTopY
	for i = 1, CRESTS do
		local phase = (t * 0.02 + i / CRESTS) % 1
		local z = SHORE - 620 + phase * 610
		local fade = math.sin(phase * math.pi)
		local a, b = parts["CrestA" .. i], parts["CrestB" .. i]
		if sp and half > 0.05 and z + 1 >= SHORE - length - WALL_THICK then
			setBox(a, -1024, sp.cx - half - WALL_THICK, y1, y1 + 0.12, z - 0.8, z + 0.8)
			setBox(b, sp.cx + half + WALL_THICK, 1024, y1, y1 + 0.12, z - 0.8, z + 0.8)
		else
			setBox(a, -1024, 1024, y1, y1 + 0.12, z - 0.8, z + 0.8)
			hide(b)
		end
		for _, p in { a, b } do
			if p.Transparency < 1 then
				p.Transparency = 1 - 0.5 * fade
			end
		end
	end
end

-- Lay out every near-sea part for the current split (or the closed sea).
-- `half` is the corridor's half-width right now, `length` how far it reaches.
local function layout(sp, half: number, length: number, rise: number, t: number)
	local y0, y1 = O.SeabedY, O.WaterTopY
	local waterline = SHORE - 2.5 -- where the water surface meets the ramp
	layoutCrests(sp, half, length, t)

	if not sp or half <= 0.05 or length <= 0.05 then
		setBox(parts.Main, -NEAR_X, NEAR_X, y0, y1, NEAR_Z, SHORE)
		hideCorridor()
		setBox(parts.FoamA, -NEAR_X, NEAR_X, y1 - 0.05, y1 + 0.15, waterline - 1, waterline + 1)
		hide(parts.FoamB)
		return
	end

	local xl, xr = sp.cx - half, sp.cx + half
	local farZ = SHORE - length
	hide(parts.Main)
	-- The flat sea stops where the walls begin, so no two water faces share
	-- a plane (coplanar translucent faces shimmer).
	setBox(parts.Left, -NEAR_X, xl - WALL_THICK, y0, y1, NEAR_Z, SHORE)
	setBox(parts.Right, xr + WALL_THICK, NEAR_X, y0, y1, NEAR_Z, SHORE)
	setBox(parts.Far, xl - WALL_THICK, xr + WALL_THICK, y0, y1, NEAR_Z, farZ - WALL_THICK)

	-- Walls of water: they rise during the cutscene, their tops roll, and
	-- they lean taller the closer they are to slamming shut.
	local eased = 1 - (1 - rise) ^ 3
	local squeeze = 1 - math.clamp(half / (sp.width / 2), 0, 1)
	local baseTop = y1 + (O.WallTopY + squeeze * 10 - y1) * eased
	for i = 1, MAX_SEGS do
		local d0 = (i - 1) * SEG
		local d1 = math.min(i * SEG, length)
		local segL, segR = wallSegs.L[i], wallSegs.R[i]
		if d1 - d0 < 0.05 then
			hide(segL.wall)
			hide(segL.cap)
			hide(segR.wall)
			hide(segR.cap)
		else
			local za, zb = SHORE - d1, SHORE - d0
			local topL = baseTop + math.sin(t * 2.1 + i * 0.9) * 1.4 * eased
			local topR = baseTop + math.sin(t * 2.1 + i * 0.9 + 2) * 1.4 * eased
			setBox(segL.wall, xl - WALL_THICK, xl, y0, topL, za, zb)
			setBox(segL.cap, xl - WALL_THICK - 0.3, xl + 0.5, topL, topL + 0.9, za, zb)
			setBox(segR.wall, xr, xr + WALL_THICK, y0, topR, za, zb)
			setBox(segR.cap, xr - 0.5, xr + WALL_THICK + 0.3, topR, topR + 0.9, za, zb)
		end
	end
	local endTop = baseTop + 1.5 + math.sin(t * 3) * 0.8 * eased
	setBox(parts.WallEnd, xl - WALL_THICK, xr + WALL_THICK, y0, endTop, farZ - WALL_THICK, farZ)
	setBox(parts.CapEnd, xl - WALL_THICK - 0.3, xr + WALL_THICK + 0.3, endTop, endTop + 1, farZ - WALL_THICK - 0.3, farZ + 0.3)

	-- Foam churn at the foot of each closing wall.
	local closing = rise >= 1
	setBox(parts.ChurnL, xl, xl + 1.2, y0, y0 + 0.5, farZ, SHORE - O.RampLength)
	setBox(parts.ChurnR, xr - 1.2, xr, y0, y0 + 0.5, farZ, SHORE - O.RampLength)
	parts.ChurnL.ParticleEmitter.Enabled = closing
	parts.ChurnR.ParticleEmitter.Enabled = closing

	-- Wet sand on the flat seabed part of the corridor.
	if length > O.RampLength then
		setBox(parts.WetSand, xl, xr, y0, y0 + 0.08, farZ, SHORE - O.RampLength)
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
	setBox(parts.FoamA, -NEAR_X, xl - WALL_THICK, y1 - 0.05, y1 + 0.15, waterline - 1, waterline + 1)
	setBox(parts.FoamB, xr + WALL_THICK, NEAR_X, y1 - 0.05, y1 + 0.15, waterline - 1, waterline + 1)
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
		eggModels[e.id] = { model = model, data = e, pos = pos, yaw = yaw, shown = false }
	end
end

----------------------------------------------------------------------------
-- The parting cutscene: a hero shot of the staff going up, then the camera
-- cranes up and back while the sea rips open down its whole length.
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
		fov = camera.FieldOfView,
		origin = Vector3.new(sp.cx, root.Position.Y, root.Position.Z),
		humanoid = hum,
		walkSpeed = hum and hum.WalkSpeed or 16,
	}
	if hum then
		hum.WalkSpeed = 0 -- hold still while the sea opens
	end
	-- Thrust the staff arm up (local only; nobody else sees the cutscene).
	local arm = char:FindFirstChild("RightUpperArm")
	local shoulder = arm and arm:FindFirstChild("RightShoulder")
	if shoulder and shoulder:IsA("Motor6D") then
		scene.shoulder = shoulder
		scene.shoulderC0 = shoulder.C0
		shoulder.C0 = shoulder.C0 * CFrame.Angles(math.rad(165), 0, 0)
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
	s.camera.CameraType = s.cameraType
	s.camera.FieldOfView = s.fov
	if s.humanoid and s.humanoid.Parent then
		s.humanoid.WalkSpeed = s.walkSpeed
	end
	if s.shoulder and s.shoulder.Parent then
		s.shoulder.C0 = s.shoulderC0
	end
end

local function updateCutscene(sp, elapsed: number)
	if not scene then
		return
	end
	local k = elapsed / O.OpenAnim
	if k >= 1 then
		endCutscene()
		return
	end
	local p = scene.origin
	local camPos, lookAt
	if k < 0.28 then
		-- Hero shot from out over the water, looking back at the player.
		local u = k / 0.28
		camPos = p + Vector3.new(7 - 5 * u, 2.5 + u, -12 + 2 * u)
		lookAt = p + Vector3.new(0, 2.2, 0)
	else
		-- Crane up and back as the corridor tears open into the distance.
		local v = (k - 0.28) / 0.72
		v = v * v * (3 - 2 * v)
		camPos = (p + Vector3.new(0, 7, 12)):Lerp(p + Vector3.new(0, 38 + sp.length * 0.08, 34), v)
		lookAt = p + Vector3.new(0, -6, -(24 + sp.length * 0.55 * v))
		local shake = (1 - v) * 0.7
		camPos += Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake
	end
	scene.camera.CFrame = CFrame.lookAt(camPos, lookAt)
	scene.camera.FieldOfView = scene.fov + 16 * math.sin(math.pi * math.clamp(k, 0, 1))
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
	if elapsed < O.OpenAnim then
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
	local half, length, rise, elapsed = 0, 0, 0, 0
	if sp then
		elapsed = State.serverNow() - sp.t0
		if not Formulas.isOpen(sp, elapsed) then
			-- The walls have met.
			playSound("rbxasset://sounds/splat.wav", 0.9, 0.6)
			State.effect:Fire("seaClosed", nil)
			Ocean.finish()
			sp = nil
		else
			half = Formulas.halfWidth(sp, elapsed)
			length = Formulas.openLength(sp, elapsed)
			rise = math.clamp(elapsed / (O.OpenAnim * 0.6), 0, 1)
			updateCutscene(sp, elapsed)
		end
	end
	layout(sp, half, length, rise, t)

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
			elseif e.data.d <= length + 0.5 then
				local bob = math.sin(t * 2 + id) * 0.25 + 0.25
				e.model.PrimaryPart.CFrame = CFrame.new(e.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, e.yaw + t * 0.6, 0)
				if not e.shown then
					e.shown = true
					e.model.Parent = folder
				end
			end
		end

		-- Grab the nearest egg in reach.
		if pendingGrab and t - pendingAt > 1.2 then
			pendingGrab = nil
		end
		if root and not pendingGrab and not Ocean.cutscene then
			for id, e in eggModels do
				if e.shown then
					local dx, dz = root.Position.X - e.pos.X, root.Position.Z - e.pos.Z
					if dx * dx + dz * dz <= O.GrabRadius * O.GrabRadius then
						if Ocean.handsFull then
							if t - lastFullWarn > 2.5 then
								lastFullWarn = t
								State.toast:Fire("Hands full! Carry your egg back to your base.", Color3.fromRGB(255, 200, 90))
							end
						else
							pendingGrab = id
							pendingAt = t
							Remotes.get("GrabEgg"):FireServer(id)
						end
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
