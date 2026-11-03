--!nonstrict
-- ThrowPower training on TrainingStation-tagged parts (StationId "PullUpBar"|"ThrowingMachine"|"Sprint").
-- Reps come from a ProximityPrompt on each station or the Train remote (must be in range). Per-station
-- server cooldowns, unlock thresholds, cash-per-rep for the Throwing Machine, a server-sampled lap
-- distance for Sprint, and AFK cut-off (no movement for Game.AfkSeconds -> reps stop crediting).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Training = require(Config:WaitForChild("Training"))
local Game = require(Config:WaitForChild("Game"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local BroadcastService = require(script.Parent:WaitForChild("BroadcastService"))

local TrainingService = {}

type Track = { LastPos: Vector3?, LastMove: number, PathSinceSprint: number, LastSprint: number }
local tracks: { [Player]: Track } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local limiter = RateLimiter.new(Game.RateLimits.Train[1], Game.RateLimits.Train[2])

local function stationPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function nearStation(player: Player, stationId: string): boolean
	local hrp = rootOf(player)
	if not hrp then
		return false
	end
	for _, inst in CollectionService:GetTagged("TrainingStation") do
		if inst:GetAttribute("StationId") == stationId then
			local part = stationPart(inst)
			if part then
				local range = Training.InteractRange + math.max(part.Size.X, part.Size.Z) / 2
				if (part.Position - hrp.Position).Magnitude <= range then
					return true
				end
			end
		end
	end
	return false
end

local function track(player: Player): Track
	local t = tracks[player]
	if not t then
		t = { LastPos = nil, LastMove = os.clock(), PathSinceSprint = 0, LastSprint = os.clock() }
		tracks[player] = t
	end
	return t
end

-- One training rep. Returns ok, message, gain.
function TrainingService.Rep(player: Player, stationId: string): (boolean, string, number)
	local station = (Training.Stations :: any)[stationId]
	local state = DataService.Get(player)
	if not station or not state then
		return false, "Unknown station", 0
	end
	local t = track(player)
	local now = os.clock()
	if now - t.LastMove > Game.AfkSeconds then
		return false, "Move around a bit to keep training!", 0
	end
	cooldowns[player] = cooldowns[player] or {}
	local last = cooldowns[player][stationId] or -math.huge
	if now - last < station.Cooldown then
		return false, "Cooldown", 0
	end
	if state.ThrowPower < station.UnlockPower then
		return false, ("%s unlocks at %d ThrowPower"):format(station.Name, station.UnlockPower), 0
	end
	local cap = Training.PowerCap(state.TrainingLevel or 0)
	if state.ThrowPower >= cap then
		if (state.TrainingLevel or 0) >= Training.Upgrades.MaxLevel or cap >= Training.MaxThrowPower then
			return false, "ThrowPower is maxed!", 0
		end
		return false, ("Power cap %d reached: buy a Training upgrade in the Shop to raise it!"):format(cap), 0
	end
	if stationId == "Sprint" then
		if t.PathSinceSprint < station.MinLapStuds or now - t.LastSprint < station.MinLapSeconds then
			return false, ("Run a lap first (%d/%d studs)"):format(math.floor(t.PathSinceSprint), station.MinLapStuds), 0
		end
	end
	local cost = Training.RepCost(stationId, state.ThrowPower)
	if cost > 0 and not DataService.TrySpendCash(player, cost) then
		return false, "Need " .. FormatNumber.Money(cost) .. " per rep", 0
	end
	cooldowns[player][stationId] = now
	if stationId == "Sprint" then
		t.PathSinceSprint = 0
		t.LastSprint = now
	end
	local gain = station.Gain * Training.Mult(state.TrainingLevel or 0)
	state.ThrowPower = math.min(cap, state.ThrowPower + gain)
	DataService.Push(player)
	return true, "+" .. FormatNumber.Compact(gain) .. " ThrowPower", gain
end

local function tryRep(player: Player, stationId: any, fromPrompt: boolean)
	if type(stationId) ~= "string" or not (Training.Stations :: any)[stationId] then
		return
	end
	if not limiter:Check(player) then
		return
	end
	if not fromPrompt and not nearStation(player, stationId) then
		return
	end
	local ok, msg = TrainingService.Rep(player, stationId)
	if not ok and msg ~= "Cooldown" then
		BroadcastService.Notify(player, msg, "Training")
	elseif ok then
		player:SetAttribute("LastTrainGain", msg)
	end
end

local function setupStation(inst: Instance)
	local id = inst:GetAttribute("StationId")
	local station = (Training.Stations :: any)[id]
	local part = stationPart(inst)
	if not station or not part then
		return
	end
	if part:FindFirstChild("TrainPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TrainPrompt"
	prompt.ActionText = "Train"
	prompt.ObjectText = station.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Training.InteractRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player: Player)
		tryRep(player, id, true)
	end)
end

function TrainingService.Start()
	for _, inst in CollectionService:GetTagged("TrainingStation") do
		setupStation(inst)
	end
	CollectionService:GetInstanceAddedSignal("TrainingStation"):Connect(setupStation)

	local train = Remotes.Get("Train") :: RemoteEvent
	train.OnServerEvent:Connect(function(player: Player, stationId: any)
		tryRep(player, stationId, false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		cooldowns[player] = nil
		limiter:Clear(player)
	end)

	-- movement sampler: AFK detection + Sprint lap distance (capped per sample, so teleports don't count)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local hrp = rootOf(player)
				if hrp then
					local t = track(player)
					local pos = hrp.Position
					if t.LastPos then
						local d = Vector2.new(pos.X - t.LastPos.X, pos.Z - t.LastPos.Z).Magnitude
						if d > 0.5 then
							t.LastMove = now
							t.PathSinceSprint += math.min(d, 15)
						end
					end
					t.LastPos = pos
				end
			end
		end
	end)
end

return TrainingService
