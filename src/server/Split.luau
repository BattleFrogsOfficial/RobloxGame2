-- Authoritative sea-parting logic.
--
-- The water is drawn on each client, so only the splitter sees their corridor
-- and eggs. The server owns the truth: corridor size and timing, which eggs
-- exist, who is carrying what, and who gets swept away.
--
-- A corridor opens straight out from the shore. Its two side walls start
-- closing as soon as it opens and meet after `duration` seconds; an egg is
-- gone once the water covers it, and so is anyone still between the walls.
-- Eggs you grab stay on your head until you carry them into your own base.

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
local FLING_SECONDS = 1.5 -- how long the client's ragdoll flight back to shore lasts

local splits: { [Player]: any } = {}
local carrying: { [Player]: { any } } = {}
local carryModels: { [Player]: { Model } } = {}
local immuneUntil: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local wasInOcean: { [Player]: boolean } = {}
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Distance out from the shore, and sideways offset from the corridor center.
local function corridorCoords(sp, pos: Vector3): (number, number)
	return O.ShoreZ - pos.Z, pos.X - sp.cx
end

local function eggWorldPos(sp, egg): Vector3
	return Vector3.new(sp.cx + egg.x, Formulas.groundY(egg.d), O.ShoreZ - egg.d)
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
	player:SetAttribute("Carrying", 0)
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
	p.CFrame = CFrame.new(pos)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(30, 55)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -60, 0)
	e.Rate = 0
	e.Parent = p
	p.Parent = workspace
	e:Emit(90)
	Debris:AddItem(p, 2.5)
end

----------------------------------------------------------------------------
-- Run outcomes
----------------------------------------------------------------------------

local endSplit: (Player) -> ()

-- The sea throws the player back onto the beach, and the run is over. The client plays the
-- ragdoll flight (it owns its character's physics); the server keeps them
-- safe meanwhile and puts them on the sand if they somehow don't land there.
local function caught(player: Player, root: BasePart, reason: string)
	local lost = carrying[player] and #carrying[player] or 0
	splash(root.Position + Vector3.new(0, 2, 0))
	clearCarry(player)
	immuneUntil[player] = os.clock() + FLING_SECONDS + 1.5
	local x = math.clamp(root.Position.X, -O.HalfX + 8, O.HalfX - 8)
	local landing = Vector3.new(x, 3.5, O.ShoreZ + 16)
	Data.effect(player, "caught", { lost = lost, reason = reason, landing = landing, seconds = FLING_SECONDS })
	-- Being caught ends the split, so the client drops its water walls and
	-- nothing blocks the flight back to shore.
	endSplit(player)
	task.delay(FLING_SECONDS + 0.8, function()
		local char = player.Character
		local r = rootOf(player)
		if char and r and (World.inOcean(r.Position) or r.Position.Y < -2) then
			char:PivotTo(CFrame.lookAt(landing, landing + Vector3.new(0, 0, 1)))
		end
	end)
end

-- Carried eggs are planted the moment their owner walks into their base.
local function plant(player: Player)
	local list = carrying[player]
	if not list or #list == 0 then
		return
	end
	local d = Data.get(player)
	if not d then
		return
	end
	local planted = {}
	for _, item in list do
		local where = Pens.addEgg(player, item.egg, item.variant)
		d.stats.eggsCollected += 1
		table.insert(planted, { egg = item.egg, variant = item.variant, where = where })
	end
	clearCarry(player)
	Data.markDirty(player)
	Data.effect(player, "planted", planted)
end

function endSplit(player: Player)
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
		return nil, "Still loading..."
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
	local cap = Formulas.carry(Data.hasPass(player, "ExtraCarry"))
	if carrying[player] and #carrying[player] >= cap then
		return nil, "Your hands are full! Plant your egg in your base first."
	end

	-- Which cast is this? Usually a plain split; sometimes a Super Split or
	-- Poseidon's Wrath, which multiply Luck for this split's eggs. In Studio
	-- a player attribute can force one for previewing:
	--   game.Players.LocalPlayer:SetAttribute("ForceCast", "Poseidon")
	local cast = Formulas.rollCast(rng:NextNumber())
	local forced = player:GetAttribute("ForceCast")
	if RunService:IsStudio() and type(forced) == "string" and Config.CastByKey[forced] then
		cast = Config.CastByKey[forced]
	end

	local params = Formulas.splitParams(d.strength, math.clamp(charge, 0, 1))
	local half = params.width / 2
	local sp = {
		cx = math.clamp(root.Position.X, -O.HalfX + half + 6, O.HalfX - half - 6),
		width = params.width,
		length = params.length,
		duration = params.duration,
		t0 = now(),
		cast = cast.key,
		anim = cast.seconds,
		slam = cast.slam,
		wallTop = cast.wallTop,
		luck = cast.luck,
	}
	local eggs = Formulas.rollEggs(rng, sp, Data.luck(player) * cast.luck)
	sp.eggs = {}
	for _, e in eggs do
		sp.eggs[e.id] = e
	end
	splits[player] = sp
	-- Every client plays the staff-raising animation from this timestamp.
	player:SetAttribute("CastKey", cast.key)
	player:SetAttribute("CastSeconds", cast.seconds)
	player:SetAttribute("CastStart", sp.t0)
	d.stats.splits += 1
	Data.markDirty(player)

	return {
		cx = sp.cx,
		width = sp.width,
		length = sp.length,
		duration = sp.duration,
		t0 = sp.t0,
		cast = sp.cast,
		anim = sp.anim,
		slam = sp.slam,
		wallTop = sp.wallTop,
		luck = sp.luck,
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
	local elapsed = now() - sp.t0
	local pos = eggWorldPos(sp, egg)
	local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude
	if flat > O.GrabRadius + 3 or elapsed < Formulas.anim(sp) then
		return
	end
	-- A little slack past "covered" so a grab at the last instant still counts.
	if math.abs(egg.x) > Formulas.halfWidth(sp, elapsed) + O.SweepGrace then
		Data.effect(player, "grabFail", { id = id, reason = "covered" })
		return
	end
	egg.taken = true
	table.insert(list, { egg = egg.egg, variant = egg.variant })
	addCarryModel(player, egg.egg, egg.variant)
	player:SetAttribute("Carrying", #list)
	Data.effect(player, "grabbed", { id = id, egg = egg.egg, variant = egg.variant, count = #list, cap = cap })
end

local function onClose(player: Player)
	local sp = splits[player]
	local root = rootOf(player)
	if not sp then
		return
	end
	if root and World.inOcean(root.Position) then
		caught(player, root, "closed")
	end
	endSplit(player)
end

----------------------------------------------------------------------------
-- Per-tick checks
----------------------------------------------------------------------------
local function step()
	local t = now()
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local sp = splits[player]
		local elapsed = sp and (t - sp.t0) or 0
		if root then
			local pos = root.Position
			local inOcean = World.inOcean(pos)
			if inOcean then
				if not immuneUntil[player] or clock > immuneUntil[player] then
					local safe = false
					if sp then
						local d, lateral = corridorCoords(sp, pos)
						local half = Formulas.halfWidth(sp, elapsed)
						safe = Formulas.isOpen(sp, elapsed) and d <= sp.length + O.SweepGrace and math.abs(lateral) <= half + O.SweepGrace
					end
					if not safe then
						caught(player, root, sp and "swept" or "closed")
					end
				end
			else
				local list = carrying[player]
				if list and #list > 0 then
					if wasInOcean[player] then
						-- Made it back to land with eggs in hand.
						Data.effect(player, "safe", { count = #list })
					end
					if Pens.contains(player, pos) then
						plant(player)
					end
				end
			end
			wasInOcean[player] = inOcean
		end
		if sp and not Formulas.isOpen(sp, elapsed) then
			endSplit(player)
		end
	end
end

function Split.carried(player: Player): number
	return carrying[player] and #carrying[player] or 0
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
		player:SetAttribute("Carrying", 0)
		player.CharacterAdded:Connect(function()
			-- A respawn drops whatever you were carrying.
			carryModels[player] = {}
			carrying[player] = {}
			player:SetAttribute("Carrying", 0)
			immuneUntil[player] = os.clock() + 2
			task.defer(Split.ensureStaff, player)
		end)
		Split.ensureStaff(player)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end

	-- Leaving with eggs you already carried to safety keeps them (in storage).
	Data.onLeaving(function(player)
		local root = rootOf(player)
		local list = carrying[player]
		if list and #list > 0 and not (root and World.inOcean(root.Position)) then
			for _, item in list do
				Pens.addEgg(player, item.egg, item.variant)
			end
		end
		carrying[player] = {}
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Deferred so the leaving hook above (run by Data's own
		-- PlayerRemoving handler) still sees what the player was carrying.
		task.defer(function()
			splits[player] = nil
			carrying[player] = nil
			carryModels[player] = nil
			immuneUntil[player] = nil
			lastRequest[player] = nil
			wasInOcean[player] = nil
		end)
	end)
end

Split.STAFF_NAME = STAFF_NAME

-- StarterPack only reaches characters that spawn after the staff exists, so
-- anyone who spawned earlier (common in Studio) is handed one directly.
function Split.ensureStaff(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local char = player.Character
	if not backpack or not char then
		return
	end
	if backpack:FindFirstChild(STAFF_NAME) or char:FindFirstChild(STAFF_NAME) then
		return
	end
	local template = game:GetService("StarterPack"):FindFirstChild(STAFF_NAME)
	if template then
		template:Clone().Parent = backpack
	end
end

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
