-- Player pens ("bases"): assignment, building, eggs incubating in slots,
-- animals wandering and earning, hatching, inventory moves, income.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Voxel = require(Shared.Voxel)

local Data = require(script.Parent.Data)
local World = require(script.Parent.World)

local Pens = {}

-- Other modules plug in here to avoid circular requires.
Pens.callbacks = {
	buyWeight = nil :: ((Player) -> ())?,
}

-- The whole fenced plot is for eggs and animals. The training pad, the
-- weights stall and the upgrade sign stand just outside the front fence, on
-- either side of the gate.
local HALF_W, HALF_D = Config.Pen.Width / 2, Config.Pen.Depth / 2
local WANDER_MIN = Vector3.new(-HALF_W + 5, 0, -HALF_D + 5)
local WANDER_MAX = Vector3.new(HALF_W - 5, 0, HALF_D - 5)
Pens.PadLocal = Vector3.new(-17.5, 0, -HALF_D - 9.5)
local STALL_LOCAL = Vector3.new(-30, 0, -HALF_D - 4.5) -- the weights stall, back against the fence
local BASE_SIGN_LOCAL = Vector3.new(22, 0, -HALF_D - 3.5)

local pens = {} -- array of pen records
local penByPlayer: { [Player]: any } = {}
local rng = Random.new()

local FENCE_POST = Color3.fromRGB(115, 110, 150)
local FENCE_RAIL = Color3.fromRGB(210, 115, 60)

----------------------------------------------------------------------------
-- UI helpers (billboards)
----------------------------------------------------------------------------
local function label(parent: Instance, text: string, color: Color3, height: number, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

-- World-sized label stack above a part: it shrinks with distance instead of
-- staying a fixed size on screen. Line heights are in "pixels" at 20 px/stud.
local STUDS_PER_PIXEL = 0.05

local function billboard(adornee: BasePart, offsetY: number, lines: { { string | Color3 | number } }, maxDistance: number?, scale: number?, reserveTop: number?)
	local total = reserveTop or 0
	for _, line in lines do
		total += (line[3] or 20) :: number
	end
	local k = STUDS_PER_PIXEL * (scale or 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(200 * k, total * k)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY + total * k / 2, 0)
	gui.MaxDistance = maxDistance or 70
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local labels = {}
	for i, line in lines do
		local height = (line[3] or 20) :: number
		labels[i] = label(gui, line[1] :: string, line[2] :: Color3, height, i)
		labels[i].Size = UDim2.fromScale(1, height / total)
	end
	gui.Parent = adornee
	return gui, labels, total
end

local function rarityColor(rarity: string): Color3
	return Config.Rarities[Config.RarityIndex[rarity]].color
end

local function variantLine(variant: string?)
	if variant and variant ~= "Normal" then
		return { variant, Config.Variants[variant].color, 18 }
	end
	return nil
end

----------------------------------------------------------------------------
-- Static pen construction
----------------------------------------------------------------------------
local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function fenceLine(parent: Instance, cf: CFrame, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 8))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		part(parent, Vector3.new(1.6, 4.4, 1.6), cf * CFrame.new(p + Vector3.new(0, 2.2, 0)), FENCE_POST)
		part(parent, Vector3.new(1.9, 0.6, 1.9), cf * CFrame.new(p + Vector3.new(0, 4.6, 0)), FENCE_POST:Lerp(Color3.new(1, 1, 1), 0.2))
	end
	for _, h in { 1.6, 3.3 } do
		local mid = (a + b) / 2 + Vector3.new(0, h, 0)
		part(parent, Vector3.new(0.5, 0.6, len), cf * CFrame.lookAt(mid, b + Vector3.new(0, h, 0)), FENCE_RAIL)
	end
end

-- Where an item stands in the plot (pen space).
local function spotLocal(key: string, item): Vector3
	local x, z = Formulas.penSpot(key, item)
	return Vector3.new(x, 0, z)
end

local function buildPen(index: number, info)
	local cf: CFrame = info.cf
	local model = Instance.new("Model")
	model.Name = "Pen" .. index
	local W, D = World.PenWidth / 2, World.PenDepth / 2

	-- Checkered pen floor.
	local cols, rows = 6, 6
	local tw, td = W * 2 / cols, D * 2 / rows
	for ix = 0, cols - 1 do
		for iz = 0, rows - 1 do
			local color = (ix + iz) % 2 == 0 and Color3.fromRGB(122, 220, 92) or Color3.fromRGB(110, 208, 80)
			local center = Vector3.new(-W + (ix + 0.5) * tw, 0.1, -D + (iz + 0.5) * td)
			part(model, Vector3.new(tw, 0.2, td), cf * CFrame.new(center), color, Enum.Material.SmoothPlastic)
		end
	end

	-- Fence with a gate gap at the front (local -Z faces the beach).
	local gate = Config.Pen.Gate

	-- Landmarks the client guide arrows point at.
	model:SetAttribute("Center", cf.Position)
	model:SetAttribute("Frame", cf)
	model:SetAttribute("Gate", (cf * CFrame.new(0, 0, -D - 3)).Position)
	model:SetAttribute("Pad", (cf * CFrame.new(Pens.PadLocal)).Position)
	fenceLine(model, cf, Vector3.new(-W, 0, -D), Vector3.new(-gate, 0, -D))
	fenceLine(model, cf, Vector3.new(gate, 0, -D), Vector3.new(W, 0, -D))
	fenceLine(model, cf, Vector3.new(-W, 0, D), Vector3.new(W, 0, D))
	fenceLine(model, cf, Vector3.new(-W, 0, -D), Vector3.new(-W, 0, D))
	fenceLine(model, cf, Vector3.new(W, 0, -D), Vector3.new(W, 0, D))

	-- Owner sign on a pole behind the back fence.
	local pole = part(model, Vector3.new(1, 12, 1), cf * CFrame.new(0, 6, D + 3), FENCE_POST)
	local ownerGui, ownerLabels, ownerTotal = billboard(pole, 7, {
		{ "Empty Base", Color3.new(1, 1, 1), 30 },
		{ "", Color3.fromRGB(120, 255, 120), 24 },
	}, 400, 2.2, 62)
	local face = Instance.new("ImageLabel")
	face.SizeConstraint = Enum.SizeConstraint.RelativeYY
	face.Size = UDim2.fromScale(60 / ownerTotal, 60 / ownerTotal)
	face.BackgroundColor3 = Color3.fromRGB(40, 170, 220)
	face.LayoutOrder = 0
	face.Image = ""
	Instance.new("UICorner", face).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = face
	face.Parent = ownerGui

	-- Training pad (pink disk) with a resting barbell.
	local padCf = cf * CFrame.new(Pens.PadLocal)
	local pad = part(model, Vector3.new(0.7, 13, 13), padCf * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(240, 160, 230), Enum.Material.SmoothPlastic)
	pad.Shape = Enum.PartType.Cylinder
	pad.Name = "TrainPad"
	local ring = part(model, Vector3.new(0.5, 14.5, 14.5), padCf * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 60, 230), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	local barbell = Voxel.barbell(1)
	-- Rests on top of the pad (pad top 0.9 + plate radius 1.1).
	local barbellCf = padCf * CFrame.new(0, 2.05, 0)
	barbell:PivotTo(barbellCf)
	barbell.Name = "PadBarbell"
	barbell.Parent = model
	local _, padLabels = billboard(pad, 4.5, { { "+1 STRENGTH", Color3.fromRGB(255, 220, 60), 30 } }, 90, 1.6)

	-- Weights stall: opens the barbell menu on the owner's client.
	local stallCf = cf * CFrame.new(STALL_LOCAL) -- counter faces the beach
	local stall = Voxel.stall(8, 5, Color3.fromRGB(255, 190, 60))
	stall.Name = "WeightsStall"
	stall:PivotTo(stallCf)
	World.signText(stall:FindFirstChild("Sign") :: BasePart, "WEIGHTS")
	local shelfBar = Voxel.barbell(4)
	shelfBar:ScaleTo(0.55)
	shelfBar:PivotTo(stallCf * CFrame.new(0, 4.2, -1.5))
	shelfBar.Parent = stall
	stall.Parent = model
	local counter = stall:FindFirstChild("Counter") :: BasePart
	local _, upLabels = billboard(counter, 12, {
		{ "Heavier Weight", Color3.new(1, 1, 1), 20 },
		{ "$250", Color3.fromRGB(120, 255, 120), 24 },
	}, 70)
	local upPrompt = Instance.new("ProximityPrompt")
	upPrompt.ActionText = "Browse"
	upPrompt.ObjectText = "Weights"
	upPrompt.HoldDuration = 0
	upPrompt.MaxActivationDistance = 11
	upPrompt.RequiresLineOfSight = false
	upPrompt:SetAttribute("Menu", "Weights")
	upPrompt.Parent = counter

	-- "Upgrade Base" sign.
	local signCf = cf * CFrame.new(BASE_SIGN_LOCAL)
	for _, sx in { -3.2, 3.2 } do
		part(model, Vector3.new(0.8, 5, 0.8), signCf * CFrame.new(sx, 2.5, 0), Color3.fromRGB(70, 75, 90))
	end
	local board = part(model, Vector3.new(7, 3.4, 0.5), signCf * CFrame.new(0, 3.8, 0), Color3.fromRGB(90, 95, 110))
	board.Name = "BaseSign"
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front -- faces the beach
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 40
	signGui.LightInfluence = 0
	signGui.Parent = board
	local signList = Instance.new("UIListLayout")
	signList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	signList.VerticalAlignment = Enum.VerticalAlignment.Center
	signList.SortOrder = Enum.SortOrder.LayoutOrder
	signList.Parent = signGui
	local signTitle = label(signGui, "Upgrade Base", Color3.new(1, 1, 1), 40, 1)
	local signInfo = label(signGui, "", Color3.fromRGB(255, 230, 120), 34, 2)
	local signCost = label(signGui, "", Color3.fromRGB(120, 255, 120), 40, 3)
	signTitle.Size = UDim2.new(1, 0, 0, 44)
	local basePrompt = Instance.new("ProximityPrompt")
	basePrompt.ActionText = "Upgrade Base"
	basePrompt.ObjectText = "+2 Slots"
	basePrompt.HoldDuration = 0.3
	basePrompt.MaxActivationDistance = 10
	basePrompt.RequiresLineOfSight = false
	basePrompt.Parent = board

	local contents = Instance.new("Folder")
	contents.Name = "Contents"
	contents.Parent = model

	model.Parent = workspace:WaitForChild("Pens")

	local pen = {
		index = index,
		cf = cf,
		model = model,
		owner = nil :: Player?,
		ownerLabels = ownerLabels,
		face = face,
		padLabels = padLabels,
		barbell = barbell,
		barbellCf = barbellCf,
		barbellShown = true,
		upLabels = upLabels,
		upPrompt = upPrompt,
		signInfo = signInfo,
		signCost = signCost,
		basePrompt = basePrompt,
		contents = contents,
		slotModels = {},
	}

	basePrompt.Triggered:Connect(function(player)
		if pen.owner == player then
			Pens.upgradeBase(player)
		end
	end)

	return pen
end

----------------------------------------------------------------------------
-- Rendering pen contents
----------------------------------------------------------------------------
local function setPromptOwner(prompt: ProximityPrompt, player: Player?)
	prompt:SetAttribute("OwnerId", player and player.UserId or 0)
end

-- Animals wander their pen. The server only decides where and when: it
-- publishes each walk as attributes and snaps the root to the destination at
-- the end. Clients animate the hops in between (client/PenAnimals.luau), so
-- movement is smooth and costs one replicated CFrame per walk.
local WALK_SPEED = 9 -- studs per second

local function wander(model: Model, pen, item)
	local root = model.PrimaryPart
	model:SetAttribute("Animal", true)
	model:SetAttribute("Uid", item.uid)
	task.spawn(function()
		task.wait(rng:NextNumber(0, 2))
		while model.Parent do
			local target = Vector3.new(rng:NextNumber(WANDER_MIN.X, WANDER_MAX.X), 0, rng:NextNumber(WANDER_MIN.Z, WANDER_MAX.Z))
			local from = pen.cf:PointToObjectSpace(root.CFrame.Position)
			local flat = Vector3.new(from.X, 0, from.Z)
			local dist = (target - flat).Magnitude
			if dist > 1 then
				local duration = dist / WALK_SPEED
				model:SetAttribute("WalkFrom", pen.cf:PointToWorldSpace(flat))
				model:SetAttribute("WalkTo", pen.cf:PointToWorldSpace(target))
				model:SetAttribute("WalkDuration", duration)
				model:SetAttribute("WalkStart", workspace:GetServerTimeNow())
				task.wait(duration)
				if not model.Parent then
					return
				end
				root.CFrame = pen.cf * (CFrame.lookAt(Vector3.zero, (target - flat).Unit) + target)
			end
			task.wait(rng:NextNumber(1.5, 5))
		end
	end)
end

local function itemSignature(item): string
	if not item then
		return ""
	end
	if item.kind == "egg" then
		return "egg:" .. item.egg .. ":" .. tostring(item.variant) .. ":" .. tostring(item.start) .. ":" .. tostring(item.x) .. ":" .. tostring(item.z)
	end
	return "animal:" .. tostring(item.uid) .. ":" .. item.animal .. ":" .. tostring(item.variant)
end

local function renderSlot(pen, key: string, item)
	local sig = itemSignature(item)
	local current = pen.slotModels[key]
	if current and current.sig == sig then
		return
	end
	if current and current.model then
		current.model:Destroy()
	end
	pen.slotModels[key] = { sig = sig }
	if not item then
		return
	end
	local slotCf = pen.cf * CFrame.new(spotLocal(key, item)) * CFrame.Angles(0, math.pi, 0)
	local model
	if item.kind == "egg" then
		local e = Config.EggById[item.egg]
		model = Voxel.egg(item.egg, item.variant, true)
		model:PivotTo(slotCf)
		local root = model.PrimaryPart
		local lines = {}
		local v = variantLine(item.variant)
		if v then
			table.insert(lines, v)
		end
		table.insert(lines, { e.name, Color3.new(1, 1, 1), 22 })
		table.insert(lines, { e.rarity, rarityColor(e.rarity), 18 })
		table.insert(lines, { "", Color3.fromRGB(120, 255, 120), 20 })
		local _, labels = billboard(root, 4.2 + e.tier * 0.3, lines, 80)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Hatch"
		prompt.ObjectText = e.name
		prompt.HoldDuration = 0.25
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		setPromptOwner(prompt, pen.owner)
		prompt.Parent = root
		prompt.Triggered:Connect(function(player)
			if pen.owner == player then
				Pens.hatch(player, key)
			end
		end)
		pen.slotModels[key].timer = labels[#labels]
		pen.slotModels[key].prompt = prompt
		pen.slotModels[key].item = item
	else
		local a = Config.AnimalById[item.animal]
		model = Voxel.animal(item.animal, item.variant)
		Voxel.weld(model, true)
		model:PivotTo(slotCf)
		local lines = {}
		local v = variantLine(item.variant)
		if v then
			table.insert(lines, v)
		end
		table.insert(lines, { a.name, Color3.new(1, 1, 1), 22 })
		table.insert(lines, { a.rarity, rarityColor(a.rarity), 18 })
		table.insert(lines, { Format.cash(Formulas.animalIncome(item.animal, item.variant)) .. "/s", Color3.fromRGB(120, 255, 120), 20 })
		local _, size = model:GetBoundingBox()
		billboard(model.PrimaryPart, size.Y + 0.6, lines, 80)
		wander(model, pen, item)
	end
	model.Parent = pen.contents
	pen.slotModels[key].model = model
end

----------------------------------------------------------------------------
-- Egg tools: every egg in the inventory is a tool on its owner's hotbar,
-- next to the Sea Staff. Holding one is how you place it.
----------------------------------------------------------------------------
local function eggSig(egg: string, variant: string?): string
	return egg .. ":" .. (variant or "Normal")
end

local function makeEggTool(egg: string, variant: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = (variant ~= "Normal" and variant .. " " or "") .. Config.EggById[egg].name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = "Click a spot in your plot to place it"
	tool:SetAttribute("Egg", egg)
	tool:SetAttribute("Variant", variant)
	-- The egg sits on an invisible handle held in the hand.
	local model = Voxel.egg(egg, variant, false)
	model:PivotTo(CFrame.new())
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new(0, 0.5, 0)
	handle.Parent = tool
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = p
			w.Parent = p
			p.Parent = tool
		end
	end
	model:Destroy()
	return tool
end

-- Make the tools match the stored eggs: one tool per egg.
function Pens.syncEggTools(player: Player)
	local d = Data.get(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not d or not backpack then
		return
	end
	local want: { [string]: number } = {}
	for _, e in d.eggs do
		local sig = eggSig(e.egg, e.variant)
		want[sig] = (want[sig] or 0) + 1
	end
	-- Tools beyond the count are removed. After placing an egg the one in
	-- the hand is the one to go; otherwise the one in the hand is kept.
	local placed = player:GetAttribute("EggPlaced")
	local char = player.Character
	local holders: { Instance } = { backpack }
	if char then
		table.insert(holders, placed and 2 or 1, char)
	end
	for _, holder in holders do
		for _, tool in holder:GetChildren() do
			local egg = tool:IsA("Tool") and tool:GetAttribute("Egg")
			if egg then
				local sig = eggSig(egg, tool:GetAttribute("Variant"))
				if (want[sig] or 0) > 0 then
					want[sig] -= 1
				else
					tool:Destroy()
				end
			end
		end
	end
	player:SetAttribute("EggPlaced", nil)
	for _, e in d.eggs do
		local sig = eggSig(e.egg, e.variant)
		if (want[sig] or 0) > 0 then
			want[sig] -= 1
			makeEggTool(e.egg, e.variant or "Normal").Parent = backpack
		end
	end
end

function Pens.refresh(player: Player)
	Pens.syncEggTools(player)
	local pen = penByPlayer[player]
	local d = Data.get(player)
	if not pen or not d then
		return
	end
	for i = 1, Config.Base.MaxSlots do
		local key = tostring(i)
		renderSlot(pen, key, d.pen[key])
	end
	Pens.refreshSigns(player)
end

function Pens.refreshSigns(player: Player)
	local pen = penByPlayer[player]
	local d = Data.get(player)
	if not pen or not d then
		return
	end
	local w = Config.Weights[d.weightTier]
	local gain = w.gain * (Data.hasPass(player, "DoubleStrength") and 2 or 1)
	pen.padLabels[1].Text = "+" .. Format.short(gain) .. " STRENGTH"
	local nextW = Config.Weights[d.weightTier + 1]
	if nextW then
		pen.upLabels[1].Text = nextW.name
		pen.upLabels[2].Text = Format.cash(nextW.cost)
		pen.upPrompt.Enabled = true
	else
		pen.upLabels[1].Text = "Max Weight!"
		pen.upLabels[2].Text = ""
		pen.upPrompt.Enabled = false
	end
	if pen.barbellTier ~= d.weightTier then
		pen.barbellTier = d.weightTier
		pen.barbell:Destroy()
		pen.barbell = Voxel.barbell(d.weightTier)
		pen.barbell.Name = "PadBarbell"
		pen.barbell:PivotTo(pen.barbellCf)
		pen.barbell.Parent = pen.barbellShown and pen.model or nil
	end
	if d.baseSlots >= Config.Base.MaxSlots then
		pen.signInfo.Text = d.baseSlots .. " slots (max)"
		pen.signCost.Text = ""
		pen.basePrompt.Enabled = false
	else
		pen.signInfo.Text = d.baseSlots .. " -> " .. (d.baseSlots + Config.Base.SlotsPerLevel) .. " slots"
		pen.signCost.Text = Format.cash(Formulas.baseCost(d.baseSlots))
		pen.basePrompt.Enabled = true
	end
end

----------------------------------------------------------------------------
-- Inventory / slots
----------------------------------------------------------------------------
local function freeSlot(d): string?
	for i = 1, d.baseSlots do
		local key = tostring(i)
		if d.pen[key] == nil then
			return key
		end
	end
	return nil
end

-- Record an animal in the Index (each variant is its own entry).
local function discover(player: Player, animalId: string, variant: string?)
	local d = Data.get(player)
	local key = Formulas.indexKey(animalId, variant)
	if d.index[key] == nil then
		local before = Formulas.indexCompleted(d.index)
		d.index[key] = 1
		Data.effect(player, "discover", { animal = animalId, variant = variant or "Normal", completedEgg = Formulas.indexCompleted(d.index) > before })
	end
end

local function changed(player: Player)
	Data.markDirty(player)
	Pens.refresh(player)
end

-- Incubation starts when the egg is put down at (x, z) in the plot.
function Pens.placeEggItem(player: Player, egg: string, variant: string, key: string, x: number, z: number)
	local d = Data.get(player)
	d.pen[key] = {
		kind = "egg",
		egg = egg,
		variant = variant,
		start = os.time(),
		dur = Formulas.hatchSeconds(egg, Data.hasPass(player, "FastHatch")),
		x = x,
		z = z,
	}
end

-- New egg from a run or reward: it goes into the Eggs inventory, and its
-- owner places it in their plot wherever they like.
function Pens.addEgg(player: Player, egg: string, variant: string?): string
	local d = Data.get(player)
	variant = variant or "Normal"
	local where
	if #d.eggs < Config.MaxStoredEggs then
		table.insert(d.eggs, { egg = egg, variant = variant })
		where = "storage"
	else
		local price = Formulas.eggSellPrice(egg, variant)
		Data.addCash(player, price)
		Data.notify(player, "Egg storage full! Sold it for " .. Format.cash(price))
		where = "sold"
	end
	changed(player)
	return where
end

function Pens.addAnimal(player: Player, animal: string, variant: string?): string
	local d = Data.get(player)
	variant = variant or "Normal"
	discover(player, animal, variant)
	local item = { uid = Data.newUid(player), animal = animal, variant = variant }
	local key = freeSlot(d)
	local where
	if key then
		item.kind = "animal"
		d.pen[key] = item
		where = "pen"
	elseif #d.animals < Config.MaxStoredAnimals then
		table.insert(d.animals, item)
		where = "storage"
	else
		local price = Formulas.animalSellPrice(animal, variant)
		Data.addCash(player, price)
		Data.notify(player, "Pet storage full! Sold it for " .. Format.cash(price))
		where = "sold"
	end
	changed(player)
	return where
end

function Pens.hatch(player: Player, key: string): boolean
	local d = Data.get(player)
	local item = d and d.pen[key]
	if not item or item.kind ~= "egg" or os.time() < item.start + item.dur then
		return false
	end
	local animal = Formulas.rollAnimal(rng, item.egg, Data.luck(player))
	local variant = item.variant or "Normal"
	discover(player, animal, variant)
	local uid = Data.newUid(player)
	-- The animal starts where its egg stood.
	d.pen[key] = { kind = "animal", uid = uid, animal = animal, variant = variant, x = item.x, z = item.z }
	d.stats.hatched += 1
	-- The uid lets the owner's client keep the new animal hidden in the pen
	-- until their hatch cutscene has revealed it.
	Data.effect(player, "hatch", { egg = item.egg, animal = animal, variant = variant, uid = uid })
	changed(player)
	return true
end

function Pens.hatchAllReady(player: Player): number
	local d = Data.get(player)
	local n = 0
	for i = 1, Config.Base.MaxSlots do
		if Pens.hatch(player, tostring(i)) then
			n += 1
		end
	end
	if n == 0 and d then
		Data.notify(player, "No eggs are ready yet!")
	end
	return n
end

function Pens.instantHatch(player: Player)
	local d = Data.get(player)
	for _, item in d.pen do
		if item.kind == "egg" then
			item.start = 0
		end
	end
	changed(player)
end

-- Put a stored egg down at a spot the player picked inside their own plot.
function Pens.placeStoredEgg(player: Player, index: number, worldPos: Vector3): (boolean, string?)
	local d = Data.get(player)
	local pen = penByPlayer[player]
	local e = d.eggs[index]
	if not e or not pen then
		return false, "That egg is gone."
	end
	local key = freeSlot(d)
	if not key then
		return false, "Your base is full! Upgrade it for more slots."
	end
	local p = pen.cf:PointToObjectSpace(worldPos)
	local ok, why = Formulas.canPlaceEgg(d.pen, p.X, p.Z)
	if not ok then
		return false, why
	end
	table.remove(d.eggs, index)
	player:SetAttribute("EggPlaced", true) -- the egg in the hand is the one that goes
	Pens.placeEggItem(player, e.egg, e.variant, key, p.X, p.Z)
	changed(player)
	return true
end

function Pens.placeStoredAnimal(player: Player, uid: number): (boolean, string?)
	local d = Data.get(player)
	for i, a in d.animals do
		if a.uid == uid then
			local key = freeSlot(d)
			if not key then
				return false, "Your base is full! Upgrade it for more slots."
			end
			table.remove(d.animals, i)
			a.kind = "animal"
			d.pen[key] = a
			changed(player)
			return true
		end
	end
	return false, "That pet is gone."
end

-- Fill the base with the highest-earning animals from the base + storage.
-- Incubating eggs keep their slots.
function Pens.placeBest(player: Player): (boolean, string?)
	local d = Data.get(player)
	local pool = {}
	local openSlots = {}
	for i = 1, d.baseSlots do
		local key = tostring(i)
		local item = d.pen[key]
		if item == nil then
			table.insert(openSlots, key)
		elseif item.kind == "animal" then
			table.insert(pool, { uid = item.uid, animal = item.animal, variant = item.variant })
			table.insert(openSlots, key)
		end
	end
	for _, a in d.animals do
		table.insert(pool, { uid = a.uid, animal = a.animal, variant = a.variant })
	end
	if #pool == 0 then
		return false, "You don't have any pets yet!"
	end
	local before = Data.income(player)
	table.sort(pool, function(x, y)
		local ix, iy = Formulas.animalIncome(x.animal, x.variant), Formulas.animalIncome(y.animal, y.variant)
		if ix ~= iy then
			return ix > iy
		end
		return x.uid < y.uid
	end)
	local rest = {}
	for i, a in pool do
		local key = openSlots[i]
		if key then
			d.pen[key] = { kind = "animal", uid = a.uid, animal = a.animal, variant = a.variant }
		else
			table.insert(rest, a)
		end
	end
	for i = #pool + 1, #openSlots do
		d.pen[openSlots[i]] = nil
	end
	d.animals = rest
	changed(player)
	local after = Data.income(player)
	if after > before then
		return true, "Best pets placed! Income " .. Format.cash(before) .. " -> " .. Format.cash(after) .. "/s"
	end
	return true, "Your best pets are already in your base."
end

function Pens.storeAnimal(player: Player, key: string): (boolean, string?)
	local d = Data.get(player)
	local item = d.pen[key]
	if not item or item.kind ~= "animal" then
		return false
	end
	if #d.animals >= Config.MaxStoredAnimals then
		return false, "Pet storage is full."
	end
	d.pen[key] = nil
	table.insert(d.animals, { uid = item.uid, animal = item.animal, variant = item.variant })
	changed(player)
	return true
end

function Pens.sellAnimal(player: Player, where: string, id: any): (boolean, string?)
	local d = Data.get(player)
	local item
	if where == "pen" then
		item = d.pen[tostring(id)]
		if not item or item.kind ~= "animal" then
			return false
		end
		d.pen[tostring(id)] = nil
	else
		for i, a in d.animals do
			if a.uid == id then
				item = table.remove(d.animals, i)
				break
			end
		end
		if not item then
			return false
		end
	end
	local price = Formulas.animalSellPrice(item.animal, item.variant)
	Data.addCash(player, price)
	changed(player)
	return true, "Sold " .. item.animal .. " for " .. Format.cash(price)
end

function Pens.sellStoredEgg(player: Player, index: number): (boolean, string?)
	local d = Data.get(player)
	local e = d.eggs[index]
	if not e then
		return false
	end
	table.remove(d.eggs, index)
	local price = Formulas.eggSellPrice(e.egg, e.variant)
	Data.addCash(player, price)
	changed(player)
	return true, "Sold " .. Config.EggById[e.egg].name .. " for " .. Format.cash(price)
end

function Pens.sellAllStored(player: Player): (boolean, string?)
	local d = Data.get(player)
	local total = 0
	for _, a in d.animals do
		total += Formulas.animalSellPrice(a.animal, a.variant)
	end
	for _, e in d.eggs do
		total += Formulas.eggSellPrice(e.egg, e.variant)
	end
	if total == 0 then
		return false, "Nothing in storage to sell."
	end
	table.clear(d.animals)
	table.clear(d.eggs)
	Data.addCash(player, total)
	changed(player)
	return true, "Sold everything in storage for " .. Format.cash(total)
end

function Pens.upgradeBase(player: Player): (boolean, string?)
	local d = Data.get(player)
	if not d then
		return false
	end
	if d.baseSlots >= Config.Base.MaxSlots then
		return false, "Your base is already max size!"
	end
	local cost = Formulas.baseCost(d.baseSlots)
	if not Data.trySpend(player, cost) then
		Data.notify(player, "You need " .. Format.cash(cost) .. " to upgrade your base.", Color3.fromRGB(255, 100, 100))
		return false
	end
	d.baseSlots = math.min(Config.Base.MaxSlots, d.baseSlots + Config.Base.SlotsPerLevel)
	Data.notify(player, "Base upgraded! " .. d.baseSlots .. " slots.", Color3.fromRGB(120, 255, 120))
	changed(player)
	return true
end

----------------------------------------------------------------------------
-- Assignment / teleport
----------------------------------------------------------------------------
function Pens.get(player: Player)
	return penByPlayer[player]
end

-- The barbell rests on the pad when nobody is using it and disappears from
-- there while its owner has it in their hands.
function Pens.showPadBarbell(player: Player, shown: boolean)
	local pen = penByPlayer[player]
	if pen then
		pen.barbellShown = shown
		pen.barbell.Parent = shown and pen.model or nil
	end
end

-- Is this position inside the player's own base?
function Pens.contains(player: Player, pos: Vector3): boolean
	local pen = penByPlayer[player]
	if not pen then
		return false
	end
	local p = pen.cf:PointToObjectSpace(pos)
	return math.abs(p.X) <= World.PenWidth / 2 and math.abs(p.Z) <= World.PenDepth / 2
end

function Pens.homeCFrame(player: Player): CFrame?
	local pen = penByPlayer[player]
	return pen and pen.cf * CFrame.new(0, 4, -27)
end

function Pens.teleportHome(player: Player)
	local cf = Pens.homeCFrame(player)
	local char = player.Character
	if cf and char then
		char:PivotTo(cf)
	end
end

local function assign(player: Player)
	for _, pen in pens do
		if not pen.owner then
			pen.owner = player
			penByPlayer[player] = pen
			pen.model:SetAttribute("OwnerId", player.UserId)
			pen.ownerLabels[1].Text = player.DisplayName .. "'s Base"
			setPromptOwner(pen.upPrompt, player)
			setPromptOwner(pen.basePrompt, player)
			task.spawn(function()
				local ok, img = pcall(function()
					return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				end)
				if ok and pen.owner == player then
					pen.face.Image = img
				end
			end)
			return pen
		end
	end
	return nil
end

local function unassign(player: Player)
	local pen = penByPlayer[player]
	if not pen then
		return
	end
	penByPlayer[player] = nil
	pen.owner = nil
	pen.model:SetAttribute("OwnerId", 0)
	pen.ownerLabels[1].Text = "Empty Base"
	pen.ownerLabels[2].Text = ""
	pen.face.Image = ""
	setPromptOwner(pen.upPrompt, nil)
	setPromptOwner(pen.basePrompt, nil)
	pen.contents:ClearAllChildren()
	table.clear(pen.slotModels)
	pen.barbellShown = true
	pen.barbell.Parent = pen.model
	pen.padLabels[1].Text = ""
	pen.upLabels[1].Text = ""
	pen.upLabels[2].Text = ""
	pen.signInfo.Text = ""
	pen.signCost.Text = ""
end

local function grantOffline(player: Player)
	local d = Data.get(player)
	if not d or d.lastOnline <= 0 then
		return
	end
	local away = os.time() - d.lastOnline
	if away < Config.Offline.MinSeconds then
		return
	end
	local secs = math.min(away, Config.Offline.MaxSeconds)
	local earned = math.floor(Data.income(player) * secs * Config.Offline.Rate)
	if earned > 0 then
		Data.addCash(player, earned)
		Data.effect(player, "offline", { cash = earned, seconds = secs })
	end
end

----------------------------------------------------------------------------
-- Loops
----------------------------------------------------------------------------
local function tickTimers()
	local now = os.time()
	for _, pen in pens do
		if pen.owner then
			for _, slot in pen.slotModels do
				if slot.timer and slot.item then
					local left = slot.item.start + slot.item.dur - now
					if left <= 0 then
						slot.timer.Text = "Ready!"
						slot.timer.TextColor3 = Color3.fromRGB(120, 255, 120)
						slot.prompt.Enabled = true
					else
						slot.timer.Text = Format.time(left)
						slot.timer.TextColor3 = Color3.fromRGB(255, 230, 120)
						slot.prompt.Enabled = false
					end
				end
			end
		end
	end
end

local function tickIncome()
	for _, player in Players:GetPlayers() do
		local d = Data.get(player)
		if d then
			local inc = Data.income(player)
			local pen = penByPlayer[player]
			if pen then
				pen.ownerLabels[2].Text = Format.cash(inc) .. "/s"
			end
			if inc > 0 then
				Data.addCash(player, inc)
				Data.effect(player, "income", inc)
			end
		end
	end
end

function Pens.init()
	local folder = Instance.new("Folder")
	folder.Name = "Pens"
	folder.Parent = workspace
	for i, info in World.Pens do
		pens[i] = buildPen(i, info)
	end

	Data.Loaded.Event:Connect(function(player: Player)
		local pen = assign(player)
		if not pen then
			Data.notify(player, "The server is full of bases! Try another server.", Color3.fromRGB(255, 90, 90))
			Pens.syncEggTools(player)
			return
		end
		Pens.refresh(player)
		Pens.teleportHome(player)
		task.delay(4, grantOffline, player)
	end)

	Players.PlayerRemoving:Connect(unassign)

	local function onCharacter(player: Player, char: Model)
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.1)
		Pens.syncEggTools(player) -- a respawn empties the hotbar
		if penByPlayer[player] then
			Pens.teleportHome(player)
		end
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			tickIncome()
			tickTimers()
		end
	end)
end

return Pens
