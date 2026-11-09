-- Strength training on the pink pad in your base, plus buying heavier weights.
--
-- Training starts as soon as you step onto your pad and stops when you step
-- off. Each rep pushes the barbell from the chest to overhead and back down;
-- Strength is awarded when the rep completes. The staff is put away while
-- you train.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Voxel = require(Shared.Voxel)

local Data = require(script.Parent.Data)
local Pens = require(script.Parent.Pens)

local Training = {}

local T = Config.Training

-- Barbell position relative to the torso, and arm joint angles (degrees),
-- at the bottom and top of a rep.
local BAR_DOWN = CFrame.new(0, 1.1, -1.1)
local BAR_UP = CFrame.new(0, 3.4, -0.3)
local SHOULDER_DOWN, SHOULDER_UP = 75, 172
local ELBOW_DOWN, ELBOW_UP = 95, 0

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

local function joint(char: Model, partName: string, jointName: string): Motor6D?
	local part = char:FindFirstChild(partName)
	local j = part and part:FindFirstChild(jointName)
	if j and j:IsA("Motor6D") then
		return j
	end
	return nil
end

-- Attach the barbell and remember the arm joints (R15; other rigs just get
-- the moving barbell).
local function setUp(player: Player, state)
	local char = player.Character
	if not char then
		return
	end
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not torso then
		return
	end
	local d = Data.get(player)
	local bar = Voxel.barbell(d and d.weightTier or 1)
	Voxel.weld(bar, false)
	bar.Name = "TrainingBarbell"
	bar:PivotTo(torso.CFrame * BAR_DOWN)
	local weld = Instance.new("Weld")
	weld.Name = "BarbellWeld"
	weld.Part0 = torso
	weld.Part1 = bar.PrimaryPart
	weld.C0 = BAR_DOWN
	weld.Parent = bar.PrimaryPart
	bar.Parent = char
	state.barbell = bar
	state.weld = weld

	state.joints = {}
	for _, side in { "Right", "Left" } do
		local shoulder = joint(char, side .. "UpperArm", side .. "Shoulder")
		local elbow = joint(char, side .. "LowerArm", side .. "Elbow")
		if shoulder then
			table.insert(state.joints, { motor = shoulder, base = shoulder.C0, down = SHOULDER_DOWN, up = SHOULDER_UP })
		end
		if elbow then
			table.insert(state.joints, { motor = elbow, base = elbow.C0, down = ELBOW_DOWN, up = ELBOW_UP })
		end
	end
	for _, j in state.joints do
		j.motor.C0 = j.base * CFrame.Angles(math.rad(j.down), 0, 0)
	end
end

local function tearDown(state)
	for _, j in state.joints or {} do
		if j.motor.Parent then
			j.motor.C0 = j.base
		end
	end
	if state.barbell then
		state.barbell:Destroy()
	end
end

-- Move the bar and arms to the top or bottom of the rep.
local function pose(state, up: boolean, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	if state.weld and state.weld.Parent then
		TweenService:Create(state.weld, info, { C0 = up and BAR_UP or BAR_DOWN }):Play()
	end
	for _, j in state.joints or {} do
		if j.motor.Parent then
			local angle = up and j.up or j.down
			TweenService:Create(j.motor, info, { C0 = j.base * CFrame.Angles(math.rad(angle), 0, 0) }):Play()
		end
	end
end

local function putStaffAway(player: Player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if char and humanoid and char:FindFirstChildOfClass("Tool") then
		humanoid:UnequipTools()
	end
end

local function awardRep(player: Player)
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
	tearDown(state)
	player:SetAttribute("Training", false)
end

function Training.start(player: Player)
	if training[player] or not Data.get(player) then
		return
	end
	local state = {}
	training[player] = state
	putStaffAway(player)
	setUp(player, state)
	player:SetAttribute("Training", true)

	-- Rep loop: up, down, then the Strength for that rep.
	task.spawn(function()
		local half = T.RepTime / 2
		while training[player] == state do
			putStaffAway(player)
			pose(state, true, half)
			task.wait(half)
			if training[player] ~= state then
				break
			end
			pose(state, false, half)
			task.wait(half)
			if training[player] ~= state then
				break
			end
			awardRep(player)
		end
	end)
end

function Training.isTraining(player: Player): boolean
	return training[player] ~= nil
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
	Data.notify(player, "New weight: " .. nextW.name .. "! +" .. nextW.gain .. " Strength per rep.", Color3.fromRGB(120, 255, 120))
	Pens.refreshSigns(player)
	-- Swap the barbell if they're mid-workout.
	if training[player] then
		Training.stop(player)
		Training.start(player)
	end
	return true
end

function Training.init()
	Pens.callbacks.buyWeight = Training.buyWeight

	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
	end)

	-- Start when the owner steps onto their pad, stop when they step off.
	task.spawn(function()
		while true do
			task.wait(0.15)
			for _, player in Players:GetPlayers() do
				local isOn = onPad(player)
				if player:GetAttribute("OnTrainPad") ~= isOn then
					player:SetAttribute("OnTrainPad", isOn)
				end
				if isOn and not training[player] then
					Training.start(player)
				elseif not isOn and training[player] then
					Training.stop(player)
				end
			end
		end
	end)
end

return Training
