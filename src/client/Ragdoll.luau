-- When the sea catches you, your character goes limp and is hurled up and
-- back onto the beach. This runs on the owning client because the client
-- simulates its own character's physics (everyone else sees the flight
-- through normal replication).

local Players = game:GetService("Players")

local State = require(script.Parent.State)

local Ragdoll = {}

local player = Players.LocalPlayer

-- These joints stay rigid so the character never falls apart (losing the
-- neck or root joint would kill it).
local KEEP = { Root = true, RootJoint = true, Neck = true }

local flying = false

-- Swap the limb motors for ball sockets so arms and legs flop.
local function goLimp(char: Model)
	local undo = {}
	for _, motor in char:GetDescendants() do
		if motor:IsA("Motor6D") and not KEEP[motor.Name] and motor.Part0 and motor.Part1 then
			local name = motor.Name .. "RigAttachment"
			local a0 = motor.Part0:FindFirstChild(name)
			local a1 = motor.Part1:FindFirstChild(name)
			if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment") then
				local socket = Instance.new("BallSocketConstraint")
				socket.Name = "RagdollSocket"
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 70
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -40
				socket.TwistUpperAngle = 40
				socket.Parent = motor.Part0
				motor.Enabled = false
				table.insert(undo, { motor = motor, socket = socket })
			end
		end
	end
	return undo
end

local function recover(undo, humanoid: Humanoid)
	for _, item in undo do
		if item.motor.Parent then
			item.motor.Enabled = true
		end
		item.socket:Destroy()
	end
	if humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- Throw the character on an arc that lands at `landing` after `seconds`.
function Ragdoll.fling(landing: Vector3, seconds: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not humanoid or flying then
		return
	end
	flying = true

	local undo = goLimp(char)
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Start just above the water so the walls and seabed can't snag the arc.
	local start = Vector3.new(root.Position.X, math.max(root.Position.Y, 2), root.Position.Z)
	root.CFrame = CFrame.new(start) * root.CFrame.Rotation
	-- Ballistic launch: velocity that reaches `landing` in `seconds` under gravity.
	local gravity = workspace.Gravity
	local delta = landing - start
	local velocity = Vector3.new(delta.X / seconds, delta.Y / seconds + 0.5 * gravity * seconds, delta.Z / seconds)
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-4, 4), math.random(-6, 6))

	task.delay(seconds + 0.7, function()
		flying = false
		recover(undo, humanoid)
	end)
end

function Ragdoll.init()
	State.effect:Connect(function(kind, payload)
		if kind == "caught" and payload and payload.landing then
			Ragdoll.fling(payload.landing, payload.seconds or 1.5)
		end
	end)
	player.CharacterAdded:Connect(function()
		flying = false
	end)
end

return Ragdoll
