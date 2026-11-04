--!strict
-- The built-in throw as a KeyframeSequence DESCRIPTION (pure: names, times and CFrames only; Lune-tested by
-- tools/tests/cutscene_path.luau). src/client/Cutscene/Rig.luau turns it into a real KeyframeSequence, registers it
-- with KeyframeSequenceProvider and plays it on the character's Animator at Action4, so it overrides the default
-- idle / walk tracks on every posed joint, whether the rig's joints are Motor6Ds or AnimationConstraints.
--   ThrowAnim.Rigs.R15 / .R6                  joint tree: Part, Parent part, Motor name, where the joint lives,
--                                             which Config/Cutscene.Pose joint drives it
--   ThrowAnim.ToTransform(angles, jointRot)   Config parent-space angles (radians) -> the joint's Transform space
--   ThrowAnim.Build(rigType, rotations?)      -> Spec { RigType, Length, Keyframes = { { Time, Root = PoseNode } } }
--   ThrowAnim.Signature(rigType, rotations?)  cache key (registered ids are cached per rig type + joint rotations)
-- Conversion: the C0 fallback shows C0' = T(p) * A * R (C0 = T(p) * R, A = CFrame.Angles(pose)). The animator
-- shows C0 * Transform = T(p) * R * X. Equal when X = R:Inverse() * A * R, R = the joint's real C0 rotation
-- (Motor6D.C0, or AnimationConstraint.Attachment0.CFrame), so both paths draw the same throw.
local Config = script.Parent.Parent:WaitForChild("Config")
local C = require(Config:WaitForChild("Cutscene"))

local ThrowAnim = {}

export type JointSpec = {
	Part: string, -- the child part (the Pose name)
	Parent: string, -- the parent part (the parent Pose name)
	Motor: string, -- the Motor6D / AnimationConstraint name
	In: "Part" | "Parent", -- which part the joint instance is parented to
	Joint: string?, -- Config/Cutscene.Pose joint that drives it; nil = held at rest (keeps the chain intact)
}
export type PoseNode = { Name: string, CFrame: CFrame, Children: { PoseNode } }
export type Keyframe = { Time: number, Root: PoseNode }
export type Spec = { RigType: string, Length: number, Keyframes: { Keyframe } }

-- Parents always come before their children.
ThrowAnim.Rigs = {
	R15 = {
		{ Part = "LowerTorso", Parent = "HumanoidRootPart", Motor = "Root", In = "Part", Joint = nil },
		{ Part = "UpperTorso", Parent = "LowerTorso", Motor = "Waist", In = "Part", Joint = "Waist" },
		{ Part = "RightUpperArm", Parent = "UpperTorso", Motor = "RightShoulder", In = "Part", Joint = "RightShoulder" },
		{ Part = "RightLowerArm", Parent = "RightUpperArm", Motor = "RightElbow", In = "Part", Joint = "RightElbow" },
		{ Part = "LeftUpperArm", Parent = "UpperTorso", Motor = "LeftShoulder", In = "Part", Joint = "LeftShoulder" },
		{ Part = "LeftUpperLeg", Parent = "LowerTorso", Motor = "LeftHip", In = "Part", Joint = "LeftHip" },
		{ Part = "LeftLowerLeg", Parent = "LeftUpperLeg", Motor = "LeftKnee", In = "Part", Joint = "LeftKnee" },
		{ Part = "RightUpperLeg", Parent = "LowerTorso", Motor = "RightHip", In = "Part", Joint = "RightHip" },
		{ Part = "RightLowerLeg", Parent = "RightUpperLeg", Motor = "RightKnee", In = "Part", Joint = "RightKnee" },
	} :: { JointSpec },
	R6 = {
		{ Part = "Torso", Parent = "HumanoidRootPart", Motor = "RootJoint", In = "Parent", Joint = "Waist" },
		{ Part = "Right Arm", Parent = "Torso", Motor = "Right Shoulder", In = "Parent", Joint = "RightShoulder" },
		{ Part = "Left Arm", Parent = "Torso", Motor = "Left Shoulder", In = "Parent", Joint = "LeftShoulder" },
		{ Part = "Left Leg", Parent = "Torso", Motor = "Left Hip", In = "Parent", Joint = "LeftHip" },
		{ Part = "Right Leg", Parent = "Torso", Motor = "Right Hip", In = "Parent", Joint = "RightHip" },
	} :: { JointSpec },
}
ThrowAnim.RootPart = "HumanoidRootPart"

-- Parent-space angles (radians, as Path.Pose returns them) -> the joint's Transform. jointRot: the rotation part of
-- the joint's C0 (or Attachment0.CFrame); nil = identity.
function ThrowAnim.ToTransform(angles: Vector3, jointRot: CFrame?): CFrame
	local a = CFrame.Angles(angles.X, angles.Y, angles.Z)
	if not jointRot then
		return a
	end
	local r = jointRot - jointRot.Position
	return r:Inverse() * a * r
end

local function keyAngles(key: any, joint: string): Vector3
	local v = key[joint] or { 0, 0, 0 }
	return Vector3.new(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

-- rotations: { [Pose part name] = joint rotation CFrame } from the live rig (missing = identity).
function ThrowAnim.Build(rigType: string, rotations: { [string]: CFrame }?): Spec
	local tree = ThrowAnim.Rigs[rigType] or ThrowAnim.Rigs.R15
	local rots = rotations or {}
	local keyframes: { Keyframe } = {}
	for _, key in C.Pose do
		local nodes: { [string]: PoseNode } = {}
		local root: PoseNode = { Name = ThrowAnim.RootPart, CFrame = CFrame.new(), Children = {} }
		nodes[root.Name] = root
		for _, j in tree do
			local cf = if j.Joint then ThrowAnim.ToTransform(keyAngles(key, j.Joint), rots[j.Part]) else CFrame.new()
			local node: PoseNode = { Name = j.Part, CFrame = cf, Children = {} }
			nodes[j.Part] = node
			local parent = nodes[j.Parent]
			assert(parent, "ThrowAnim: " .. j.Part .. " listed before its parent " .. j.Parent)
			table.insert(parent.Children, node)
		end
		table.insert(keyframes, { Time = key.At * C.WindUp.Duration, Root = root })
	end
	return { RigType = rigType, Length = keyframes[#keyframes].Time, Keyframes = keyframes }
end

-- Registered sequences are cached per rig type + the rig's joint rotations (rounded), so two avatars with the same
-- joint frames share one id and an unusual rig still gets a correct conversion.
function ThrowAnim.Signature(rigType: string, rotations: { [string]: CFrame }?): string
	local parts = { rigType }
	local tree = ThrowAnim.Rigs[rigType] or ThrowAnim.Rigs.R15
	for _, j in tree do
		local r = rotations and rotations[j.Part]
		if r then
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = r:GetComponents()
			local q = {}
			for _, n in { r00, r01, r02, r10, r11, r12, r20, r21, r22 } do
				table.insert(q, string.format("%.3f", n))
			end
			table.insert(parts, j.Part .. "=" .. table.concat(q, ","))
		end
	end
	return table.concat(parts, "|")
end

return ThrowAnim
