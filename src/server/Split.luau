-- Authoritative sea-parting logic.
--
-- The water is drawn on each client, so only the splitter sees their corridor
-- and eggs. The server owns the truth: corridor size and timing, which eggs
-- exist, who is carrying what, and who gets swept back by the sea.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Voxel = require(Shared.Voxel)

local Data = require(script.Parent.Data)
local Pens = require(script.Parent.Pens)
local World = require(script.Parent.World)

local Split = {}

local O = Config.Ocean
local STAFF_NAME = "Sea Staff"

local splits: { [Player]: any } = {}
local carrying: { [Player]: { any } } = {}
local carryModels: { [Player]: { Model } } = {}
local immuneUntil: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Distance from this split's shore toward the far side, and sideways offset.
local function corridorCoords(sp, pos: Vector3): (number, number)
	local d = O.ShoreZ - sp.side * pos.Z
	return d, pos.X - sp.cx
end

local function eggWorldPos(sp, egg): Vector3
	return Vector3.new(sp.cx + egg.x, O.SeabedY, sp.side * (O.ShoreZ - egg.d))
end

----------------------------------------------------------------------------
-- Carried egg visuals (visible to everyone)
----------------------------------------------------------------------------
local function clearCarry(player: Player)
	for _, m in carryModels[player] or {} do
		m:Destroy()
	end
	carryModels[player] = {}
	carrying[player] = {}
end

local function addCarryModel(player: Player, egg: string, variant: string)
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local list = carryModels[player] or {}
	carryModels[player] = list
	local m = Voxel.egg(egg, variant, false)
	m:ScaleTo(0.8)
	Voxel.weld(m, false)
	local _, size = m:GetBoundingBox()
	local y = head.Size.Y / 2 + 0.6 + #list * (size.Y + 0.2)
	m:PivotTo(head.CFrame * CFrame.new(0, y, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = m.PrimaryPart
	weld.Parent = m.PrimaryPart
	m.Name = "CarriedEgg"
	m.Parent = char
	table.insert(list, m)
end

local function splash(pos: Vector3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(18, 30)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -50, 0)
	e.Rate = 0
	e.Parent = p
	p.Parent = workspace
	e:Emit(60)
	Debris:AddItem(p, 2)
end

----------------------------------------------------------------------------
-- Run outcomes
----------------------------------------------------------------------------
local function caught(player: Player, root: BasePart)
	local sp = splits[player]
	local lost = carrying[player] and #carrying[player] or 0
	splash(root.Position + Vector3.new(0, 2, 0))
	clearCarry(player)
	immuneUntil[player] = os.clock() + 1.5
	local side = sp and sp.side or (root.Position.Z >= 0 and 1 or -1)
	local x = math.clamp(root.Position.X, -O.HalfX + 4, O.HalfX - 4)
	local back = Vector3.new(x, 4, side * (O.ShoreZ + 8))
	local char = player.Character
	if char then
		char:PivotTo(CFrame.lookAt(back, back + Vector3.new(0, 0, side)))
	end
	if sp then
		Data.effect(player, "caught", { lost = lost })
		if lost > 0 then
			Data.notify(player, "The sea swept you back! You lost your egg.", Color3.fromRGB(120, 200, 255))
		else
			Data.notify(player, "The sea swept you back!", Color3.fromRGB(120, 200, 255))
		end
	else
		Data.effect(player, "pushed", nil)
		Data.notify(player, "The sea pushes you back! Part it with your staff first.", Color3.fromRGB(120, 200, 255))
	end
end

local function bank(player: Player)
	local list = carrying[player]
	if not list or #list == 0 then
		return
	end
	local d = Data.get(player)
	local banked = {}
	for _, item in list do
		local where = Pens.addEgg(player, item.egg, item.variant)
		d.stats.eggsCollected += 1
		table.insert(banked, { egg = item.egg, variant = item.variant, where = where })
	end
	clearCarry(player)
	Data.markDirty(player)
	Data.effect(player, "banked", banked)
end

local function endSplit(player: Player)
	if splits[player] then
		splits[player] = nil
		Data.effect(player, "splitEnd", nil)
	end
end

----------------------------------------------------------------------------
-- Remote handlers
----------------------------------------------------------------------------
local function onRequestSplit(player: Player, charge: any)
	if type(charge) ~= "number" or charge ~= charge then
		return nil, "bad"
	end
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.5 then
		return nil, "Slow down!"
	end
	lastRequest[player] = t
	local d = Data.get(player)
	if not d then
		return nil, "Still loading…"
	end
	if splits[player] then
		return nil, "Your ocean is still open!"
	end
	local char = player.Character
	local root = rootOf(player)
	if not char or not root or not char:FindFirstChild(STAFF_NAME) then
		return nil, "Hold your Sea Staff!"
	end
	if not World.inSplitZone(root.Position) then
		return nil, "Walk up to the shoreline to part the sea!"
	end

	local side = root.Position.Z >= 0 and 1 or -1
	local params = Formulas.splitParams(d.strength, math.clamp(charge, 0, 1))
	local half = params.width / 2
	local sp = {
		side = side,
		cx = math.clamp(root.Position.X, -O.HalfX + half + 1, O.HalfX - half - 1),
		width = params.width,
		length = params.length,
		openTime = params.openTime,
		closeSpeed = params.closeSpeed,
		t0 = now(),
	}
	local eggs = Formulas.rollEggs(rng, sp, Data.luck(player))
	sp.eggs = {}
	for _, e in eggs do
		sp.eggs[e.id] = e
	end
	splits[player] = sp
	d.stats.splits += 1
	Data.markDirty(player)

	return {
		side = sp.side,
		cx = sp.cx,
		width = sp.width,
		length = sp.length,
		openTime = sp.openTime,
		closeSpeed = sp.closeSpeed,
		t0 = sp.t0,
		eggs = eggs,
	}
end

local function onGrab(player: Player, id: any)
	local sp = splits[player]
	if not sp or type(id) ~= "number" then
		return
	end
	local egg = sp.eggs[id]
	local root = rootOf(player)
	if not egg or egg.taken or not root then
		return
	end
	local list = carrying[player] or {}
	carrying[player] = list
	local cap = Formulas.carry(Data.hasPass(player, "ExtraCarry"))
	if #list >= cap then
		Data.effect(player, "grabFail", { id = id, reason = "full" })
		return
	end
	local L = Formulas.currentLength(sp, now() - sp.t0)
	local pos = eggWorldPos(sp, egg)
	local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude
	if flat > O.GrabRadius + 3 or egg.d > L + 1 then
		return
	end
	egg.taken = true
	table.insert(list, { egg = egg.egg, variant = egg.variant })
	addCarryModel(player, egg.egg, egg.variant)
	Data.effect(player, "grabbed", { id = id, egg = egg.egg, variant = egg.variant, count = #list, cap = cap })
end

local function onClose(player: Player)
	local sp = splits[player]
	local root = rootOf(player)
	if not sp then
		return
	end
	if root and World.inOcean(root.Position) then
		caught(player, root)
	end
	endSplit(player)
end

----------------------------------------------------------------------------
-- Per-frame checks
----------------------------------------------------------------------------
local function step()
	local t = now()
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local sp = splits[player]
		if root then
			local pos = root.Position
			if World.inOcean(pos) then
				if not immuneUntil[player] or clock > immuneUntil[player] then
					local safe = false
					if sp then
						local d, lateral = corridorCoords(sp, pos)
						local L = Formulas.currentLength(sp, t - sp.t0)
						safe = math.abs(lateral) <= sp.width / 2 + 2.5 and d <= L + O.SweepGrace
					end
					if not safe then
						caught(player, root)
					end
				end
			elseif carrying[player] and #carrying[player] > 0 then
				bank(player)
			end
		end
		if sp and t - sp.t0 > Formulas.totalDuration(sp) then
			endSplit(player)
		end
	end
end

function Split.init()
	Remotes.get("RequestSplit").OnServerInvoke = onRequestSplit
	Remotes.get("GrabEgg").OnServerEvent:Connect(onGrab)
	Remotes.get("CloseSplit").OnServerEvent:Connect(onClose)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			step()
		end
	end)

	local function hook(player: Player)
		carrying[player] = {}
		carryModels[player] = {}
		player.CharacterAdded:Connect(function()
			-- A respawn drops whatever you were carrying.
			carryModels[player] = {}
			carrying[player] = {}
			immuneUntil[player] = os.clock() + 2
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		splits[player] = nil
		carrying[player] = nil
		carryModels[player] = nil
		immuneUntil[player] = nil
		lastRequest[player] = nil
	end)
end

Split.STAFF_NAME = STAFF_NAME

-- Gives the Sea Staff tool to everyone (and every respawn) via StarterPack.
function Split.makeStaff()
	local tool = Instance.new("Tool")
	tool.Name = STAFF_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Hold click on the shoreline to part the sea"
	-- Default grip holds a +Y-long handle upright in the tool-hold pose.
	tool.Grip = CFrame.new()
	local staff = Voxel.staff()
	local handle = staff:FindFirstChild("Handle") :: BasePart
	for _, p in staff:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			if p ~= handle then
				local w = Instance.new("WeldConstraint")
				w.Part0 = handle
				w.Part1 = p
				w.Parent = p
			end
			p.Parent = tool
		end
	end
	tool.Parent = game:GetService("StarterPack")
end

return Split
