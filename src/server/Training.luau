-- Strength training on the pink pad in your base, plus buying heavier weights.
--
-- Training starts as soon as you step onto your pad and stops when you step
-- off. The server only keeps time: it marks the player as training, says
-- when the current run of reps began and awards Strength as each rep ends.
-- Every client plays the lifting animation from those attributes (see
-- client/Poses.luau), so it works on any avatar and everyone can see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

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
	if not training[player] then
		return
	end
	training[player] = nil
	player:SetAttribute("Training", false)
end

function Training.start(player: Player)
	local d = Data.get(player)
	if training[player] or not d then
		return
	end
	local state = {}
	training[player] = state
	putStaffAway(player)
	-- Clients animate the reps from these: which barbell, and when rep 1 began.
	player:SetAttribute("WeightTier", d.weightTier)
	player:SetAttribute("RepStart", workspace:GetServerTimeNow())
	player:SetAttribute("Training", true)

	-- One rep = up and back down; the Strength lands as the bar comes down.
	task.spawn(function()
		while training[player] == state do
			task.wait(T.RepTime)
			if training[player] ~= state then
				break
			end
			putStaffAway(player)
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
