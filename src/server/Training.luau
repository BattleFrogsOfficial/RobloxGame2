-- Strength training on the pink pad in your pen, plus buying heavier weights.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Voxel = require(Shared.Voxel)

local Data = require(script.Parent.Data)
local Pens = require(script.Parent.Pens)

local Training = {}

local T = Config.Training

local training: { [Player]: any } = {}

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function onPad(player: Player): boolean
	local pen = Pens.get(player)
	local root = rootOf(player)
	if not pen or not root then
		return false
	end
	local padPos = (pen.cf * CFrame.new(Pens.PadLocal)).Position
	local flat = Vector3.new(root.Position.X - padPos.X, 0, root.Position.Z - padPos.Z)
	return flat.Magnitude <= T.PadRadius and math.abs(root.Position.Y - padPos.Y) < 8
end

-- Arms up holding a barbell overhead (R15 rigs; R6 just shows the barbell).
local function setPose(player: Player, state)
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if state.on then
		if humanoid then
			state.walkSpeed = humanoid.WalkSpeed
			state.jumpPower = humanoid.JumpPower
			state.jumpHeight = humanoid.JumpHeight
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
		state.shoulders = {}
		for _, name in { "RightUpperArm", "LeftUpperArm" } do
			local arm = char:FindFirstChild(name)
			local joint = arm and arm:FindFirstChild(name == "RightUpperArm" and "RightShoulder" or "LeftShoulder")
			if joint and joint:IsA("Motor6D") then
				state.shoulders[joint] = joint.C0
				joint.C0 = joint.C0 * CFrame.Angles(math.rad(170), 0, 0)
			end
		end
		local head = char:FindFirstChild("Head") :: BasePart?
		if head then
			local d = Data.get(player)
			local bar = Voxel.barbell(d and d.weightTier or 1)
			Voxel.weld(bar, false)
			bar:PivotTo(head.CFrame * CFrame.new(0, 2.2, 0))
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = bar.PrimaryPart
			w.Parent = bar.PrimaryPart
			bar.Name = "TrainingBarbell"
			bar.Parent = char
			state.barbell = bar
		end
	else
		if humanoid then
			humanoid.WalkSpeed = state.walkSpeed or 16
			humanoid.JumpPower = state.jumpPower or 50
			humanoid.JumpHeight = state.jumpHeight or 7.2
		end
		for joint, c0 in state.shoulders or {} do
			if joint.Parent then
				joint.C0 = c0
			end
		end
		if state.barbell then
			state.barbell:Destroy()
		end
	end
end

local function lift(player: Player)
	local d = Data.get(player)
	if not d then
		return
	end
	local gain = Config.Weights[d.weightTier].gain
	if Data.hasPass(player, "DoubleStrength") then
		gain *= 2
	end
	d.strength += gain
	Data.markDirty(player)
	Data.effect(player, "lift", { gain = gain })
end

function Training.stop(player: Player)
	local state = training[player]
	if not state then
		return
	end
	training[player] = nil
	state.on = false
	setPose(player, state)
	player:SetAttribute("Training", false)
end

function Training.start(player: Player)
	if training[player] or not onPad(player) then
		return
	end
	local state = { on = true, lastLift = 0, nextAuto = os.clock() + T.AutoLiftInterval }
	training[player] = state
	setPose(player, state)
	player:SetAttribute("Training", true)
end

function Training.buyWeight(player: Player): (boolean, string?)
	local d = Data.get(player)
	if not d then
		return false
	end
	local nextW = Config.Weights[d.weightTier + 1]
	if not nextW then
		return false, "You have the heaviest weight!"
	end
	if not Data.trySpend(player, nextW.cost) then
		Data.notify(player, "You need " .. Format.cash(nextW.cost) .. " for the " .. nextW.name .. ".", Color3.fromRGB(255, 100, 100))
		return false
	end
	d.weightTier += 1
	Data.notify(player, "New weight: " .. nextW.name .. "! +" .. nextW.gain .. " per lift.", Color3.fromRGB(120, 255, 120))
	Pens.refreshSigns(player)
	return true
end

function Training.init()
	Pens.callbacks.buyWeight = Training.buyWeight

	Remotes.get("Train").OnServerEvent:Connect(function(player: Player, action: any)
		if action == "start" then
			Training.start(player)
		elseif action == "stop" then
			Training.stop(player)
		elseif action == "lift" then
			local state = training[player]
			local t = os.clock()
			if state and t - state.lastLift >= T.MinClickInterval then
				state.lastLift = t
				lift(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local t = os.clock()
			for _, player in Players:GetPlayers() do
				local isOn = onPad(player)
				if player:GetAttribute("OnTrainPad") ~= isOn then
					player:SetAttribute("OnTrainPad", isOn)
				end
				local state = training[player]
				if state then
					if not isOn or not player.Character then
						Training.stop(player)
					elseif t >= state.nextAuto then
						state.nextAuto = t + T.AutoLiftInterval
						lift(player)
					end
				end
			end
		end
	end)
end

return Training
