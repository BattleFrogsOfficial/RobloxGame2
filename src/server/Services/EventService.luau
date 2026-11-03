--!nonstrict
-- World events: the squirrel chase every 15 min along SquirrelPath (winner's dog drops Bones), runaway
-- dogs that roam RunawayArea for 60 s after a missed catch, and the once-per-UTC-day walk claim.
-- EventState payload: { Kind = "Squirrel"|"RunawayDog"|"DailyWalk", Active, EndsAt, Data }
-- EndsAt is epoch seconds (workspace:GetServerTimeNow() on the server; compare with the same on the client).
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Layout = require(Config:WaitForChild("Layout"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Timers = require(Config:WaitForChild("Timers"))
local Shop = require(Config:WaitForChild("Shop"))
local Game = require(Config:WaitForChild("Game"))
local Products = require(Config:WaitForChild("Products"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local DogService = require(script.Parent:WaitForChild("DogService"))
local BroadcastService = require(script.Parent:WaitForChild("BroadcastService"))

local EventService = {}

local eventsRoot: Folder = nil
local runaways: { [string]: { Model: Model, EndsAt: number, Target: Vector3, Payload: any } } = {}
local squirrelState: any = nil -- last Squirrel EventState payload while active
local squirrelRunning = false

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function fireState(payload: any, player: Player?)
	local remote = Remotes.Get("EventState")
	if player then
		remote:FireClient(player, payload)
	else
		remote:FireAllClients(payload)
	end
end

----------------------------------------------------------------------------------------------------
-- Areas
----------------------------------------------------------------------------------------------------
type Area = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Y: number }

local function runawayArea(): Area
	for _, inst in CollectionService:GetTagged("RunawayArea") do
		if inst:IsA("BasePart") then
			local p, s = inst.Position, inst.Size
			return { MinX = p.X - s.X / 2 + 4, MaxX = p.X + s.X / 2 - 4, MinZ = p.Z - s.Z / 2 + 4,
				MaxZ = p.Z + s.Z / 2 - 4, Y = if s.Y <= 4 then p.Y + s.Y / 2 else p.Y - s.Y / 2 }
		end
	end
	local pl = Layout.Plaza
	return { MinX = pl.MinX + 20, MaxX = pl.MaxX - 20, MinZ = pl.MinZ + 15, MaxZ = pl.MaxZ - 25, Y = Layout.HubY } -- plaza on the plateau
end

local function randomPoint(a: Area): Vector3
	return Vector3.new(a.MinX + math.random() * (a.MaxX - a.MinX), a.Y, a.MinZ + math.random() * (a.MaxZ - a.MinZ))
end

local function inPlaza(pos: Vector3): boolean
	local pl = Layout.Plaza
	return pos.X >= pl.MinX and pos.X <= pl.MaxX and pos.Z >= pl.MinZ and pos.Z <= pl.MaxZ
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

----------------------------------------------------------------------------------------------------
-- Runaway dogs
----------------------------------------------------------------------------------------------------
-- Spawns the missed dog in the plaza for `duration` seconds (visible to all).
function EventService.SpawnRunaway(throwId: string, owner: Player, dogId: string, variant: string?, duration: number?)
	if runaways[throwId] then
		return
	end
	local def = DogCatalog.Get(dogId)
	if not def then
		return
	end
	local area = runawayArea()
	local model = DogService.BuildModel(def, variant, false)
	model.Name = "Runaway_" .. throwId
	DogService.PlaceModel(model, randomPoint(area), math.random() * math.pi * 2)
	local tierColor = (Rarities.Tiers :: any)[def.Rarity].Color
	DogService.AddNameplate(model, def.Name, "Ran off from " .. owner.DisplayName, tierColor)
	model:SetAttribute("ThrowId", throwId)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("DogId", dogId)
	model:SetAttribute("Rarity", def.Rarity)
	model:SetAttribute("Variant", variant or "")
	CollectionService:AddTag(model, "RunawayDog")
	model.Parent = eventsRoot
	local endsAt = serverNow() + (duration or Timers.RunawaySeconds)
	local payload = {
		Kind = "RunawayDog",
		Active = true,
		EndsAt = endsAt,
		Data = { ThrowId = throwId, DogId = dogId, DogName = def.Name, Rarity = def.Rarity, Variant = variant,
			OwnerUserId = owner.UserId, OwnerName = owner.DisplayName },
	}
	runaways[throwId] = { Model = model, EndsAt = endsAt, Target = randomPoint(area), Payload = payload }
	fireState(payload)
end

-- reason: "Expired" | "Recalled"
function EventService.DespawnRunaway(throwId: string, reason: string?)
	local r = runaways[throwId]
	if not r then
		return
	end
	runaways[throwId] = nil
	if r.Model then
		r.Model:Destroy()
	end
	local payload = table.clone(r.Payload)
	payload.Active = false
	payload.Data = table.clone(r.Payload.Data)
	payload.Data.Reason = reason or "Expired"
	fireState(payload)
end

function EventService.IsRunawayActive(throwId: string): boolean
	return runaways[throwId] ~= nil
end

local function runawayLoop()
	local area = runawayArea()
	local speed = 9
	local step = 0.1
	while true do
		task.wait(step)
		local now = serverNow()
		for id, r in runaways do
			if now >= r.EndsAt then
				EventService.DespawnRunaway(id, "Expired")
			elseif r.Model.Parent then
				local pivot = r.Model:GetPivot()
				local pos = pivot.Position
				local flatTarget = Vector3.new(r.Target.X, pos.Y, r.Target.Z)
				local delta = flatTarget - pos
				if delta.Magnitude < 1.5 then
					r.Target = randomPoint(area)
				else
					local move = delta.Unit * math.min(speed * step, delta.Magnitude)
					local newPos = pos + move
					r.Model:PivotTo(CFrame.lookAt(newPos, newPos + delta.Unit))
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Squirrel
----------------------------------------------------------------------------------------------------
local function squirrelPath(): { Vector3 }
	local parts = {}
	for _, inst in CollectionService:GetTagged("SquirrelPath") do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	table.sort(parts, function(a, b)
		return (tonumber(a:GetAttribute("Order")) or 0) < (tonumber(b:GetAttribute("Order")) or 0)
	end)
	local out = {}
	for _, p in parts do
		local dy = if p.Size.Y <= 4 then p.Size.Y / 2 else -p.Size.Y / 2
		table.insert(out, p.Position + Vector3.new(0, dy, 0))
	end
	if #out < 2 then
		local pl = Layout.Plaza
		local y = Layout.HubY -- plaza on the plateau
		out = {
			Vector3.new(pl.MinX + 15, y, pl.MinZ + 15), Vector3.new(pl.MaxX - 15, y, pl.MinZ + 15),
			Vector3.new(pl.MaxX - 15, y, pl.MaxZ - 20), Vector3.new(pl.MinX + 15, y, pl.MaxZ - 20),
		}
	end
	return out
end

local function bonesMult(player: Player): number
	local m = 1
	local passes = DataService.GetPasses(player)
	for key, pass in Products.GamePasses do
		if pass.BonesMult and passes[key] then
			m *= pass.BonesMult
		end
	end
	return m
end

local function dropBonesVisual(player: Player, amount: number)
	local yard = DogService.GetYardIndex(player)
	if not yard then
		return
	end
	local c = DogService.GetYardCenter(yard)
	for _ = 1, math.min(12, math.max(3, amount // 5)) do
		local bone = Instance.new("Part")
		bone.Name = "Bone"
		bone.Size = Vector3.new(1.6, 0.4, 0.4)
		bone.Color = Color3.fromRGB(245, 240, 225)
		bone.Material = Enum.Material.SmoothPlastic
		bone.CanCollide = false
		bone.Anchored = true
		bone.CFrame = CFrame.new(c + Vector3.new(math.random(-25, 25), 0.3, math.random(-25, 25)))
			* CFrame.Angles(0, math.random() * math.pi, 0)
		bone.Parent = eventsRoot
		Debris:AddItem(bone, 12)
	end
end

function EventService.StartSquirrel()
	if squirrelRunning then
		return
	end
	squirrelRunning = true
	local path = squirrelPath()
	local squirrel = Instance.new("Part")
	squirrel.Name = "Squirrel"
	squirrel.Shape = Enum.PartType.Ball
	squirrel.Size = Vector3.new(2, 2, 2)
	squirrel.Color = Color3.fromRGB(150, 95, 50)
	squirrel.Material = Enum.Material.SmoothPlastic
	squirrel.Anchored = true
	squirrel.CanCollide = false
	squirrel.Position = path[1] + Vector3.new(0, 1, 0)
	local tail = Instance.new("Part")
	tail.Name = "Tail"
	tail.Size = Vector3.new(0.8, 2.2, 0.8)
	tail.Color = Color3.fromRGB(180, 120, 70)
	tail.Anchored = false
	tail.CanCollide = false
	tail.Massless = true
	tail.CFrame = squirrel.CFrame * CFrame.new(0, 0.9, -1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = squirrel
	weld.Part1 = tail
	weld.Parent = squirrel
	tail.Parent = squirrel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 30)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.TextStrokeTransparency = 0.2
	label.Text = "SQUIRREL!"
	label.Parent = gui
	gui.Parent = squirrel
	CollectionService:AddTag(squirrel, "Squirrel")
	squirrel.Parent = eventsRoot

	local endsAt = serverNow() + Timers.SquirrelDuration
	squirrelState = { Kind = "Squirrel", Active = true, EndsAt = endsAt, Data = {} }
	fireState(squirrelState)
	BroadcastService.Send("Squirrel", "A squirrel is loose in the plaza! First to touch it wins Bones!")

	local participants: { [Player]: boolean } = {}
	local winner: Player? = nil
	local idx, speed, step = 1, 16, 0.1
	while serverNow() < endsAt and not winner do
		task.wait(step)
		local target = path[idx % #path + 1] + Vector3.new(0, 1, 0)
		local pos = squirrel.Position
		local delta = target - pos
		if delta.Magnitude < 1 then
			idx += 1
		else
			local np = pos + delta.Unit * math.min(speed * step, delta.Magnitude)
			squirrel.CFrame = CFrame.lookAt(np, np + delta.Unit)
		end
		for _, player in DataService.Players() do
			local hrp = rootOf(player)
			if hrp then
				if inPlaza(hrp.Position) then
					participants[player] = true
				end
				if (hrp.Position - squirrel.Position).Magnitude <= Timers.SquirrelCatchRadius then
					winner = player
					break
				end
			end
		end
	end
	squirrel:Destroy()

	local data: any = {}
	if winner and winner.Parent then
		local amount = math.floor((Shop.Squirrel.WinnerBones + Shop.Squirrel.BonesPerPlayer * #Players:GetPlayers())
			* bonesMult(winner))
		DataService.AddBones(winner, amount)
		DataService.Push(winner)
		dropBonesVisual(winner, amount)
		data = { WinnerUserId = winner.UserId, WinnerName = winner.DisplayName, Bones = amount }
		BroadcastService.Send("Squirrel", ("%s's dog caught the squirrel and dropped %d Bones!"):format(
			winner.DisplayName, amount))
	else
		data = { Escaped = true }
		BroadcastService.Send("Squirrel", "The squirrel got away!")
	end
	for player in participants do
		if player ~= winner and player.Parent then
			local amount = math.floor(Shop.Squirrel.ConsolationBones * bonesMult(player))
			DataService.AddBones(player, amount)
			DataService.Push(player)
			BroadcastService.Notify(player, ("+%d Bones for joining the squirrel chase"):format(amount), "Squirrel")
		end
	end
	squirrelState = nil
	fireState({ Kind = "Squirrel", Active = false, EndsAt = serverNow(), Data = data })
	squirrelRunning = false
end

----------------------------------------------------------------------------------------------------
-- Daily walk
----------------------------------------------------------------------------------------------------
local function today(): number
	return os.time() // Timers.DayLength
end

local function dailyWalkPayload(state: any): any
	local available = state.LastDailyWalk ~= today()
	local nextAt = (today() + 1) * Timers.DayLength
	return { Kind = "DailyWalk", Active = available, EndsAt = nextAt,
		Data = { Available = available, NextAt = if available then os.time() else nextAt } }
end

local function claimDailyWalk(player: Player): (boolean, string)
	local state = DataService.Get(player)
	if not state then
		return false, "Still loading"
	end
	if state.LastDailyWalk == today() then
		local left = (today() + 1) * Timers.DayLength - os.time()
		return false, "Next walk in " .. FormatNumber.Duration(left)
	end
	state.LastDailyWalk = today()
	local income = DogService.CurrentIncome(player)
	local cash = math.max(Shop.DailyWalk.MinCash, math.floor(income * Shop.DailyWalk.IncomeSeconds))
	local bones = math.floor(Shop.DailyWalk.Bones * bonesMult(player))
	DataService.AddCash(player, cash)
	DataService.AddBones(player, bones)
	state.PremiumThrows += Shop.DailyWalk.PremiumThrows
	DataService.Push(player)
	fireState(dailyWalkPayload(state), player)
	return true, ("Daily walk: +%s, +%d Bones and a free premium throw!"):format(FormatNumber.Money(cash), bones)
end

----------------------------------------------------------------------------------------------------
function EventService.Start()
	eventsRoot = Instance.new("Folder")
	eventsRoot.Name = "WorldEvents"
	eventsRoot.Parent = workspace

	local limiter = RateLimiter.new(Game.RateLimits.Claim[1], Game.RateLimits.Claim[2])
	local remote = Remotes.Get("ClaimDailyWalk") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player)
		if not limiter:Check(player) then
			return false, "Slow down"
		end
		local ok, a, b = pcall(claimDailyWalk, player)
		if not ok then
			warn("[EventService] daily walk error: " .. tostring(a))
			return false, "Error"
		end
		return a, b
	end

	-- late joiners get the current event states
	DataService.OnLoaded(function(player: Player, state: any)
		task.wait(1)
		if player.Parent == nil then
			return
		end
		fireState(dailyWalkPayload(state), player)
		if squirrelState then
			fireState(squirrelState, player)
		end
		for _, r in runaways do
			fireState(r.Payload, player)
		end
	end)

	task.spawn(runawayLoop)
	task.spawn(function()
		task.wait(Timers.SquirrelFirstDelay)
		while true do
			local ok, err = pcall(EventService.StartSquirrel)
			if not ok then
				warn("[EventService] squirrel error: " .. tostring(err))
				squirrelRunning = false
			end
			task.wait(math.max(5, Timers.SquirrelInterval - Timers.SquirrelDuration))
		end
	end)
end

return EventService
