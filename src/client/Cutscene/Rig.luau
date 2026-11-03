--!strict
-- The thrower's avatar: wind-up + overhand throw, with the ball in the right hand until the release frame.
-- Runs on EVERY client for every throw (procedural Motor6D C0 changes never replicate, so each client animates
-- the thrower's character locally from the ThrowResult). R15 and R6.
--   local rig = Rig.Play(character, ballPart?, { Assets = boolean })   -- starts at t = 0 (the meter release)
--   rig:HandPosition() -> Vector3           where the ball is right now
--   rig:Release()                           the ball leaves the hand (caller flies it from here on)
--   rig:Stop()                              restore every C0, stop tracks, disconnect (idempotent)
-- Procedural poses come from Config/Cutscene.Pose via Shared/Cutscene/Path.Pose. When AnimationIds.WindUp and
-- .Throw are both non-zero the uploaded animations play instead (on the local player's own Animator only: those
-- replicate by themselves, so spectators do not play them again).
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Cutscene"))
local Path = require(Shared:WaitForChild("Cutscene"):WaitForChild("Path"))

local Rig = {}
Rig.__index = Rig

-- joint -> { R15 part, R15 motor } / { R6 part, R6 motor }
local R15 = {
	Waist = { "UpperTorso", "Waist" },
	RightShoulder = { "RightUpperArm", "RightShoulder" },
	RightElbow = { "RightLowerArm", "RightElbow" },
	LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
	LeftHip = { "LeftUpperLeg", "LeftHip" },
	LeftKnee = { "LeftLowerLeg", "LeftKnee" },
	RightHip = { "RightUpperLeg", "RightHip" },
	RightKnee = { "RightLowerLeg", "RightKnee" },
}
local R6 = {
	Waist = { "HumanoidRootPart", "RootJoint" },
	RightShoulder = { "Torso", "Right Shoulder" },
	LeftShoulder = { "Torso", "Left Shoulder" },
	LeftHip = { "Torso", "Left Hip" },
	RightHip = { "Torso", "Right Hip" },
}

function Rig.UsesAssets(): boolean
	return (C.AnimationIds.WindUp or 0) ~= 0 and (C.AnimationIds.Throw or 0) ~= 0
end

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

export type RigHandle = typeof(setmetatable({} :: {
	Character: Model?,
	Ball: BasePart?,
	_motors: { [string]: Motor6D },
	_base: { [Motor6D]: CFrame },
	_tracks: { AnimationTrack },
	_conn: RBXScriptConnection?,
	_start: number,
	_released: boolean,
	_stopped: boolean,
	_hand: BasePart?,
	_grip: CFrame,
	_fallback: Vector3,
}, Rig))

-- fallback: hand position to use when there is no character (fakes without an avatar, streamed-out thrower)
function Rig.Play(character: Model?, ball: BasePart?, fallback: Vector3, opts: { Assets: boolean? }?): RigHandle
	local self = setmetatable({
		Character = character,
		Ball = ball,
		_motors = {},
		_base = {},
		_tracks = {},
		_conn = nil,
		_start = os.clock(),
		_released = false,
		_stopped = false,
		_hand = nil,
		_grip = CFrame.new(),
		_fallback = fallback,
	}, Rig)
	if character then
		local h, grip = hand(character)
		self._hand, self._grip = h, grip
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local isR15 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
		local map = if isR15 then R15 else R6
		for joint, spec in map do
			local part = character:FindFirstChild(spec[1])
			local m = part and part:FindFirstChild(spec[2])
			if m and m:IsA("Motor6D") then
				self._motors[joint] = m
				self._base[m] = m.C0
			end
		end
		local useAssets = opts ~= nil and opts.Assets == true and Rig.UsesAssets()
		if useAssets and humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
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
		end
		if Rig.UsesAssets() then
			-- the uploaded animation drives the joints (played above for the thrower; replicated to spectators)
			table.clear(self._motors)
			table.clear(self._base)
		end
	end
	local length = Path.PoseLength()
	self._conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			local t = os.clock() - self._start
			if next(self._motors) then
				local pose = Path.Pose(t)
				for joint, m in self._motors do
					local a = pose[joint]
					local base = self._base[m]
					if a and base and m.Parent then
						m.C0 = CFrame.new(base.Position) * CFrame.Angles(a.X, a.Y, a.Z) * base.Rotation
					end
				end
			end
			if not self._released and self.Ball then
				self.Ball.CFrame = CFrame.new(self:HandPosition())
			end
			if t >= length and self._released then
				self:_restore()
				if self._conn then
					self._conn:Disconnect()
					self._conn = nil
				end
			end
		end)
		if not ok then
			warn("[Cutscene.Rig] " .. tostring(err))
			self:Stop()
		end
	end)
	return self
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
	for m, base in self._base do
		if m.Parent then
			m.C0 = base
		end
	end
	table.clear(self._base)
	table.clear(self._motors)
end

function Rig.Stop(self: RigHandle)
	if self._stopped then
		return
	end
	self._stopped = true
	self._released = true
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:_restore()
	for _, tr in self._tracks do
		pcall(function()
			tr:Stop(0.1)
		end)
	end
	table.clear(self._tracks)
end

return Rig
