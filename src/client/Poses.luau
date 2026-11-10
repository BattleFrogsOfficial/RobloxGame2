-- Procedural full-body animation for every player, on every client.
--
-- Two moves:
--   cast    - parting the sea: coil, leap, slam the staff down, then rise off
--             the ground with both arms spreading apart as the sea opens
--   workout - a clean-and-press rep: deep squat, explosive drive with a hop
--             as the bar punches overhead, a shaking hold, and the lower
--
-- The server only publishes timing as player attributes (CastStart,
-- Training, RepStart, WeightTier); each client turns that into joint
-- rotations here, so the motion works on both R6 and R15 avatars and is seen
-- by everyone.
--
-- Joints are posed by changing each joint's resting offset from the value it
-- had when the move began, and putting that value back when the move ends.
-- The engine's Animator never writes that offset (it writes Transform), so
-- nothing overrides the pose; whatever default animation is playing (idle,
-- holding a tool) simply layers on top.
--
-- Characters come with one of two joint types, and both are handled:
--   Motor6D             (classic)  resting offset = Motor6D.C0
--   AnimationConstraint (newer "avatar joint upgrade" rigs)
--                                  resting offset = its Attachment0.CFrame

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voxel = require(Shared.Voxel)

local State = require(script.Parent.State)

local Poses = {}

local rad = math.rad

-- workout: the fraction of a rep at which the bar locks out overhead
Poses.LOCKOUT = 0.5

local folder: Folder
local barbells: { [Player]: { model: Model, tier: number } } = {}
local lastPhase: { [Player]: number } = {}
local lastBolt: { [Player]: number } = {}
local hold: { pos: Vector3 }? = nil -- where the local player is pinned while posing

----------------------------------------------------------------------------
-- Rig access
----------------------------------------------------------------------------
local R15_JOINTS = {
	rShoulder = { "RightUpperArm", "RightShoulder" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	rElbow = { "RightLowerArm", "RightElbow" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	rHip = { "RightUpperLeg", "RightHip" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	waist = { "UpperTorso", "Waist" },
	root = { "LowerTorso", "Root" },
}
local R6_JOINTS = {
	rShoulder = { "Torso", "Right Shoulder" },
	lShoulder = { "Torso", "Left Shoulder" },
	rHip = { "Torso", "Right Hip" },
	lHip = { "Torso", "Left Hip" },
	root = { "HumanoidRootPart", "RootJoint" },
}

local function isR6(char: Model): boolean
	return char:FindFirstChild("Torso") ~= nil and char:FindFirstChild("UpperTorso") == nil
end

-- The joint for a pose key: a Motor6D or an AnimationConstraint, wherever in
-- the character it lives.
local function joint(char: Model, r6: boolean, key: string): Instance?
	local def = (r6 and R6_JOINTS or R15_JOINTS)[key]
	if not def then
		return nil
	end
	local part = char:FindFirstChild(def[1])
	local j = part and part:FindFirstChild(def[2])
	if not j then
		j = char:FindFirstChild(def[2], true)
	end
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return j
	end
	return nil
end

-- Read / write a joint's resting offset, whichever type it is.
local function getOffset(j: Instance): CFrame?
	if j:IsA("Motor6D") then
		return j.C0
	end
	local att = (j :: any).Attachment0
	return att and att.CFrame
end

local function setOffset(j: Instance, cf: CFrame)
	if j:IsA("Motor6D") then
		j.C0 = cf
	else
		local att = (j :: any).Attachment0
		if att then
			att.CFrame = cf
		end
	end
end

-- Turn a pose entry into the rotation for a joint on this rig.
--   limbs (shoulder, elbow, hip, knee): { f = degrees forward/up from hanging
--     straight down, s = degrees out to the side }
--   root:  { y = studs up, lean = degrees forward, yaw = degrees of turn }
--   waist: { lean = degrees forward, yaw = degrees of turn }
-- R15 joints share their limb's axes. R6 shoulder and hip joints are turned
-- sideways (mirrored left to right) and its root joint is tipped on its back.
local function offsetFor(r6: boolean, key: string, v): CFrame
	if key == "root" then
		if r6 then
			return CFrame.new(0, 0, v.y or 0) * CFrame.Angles(rad(v.lean or 0), 0, rad(v.yaw or 0))
		end
		return CFrame.new(0, v.y or 0, 0) * CFrame.Angles(rad(-(v.lean or 0)), rad(v.yaw or 0), 0)
	elseif key == "waist" then
		return CFrame.Angles(rad(-(v.lean or 0)), rad(v.yaw or 0), 0)
	end
	local left = string.sub(key, 1, 1) == "l"
	local f, s = v.f or 0, v.s or 0
	if r6 then
		return CFrame.Angles(0, 0, rad(left and -f or f)) * CFrame.Angles(rad(-s), 0, 0)
	end
	return CFrame.Angles(rad(f), 0, 0) * CFrame.Angles(0, 0, rad(left and -s or s))
end

-- What we are currently posing: per player, the character and each posed
-- joint's original resting offset.
local posed: { [Player]: { char: Model, move: string, base: { [Instance]: CFrame } } } = {}

local function release(player: Player)
	local state = posed[player]
	if not state then
		return
	end
	posed[player] = nil
	for j, offset in state.base do
		if j.Parent then
			setOffset(j, offset)
		end
	end
end

local function apply(player: Player, char: Model, move: string, pose: { [string]: any })
	local state = posed[player]
	if state and (state.char ~= char or state.move ~= move) then
		release(player)
		state = nil
	end
	local r6 = isR6(char)
	if not state then
		state = { char = char, move = move, base = {} }
		posed[player] = state
		-- One line in the Output window per move, for diagnosis.
		local found, kind = 0, "no"
		for key in pose do
			local j = joint(char, r6, key)
			if j then
				found += 1
				kind = j.ClassName
			end
		end
		print(string.format("[Poses] %s: %s on a %s rig, %d %s joints", player.Name, move, r6 and "R6" or "R15", found, kind))
	end
	for key, value in pose do
		local j = joint(char, r6, key)
		if j then
			if not state.base[j] then
				local current = getOffset(j)
				if current then
					state.base[j] = current
				end
			end
			local base = state.base[j]
			if base then
				setOffset(j, base * offsetFor(r6, key, value))
			end
		end
	end
end

----------------------------------------------------------------------------
-- Keyframe helper: value at time k along { {time, value}, ... }, eased.
----------------------------------------------------------------------------
local function track(k: number, keys: { { number } }): number
	if k <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if k <= b[1] then
			local u = (k - a[1]) / (b[1] - a[1])
			u = u * u * (3 - 2 * u)
			return a[2] + (b[2] - a[2]) * u
		end
	end
	return keys[#keys][2]
end

----------------------------------------------------------------------------
-- The moves
----------------------------------------------------------------------------

-- How each cast moves. Times are fractions of that cast's cutscene.
--   coil    deepest point of the wind-up crouch
--   apex    top of the leap (Poseidon's Wrath stays up there until `dive`)
--   slam    the staff hits the ground (Config.Casts[...].slam)
--   height  how far off the ground the leap goes, in studs
--   spin    degrees the body turns on the way up and down
local CAST_SHAPE = {
	Split = { coil = 0.12, apex = 0.24, height = 3.4, slamY = -0.9, slamLean = 32, hover = 1.8, spin = 0 },
	Super = { coil = 0.12, apex = 0.3, height = 7, slamY = -1.6, slamLean = 44, hover = 3, spin = 360 },
	Poseidon = { coil = 0.07, apex = 0.26, dive = 0.47, height = 26, slamY = -1.9, slamLean = 50, hover = 5, spin = 720 },
}

local function castShape(key: string?)
	local cast = Config.CastByKey[key or "Split"] or Config.Casts[1]
	return CAST_SHAPE[cast.key] or CAST_SHAPE.Split, cast
end

-- How far off the ground the body is at time k of a cast (for the camera).
function Poses.castHeight(k: number, key: string?): number
	local shape, cast = castShape(key)
	local keys = { { 0, 0 }, { shape.coil, -1.4 }, { shape.apex, shape.height } }
	if shape.dive then
		table.insert(keys, { shape.dive, shape.height + 1.5 })
	end
	table.insert(keys, { cast.slam, shape.slamY })
	table.insert(keys, { cast.slam + 0.1, -0.3 })
	table.insert(keys, { 0.85, shape.hover })
	table.insert(keys, { 0.95, 0.3 })
	table.insert(keys, { 1, 0 })
	return track(k, keys)
end

-- Parting the sea, k from 0 to 1 over the cutscene:
--   coil   drop into a deep crouch, twist away, staff wound back
--   leap   launch off the ground, staff swung up overhead (the bigger
--          casts spin on the way up and go far higher; Poseidon's Wrath
--          hangs in the sky with both arms raised before diving)
--   slam   come down into a lunge, staff driven forward and down
--   part   rise off the ground, both arms pushed out in front and then
--          slowly spread wide apart as the sea opens, straining
--   settle back onto the sand
-- The staff arm's angles are added to the default tool-holding pose, which
-- already has that arm raised about 90 degrees in front of the body.
function Poses.cast(k: number, clock: number, key: string?)
	local shape, cast = castShape(key)
	local c, a, s = shape.coil, shape.apex, cast.slam
	local d = shape.dive or a -- when the descent begins
	local after = s + 0.1
	-- Value at each beat: start, coil, apex, (held until the dive), slam, just after, parted, end.
	local function beats(v0, vCoil, vApex, vSlam, vAfter, vPart)
		return track(k, { { 0, v0 }, { c, vCoil }, { a, vApex }, { d, vApex }, { s, vSlam }, { after, vAfter }, { 0.85, vPart }, { 1, v0 } })
	end
	local strain = (k > after and k < 0.86) and math.sin(clock * 42) * 3 or 0
	local hoverBob = (k > after + 0.05 and k < 0.9) and math.sin(clock * 3) * 0.25 or 0
	local spread = track(k, { { 0, 0 }, { after - 0.04, 0 }, { after + 0.05, 12 }, { 0.85, 88 }, { 1, 0 } })
	-- In the sky (Poseidon's Wrath) both arms are thrown wide and up.
	local sky = shape.dive and track(k, { { 0, 0 }, { a - 0.05, 0 }, { a + 0.04, 50 }, { d, 50 }, { s, 0 } }) or 0
	local turn = track(k, { { 0, 0 }, { c, -40 }, { a, shape.spin * 0.5 }, { d, shape.spin * 0.5 }, { s, shape.spin + 12 }, { after, shape.spin }, { 1, shape.spin } })
	return {
		rShoulder = { f = beats(0, -150, 95, -15, 5, 8) + strain, s = spread + sky },
		rElbow = { f = beats(0, 80, 0, 25, 0, 0) },
		lShoulder = { f = beats(0, 75, 160, 55, 95, 98) - strain, s = spread + sky },
		lElbow = { f = beats(0, 50, 10, 30, 0, 0) },
		rHip = { f = beats(0, 75, -20, 65, 25, 12), s = spread * 0.12 },
		lHip = { f = beats(0, 75, 25, -30, -10, 6), s = spread * 0.12 },
		rKnee = { f = beats(0, -115, -35, -75, -30, -14) },
		lKnee = { f = beats(0, -115, -55, -10, -10, -20) },
		waist = { lean = beats(0, 18, -22, 30, 5, -16), yaw = track(k, { { 0, 0 }, { c, -35 }, { a, 10 }, { s, 0 }, { 1, 0 } }) },
		root = {
			y = Poses.castHeight(k, key) + hoverBob,
			lean = beats(0, -10, -18, shape.slamLean, 8, -14),
			yaw = turn,
		},
	}
end

-- One clean-and-press rep, p from 0 to 1:
--   0.00 - 0.30  drop into a deep squat with the bar racked at the shoulders
--   0.30 - 0.50  drive: legs fire, a small hop, the bar punches overhead
--   0.50 - 0.80  hold the lockout, arms shaking
--   0.80 - 1.00  lower the bar back to the shoulders
function Poses.rep(p: number, clock: number)
	local shake = (p > 0.52 and p < 0.8) and math.sin(clock * 46) * 2.5 or 0
	local press = track(p, { { 0, 45 }, { 0.3, 60 }, { 0.5, 178 }, { 0.8, 174 }, { 1, 45 } }) + shake
	local bend = track(p, { { 0, 130 }, { 0.3, 125 }, { 0.5, 0 }, { 0.8, 0 }, { 1, 130 } })
	local wide = track(p, { { 0, 10 }, { 0.3, 10 }, { 0.5, 20 }, { 0.8, 20 }, { 1, 10 } })
	local hip = track(p, { { 0, 5 }, { 0.3, 95 }, { 0.47, -5 }, { 1, 5 } })
	local knee = track(p, { { 0, -5 }, { 0.3, -120 }, { 0.47, 0 }, { 1, -5 } })
	return {
		rShoulder = { f = press, s = wide },
		lShoulder = { f = press, s = wide },
		rElbow = { f = bend },
		lElbow = { f = bend },
		rHip = { f = hip, s = 12 },
		lHip = { f = hip, s = 12 },
		rKnee = { f = knee },
		lKnee = { f = knee },
		waist = { lean = track(p, { { 0, 0 }, { 0.3, 16 }, { 0.5, -10 }, { 0.8, -5 }, { 1, 0 } }) },
		root = {
			y = track(p, { { 0, 0 }, { 0.3, -1.5 }, { 0.46, 0.2 }, { 0.52, 1.1 }, { 0.6, 0 }, { 1, 0 } }),
			lean = track(p, { { 0, 0 }, { 0.3, 22 }, { 0.5, -8 }, { 0.8, -4 }, { 1, 0 } }),
		},
	}
end

----------------------------------------------------------------------------
-- Impact effects: a shockwave ring and a burst of debris at the feet
----------------------------------------------------------------------------
local function shockwave(pos: Vector3, color: Color3, size: number)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.35, 2, 2)
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.7)

	for _ = 1, 10 do
		local chunk = Instance.new("Part")
		chunk.Name = "Debris"
		local s = 0.4 + math.random() * 0.7
		chunk.Size = Vector3.new(s, s, s)
		chunk.Color = color:Lerp(Color3.new(1, 1, 1), math.random() * 0.6)
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0))
		chunk.Parent = folder
		local angle = math.random() * math.pi * 2
		local speed = size * (1.2 + math.random())
		chunk.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * speed, 22 + math.random() * 26, math.sin(angle) * speed)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() * 12 - 6, math.random() * 12 - 6, math.random() * 12 - 6)
		Debris:AddItem(chunk, 1.2)
	end
end

-- A jagged bolt of lightning from `from` down to `to`, gone in a blink.
local function lightning(from: Vector3, to: Vector3)
	local points = { from }
	local steps = 8
	for i = 1, steps - 1 do
		local p = from:Lerp(to, i / steps)
		table.insert(points, p + Vector3.new(math.random() * 8 - 4, 0, math.random() * 8 - 4))
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = Instance.new("Part")
		seg.Name = "Lightning"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = Color3.fromRGB(205, 235, 255)
		local thick = 0.5 + math.random() * 0.7
		seg.Size = Vector3.new(thick, thick, (b - a).Magnitude)
		seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		seg.Parent = folder
		Debris:AddItem(seg, 0.16)
	end
	local glow = Instance.new("Part")
	glow.Name = "LightningFlash"
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.Transparency = 1
	glow.Size = Vector3.new(1, 1, 1)
	glow.CFrame = CFrame.new(to + Vector3.new(0, 2, 0))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 225, 255)
	light.Brightness = 12
	light.Range = 60
	light.Parent = glow
	glow.Parent = folder
	Debris:AddItem(glow, 0.2)
end

-- A short downward kick of the local camera, for weight.
local function cameraKick(char: Model, amount: number)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.CameraOffset = Vector3.new(0, -amount, 0)
	TweenService:Create(humanoid, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CameraOffset = Vector3.zero }):Play()
end

local function feetPosition(char: Model): Vector3
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	return root.Position - Vector3.new(0, 2.9, 0)
end

-- Fire `fn` once when a move's phase passes `mark`.
local function crossed(player: Player, phase: number, mark: number): boolean
	local last = lastPhase[player]
	lastPhase[player] = phase
	return last ~= nil and last < mark and phase >= mark
end

----------------------------------------------------------------------------
-- Barbell: held in the hands, wherever the arms actually are
----------------------------------------------------------------------------
local function handPosition(char: Model, r6: boolean, side: string): Vector3?
	if r6 then
		local arm = char:FindFirstChild(side .. " Arm") :: BasePart?
		return arm and (arm.CFrame * CFrame.new(0, -0.9, 0)).Position
	end
	local hand = (char:FindFirstChild(side .. "Hand") or char:FindFirstChild(side .. "LowerArm") or char:FindFirstChild(side .. "UpperArm")) :: BasePart?
	return hand and hand.Position
end

local function dropBarbell(player: Player)
	local held = barbells[player]
	if held then
		held.model:Destroy()
		barbells[player] = nil
	end
end

local function holdBarbell(player: Player, char: Model)
	local r6 = isR6(char)
	local right = handPosition(char, r6, "Right")
	local left = handPosition(char, r6, "Left")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not right or not left or not root then
		dropBarbell(player)
		return
	end
	local tier = player:GetAttribute("WeightTier") or 1
	local held = barbells[player]
	if not held or held.tier ~= tier then
		dropBarbell(player)
		local model = Voxel.barbell(tier)
		model.Name = "TrainingBarbell"
		Voxel.weld(model, true) -- move the whole bar by its root
		model.Parent = folder
		held = { model = model, tier = tier }
		barbells[player] = held
	end
	-- The bar runs hand to hand (it's built along its X axis).
	local across = right - left
	local axis = across.Magnitude > 0.2 and across.Unit or root.CFrame.RightVector
	held.model.PrimaryPart.CFrame = CFrame.fromMatrix((right + left) / 2, axis, root.CFrame.UpVector)
end

----------------------------------------------------------------------------
-- Per-frame
----------------------------------------------------------------------------

-- Where in the rep a training player is. The server awards Strength at each
-- multiple of RepTime after RepStart; that moment is the lockout here.
function Poses.repPhase(player: Player, now: number): number
	local start = player:GetAttribute("RepStart") or now
	return ((now - start) / Config.Training.RepTime + Poses.LOCKOUT) % 1
end

-- While the local player is posing, pin them where they stand unless they
-- are actually steering. The body moving around over the feet otherwise
-- nudges the character a little each rep until they slide off the pad.
local function pin(char: Model, always: boolean)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local steering = not always and humanoid:GetMoveVelocity().Magnitude > 0.5
	if not hold or steering then
		hold = { pos = root.Position }
		return
	end
	local drift = Vector3.new(root.Position.X - hold.pos.X, 0, root.Position.Z - hold.pos.Z)
	if drift.Magnitude > 0.02 then
		root.CFrame = CFrame.new(hold.pos.X, root.Position.Y, hold.pos.Z) * root.CFrame.Rotation
	end
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
end

-- The impact effects for a cast, by how far through it is.
local function castEffects(player: Player, char: Model, k: number, key: string, me: boolean)
	local shape, cast = castShape(key)
	local feet = feetPosition(char)
	local now = os.clock()
	-- Lightning: the bigger casts call it down while they wind up and fly.
	if cast.tier >= 2 and k > shape.coil and k < cast.slam then
		local gap = cast.tier == 3 and 0.11 or 0.22
		if now - (lastBolt[player] or 0) > gap then
			lastBolt[player] = now
			local reach = cast.tier == 3 and 34 or 14
			local angle = math.random() * math.pi * 2
			local target = feet + Vector3.new(math.cos(angle) * reach * math.random(), 0, math.sin(angle) * reach * math.random())
			lightning(target + Vector3.new(math.random() * 20 - 10, 150, math.random() * 20 - 10), target)
			if me then
				State.effect:Fire("bolt", cast.tier)
			end
		end
	end
	if crossed(player, k, cast.slam) then
		local size = cast.tier == 3 and 110 or cast.tier == 2 and 60 or 30
		local color = cast.tier == 3 and Color3.fromRGB(255, 225, 120) or Color3.fromRGB(120, 230, 255)
		shockwave(feet, color, size)
		if cast.tier >= 2 then
			-- A bolt straight onto the staff, and more rings rolling out.
			lightning(feet + Vector3.new(0, 160, 0), feet)
			for i = 1, cast.tier do
				task.delay(i * 0.12, shockwave, feet, Color3.fromRGB(120, 230, 255), size * (0.5 + i * 0.25))
			end
			if cast.tier == 3 then
				for i = 1, 6 do
					local angle = i * math.pi / 3
					local at = feet + Vector3.new(math.cos(angle) * 22, 0, math.sin(angle) * 22)
					lightning(at + Vector3.new(0, 150, 0), at)
				end
			end
		end
	end
end

-- Every frame: pose whoever is casting or training, release everyone else.
local function poseAll()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local me = Players.LocalPlayer
	local mePosing = false
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local active = false
		if char and char:FindFirstChild("HumanoidRootPart") then
			if player:GetAttribute("Training") then
				local p = Poses.repPhase(player, now)
				apply(player, char, "workout", Poses.rep(p, clock))
				active = true
				if player == me then
					mePosing = true
					pin(char, false)
				end
				if crossed(player, p, Poses.LOCKOUT) then
					shockwave(feetPosition(char), Color3.fromRGB(255, 215, 80), 16)
					if player == me then
						cameraKick(char, 0.7)
					end
				end
			else
				local castStart = player:GetAttribute("CastStart")
				if castStart then
					local seconds = player:GetAttribute("CastSeconds") or Config.Ocean.OpenAnim
					local key = player:GetAttribute("CastKey") or "Split"
					local k = (now - castStart) / seconds
					if k >= 0 and k < 1 then
						apply(player, char, "cast", Poses.cast(k, clock, key))
						active = true
						if player == me then
							mePosing = true
							pin(char, true)
						end
						castEffects(player, char, k, key, player == me)
					end
				end
			end
		end
		if not active then
			lastPhase[player] = nil
			if posed[player] then
				release(player)
			end
		end
	end
	if not mePosing then
		hold = nil
	end
end

-- Keep every training player's barbell in their hands.
local function carryBarbells()
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and player:GetAttribute("Training") then
			holdBarbell(player, char)
		elseif barbells[player] then
			dropBarbell(player)
		end
	end
	for player in barbells do
		if not player.Parent then
			dropBarbell(player)
		end
	end
end

function Poses.init()
	folder = Instance.new("Folder")
	folder.Name = "Poses"
	folder.Parent = workspace
	local reported = false
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			poseAll()
			carryBarbells()
		end)
		if not ok and not reported then
			reported = true
			warn("[Poses] error: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		dropBarbell(player)
		lastPhase[player] = nil
		lastBolt[player] = nil
	end)
end

return Poses
