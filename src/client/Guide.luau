-- New-player guide: works out what to do next, shows it as a line of text
-- (read by the HUD) and lays a trail of green arrows on the ground toward it.
-- It goes quiet once the player has banked an egg, hatched one and trained.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local State = require(script.Parent.State)
local Ocean = require(script.Parent.Ocean)
local Placement = require(script.Parent.Placement)

local Guide = {}

Guide.text = nil :: string? -- current objective, or nil
Guide.urgent = false

local O = Config.Ocean
local player = Players.LocalPlayer
local SPACING = 6
local MAX_ARROWS = 18
local GREEN = Color3.fromRGB(70, 255, 120)
local RED = Color3.fromRGB(255, 110, 90)

local folder: Folder
local arrows: { Model } = {}
local target: Vector3? = nil
local lastThink = 0

-- A chevron lying flat, pointing along its -Z (LookVector).
local function newArrow(): Model
	local m = Instance.new("Model")
	m.Name = "GuideArrow"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = m
	m.PrimaryPart = root
	for _, sx in { -1, 1 } do
		local arm = Instance.new("Part")
		arm.Size = Vector3.new(1.9, 0.3, 0.7)
		arm.CFrame = CFrame.new(sx * 0.6, 0, -0.1) * CFrame.Angles(0, -sx * 0.685, 0)
		arm.Color = GREEN
		arm.Material = Enum.Material.Neon
		arm.Anchored = true
		arm.CanCollide = false
		arm.CanQuery = false
		arm.CanTouch = false
		arm.CastShadow = false
		arm.Parent = m
	end
	return m
end

local function myPen(): Model?
	local pens = workspace:FindFirstChild("Pens")
	if not pens then
		return nil
	end
	for _, m in pens:GetChildren() do
		if m:GetAttribute("OwnerId") == player.UserId then
			return m :: Model
		end
	end
	return nil
end

local function insidePen(pen: Model, pos: Vector3): boolean
	local c = pen:GetAttribute("Center") :: Vector3
	return math.abs(pos.X - c.X) < Config.Pen.Width / 2 and math.abs(pos.Z - c.Z) < Config.Pen.Depth / 2
end

-- Ground height under a point (ocean ramp + seabed, flat land elsewhere).
local function groundY(pos: Vector3): number
	if pos.Z < O.ShoreZ then
		return Formulas.groundY(O.ShoreZ - pos.Z)
	end
	return 0
end

-- First egg sitting in the player's pen, if any.
local function penEgg(pen: Model): Vector3?
	local contents = pen:FindFirstChild("Contents")
	if not contents then
		return nil
	end
	for _, m in contents:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and string.sub(m.Name, -3) == "Egg" then
			return m.PrimaryPart.Position
		end
	end
	return nil
end

local function penCount(d): number
	local n = 0
	for _ in d.pen do
		n += 1
	end
	return n
end

-- What should the player do right now? Returns text and an optional target.
local function think(root: BasePart): (string?, Vector3?, boolean)
	local d = State.data
	if not d then
		return nil, nil, false
	end
	local pos = root.Position
	local newbie = d.stats.eggsCollected < 3
	local sp = Ocean.active
	local pen = myPen()
	local inSea = pos.Z < O.ShoreZ

	-- Carrying: get out of the sea. On land the egg goes into your inventory.
	if Ocean.carried > 0 then
		if inSea then
			return "Run back to the beach!", newbie and Vector3.new(pos.X, 0, O.ShoreZ + 6) or nil, true
		end
		return nil, nil, false
	end

	-- Picking a spot for an egg: the HUD panel does the talking.
	if Placement.active then
		return nil, nil, false
	end

	-- An egg in the inventory and room in the plot: go and place it.
	if pen and newbie and not inSea and #d.eggs > 0 and penCount(d) < d.baseSlots then
		if insidePen(pen, pos) then
			return "Open EGGS, press Place, then pick a spot in your plot!", nil, false
		end
		return "Take your egg to your plot and place it!", pen:GetAttribute("Center") :: Vector3, false
	end

	if sp and not Ocean.cutscene then
		local best, bestDist
		for _, e in Ocean.eggPositions() do
			local dist = (e - pos).Magnitude
			if not bestDist or dist < bestDist then
				best, bestDist = e, dist
			end
		end
		if best and newbie then
			return "Go to an egg and hold E to grab it before the sea closes!", best, false
		end
		return nil, nil, false
	end
	if sp then
		return nil, nil, false
	end

	if d.stats.eggsCollected == 0 then
		if Ocean.inZone then
			return Ocean.canCharge and "Hold to charge, then let go to part the sea!" or "Equip your Sea Staff!", nil, false
		end
		local shore = Vector3.new(math.clamp(pos.X, -O.HalfX + 40, O.HalfX - 40), 0, O.ShoreZ + 8)
		return "Walk to the shoreline to part the sea!", shore, false
	end
	if pen and d.stats.hatched == 0 then
		local egg = penEgg(pen)
		if egg then
			return "Your egg is incubating. Hatch it at your base when it's ready!", egg, false
		end
	end
	if pen and d.strength == 0 then
		return "Step onto the pink pad to train your Strength!", pen:GetAttribute("Pad") :: Vector3, false
	end
	return nil, nil, false
end

local function hideFrom(i: number)
	for k = i, #arrows do
		if arrows[k].Parent then
			arrows[k].Parent = nil
		end
	end
end

local function draw(root: BasePart, t: number)
	if not target then
		hideFrom(1)
		return
	end
	local start = Vector3.new(root.Position.X, 0, root.Position.Z)
	local goal = Vector3.new(target.X, 0, target.Z)
	local points = { start }
	-- Route through the gate when the trail crosses our pen fence.
	local pen = myPen()
	if pen and insidePen(pen, start) ~= insidePen(pen, goal) then
		local gate = pen:GetAttribute("Gate") :: Vector3
		table.insert(points, Vector3.new(gate.X, 0, gate.Z))
	end
	table.insert(points, goal)

	local color = Guide.urgent and RED or GREEN
	local n = 0
	local carry = 4 + (t * 9) % SPACING -- skip the first few studs, then scroll
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		if len > 0.5 then
			local dir = (b - a).Unit
			local along = carry
			while along < len - 2 and n < MAX_ARROWS do
				n += 1
				local p = a + dir * along
				local arrow = arrows[n]
				if not arrow then
					arrow = newArrow()
					arrows[n] = arrow
				end
				local ground = Vector3.new(p.X, groundY(p) + 0.35, p.Z)
				local ahead = p + dir
				arrow:PivotTo(CFrame.lookAt(ground, Vector3.new(ahead.X, groundY(ahead) + 0.35, ahead.Z)))
				for _, part in arrow:GetChildren() do
					if part:IsA("BasePart") and part ~= arrow.PrimaryPart then
						part.Color = color
					end
				end
				if arrow.Parent ~= folder then
					arrow.Parent = folder
				end
				along += SPACING
			end
			carry = math.max(0, along - len)
		end
	end
	hideFrom(n + 1)
end

function Guide.init()
	folder = Instance.new("Folder")
	folder.Name = "GuideArrows"
	folder.Parent = workspace

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			Guide.text = nil
			target = nil
			hideFrom(1)
			return
		end
		if t - lastThink > 0.2 then
			lastThink = t
			Guide.text, target, Guide.urgent = think(root)
			-- No trail once we're basically standing on the target.
			if target and (Vector3.new(target.X, 0, target.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude < 7 then
				target = nil
			end
		end
		draw(root, t)
	end)
end

return Guide
