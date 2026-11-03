--!strict
-- Procedural animation for the shared DogFactory rig. One rig, every animation: no AnimationController,
-- no uploaded animations. Poses are written to Motor6D.Transform each frame from a single shared loop,
-- so CLIENT-SIDE use is purely local (Transform never replicates).
--
--   local anim = DogAnimator.new(model, { AlwaysAnimate = true })
--   anim:Play("idle" | "run" | "bolt" | "sit" | "hop")     looping states
--   anim:PlayOnce("leap" | "catch" | "fumble" | "sniff" | "look" | "pickup", seconds?)   one-shot; YIELDS, then
--                                                    returns to the loop state
--   anim:StartOnce(state, seconds?)                  same one-shot without yielding (cutscene timelines)
--   anim.LookYaw / anim.LookPitch (radians)          where the "look" one-shot turns the head (e.g. at the camera)
--   anim.HopRate (hops per second)                   pace of the "hop" loop
--   anim:Destroy()
--
-- Root motion (moving the whole model across the ground) is the caller's job (PivotTo); the animator
-- only moves joints, including the RootJoint bob/leap arc relative to the Root part.
local RunService = game:GetService("RunService")

local DogAnimator = {}
DogAnimator.__index = DogAnimator

export type LoopState = "idle" | "run" | "bolt" | "sit" | "hop"
export type OnceState = "leap" | "catch" | "fumble" | "sniff" | "look" | "pickup"

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
}, DogAnimator))

DogAnimator.CullDistance = 220 -- studs; farther dogs freeze (unless AlwaysAnimate)
DogAnimator.Lengths = { leap = 0.9, catch = 0.8, fumble = 1.1, sniff = 0.6, look = 0.6, pickup = 0.4 }

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

return DogAnimator
