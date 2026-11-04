--!nonstrict
-- ThrowPower training on the ONE TrainingStation-tagged part (StationId "Main"; Config/Training.luau).
-- Reps come from its ProximityPrompt or the Train remote ("Main"; must be in range). Server cooldown,
-- power cap per training level and an AFK cut-off (no movement for Game.AfkSeconds -> reps stop crediting).
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

type Track = { LastPos: Vector3?, LastMove: number }
local tracks: { [Player]: Track } = {}
local lastRep: { [Player]: number } = {}
local limiter = RateLimiter.new(Game.RateLimits.Train[1], Game.RateLimits.Train[2])

local function stationPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

-- A tagged station counts as "Main" when its StationId is "Main" (or missing).
local function stationIdOf(inst: Instance): string?
	local id = inst:GetAttribute("StationId")
	if id == nil then
		return Training.DefaultStation
	end
	return if type(id) == "string" and (Training.Stations :: any)[id] then id else nil
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
		if stationIdOf(inst) == stationId then
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
		t = { LastPos = nil, LastMove = os.clock() }
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
	local now = os.clock()
	if now - track(player).LastMove > Game.AfkSeconds then
		return false, "Move around a bit to keep training!", 0
	end
	if now - (lastRep[player] or -math.huge) < station.Cooldown then
		return false, "Cooldown", 0
	end
	if state.ThrowPower < station.UnlockPower then
		return false, ("%s unlocks at %d ThrowPower"):format(station.Name, station.UnlockPower), 0
	end
	local cap = Training.PowerCap(state.TrainingLevel or 0)
	-- At or above the cap (a dev-tools ThrowPower can be far above it): refuse the rep, never clamp power down.
	if state.ThrowPower >= cap then
		if (state.TrainingLevel or 0) >= Training.Upgrades.MaxLevel or cap >= Training.MaxThrowPower then
			return false, "ThrowPower is maxed!", 0
		end
		return false, ("Power cap %d reached: buy a Training upgrade in the Shop to raise it!"):format(cap), 0
	end
	local cost = Training.RepCost(stationId, state.ThrowPower)
	if cost > 0 and not DataService.TrySpendCash(player, cost) then
		return false, "Need " .. FormatNumber.Money(cost) .. " per rep", 0
	end
	lastRep[player] = now
	local gain = station.Gain * Training.Mult(state.TrainingLevel or 0)
	state.ThrowPower = Training.ApplyRep(state.ThrowPower, gain, cap)
	DataService.Push(player)
	return true, "+" .. FormatNumber.Compact(gain) .. " ThrowPower", gain
end

local function tryRep(player: Player, stationId: any, fromPrompt: boolean)
	if type(stationId) ~= "string" or #stationId > 32 or not (Training.Stations :: any)[stationId] then
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
	local id = stationIdOf(inst)
	local station = id and (Training.Stations :: any)[id]
	local part = stationPart(inst)
	if not station or not part then
		if inst:GetAttribute("StationId") ~= nil then
			warn(("[TrainingService] TrainingStation %s has unknown StationId %s"):format(inst:GetFullName(),
				tostring(inst:GetAttribute("StationId"))))
		end
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
	local tagged = CollectionService:GetTagged("TrainingStation")
	if #tagged > 1 then
		warn(("[TrainingService] expected one TrainingStation, found %d"):format(#tagged))
	end
	for _, inst in tagged do
		setupStation(inst)
	end
	CollectionService:GetInstanceAddedSignal("TrainingStation"):Connect(setupStation)

	local train = Remotes.Get("Train") :: RemoteEvent
	train.OnServerEvent:Connect(function(player: Player, stationId: any)
		tryRep(player, stationId, false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		lastRep[player] = nil
		limiter:Clear(player)
	end)

	-- movement sampler: AFK detection
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
						end
					end
					t.LastPos = pos
				end
			end
		end
	end)
end

return TrainingService
