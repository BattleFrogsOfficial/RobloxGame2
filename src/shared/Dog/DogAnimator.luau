--!strict
-- Procedural animation for the shared DogFactory rig. One rig, every animation: no AnimationController,
-- no uploaded animations. Poses are written to Motor6D.Transform each frame from a single shared loop,
-- so CLIENT-SIDE use is purely local (Transform never replicates).
--
--   local anim = DogAnimator.new(model, { AlwaysAnimate = true })
--   anim:Play("idle" | "run" | "bolt" | "sit" | "hop")     looping states
--   anim:PlayOnce("leap" | "catch" | "fumble" | "sniff" | "look" | "pickup" | "victory" | "sadlook", seconds?)
--                                                    one-shot; YIELDS, then
--                                                    returns to the loop state
--   anim:StartOnce(state, seconds?)                  same one-shot without yielding (cutscene timelines)
--   anim.LookYaw / anim.LookPitch (radians)          where the "look" one-shot turns the head (e.g. at the camera)
--   anim.HopRate (hops per second)                   pace of the "hop" loop
--   anim.Victory = { Jumps, JumpTime, JumpGap, Height, WagHz, WagDegrees, EarLag, EarFlapDegrees }
--                                                    shape of the "victory" one-shot (the cutscene catch celebration:
--                                                    bouncy jumps in place, fast tail wag, ears lagging the body)
--   anim.Sad = { EarDownDegrees }                    "sadlook": look at (LookYaw, LookPitch), ears drop, tail still
--   DogAnimator.Idle(model, opts?) -> { Stop }        self-contained C0-driven idle (ViewportFrame WorldModels)
--   anim:Destroy()
--
-- Root motion (moving the whole model across the ground) is the caller's job (PivotTo); the animator
-- only moves joints, including the RootJoint bob/leap arc relative to the Root part.
local RunService = game:GetService("RunService")

local DogAnimator = {}
DogAnimator.__index = DogAnimator

export type LoopState = "idle" | "run" | "bolt" | "sit" | "hop"
export type OnceState = "leap" | "catch" | "fumble" | "sniff" | "look" | "pickup" | "victory" | "sadlook"

export type VictoryShape = {
	Jumps: number, -- bouncy jumps in place
	JumpTime: number, -- s per jump (crouch + air + land)
	JumpGap: number, -- s standing between jumps
	Height: number, -- studs at scale 1
	WagHz: number, -- tail wag frequency (whole beat)
	WagDegrees: number, -- tail wag amplitude
	EarLag: number, -- s the ears lag the body
	EarFlapDegrees: number, -- ear swing at full body speed
}

type Motors = {
	Root: Motor6D?,
	Necks: { Motor6D },
	Hips: { [string]: Motor6D },
	Tails: { Motor6D },
	Ears: { Motor6D },
	Wings: { Motor6D },
	Orbit: Motor6D?,
}

export type Animator = typeof(setmetatable({} :: {
	Model: Model,
	Motors: Motors,
	Loop: string,
	Once: string?,
	OnceStart: number,
	OnceLength: number,
	Time: number,
	Phase: number,
	Scale: number,
	Speed: number,
	AlwaysAnimate: boolean,
	Destroyed: boolean,
	LookYaw: number,
	LookPitch: number,
	HopRate: number,
	Victory: VictoryShape,
	Sad: { EarDownDegrees: number },
}, DogAnimator))

DogAnimator.CullDistance = 220 -- studs; farther dogs freeze (unless AlwaysAnimate)
DogAnimator.Lengths = { leap = 0.9, catch = 0.8, fumble = 1.1, sniff = 0.6, look = 0.6, pickup = 0.4, victory = 2.0, sadlook = 0.75 }
-- Defaults for anim.Victory / anim.Sad (the cutscene overrides them from Config/Cutscene.Victory / .Sniff).
DogAnimator.VictoryDefaults = { Jumps = 2, JumpTime = 0.7, JumpGap = 0.15, Height = 1.6, WagHz = 6, WagDegrees = 40,
	EarLag = 0.1, EarFlapDegrees = 45 } :: VictoryShape
DogAnimator.SadDefaults = { EarDownDegrees = 55 }

local active: { [Animator]: boolean } = {}
local conn: RBXScriptConnection? = nil

local function collect(model: Model): Motors
	local m: Motors = { Root = nil, Necks = {}, Hips = {}, Tails = {}, Ears = {}, Wings = {}, Orbit = nil }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local n = d.Name
			if n == "RootJoint" then
				m.Root = d
			elseif string.sub(n, 1, 4) == "Neck" then
				table.insert(m.Necks, d)
			elseif string.sub(n, 1, 3) == "Hip" then
				m.Hips[string.sub(n, 4)] = d
			elseif string.sub(n, 1, 9) == "TailJoint" then
				table.insert(m.Tails, d)
			elseif string.sub(n, 1, 3) == "Ear" then
				table.insert(m.Ears, d)
			elseif n == "WingL" or n == "WingR" then
				table.insert(m.Wings, d)
			elseif n == "Orbit" then
				m.Orbit = d
			end
		end
	end
	return m
end

local function setT(motor: Motor6D?, cf: CFrame)
	if motor then
		motor.Transform = cf
	end
end

local function smooth(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- Shared secondary motion (tails, ears, wings, orbit) for every state.
local function secondary(self: Animator, t: number, wagSpeed: number, wagAmp: number, earAmp: number, flap: number)
	for i, tail in self.Motors.Tails do
		setT(tail, CFrame.Angles(0, 0, math.sin(t * wagSpeed + i * 0.6) * wagAmp))
	end
	for i, ear in self.Motors.Ears do
		setT(ear, CFrame.Angles(math.sin(t * 3 + i) * earAmp, 0, 0))
	end
	for _, wing in self.Motors.Wings do
		local side = if wing.Name == "WingL" then -1 else 1
		setT(wing, CFrame.Angles(0, 0, side * math.sin(t * (2 + flap * 8)) * (0.12 + flap * 0.6)))
	end
	if self.Motors.Orbit then
		setT(self.Motors.Orbit, CFrame.Angles(0, t * 1.6, 0))
	end
end

local function necks(self: Animator, cf: (number) -> CFrame)
	for i, n in self.Motors.Necks do
		setT(n, cf(i))
	end
end

local function legs(self: Animator, fl: number, fr: number, bl: number, br: number)
	local h = self.Motors.Hips
	setT(h.FL, CFrame.Angles(fl, 0, 0))
	setT(h.FR, CFrame.Angles(fr, 0, 0))
	setT(h.BL, CFrame.Angles(bl, 0, 0))
	setT(h.BR, CFrame.Angles(br, 0, 0))
end

local Poses: { [string]: (Animator, number, number) -> () } = {}

Poses.idle = function(self, t, _p)
	setT(self.Motors.Root, CFrame.new(0, math.sin(t * 2) * 0.03 * self.Scale, 0))
	necks(self, function(i)
		return CFrame.Angles(math.sin(t * 0.7 + i) * 0.08, math.sin(t * 0.45 + i * 1.7) * 0.25, 0)
	end)
	legs(self, 0, 0, 0, 0)
	secondary(self, t, 7, 0.45, 0.08, 0)
end

local function gait(self: Animator, t: number, freq: number, amp: number, bob: number, lower: number)
	local ph = t * freq
	setT(self.Motors.Root, CFrame.new(0, (math.abs(math.sin(ph)) * bob - lower) * self.Scale, 0) * CFrame.Angles(math.sin(ph * 2) * 0.05, 0, 0))
	necks(self, function(i)
		return CFrame.Angles(-0.12 + math.sin(ph + i) * 0.08, 0, 0)
	end)
	local a = math.sin(ph) * amp
	legs(self, a, -a, -a, a)
	secondary(self, t, freq * 1.5, 0.25, 0.35, 0.6)
end

Poses.run = function(self, t, _p)
	gait(self, t, 9, 0.7, 0.15, 0)
end

Poses.bolt = function(self, t, _p)
	gait(self, t, 14, 0.95, 0.22, 0.12)
end

Poses.sit = function(self, t, _p)
	setT(self.Motors.Root, CFrame.new(0, -0.35 * self.Scale, 0.2 * self.Scale) * CFrame.Angles(0.45, 0, 0))
	necks(self, function(i)
		return CFrame.Angles(-0.35 + math.sin(t * 0.8 + i) * 0.05, math.sin(t * 0.5 + i) * 0.2, 0)
	end)
	legs(self, -0.45, -0.45, -1.3, -1.3)
	secondary(self, t, 5, 0.3, 0.05, 0)
end

Poses.leap = function(self, t, p)
	local s = self.Scale
	local y, pitch, front, back = 0, 0, 0, 0
	if p < 0.25 then -- crouch
		local k = smooth(p / 0.25)
		y = -0.35 * k
		pitch = -0.15 * k
		front, back = -0.3 * k, 0.4 * k
	elseif p < 0.8 then -- airborne arc
		local k = (p - 0.25) / 0.55
		y = math.sin(math.pi * k) * 2.6
		pitch = 0.45 * math.cos(math.pi * k)
		front, back = -0.9, 0.9
	else -- land
		local k = smooth((p - 0.8) / 0.2)
		y = -0.2 * (1 - k)
		front, back = -0.3 * (1 - k), 0.3 * (1 - k)
	end
	setT(self.Motors.Root, CFrame.new(0, y * s, 0) * CFrame.Angles(pitch, 0, 0))
	necks(self, function(_i)
		return CFrame.Angles(0.35 * math.sin(math.pi * p), 0, 0)
	end)
	legs(self, front, front, back, back)
	secondary(self, t, 12, 0.3, 0.4, 1)
end

Poses.catch = function(self, t, p)
	local hop = math.sin(math.pi * math.clamp(p * 1.6, 0, 1)) * 0.6
	setT(self.Motors.Root, CFrame.new(0, hop * self.Scale, 0) * CFrame.Angles(-0.25 * math.sin(math.pi * p), 0, 0))
	necks(self, function(_i)
		return CFrame.Angles(0.7 * math.sin(math.pi * math.min(p * 2, 1)), 0, 0)
	end)
	legs(self, -0.4 * hop, -0.4 * hop, 0.2 * hop, 0.2 * hop)
	secondary(self, t, 18, 0.7, 0.3, 0.8) -- happy fast wag
end

Poses.fumble = function(self, t, p)
	local decay = 1 - p
	setT(self.Motors.Root, CFrame.new(0, -0.25 * math.sin(math.pi * p) * self.Scale, 0) * CFrame.Angles(0, 0, math.sin(math.pi * p) * 0.55))
	necks(self, function(i)
		return CFrame.Angles(-0.3, math.sin(t * 28 + i) * 0.55 * decay, 0)
	end)
	legs(self, 0.5 * math.sin(t * 20) * decay, -0.4, 0.3, -0.5 * math.sin(t * 20) * decay)
	secondary(self, t, 4, 0.15, 0.6, 0.3)
end

-- Bounding hops (the cutscene dog arriving / leaving): the whole body arcs, legs tuck in the air.
Poses.hop = function(self, t, _p)
	local ph = t * math.pi * self.HopRate
	local air = math.abs(math.sin(ph))
	setT(self.Motors.Root, CFrame.new(0, air * 0.9 * self.Scale, 0) * CFrame.Angles(math.cos(ph) * 0.18, 0, 0))
	necks(self, function(i)
		return CFrame.Angles(-0.1 + math.sin(ph * 2 + i) * 0.06, 0, 0)
	end)
	local tuck = air * 0.8
	legs(self, -tuck, -tuck * 0.9, tuck, tuck * 0.9)
	secondary(self, t, 14, 0.5, 0.35, 0.7)
end

-- Nose down to the ball, small quick sniffs.
Poses.sniff = function(self, t, p)
	local down = smooth(math.min(p * 4, 1)) * (1 - smooth((p - 0.85) / 0.15))
	setT(self.Motors.Root, CFrame.new(0, -0.15 * down * self.Scale, 0) * CFrame.Angles(0.12 * down, 0, 0))
	necks(self, function(i)
		return CFrame.Angles(0.75 * down + math.sin(t * 22 + i) * 0.06 * down, math.sin(t * 3 + i) * 0.15 * down, 0)
	end)
	legs(self, 0.15 * down, 0.15 * down, 0, 0)
	secondary(self, t, 4, 0.12, 0.05, 0)
end

-- Turn the head toward (LookYaw, LookPitch) and hold (looking at the camera).
Poses.look = function(self, t, p)
	local k = smooth(math.min(p * 3, 1))
	setT(self.Motors.Root, CFrame.new())
	necks(self, function(_i)
		return CFrame.Angles(-self.LookPitch * k, self.LookYaw * k, 0)
	end)
	legs(self, 0, 0, 0, 0)
	secondary(self, t, 2, 0.05, 0.25 * k, 0)
end

-- Dip the head to the ground and come back up (picking up the ball).
Poses.pickup = function(self, t, p)
	local dip = math.sin(math.pi * math.clamp(p, 0, 1))
	setT(self.Motors.Root, CFrame.new(0, -0.2 * dip * self.Scale, 0) * CFrame.Angles(0.2 * dip, 0, 0))
	necks(self, function(_i)
		return CFrame.Angles(0.9 * dip, 0, 0)
	end)
	legs(self, 0.25 * dip, 0.25 * dip, -0.1 * dip, -0.1 * dip)
	secondary(self, t, 16, 0.6, 0.3, 0.5)
end

-- Body height (studs at scale 1, + = up) of the victory jumps at time `t` into the beat: per jump a crouch,
-- an airborne arc and a squash on landing; flat after the last jump. Pure, shared with the ear lag.
local function victoryY(v: VictoryShape, t: number): number
	if t <= 0 then
		return 0
	end
	local period = v.JumpTime + v.JumpGap
	local j = math.floor(t / period)
	if j >= v.Jumps then
		return 0
	end
	local u = (t - j * period) / math.max(1e-3, v.JumpTime)
	if u >= 1 then
		return 0
	elseif u < 0.2 then -- crouch
		return -0.22 * v.Height * smooth(u / 0.2)
	elseif u < 0.85 then -- air
		local k = (u - 0.2) / 0.65
		return -0.22 * v.Height * (1 - smooth(k * 4)) + v.Height * math.sin(math.pi * k)
	end
	return -0.15 * v.Height * math.sin(math.pi * (u - 0.85) / 0.15) -- squash on landing
end
DogAnimator.VictoryY = victoryY

-- Catch celebration (cutscene): bouncy jumps in place with the ball in the mouth, tail wagging fast the whole
-- time, ears lagging the body by EarLag (they flap up as the body drops and down as it rises).
Poses.victory = function(self, t, p)
	local v = self.Victory
	local bt = p * self.OnceLength -- seconds into the beat
	local y = victoryY(v, bt)
	local air = math.max(0, y) / math.max(1e-3, v.Height)
	local s = self.Scale
	setT(self.Motors.Root, CFrame.new(0, y * s, 0) * CFrame.Angles(-0.25 * air, 0, 0))
	necks(self, function(i)
		return CFrame.Angles(0.15 * air + math.sin(t * 5 + i) * 0.05, 0, 0)
	end)
	local tuck = air * 0.9
	legs(self, -tuck, -tuck, tuck * 0.8, tuck * 0.8)
	local wag = math.rad(v.WagDegrees)
	for i, tail in self.Motors.Tails do
		setT(tail, CFrame.Angles(0, 0, math.sin(bt * 2 * math.pi * v.WagHz + i * 0.6) * wag))
	end
	-- ears: body vertical speed EarLag ago (finite difference), normalised to the jump's take-off speed
	local lagT = bt - v.EarLag
	local dt = 1 / 60
	local vel = (victoryY(v, lagT) - victoryY(v, lagT - dt)) / dt
	local norm = math.pi * v.Height / math.max(1e-3, 0.65 * v.JumpTime)
	local flap = math.clamp(vel / norm, -1, 1) * math.rad(v.EarFlapDegrees)
	for _, ear in self.Motors.Ears do
		setT(ear, CFrame.Angles(flap, 0, 0))
	end
	for _, wing in self.Motors.Wings do
		local side = if wing.Name == "WingL" then -1 else 1
		setT(wing, CFrame.Angles(0, 0, side * (0.3 + air * 0.6 + math.sin(t * 10) * 0.15)))
	end
	if self.Motors.Orbit then
		setT(self.Motors.Orbit, CFrame.Angles(0, t * 3, 0))
	end
end

-- Missed: turn the head to (LookYaw, LookPitch), ears drop back, tail goes still, body sinks a little.
Poses.sadlook = function(self, t, p)
	local k = smooth(math.min(p * 3, 1))
	local ears = smooth(math.clamp((p - 0.2) * 3, 0, 1)) -- the ears drop just after the look lands
	setT(self.Motors.Root, CFrame.new(0, -0.08 * k * self.Scale, 0) * CFrame.Angles(-0.05 * k, 0, 0))
	necks(self, function(_i)
		return CFrame.Angles(-self.LookPitch * k - 0.1 * ears, self.LookYaw * k, 0)
	end)
	legs(self, 0, 0, 0, 0)
	for _, tail in self.Motors.Tails do
		setT(tail, CFrame.Angles(0.35 * ears, 0, 0)) -- still, drooping a little
	end
	local down = math.rad(self.Sad.EarDownDegrees) * ears
	for _, ear in self.Motors.Ears do
		setT(ear, CFrame.Angles(down, 0, 0))
	end
	for _, wing in self.Motors.Wings do
		local side = if wing.Name == "WingL" then -1 else 1
		setT(wing, CFrame.Angles(0, 0, side * -0.15 * ears))
	end
	if self.Motors.Orbit then
		setT(self.Motors.Orbit, CFrame.Angles(0, t * 0.6, 0))
	end
end

local function cameraPos(): Vector3?
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

local function stepAll(dt: number)
	local camPos = cameraPos()
	local now = os.clock()
	for self in active do
		if self.Destroyed or self.Model.Parent == nil then
			active[self] = nil
			continue
		end
		if not self.AlwaysAnimate and camPos then
			local root = self.Model.PrimaryPart
			if root and (root.Position - camPos).Magnitude > DogAnimator.CullDistance then
				continue
			end
		end
		self.Time += dt * self.Speed
		local state = self.Loop
		local p = 0
		if self.Once then
			p = (now - self.OnceStart) / self.OnceLength
			if p >= 1 then
				self.Once = nil
			else
				state = self.Once :: string
			end
		end
		local pose = Poses[state] or Poses.idle
		pose(self, self.Time, p)
	end
	if next(active) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function ensureLoop()
	if conn == nil and RunService:IsClient() then
		conn = RunService.PreSimulation:Connect(stepAll)
	end
end

function DogAnimator.new(model: Model, opts: { AlwaysAnimate: boolean?, Speed: number? }?): Animator
	local self = setmetatable({
		Model = model,
		Motors = collect(model),
		Loop = "idle",
		Once = nil :: string?,
		OnceStart = 0,
		OnceLength = 1,
		Time = math.random() * 10,
		Phase = 0,
		Scale = model:GetScale(),
		Speed = (opts and opts.Speed) or 1,
		AlwaysAnimate = (opts and opts.AlwaysAnimate) == true,
		Destroyed = false,
		LookYaw = 0,
		LookPitch = 0,
		HopRate = 2.4,
		Victory = table.clone(DogAnimator.VictoryDefaults),
		Sad = table.clone(DogAnimator.SadDefaults),
	}, DogAnimator)
	active[self] = true
	ensureLoop()
	return self
end

function DogAnimator.Play(self: Animator, state: LoopState)
	self.Loop = state
end

-- One-shot; yields for its length, then the loop state resumes.
function DogAnimator.PlayOnce(self: Animator, state: OnceState, seconds: number?)
	local len = seconds or (DogAnimator.Lengths :: any)[state] or 1
	self.Once = state
	self.OnceStart = os.clock()
	self.OnceLength = math.max(0.05, len)
	task.wait(len)
	if self.Once == state then
		self.Once = nil
	end
end

-- One-shot that does not yield: the pose plays for `seconds`, then the loop state resumes.
function DogAnimator.StartOnce(self: Animator, state: OnceState, seconds: number?)
	self.Once = state
	self.OnceStart = os.clock()
	self.OnceLength = math.max(0.05, seconds or (DogAnimator.Lengths :: any)[state] or 1)
end

function DogAnimator.Reset(self: Animator)
	local m = self.Motors
	setT(m.Root, CFrame.new())
	for _, list in { m.Necks, m.Tails, m.Ears, m.Wings } do
		for _, motor in list do
			motor.Transform = CFrame.new()
		end
	end
	for _, motor in m.Hips do
		motor.Transform = CFrame.new()
	end
end

function DogAnimator.Destroy(self: Animator)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	active[self] = nil
	if self.Model.Parent then
		self:Reset()
	end
end

-- ============================================================================================
-- DogAnimator.Idle(model, opts?) -> { Stop }   (SHARED API: the reveal end card codes against it)
-- A self-contained idle loop for a dog shown on its own (end card ViewportFrame WorldModel, previews).
-- No physics, no Humanoid, no Transform: it writes Motor6D.C0 (from the C0 captured at start) and
-- restores every C0 on Stop(). Works in a WorldModel because C0 is solved by the joint, not by physics.
--   WagHz     tail wag frequency (default 6; ignored when Mood = "Sad": tail still)
--   HopEvery  seconds between little happy hops (default 0 = no hops; hops move the RootJoint, not the pivot)
--   HopHeight hop height in studs at scale 1 (default 0.6)
--   Ears      flap the ears (default true; "Sad" holds them down)
--   Mood      "Happy" (default) or "Sad": tail still, ears down, head turned to look back over the shoulder
-- ============================================================================================
export type IdleOpts = { WagHz: number?, HopEvery: number?, HopHeight: number?, Ears: boolean?, Mood: ("Happy" | "Sad")? }
export type IdleHandle = { Stop: () -> () }

DogAnimator.IdleDefaults = {
	WagHz = 6, -- tail wag frequency
	WagDegrees = 30, -- tail wag amplitude (Happy)
	HopEvery = 0, -- s between hops; 0 = no hops
	HopHeight = 0.6, -- studs at scale 1
	HopTime = 0.45, -- s per hop
	EarLag = 0.1, -- s the ears lag the body on a hop
	EarFlapDegrees = 35, -- ear swing on a hop
	EarIdleDegrees = 5, -- slow ear drift between hops
	SadEarDegrees = 55, -- Sad: ears pinned back / down
	SadLookYawDegrees = 70, -- Sad: head turned to look back over the shoulder
	SadLookPitchDegrees = -8, -- Sad: and a little down
	SadTailDroopDegrees = 25, -- Sad: tail still, drooping
}

local function idleHopY(t: number, every: number, height: number, hopTime: number): number
	if every <= 0 or t < 0 then
		return 0
	end
	local u = (t % every) / math.max(1e-3, hopTime)
	if u >= 1 then
		return 0
	end
	return height * math.sin(math.pi * u)
end
DogAnimator.IdleHopY = idleHopY

-- One frame of the Idle pose at time `t`: returns { [Motor6D] = CFrame offset } applied as base C0 * offset.
-- Pure (no services) so tools can sample it.
function DogAnimator.IdlePose(motors: Motors, t: number, scale: number, o: IdleOpts?): { [Motor6D]: CFrame }
	local d = DogAnimator.IdleDefaults
	local opts: IdleOpts = o or {}
	local sad = opts.Mood == "Sad"
	local out: { [Motor6D]: CFrame } = {}
	local wagHz = opts.WagHz or d.WagHz
	local every = if sad then 0 else (opts.HopEvery or d.HopEvery)
	local height = opts.HopHeight or d.HopHeight
	local y = idleHopY(t, every, height, d.HopTime)
	local breathe = math.sin(t * 2) * 0.03
	if motors.Root then
		local air = if height > 0 then y / height else 0
		out[motors.Root] = CFrame.new(0, (y + breathe - (if sad then 0.08 else 0)) * scale, 0)
			* CFrame.Angles(-0.15 * air - (if sad then 0.05 else 0), 0, 0)
	end
	for i, n in motors.Necks do
		if sad then
			local yaw = math.rad(d.SadLookYawDegrees) * (if i == 3 then -1 else 1) -- a third head looks the other way
			out[n] = CFrame.Angles(math.rad(d.SadLookPitchDegrees) + math.sin(t * 0.6 + i) * 0.02, yaw, 0)
		else
			out[n] = CFrame.Angles(math.sin(t * 0.7 + i) * 0.08, math.sin(t * 0.45 + i * 1.7) * 0.2, 0)
		end
	end
	for _, hip in motors.Hips do
		out[hip] = CFrame.new()
	end
	for i, tail in motors.Tails do
		if sad then
			out[tail] = CFrame.Angles(math.rad(d.SadTailDroopDegrees), 0, 0)
		else
			out[tail] = CFrame.Angles(0, 0, math.sin(t * 2 * math.pi * wagHz + i * 0.6) * math.rad(d.WagDegrees))
		end
	end
	local earsOn = opts.Ears ~= false
	for i, ear in motors.Ears do
		if sad then
			out[ear] = CFrame.Angles(math.rad(d.SadEarDegrees), 0, 0)
		elseif earsOn then
			local lt = t - d.EarLag
			local dt = 1 / 60
			local vel = (idleHopY(lt, every, height, d.HopTime) - idleHopY(lt - dt, every, height, d.HopTime)) / dt
			local norm = math.pi * math.max(1e-3, height) / d.HopTime
			local flap = math.clamp(vel / norm, -1, 1) * math.rad(d.EarFlapDegrees)
			out[ear] = CFrame.Angles(flap + math.sin(t * 3 + i) * math.rad(d.EarIdleDegrees), 0, 0)
		else
			out[ear] = CFrame.new()
		end
	end
	for _, wing in motors.Wings do
		local side = if wing.Name == "WingL" then -1 else 1
		out[wing] = CFrame.Angles(0, 0, side * (if sad then -0.15 else math.sin(t * 2) * 0.12))
	end
	if motors.Orbit then
		out[motors.Orbit] = CFrame.Angles(0, t * (if sad then 0.5 else 1.6), 0)
	end
	return out
end

function DogAnimator.Idle(model: Model, opts: IdleOpts?): IdleHandle
	local motors = collect(model)
	local base: { [Motor6D]: CFrame } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			base[d] = d.C0
		end
	end
	local scale = 1
	pcall(function()
		scale = model:GetScale()
	end)
	local t = 0
	local stopped = false
	local conn: RBXScriptConnection? = nil
	local destroying: RBXScriptConnection? = nil
	local function step(dt: number)
		if stopped or model.Parent == nil then
			return
		end
		t += dt
		for motor, off in DogAnimator.IdlePose(motors, t, scale, opts) do
			local c0 = base[motor]
			if c0 and motor.Parent then
				motor.C0 = c0 * off
			end
		end
	end
	local function stop()
		if stopped then
			return
		end
		stopped = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if destroying then
			destroying:Disconnect()
			destroying = nil
		end
		for motor, c0 in base do
			pcall(function()
				motor.C0 = c0
			end)
		end
	end
	local ok, signal = pcall(function()
		return if RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat
	end)
	if ok and signal then
		conn = (signal :: any):Connect(step)
	end
	pcall(function()
		destroying = (model :: any).Destroying:Connect(stop)
	end)
	step(0)
	return { Stop = stop }
end

return DogAnimator
