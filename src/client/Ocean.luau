-- Draws the ocean on this client and runs this player's sea-parting.
--
-- Everyone draws the same closed sea. When YOU part it, only your client
-- carves out the corridor, raises the walls of water and shows your eggs.
-- Anyone watching just sees you walk into the (closed) water.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Voxel = require(Shared.Voxel)

local State = require(script.Parent.State)

local Ocean = {}

local O = Config.Ocean
local STAFF_NAME = "Sea Staff"
local player = Players.LocalPlayer

local WATER = Color3.fromRGB(35, 135, 235)
local WALL = Color3.fromRGB(60, 160, 245)
local FOAM = Color3.fromRGB(235, 250, 255)

-- Public state read by the HUD.
Ocean.active = nil :: any -- current split (or nil)
Ocean.charging = false
Ocean.charge = 0
Ocean.inZone = false
Ocean.canCharge = false
Ocean.carried = 0
Ocean.cap = 1

local folder: Folder
local parts: { [string]: BasePart } = {}
local eggModels: { [number]: any } = {}
local chargeStart = 0
local pendingGrab: number? = nil
local pendingAt = 0
local lastFullWarn = 0
local wasInZone = false
local shakeUntil = 0

----------------------------------------------------------------------------
-- Water parts
----------------------------------------------------------------------------
local function newPart(name: string, color: Color3, transparency: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.Transparency = transparency
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0.08
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(1, 1, 1)
	p.Parent = folder
	p:SetAttribute("BaseTransparency", transparency)
	parts[name] = p
	return p
end

-- Fit a part to an axis-aligned box; hide it if the box is empty.
local function setBox(p: BasePart, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
	if x1 - x0 < 0.05 or y1 - y0 < 0.05 or z1 - z0 < 0.05 then
		p.Transparency = 1
		return
	end
	p.Transparency = p:GetAttribute("BaseTransparency") :: number
	p.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	p.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
end

local function zSpan(a: number, b: number): (number, number)
	return math.min(a, b), math.max(a, b)
end

local function addSpray(p: BasePart, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(FOAM)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Acceleration = Vector3.new(0, -25, 0)
	e.Rate = rate
	e.LightInfluence = 0.5
	e.Enabled = false
	e.Parent = p
	return e
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "LocalOcean"
	folder.Parent = workspace

	newPart("Main", WATER, 0.25)
	newPart("Left", WATER, 0.25)
	newPart("Right", WATER, 0.25)
	newPart("Far", WATER, 0.25)
	addSpray(newPart("WallL", WALL, 0.12), 12)
	addSpray(newPart("WallR", WALL, 0.12), 12)
	addSpray(newPart("WallEnd", WALL, 0.08), 40)
	newPart("CapL", FOAM, 0.15)
	newPart("CapR", FOAM, 0.15)
	newPart("CapEnd", FOAM, 0.1)
	for _, s in { 1, -1 } do
		newPart("FoamA" .. s, FOAM, 0.35)
		newPart("FoamB" .. s, FOAM, 0.35)
	end
end

-- Lay out every water part for the current split (or the closed sea).
local function layout(sp, L: number, rise: number, t: number)
	local H, Z = O.HalfX, O.ShoreZ
	local y0, y1 = O.SeabedY, O.WaterTopY + math.sin(t * 1.3) * 0.12
	local waterline = Z - 2.5 -- where the water surface meets the ramp

	if not sp or L <= 0.05 then
		setBox(parts.Main, -H, H, y0, y1, -Z, Z)
		for _, n in { "Left", "Right", "Far", "WallL", "WallR", "WallEnd", "CapL", "CapR", "CapEnd" } do
			parts[n].Transparency = 1
		end
		for _, s in { 1, -1 } do
			local a, b = zSpan(s * (waterline - 1), s * (waterline + 1))
			setBox(parts["FoamA" .. s], -H, H, y1 - 0.05, y1 + 0.15, a, b)
			parts["FoamB" .. s].Transparency = 1
		end
		parts.WallL.ParticleEmitter.Enabled = false
		parts.WallR.ParticleEmitter.Enabled = false
		parts.WallEnd.ParticleEmitter.Enabled = false
		return
	end

	local s = sp.side
	local xl, xr = sp.cx - sp.width / 2, sp.cx + sp.width / 2
	local shoreZ = s * Z
	local farZ = s * (Z - L)
	parts.Main.Transparency = 1
	setBox(parts.Left, -H, xl, y0, y1, -Z, Z)
	setBox(parts.Right, xr, H, y0, y1, -Z, Z)
	local fa, fb = zSpan(farZ, -shoreZ)
	setBox(parts.Far, xl, xr, y0, y1, fa, fb)

	-- Walls of water rise up along the corridor.
	local top = y1 + (O.WallTopY - y1) * (1 - (1 - rise) ^ 3)
	local ca, cb = zSpan(shoreZ, farZ)
	setBox(parts.WallL, xl - 4, xl, y0, top, ca, cb)
	setBox(parts.WallR, xr, xr + 4, y0, top, ca, cb)
	local ea, eb = zSpan(farZ, farZ - s * 4)
	setBox(parts.WallEnd, xl - 4, xr + 4, y0, top, ea, eb)
	setBox(parts.CapL, xl - 4.3, xl + 0.3, top, top + 0.7, ca, cb)
	setBox(parts.CapR, xr - 0.3, xr + 4.3, top, top + 0.7, ca, cb)
	setBox(parts.CapEnd, xl - 4.3, xr + 4.3, top, top + 0.7, ea - 0.3, eb + 0.3)

	-- Shore foam, with a gap where the corridor is on our side.
	for _, side in { 1, -1 } do
		local a, b = zSpan(side * (waterline - 1), side * (waterline + 1))
		if side == s then
			setBox(parts["FoamA" .. side], -H, xl - 4, y1 - 0.05, y1 + 0.15, a, b)
			setBox(parts["FoamB" .. side], xr + 4, H, y1 - 0.05, y1 + 0.15, a, b)
		else
			setBox(parts["FoamA" .. side], -H, H, y1 - 0.05, y1 + 0.15, a, b)
			parts["FoamB" .. side].Transparency = 1
		end
	end

	local closing = L < sp.length - 0.01 and rise >= 1
	parts.WallL.ParticleEmitter.Enabled = true
	parts.WallR.ParticleEmitter.Enabled = true
	parts.WallEnd.ParticleEmitter.Enabled = closing
	parts.WallEnd.Color = closing and Color3.fromRGB(30, 110, 215) or WALL
end

----------------------------------------------------------------------------
-- Sounds & shake
----------------------------------------------------------------------------
local function playSound(id: string, volume: number?, speed: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
Ocean.playSound = playSound

----------------------------------------------------------------------------
-- Eggs (only on this client)
----------------------------------------------------------------------------
local function clearEggs()
	for _, e in eggModels do
		e.model:Destroy()
	end
	table.clear(eggModels)
end

local function eggLabel(root: BasePart, egg: string, variant: string)
	local e = Config.EggById[egg]
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, variant ~= "Normal" and 62 or 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = root
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local function line(text: string, color: Color3, h: number, order: number)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.LayoutOrder = order
		l.Parent = gui
	end
	if variant ~= "Normal" then
		line(variant, Config.Variants[variant].color, 18, 0)
	end
	line(e.name, Color3.new(1, 1, 1), 24, 1)
	line(e.rarity, Config.Rarities[Config.RarityIndex[e.rarity]].color, 20, 2)
	gui.Parent = root
end

local function spawnEggs(sp)
	clearEggs()
	local rng = Random.new(math.floor(sp.t0 * 1000) % 100000)
	for _, e in sp.eggs do
		local model = Voxel.egg(e.egg, e.variant, true)
		local pos = Vector3.new(sp.cx + e.x, O.SeabedY, sp.side * (O.ShoreZ - e.d))
		local yaw = rng:NextNumber(0, math.pi * 2)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
		eggLabel(model.PrimaryPart, e.egg, e.variant)
		eggModels[e.id] = { model = model, data = e, pos = pos, yaw = yaw, shown = false }
	end
end

----------------------------------------------------------------------------
-- Split lifecycle
----------------------------------------------------------------------------
local function character()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, root
end

local function inZone(pos: Vector3): boolean
	local az = math.abs(pos.Z)
	return az >= O.ShoreZ - 1 and az <= O.ShoreZ + O.SplitZoneDepth + 2 and math.abs(pos.X) <= O.HalfX - 2 and pos.Y > -3
end

function Ocean.start(sp)
	Ocean.active = sp
	Ocean.carried = 0
	pendingGrab = nil
	spawnEggs(sp)
	shakeUntil = os.clock() + 0.8
	playSound("rbxasset://sounds/swoosh.wav", 0.9, 0.6)
	playSound("rbxasset://sounds/swoosh.wav", 0.6, 0.45)
end

function Ocean.finish()
	Ocean.active = nil
	Ocean.carried = 0
	pendingGrab = nil
	clearEggs()
end

function Ocean.close()
	if Ocean.active then
		Remotes.get("CloseSplit"):FireServer()
		Ocean.finish()
	end
end

-- Time info for the HUD: phase ("open"/"closing"), seconds left in phase.
function Ocean.timing(): (string?, number)
	local sp = Ocean.active
	if not sp then
		return nil, 0
	end
	local elapsed = State.serverNow() - sp.t0
	local openEnd = O.OpenAnim + sp.openTime
	if elapsed < openEnd then
		return "open", openEnd - elapsed
	end
	return "closing", math.max(0, Formulas.totalDuration(sp) - elapsed)
end

local function release()
	if not Ocean.charging then
		return
	end
	Ocean.charging = false
	local charge = Ocean.charge
	Ocean.charge = 0
	local ok, payload, err = pcall(function()
		return Remotes.get("RequestSplit"):InvokeServer(charge)
	end)
	if ok and type(payload) == "table" then
		Ocean.start(payload)
	elseif ok and err then
		State.toast:Fire(err, Color3.fromRGB(255, 200, 90))
	end
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

----------------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------------
local function update()
	local t = os.clock()
	local char, root = character()
	local sp = Ocean.active

	-- Can we charge a split right now?
	local zone = root ~= nil and inZone(root.Position)
	Ocean.inZone = zone
	local holdingStaff = char ~= nil and char:FindFirstChild(STAFF_NAME) ~= nil
	Ocean.canCharge = zone and holdingStaff and sp == nil
	if zone and not wasInZone and char and not holdingStaff and sp == nil then
		-- Walking onto the shore pulls out the staff for you.
		local tool = player.Backpack:FindFirstChild(STAFF_NAME)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if tool and hum and not char:FindFirstChildOfClass("Tool") then
			hum:EquipTool(tool)
		end
	end
	wasInZone = zone
	if Ocean.charging then
		if not Ocean.canCharge then
			Ocean.charging = false
			Ocean.charge = 0
		else
			Ocean.charge = math.clamp((t - chargeStart) / Config.Split.ChargeTime, 0, 1)
		end
	end

	-- Water + corridor.
	local L, rise = 0, 0
	if sp then
		local elapsed = State.serverNow() - sp.t0
		L = Formulas.currentLength(sp, elapsed)
		rise = math.clamp(elapsed / O.OpenAnim, 0, 1)
		if elapsed > Formulas.totalDuration(sp) + 0.5 then
			Ocean.finish()
			sp = nil
		end
	end
	layout(sp, L, rise, t)

	-- Eggs: appear as the corridor reaches them, get swept as it closes.
	if sp then
		for id, e in eggModels do
			if e.data.d <= L + 0.5 then
				local bob = math.sin(t * 2 + id) * 0.25 + 0.25
				e.model:PivotTo(CFrame.new(e.pos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, e.yaw + t * 0.6, 0))
				if not e.shown then
					e.shown = true
					e.model.Parent = folder
				end
			elseif e.shown then
				-- Swallowed by the sea.
				e.model:Destroy()
				eggModels[id] = nil
			end
		end

		-- Grab the nearest egg in reach.
		if pendingGrab and t - pendingAt > 1.2 then
			pendingGrab = nil
		end
		if root and not pendingGrab then
			for id, e in eggModels do
				if e.shown then
					local dx, dz = root.Position.X - e.pos.X, root.Position.Z - e.pos.Z
					if dx * dx + dz * dz <= O.GrabRadius * O.GrabRadius then
						local cap = State.data and State.data.carry or 1
						if Ocean.carried >= cap then
							if t - lastFullWarn > 2.5 then
								lastFullWarn = t
								State.toast:Fire("Hands full! Run back to the beach!", Color3.fromRGB(255, 200, 90))
							end
						else
							pendingGrab = id
							pendingAt = t
							Remotes.get("GrabEgg"):FireServer(id)
						end
						break
					end
				end
			end
		end
	end

	-- Camera shake while the sea tears open.
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		if t < shakeUntil then
			local k = (shakeUntil - t) / 0.8
			hum.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * k * 0.9
		elseif hum.CameraOffset ~= Vector3.zero then
			hum.CameraOffset = Vector3.zero
		end
	end
end

function Ocean.init()
	build()
	RunService.RenderStepped:Connect(update)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not isPress(input) then
			return
		end
		if Ocean.canCharge then
			Ocean.charging = true
			Ocean.charge = 0
			chargeStart = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			release()
		end
	end)

	State.effect:Connect(function(kind, payload)
		if kind == "grabbed" then
			local e = eggModels[payload.id]
			if e then
				e.model:Destroy()
				eggModels[payload.id] = nil
			end
			pendingGrab = nil
			Ocean.carried = payload.count
			playSound("rbxasset://sounds/electronicpingshort.wav", 0.7, 1.3)
			State.toast:Fire("Got a " .. Config.EggById[payload.egg].name .. "! Run back to the beach!", Color3.fromRGB(120, 255, 120))
		elseif kind == "grabFail" then
			pendingGrab = nil
		elseif kind == "caught" then
			Ocean.carried = 0
			playSound("rbxasset://sounds/splat.wav", 0.8, 0.7)
		elseif kind == "pushed" then
			playSound("rbxasset://sounds/splat.wav", 0.6, 0.9)
		elseif kind == "banked" then
			Ocean.carried = 0
		elseif kind == "splitEnd" then
			Ocean.finish()
		end
	end)

	player.CharacterAdded:Connect(function()
		Ocean.carried = 0
		Ocean.charging = false
	end)
end

return Ocean
