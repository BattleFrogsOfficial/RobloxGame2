--!strict
-- The thrower's avatar: wind-up + overhand throw, with the ball in the right hand until the release frame.
-- Runs on EVERY client for every throw (each client animates the thrower's character locally from the
-- ThrowResult; Spectator.luau calls it for other players' characters). R15 and R6, Motor6D or AnimationConstraint
-- joints (Roblox's Avatar Joint Upgrade).
--   local rig = Rig.Play(character, ballPart?, fallbackHand, { Assets = boolean })   -- t = 0 is the meter release
--   rig:HandPosition() -> Vector3           where the ball is right now (the hand part's world CFrame, every path)
--   rig:Release()                           the ball leaves the hand (caller flies it from here on)
--   rig:Stop()                              restore every joint, stop / restore tracks, disconnect (idempotent)
--   rig.Path                                which path animates this throw (see below)
-- Paths, first that works wins:
--   1. "uploaded ids": AnimationIds.WindUp and .Throw both non-zero -> the uploaded animations (local player's own
--      Animator only: those replicate by themselves, so spectators do not play them again).
--   2. "KeyframeSequence (R15|R6)": Config/Cutscene.Pose built into a KeyframeSequence at runtime
--      (Shared/Cutscene/ThrowAnim), registered with KeyframeSequenceProvider (id cached per rig type), loaded on
--      Humanoid.Animator and played at Action4 / weight 1 / not looped, so it beats the default Animate script's
--      idle / walk (Core / Idle / Movement) on every posed joint. Those lower tracks are also faded to weight 0
--      while it plays and faded back after. Runtime-registered ids play locally on each client, which is what we
--      want (every client plays its own copy). If the track never loads (Length stays 0) -> path 3.
--   3. Procedural fallback, per joint, from Path.Pose: "Motor6D C0" (C0 rewritten each RenderStepped and restored
--      after) and / or "AnimationConstraint" (constraint.Transform rewritten each frame, after the Animator).
-- In Studio the path used is printed once per session ("[Cutscene] throw animation: ...").
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Cutscene"))
local CutsceneShared = Shared:WaitForChild("Cutscene")
local Path = require(CutsceneShared:WaitForChild("Path"))
local ThrowAnim = require(CutsceneShared:WaitForChild("ThrowAnim"))

local Rig = {}
Rig.__index = Rig

local LOAD_CHECK = 0.3 -- s: a KeyframeSequence track still at Length 0 after this never loaded -> fall back
local REWEIGHT_EVERY = 0.1 -- s: re-check for new lower-priority tracks (Animate restarts idles) while ours plays

function Rig.UsesAssets(): boolean
	return (C.AnimationIds.WindUp or 0) ~= 0 and (C.AnimationIds.Throw or 0) ~= 0
end

-- One diagnostic line per distinct path per session, Studio only.
local printed: { [string]: boolean } = {}
local function diagnose(msg: string)
	if printed[msg] then
		return
	end
	printed[msg] = true
	local studio = false
	pcall(function()
		studio = RunService:IsStudio()
	end)
	if studio then
		print("[Cutscene] throw animation: " .. msg)
	end
end
Rig._printed = printed -- tests

local function hand(character: Model): (BasePart?, CFrame)
	local r15 = character:FindFirstChild("RightHand")
	if r15 and r15:IsA("BasePart") then
		return r15, CFrame.new(0, -0.15, -0.1)
	end
	local r6 = character:FindFirstChild("Right Arm")
	if r6 and r6:IsA("BasePart") then
		return r6, CFrame.new(0, -C.WindUp.BallGrip, 0)
	end
	return nil, CFrame.new()
end

type Joint = {
	Inst: Instance,
	Kind: "Motor6D" | "AnimationConstraint",
	Pose: string?, -- Config/Cutscene.Pose joint name (nil = not driven by the fallback)
	Part: string, -- ThrowAnim pose / part name
	Base: CFrame, -- Motor6D: original C0; AnimationConstraint: original Transform
	Rot: CFrame, -- joint frame rotation (C0 / Attachment0.CFrame) for the Transform conversion
}

local function linkNames(j: Instance): (string?, string?)
	local ok, p0, p1 = pcall(function(): (string?, string?)
		if j:IsA("Motor6D") then
			local m = j :: Motor6D
			return m.Part0 and m.Part0.Name, m.Part1 and m.Part1.Name
		end
		local a = j :: any
		local a0, a1 = a.Attachment0, a.Attachment1
		return a0 and a0.Parent and a0.Parent.Name, a1 and a1.Parent and a1.Parent.Name
	end)
	if ok then
		return p0, p1
	end
	return nil, nil
end

local function isJoint(i: Instance?): boolean
	return i ~= nil and (i:IsA("Motor6D") or i:IsA("AnimationConstraint"))
end

-- Find the joint driving spec.Part: by its usual name and place first, else any Motor6D / AnimationConstraint
-- linking spec.Parent -> spec.Part (rigs that renamed or moved their joints).
local function findJoint(character: Model, spec: ThrowAnim.JointSpec, scan: { Instance }?): Instance?
	local holder = character:FindFirstChild(if spec.In == "Part" then spec.Part else spec.Parent)
	local j = holder and holder:FindFirstChild(spec.Motor)
	if isJoint(j) then
		return j
	end
	for _, d in scan or {} do
		local p0, p1 = linkNames(d)
		if p0 == spec.Parent and p1 == spec.Part then
			return d
		end
	end
	return nil
end

local function jointRotation(j: Instance): CFrame
	local ok, cf = pcall(function(): CFrame
		if j:IsA("Motor6D") then
			return (j :: Motor6D).C0
		end
		return (j :: any).Attachment0.CFrame
	end)
	if ok and typeof(cf) == "CFrame" then
		return cf - cf.Position
	end
	return CFrame.new()
end

export type RigHandle = typeof(setmetatable({} :: {
	Character: Model?,
	Ball: BasePart?,
	Path: string,
	RigType: string,
	_joints: { Joint },
	_driven: boolean, -- the procedural fallback is writing joints
	_tracks: { AnimationTrack },
	_seq: AnimationTrack?,
	_animator: Animator?,
	_muted: { [AnimationTrack]: number },
	_lastMute: number,
	_conns: { RBXScriptConnection },
	_start: number,
	_released: boolean,
	_stopped: boolean,
	_restored: boolean,
	_hand: BasePart?,
	_grip: CFrame,
	_fallback: Vector3,
}, Rig))

-- KeyframeSequenceProvider ids, cached per ThrowAnim.Signature (rig type + joint rotations).
local registered: { [string]: string } = {}
local registeredCount = 0
local MAX_CACHED = 16

local function buildSequence(spec: ThrowAnim.Spec): KeyframeSequence
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = "ThrowCutscene_" .. spec.RigType
	kfs.Loop = false
	kfs.Priority = Enum.AnimationPriority.Action4
	for i, k in spec.Keyframes do
		local kf = Instance.new("Keyframe")
		kf.Name = "Key" .. i
		kf.Time = k.Time
		local function add(node: ThrowAnim.PoseNode, parent: Instance)
			local p = Instance.new("Pose")
			p.Name = node.Name
			p.CFrame = node.CFrame
			p.Weight = 1
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.InOut
			for _, child in node.Children do
				add(child, p)
			end
			p.Parent = parent
		end
		add(k.Root, kf)
		kf.Parent = kfs
	end
	return kfs
end

local function sequenceId(rigType: string, rotations: { [string]: CFrame }): string
	local key = ThrowAnim.Signature(rigType, rotations)
	local id = registered[key]
	if id then
		return id
	end
	local provider = game:GetService("KeyframeSequenceProvider") :: any
	local kfs = buildSequence(ThrowAnim.Build(rigType, rotations))
	local result = provider:RegisterKeyframeSequence(kfs)
	assert(type(result) == "string" and result ~= "", "RegisterKeyframeSequence returned no id")
	if registeredCount >= MAX_CACHED then
		table.clear(registered)
		registeredCount = 0
	end
	registered[key] = result
	registeredCount += 1
	return result
end
Rig._registered = registered -- tests

-- fallback: hand position to use when there is no character (fakes without an avatar, streamed-out thrower)
function Rig.Play(character: Model?, ball: BasePart?, fallback: Vector3, opts: { Assets: boolean? }?): RigHandle
	local self = setmetatable({
		Character = character,
		Ball = ball,
		Path = "NONE: no character",
		RigType = "R15",
		_joints = {},
		_driven = false,
		_tracks = {},
		_seq = nil,
		_animator = nil,
		_muted = {},
		_lastMute = -math.huge,
		_conns = {},
		_start = os.clock(),
		_released = false,
		_stopped = false,
		_restored = false,
		_hand = nil,
		_grip = CFrame.new(),
		_fallback = fallback,
	}, Rig)
	if character then
		self:_setup(character, opts)
		diagnose(self.Path)
	end
	local length = Path.PoseLength()
	local function step()
		local ok, err = pcall(function()
			local t = os.clock() - self._start
			local seq = self._seq
			if seq then
				if t >= LOAD_CHECK and seq.Length <= 0 then
					-- registered but never loaded (e.g. temp ids refused here): switch to the per-joint fallback
					self:_dropSequence()
					self._driven = #self._joints > 0
					self.Path = "KeyframeSequence did not load; fell back to " .. self:_fallbackName()
					diagnose(self.Path)
				elseif t - self._lastMute >= REWEIGHT_EVERY then
					self._lastMute = t
					self:_muteOthers()
				end
			end
			if self._driven then
				self:_drive(t)
			end
			if not self._released and self.Ball then
				self.Ball.CFrame = CFrame.new(self:HandPosition())
			end
			if t >= length and self._released then
				self:_restore()
				self:_disconnect()
			end
		end)
		if not ok then
			warn("[Cutscene.Rig] " .. tostring(err))
			self:Stop()
		end
	end
	table.insert(self._conns, RunService.RenderStepped:Connect(step))
	-- AnimationConstraint fallback: the Animator rewrites Transform every frame, so write it again after the
	-- Animator's step too (Stepped runs after animations, before physics).
	pcall(function()
		table.insert(self._conns, RunService.Stepped:Connect(function()
			if self._driven and not self._stopped then
				pcall(self._drive, self, os.clock() - self._start, "AnimationConstraint")
			end
		end))
	end)
	return self
end

function Rig._fallbackName(self: RigHandle): string
	local motors, constraints = 0, 0
	for _, j in self._joints do
		if j.Kind == "Motor6D" then
			motors += 1
		else
			constraints += 1
		end
	end
	if motors > 0 and constraints > 0 then
		return "Motor6D C0 + AnimationConstraint"
	elseif motors > 0 then
		return "Motor6D C0"
	elseif constraints > 0 then
		return "AnimationConstraint"
	end
	return "NONE: no joints found on " .. (if self.Character then self.Character.Name else "?") .. " (" .. self.RigType .. ")"
end

function Rig._setup(self: RigHandle, character: Model, opts: { Assets: boolean? }?)
	local h, grip = hand(character)
	self._hand, self._grip = h, grip
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR15 = if humanoid then humanoid.RigType == Enum.HumanoidRigType.R15 else character:FindFirstChild("UpperTorso") ~= nil
	self.RigType = if isR15 then "R15" else "R6"
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	self._animator = animator

	-- 1. uploaded animations
	if Rig.UsesAssets() then
		self.Path = "uploaded ids"
		if opts ~= nil and opts.Assets == true and animator then
			pcall(function()
				local a1 = Instance.new("Animation")
				a1.AnimationId = "rbxassetid://" .. tostring(C.AnimationIds.WindUp)
				local a2 = Instance.new("Animation")
				a2.AnimationId = "rbxassetid://" .. tostring(C.AnimationIds.Throw)
				local t1 = animator:LoadAnimation(a1)
				local t2 = animator:LoadAnimation(a2)
				table.insert(self._tracks, t1)
				table.insert(self._tracks, t2)
				t1.Priority = Enum.AnimationPriority.Action4
				t2.Priority = Enum.AnimationPriority.Action4
				t1:Play(0.1)
				task.delay(math.max(0, C.WindUp.ReleaseAt - C.WindUp.ThrowLead), function()
					if not self._stopped then
						t1:Stop(0.1)
						t2:Play(0.05)
					end
				end)
			end)
		end
		-- the uploaded animation drives the joints (played above for the thrower; replicated to spectators)
		return
	end

	-- the rig's joints (needed by both the conversion and the fallback)
	local tree = ThrowAnim.Rigs[self.RigType]
	local scan: { Instance }? = nil
	local rotations: { [string]: CFrame } = {}
	for _, spec in tree do
		local j = findJoint(character, spec, scan)
		if not j and not scan then
			scan = {}
			for _, d in character:GetDescendants() do
				if isJoint(d) then
					table.insert(scan :: { Instance }, d)
				end
			end
			j = findJoint(character, spec, scan)
		end
		if j then
			local kind: "Motor6D" | "AnimationConstraint" = if j:IsA("Motor6D") then "Motor6D" else "AnimationConstraint"
			local base: CFrame
			if kind == "Motor6D" then
				base = (j :: Motor6D).C0
			else
				local okT, tr = pcall(function()
					return (j :: any).Transform
				end)
				base = if okT and typeof(tr) == "CFrame" then tr else CFrame.new()
			end
			local rot = jointRotation(j)
			rotations[spec.Part] = rot
			table.insert(self._joints, { Inst = j, Kind = kind, Pose = spec.Joint, Part = spec.Part, Base = base, Rot = rot })
		end
	end

	-- 2. KeyframeSequence on the Animator
	if animator and #self._joints > 0 then
		local ok, err = pcall(function()
			local id = sequenceId(self.RigType, rotations)
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			self:_muteOthers(track)
			track:Play(0.05, 1, 1)
			self._seq = track
			table.insert(self._tracks, track)
		end)
		if ok then
			self.Path = "KeyframeSequence (" .. self.RigType .. ")"
			return
		end
		self:_dropSequence()
		self.Path = self:_fallbackName() .. " (KeyframeSequence failed: " .. tostring(err) .. ")"
	elseif #self._joints > 0 then
		self.Path = self:_fallbackName() .. " (no Animator)"
	else
		self.Path = self:_fallbackName()
	end
	-- 3. per-joint fallback
	self._driven = #self._joints > 0
end

local function lowPriority(p: Enum.AnimationPriority): boolean
	return p == Enum.AnimationPriority.Core or p == Enum.AnimationPriority.Idle or p == Enum.AnimationPriority.Movement
end

-- Fade every other playing track below Action priority to weight 0 (remembering its weight for _unmute).
function Rig._muteOthers(self: RigHandle, own: AnimationTrack?)
	local animator = self._animator
	if not animator then
		return
	end
	pcall(function()
		for _, tr in animator:GetPlayingAnimationTracks() do
			if tr ~= own and tr ~= self._seq and self._muted[tr] == nil and lowPriority(tr.Priority) then
				local w = 1
				pcall(function()
					w = tr.WeightTarget
				end)
				self._muted[tr] = if w > 0 then w else 1
				tr:AdjustWeight(0, 0.1)
			end
		end
	end)
end

function Rig._unmute(self: RigHandle)
	for tr, w in self._muted do
		pcall(function()
			if tr.IsPlaying then
				tr:AdjustWeight(w, 0.2)
			end
		end)
	end
	table.clear(self._muted)
end

function Rig._dropSequence(self: RigHandle)
	local seq = self._seq
	self._seq = nil
	if seq then
		pcall(function()
			seq:Stop(0)
		end)
		local i = table.find(self._tracks, seq)
		if i then
			table.remove(self._tracks, i)
		end
	end
	self:_unmute()
end

-- Procedural fallback: write the pose at t into every joint (only = one joint kind).
function Rig._drive(self: RigHandle, t: number, only: string?)
	local pose = Path.Pose(t)
	for _, j in self._joints do
		local a = j.Pose and pose[j.Pose]
		if a and j.Inst.Parent and (only == nil or j.Kind == only) then
			if j.Kind == "Motor6D" then
				local base = j.Base
				;(j.Inst :: Motor6D).C0 = CFrame.new(base.Position) * CFrame.Angles(a.X, a.Y, a.Z) * j.Rot
			else
				(j.Inst :: any).Transform = ThrowAnim.ToTransform(a, j.Rot)
			end
		end
	end
end

function Rig.HandPosition(self: RigHandle): Vector3
	local h = self._hand
	if h and h.Parent then
		return (h.CFrame * self._grip).Position
	end
	return self._fallback
end

function Rig.Release(self: RigHandle)
	self._released = true
end

function Rig._restore(self: RigHandle)
	if self._restored then
		return
	end
	self._restored = true
	self._driven = false
	for _, j in self._joints do
		if j.Inst.Parent then
			pcall(function()
				if j.Kind == "Motor6D" then
					(j.Inst :: Motor6D).C0 = j.Base
				else
					(j.Inst :: any).Transform = j.Base
				end
			end)
		end
	end
	table.clear(self._joints)
	if self._seq then
		local seq = self._seq
		self._seq = nil
		pcall(function()
			seq:Stop(0.15)
		end)
	end
	self:_unmute()
end

function Rig._disconnect(self: RigHandle)
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
end

function Rig.Stop(self: RigHandle)
	if self._stopped then
		return
	end
	self._stopped = true
	self._released = true
	self:_disconnect()
	self:_restore()
	for _, tr in self._tracks do
		pcall(function()
			tr:Stop(0.1)
		end)
	end
	table.clear(self._tracks)
end

return Rig
