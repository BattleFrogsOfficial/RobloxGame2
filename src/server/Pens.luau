-- Player pens ("bases"): assignment, building, eggs incubating in slots,
-- animals wandering and earning, hatching, inventory moves, income.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
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

local SLOT_COLS = { -28, -14, 0, 14, 28 }
local SLOT_ROWS = { 4, 13, 22, 31 }
local WANDER_MIN = Vector3.new(-34, 0, -8)
local WANDER_MAX = Vector3.new(34, 0, 33)
Pens.PadLocal = Vector3.new(-22, 0, -22)
local UPGRADE_PAD_LOCAL = Vector3.new(-6, 0, -29)
local BASE_SIGN_LOCAL = Vector3.new(26, 0, -28)

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

local function billboard(adornee: BasePart, offsetY: number, lines: { { string | Color3 | number } }, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 22 * #lines)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 70
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = gui
	local labels = {}
	for i, line in lines do
		labels[i] = label(gui, line[1] :: string, line[2] :: Color3, (line[3] or 20) :: number, i)
	end
	gui.Parent = adornee
	return gui, labels
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
		local rail = part(parent, Vector3.new(0.5, 0.6, len), cf * CFrame.lookAt(mid, b + Vector3.new(0, h, 0)), FENCE_RAIL)
		rail.CanCollide = false
	end
end

local function slotLocal(i: number): Vector3
	local col = (i - 1) % #SLOT_COLS + 1
	local row = (i - 1) // #SLOT_COLS + 1
	return Vector3.new(SLOT_COLS[col], 0, SLOT_ROWS[row])
end

local function buildPen(index: number, info)
	local cf: CFrame = info.cf
	local model = Instance.new("Model")
	model.Name = "Pen" .. index
	local W, D = World.PenWidth / 2, World.PenDepth / 2

	part(model, Vector3.new(W * 2, 0.2, D * 2), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(115, 215, 85), Enum.Material.Plastic).TopSurface = Enum.SurfaceType.Studs

	-- Fence with a gate gap at the front (local -Z faces the beach).
	local gate = 9
	fenceLine(model, cf, Vector3.new(-W, 0, -D), Vector3.new(-gate, 0, -D))
	fenceLine(model, cf, Vector3.new(gate, 0, -D), Vector3.new(W, 0, -D))
	fenceLine(model, cf, Vector3.new(-W, 0, D), Vector3.new(W, 0, D))
	fenceLine(model, cf, Vector3.new(-W, 0, -D), Vector3.new(-W, 0, D))
	fenceLine(model, cf, Vector3.new(W, 0, -D), Vector3.new(W, 0, D))

	-- Owner sign on a pole behind the back fence.
	local pole = part(model, Vector3.new(1, 12, 1), cf * CFrame.new(0, 6, D + 3), FENCE_POST)
	local ownerGui, ownerLabels = billboard(pole, 9, {
		{ "Empty Base", Color3.new(1, 1, 1), 28 },
		{ "", Color3.fromRGB(120, 255, 120), 22 },
	}, 400)
	ownerGui.Size = UDim2.fromOffset(240, 120)
	ownerLabels[1].Size = UDim2.new(1, 0, 0, 30)
	local face = Instance.new("ImageLabel")
	face.Size = UDim2.fromOffset(60, 60)
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
	local pad = part(model, Vector3.new(0.4, 13, 13), padCf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(240, 160, 230), Enum.Material.SmoothPlastic)
	pad.Shape = Enum.PartType.Cylinder
	pad.Name = "TrainPad"
	local ring = part(model, Vector3.new(0.3, 14, 14), padCf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 60, 230), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	local barbell = Voxel.barbell(1)
	barbell:PivotTo(padCf * CFrame.new(0, 1.6, 2))
	barbell.Name = "PadBarbell"
	barbell.Parent = model
	local _, padLabels = billboard(pad, 5, { { "+1 STRENGTH", Color3.fromRGB(255, 220, 60), 30 } }, 80)

	-- Weight upgrade pad (yellow).
	local upCf = cf * CFrame.new(UPGRADE_PAD_LOCAL)
	local upPad = part(model, Vector3.new(0.4, 7, 7), upCf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 220, 60), Enum.Material.SmoothPlastic)
	upPad.Shape = Enum.PartType.Cylinder
	upPad.Name = "UpgradePad"
	local _, upLabels = billboard(upPad, 3.5, {
		{ "Heavier Weight", Color3.new(1, 1, 1), 20 },
		{ "$250", Color3.fromRGB(120, 255, 120), 24 },
	}, 60)
	local upPrompt = Instance.new("ProximityPrompt")
	upPrompt.ActionText = "Buy Weight"
	upPrompt.ObjectText = "Upgrades"
	upPrompt.HoldDuration = 0.2
	upPrompt.MaxActivationDistance = 9
	upPrompt.RequiresLineOfSight = false
	upPrompt.Parent = upPad

	-- "Upgrade Base" sign.
	local signCf = cf * CFrame.new(BASE_SIGN_LOCAL)
	for _, sx in { -3.2, 3.2 } do
		part(model, Vector3.new(0.8, 5, 0.8), signCf * CFrame.new(sx, 2.5, 0), Color3.fromRGB(70, 75, 90))
	end
	local board = part(model, Vector3.new(7, 3.4, 0.5), signCf * CFrame.new(0, 3.8, 0), Color3.fromRGB(90, 95, 110))
	board.Name = "BaseSign"
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Back
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

	local slotsFolder = Instance.new("Folder")
	slotsFolder.Name = "Slots"
	slotsFolder.Parent = model
	local contents = Instance.new("Folder")
	contents.Name = "Contents"
	contents.Parent = model

	model.Parent = workspace:WaitForChild("Pens")

	local pen = {
		index = index,
		cf = cf,
		side = info.side,
		model = model,
		owner = nil :: Player?,
		ownerLabels = ownerLabels,
		face = face,
		padLabels = padLabels,
		barbell = barbell,
		upLabels = upLabels,
		upPrompt = upPrompt,
		signInfo = signInfo,
		signCost = signCost,
		basePrompt = basePrompt,
		slotsFolder = slotsFolder,
		contents = contents,
		slotModels = {},
	}

	upPrompt.Triggered:Connect(function(player)
		if pen.owner == player and Pens.callbacks.buyWeight then
			Pens.callbacks.buyWeight(player)
		end
	end)
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

local function wander(model: Model, pen)
	local root = model.PrimaryPart
	task.spawn(function()
		task.wait(rng:NextNumber(0, 2))
		while model.Parent do
			local target = Vector3.new(rng:NextNumber(WANDER_MIN.X, WANDER_MAX.X), 0, rng:NextNumber(WANDER_MIN.Z, WANDER_MAX.Z))
			local from = pen.cf:PointToObjectSpace(root.Position)
			local flat = Vector3.new(from.X, 0, from.Z)
			local dist = (target - flat).Magnitude
			if dist > 1 then
				local goal = pen.cf * CFrame.lookAt(target, target + (target - flat).Unit)
				-- Turn first, then walk.
				local turn = TweenService:Create(root, TweenInfo.new(0.35), { CFrame = CFrame.new(root.Position) * goal.Rotation })
				turn:Play()
				task.wait(0.35)
				if not model.Parent then
					break
				end
				local walk = TweenService:Create(root, TweenInfo.new(dist / 5, Enum.EasingStyle.Linear), { CFrame = goal })
				walk:Play()
				task.wait(dist / 5)
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
		return "egg:" .. item.egg .. ":" .. tostring(item.variant) .. ":" .. tostring(item.start)
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
	local slotCf = pen.cf * CFrame.new(slotLocal(tonumber(key) :: number)) * CFrame.Angles(0, math.pi, 0)
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
		local _, labels = billboard(root, 5 + e.tier * 0.3, lines, 70)
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
		billboard(model.PrimaryPart, size.Y + 2, lines, 60)
		wander(model, pen)
	end
	model.Parent = pen.contents
	pen.slotModels[key].model = model
end

local function renderSlotPads(pen, slots: number)
	pen.slotsFolder:ClearAllChildren()
	for i = 1, slots do
		local p = part(pen.slotsFolder, Vector3.new(7, 0.1, 7), pen.cf * CFrame.new(slotLocal(i) + Vector3.new(0, 0.22, 0)), Color3.fromRGB(235, 215, 160), Enum.Material.SmoothPlastic)
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 0.25
	end
end

function Pens.refresh(player: Player)
	local pen = penByPlayer[player]
	local d = Data.get(player)
	if not pen or not d then
		return
	end
	if #pen.slotsFolder:GetChildren() ~= d.baseSlots then
		renderSlotPads(pen, d.baseSlots)
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
		local cf = pen.barbell:GetPivot()
		pen.barbell:Destroy()
		pen.barbell = Voxel.barbell(d.weightTier)
		pen.barbell.Name = "PadBarbell"
		pen.barbell:PivotTo(cf)
		pen.barbell.Parent = pen.model
	end
	if d.baseSlots >= Config.Base.MaxSlots then
		pen.signInfo.Text = d.baseSlots .. " slots (max)"
		pen.signCost.Text = ""
		pen.basePrompt.Enabled = false
	else
		pen.signInfo.Text = d.baseSlots .. " → " .. (d.baseSlots + Config.Base.SlotsPerLevel) .. " slots"
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

local function discover(player: Player, animalId: string)
	local d = Data.get(player)
	if d.index[animalId] == nil then
		d.index[animalId] = 1
		Data.effect(player, "discover", { animal = animalId })
	end
end

local function changed(player: Player)
	Data.markDirty(player)
	Pens.refresh(player)
end

function Pens.placeEggItem(player: Player, egg: string, variant: string, key: string)
	local d = Data.get(player)
	d.pen[key] = {
		kind = "egg",
		egg = egg,
		variant = variant,
		start = os.time(),
		dur = Formulas.hatchSeconds(egg, Data.hasPass(player, "FastHatch")),
	}
end

-- New egg from a run or reward: incubate if there's room, else store.
function Pens.addEgg(player: Player, egg: string, variant: string?): string
	local d = Data.get(player)
	variant = variant or "Normal"
	local key = freeSlot(d)
	local where
	if key then
		Pens.placeEggItem(player, egg, variant :: string, key)
		where = "pen"
	elseif #d.eggs < Config.MaxStoredEggs then
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
	discover(player, animal)
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
	discover(player, animal)
	d.pen[key] = { kind = "animal", uid = Data.newUid(player), animal = animal, variant = variant }
	d.stats.hatched += 1
	Data.effect(player, "hatch", { egg = item.egg, animal = animal, variant = variant })
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

function Pens.placeStoredEgg(player: Player, index: number): (boolean, string?)
	local d = Data.get(player)
	local e = d.eggs[index]
	if not e then
		return false, "That egg is gone."
	end
	local key = freeSlot(d)
	if not key then
		return false, "Your base is full! Upgrade it for more slots."
	end
	table.remove(d.eggs, index)
	Pens.placeEggItem(player, e.egg, e.variant, key)
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
	pen.slotsFolder:ClearAllChildren()
	table.clear(pen.slotModels)
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
