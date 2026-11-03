--!nonstrict
-- Yards and owned dogs: yard assignment (1-6) on join, YardSign owner text, slots + held dogs,
-- adding/selling dogs, dupe auto-sell (with a short Keep window), puppy -> adult growth, the 1 s
-- income tick, offline earnings (capped), the top-12 roaming display on DogSpots and the kennel sign.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
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
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))
local Signal = require(Util:WaitForChild("Signal"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local BroadcastService = require(script.Parent:WaitForChild("BroadcastService"))

local DogService = {}

DogService.YardAssigned = Signal.new() -- (player, yardIndex)
DogService.YardFreed = Signal.new() -- (yardIndex)
DogService.DogAdded = Signal.new() -- (player, dogRecord, status)

local yardOwner: { [number]: Player } = {}
local playerYard: { [Player]: number } = {}
local yardModels: { [number]: { [string]: Model } } = {} -- yard -> uid -> model
local lastPuppyCount: { [Player]: number } = {}
local lastIncome: { [Player]: number } = {}
local pendingSales: { [string]: { Player: Player, At: number } } = {}

local dogsRoot: Folder = nil

----------------------------------------------------------------------------------------------------
-- World lookups (tags created by the world builder; Layout fallbacks if absent)
----------------------------------------------------------------------------------------------------
local function findTagged(tag: string, attr: string, value: any): { Instance }
	local out = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:GetAttribute(attr) == value then
			table.insert(out, inst)
		end
	end
	return out
end

local function partPosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		-- thin marker -> stand on top of it; tall (invisible volume) -> stand at its bottom
		local dy = if inst.Size.Y <= 4 then inst.Size.Y / 2 else -inst.Size.Y / 2
		return inst.Position + Vector3.new(0, dy, 0)
	elseif inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y / 2, 0)
	elseif inst:IsA("Attachment") then
		return inst.WorldPosition
	end
	return nil
end

function DogService.GetYardCenter(index: number): Vector3
	return Vector3.new(Layout.Yards.CentersX[index] or 0, Layout.HubY, Layout.Yards.CenterZ) -- yards are on the plateau
end

-- Position for spot 1..12 of a yard: tagged DogSpot if present, else a 4x3 grid in the yard.
local function spotPosition(yard: number, spot: number): Vector3
	for _, inst in findTagged("DogSpot", "YardIndex", yard) do
		if inst:GetAttribute("SpotIndex") == spot then
			local p = partPosition(inst)
			if p then
				return p
			end
		end
	end
	local c = DogService.GetYardCenter(yard)
	local col = (spot - 1) % 4
	local row = (spot - 1) // 4
	return c + Vector3.new(-30 + col * 20, 0, -20 + row * 20)
end

local function setLabel(tag: string, yard: number, labelName: string, text: string)
	for _, inst in findTagged(tag, "YardIndex", yard) do
		local label = inst:FindFirstChild(labelName, true)
		if label and label:IsA("TextLabel") then
			label.Text = text
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Dog models
----------------------------------------------------------------------------------------------------
local factory: any = nil
local factoryTried = false
local function getFactory(): any
	if factoryTried then
		return factory
	end
	factoryTried = true
	local folder = Shared:FindFirstChild("Dog")
	local mod = folder and folder:FindFirstChild("DogFactory")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok and type(result) == "table" then
			factory = result
		else
			warn("[DogService] DogFactory failed to load, using block dogs: " .. tostring(result))
		end
	else
		warn("[DogService] Shared.Dog.DogFactory not found, using block dogs")
	end
	return factory
end

local function hexColor(hex: any, fallback: Color3): Color3
	if type(hex) == "string" then
		local ok, c = pcall(Color3.fromHex, hex)
		if ok then
			return c
		end
	end
	return fallback
end

local function blockDog(def: any, variant: string?, isPuppy: boolean): Model
	local model = Instance.new("Model")
	model.Name = def.Name
	local s = (tonumber(def.Scale) or 1) * (if isPuppy then 0.6 else 1)
	local coat = hexColor(def.CoatPrimary, Color3.fromRGB(200, 160, 110))
	local accent = hexColor(def.CoatSecondary, Color3.new(1, 1, 1))
	if variant == "Gold" then
		coat = Color3.fromRGB(255, 200, 60)
	elseif variant == "Shadow" then
		coat = Color3.fromRGB(25, 20, 30)
	elseif variant == "Rainbow" then
		coat = Color3.fromHSV(math.random(), 0.8, 1)
	end
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.CFrame = CFrame.new(offset * s)
		p.Color = color
		p.Material = if variant == "Gold" then Enum.Material.Metal else Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local body = part("Body", Vector3.new(2, 1.6, 3.4), Vector3.new(0, 2.2, 0), coat)
	part("Head", Vector3.new(1.6, 1.5, 1.5), Vector3.new(0, 3.1, 2.1), coat)
	part("Snout", Vector3.new(0.9, 0.7, 0.8), Vector3.new(0, 2.8, 3.1), accent)
	for i, o in { Vector3.new(-0.6, 0.7, 1.2), Vector3.new(0.6, 0.7, 1.2), Vector3.new(-0.6, 0.7, -1.2),
		Vector3.new(0.6, 0.7, -1.2) } do
		part("Leg" .. i, Vector3.new(0.5, 1.4, 0.5), o, accent)
	end
	part("Tail", Vector3.new(0.3, 0.3, 1.2), Vector3.new(0, 2.8, -2.1), coat)
	model.PrimaryPart = body
	return model
end

-- Builds a dog model. Uses Shared.Dog.DogFactory.Build(def, {Variant, IsPuppy}) when available.
function DogService.BuildModel(def: any, variant: string?, isPuppy: boolean): Model
	local f = getFactory()
	if f then
		local fn = f.Build or f.Create or f.new
		if type(fn) == "function" then
			local ok, model = pcall(fn, def, { Variant = variant, IsPuppy = isPuppy, Puppy = isPuppy })
			if ok and typeof(model) == "Instance" and model:IsA("Model") then
				return model
			elseif not ok then
				warn("[DogService] DogFactory.Build error for " .. tostring(def.Id) .. ": " .. tostring(model))
			end
		end
	end
	return blockDog(def, variant, isPuppy)
end

-- Place a model so its bounding box bottom rests at pos.Y, facing `yaw` radians.
function DogService.PlaceModel(model: Model, pos: Vector3, yaw: number?)
	local anchoredAny = false
	if model.PrimaryPart then
		model.PrimaryPart.Anchored = true
		anchoredAny = true
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = true
			if not anchoredAny then
				d.Anchored = true
			end
		end
	end
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0))
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, pos.Y - bottom, 0))
end

function DogService.AddNameplate(model: Model, title: string, subtitle: string, color: Color3)
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then
		return
	end
	local _, size = model:GetBoundingBox()
	local gui = Instance.new("BillboardGui")
	gui.Name = "DogNameplate"
	gui.Size = UDim2.fromOffset(180, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.5, 0)
	gui.MaxDistance = 80
	gui.AlwaysOnTop = false
	gui.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0.55, 0)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.4
	t.Text = title
	t.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 0, 0.55, 0)
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextStrokeTransparency = 0.4
	sub.Text = subtitle
	sub.Parent = gui
	gui.Parent = model
end

local function yardFolder(yard: number): Folder
	local name = "Yard_" .. yard
	local f = dogsRoot:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = dogsRoot
	end
	return f :: Folder
end

local function clearYardModels(yard: number)
	local models = yardModels[yard]
	if models then
		for _, m in models do
			m:Destroy()
		end
	end
	yardModels[yard] = {}
end

----------------------------------------------------------------------------------------------------
-- Dog records
----------------------------------------------------------------------------------------------------
function DogService.FindDog(state: any, uid: string): (any, number?)
	for i, d in state.Dogs do
		if d.Uid == uid then
			return d, i
		end
	end
	return nil, nil
end

local function earningCount(state: any): number
	local n = 0
	for _, d in state.Dogs do
		if not d.Held and not d.PendingSale then
			n += 1
		end
	end
	return n
end

local function growthSpeed(player: Player): number
	local speed = 1
	local passes = DataService.GetPasses(player)
	for key, pass in Products.GamePasses do
		if pass.GrowthSpeed and passes[key] then
			speed *= pass.GrowthSpeed
		end
	end
	return speed
end

-- Move held dogs into free slots (oldest first).
function DogService.FillSlots(player: Player)
	local state = DataService.Get(player)
	if not state then
		return
	end
	local slots = PlayerStats.EffectiveSlots(state, DataService.Ctx(player))
	local free = slots - earningCount(state)
	if free <= 0 then
		return
	end
	for _, d in state.Dogs do
		if free <= 0 then
			break
		end
		if d.Held then
			d.Held = nil
			free -= 1
		end
	end
end

local function sortKey(dog: any): number
	local def = DogCatalog.Get(dog.DogId)
	return if def then DogCatalog.AdultIncome(def, dog.Variant) else 0
end

-- Returns the up-to-12 dogs to render: pinned (Displayed == true) first, then auto (nil), each by $/s.
function DogService.DisplayList(state: any): { any }
	local pinned, auto = {}, {}
	for _, d in state.Dogs do
		if not d.Held and not d.PendingSale and DogCatalog.Get(d.DogId) then
			if d.Displayed == true then
				table.insert(pinned, d)
			elseif d.Displayed == nil then
				table.insert(auto, d)
			end
		end
	end
	local function cmp(a, b)
		return sortKey(a) > sortKey(b)
	end
	table.sort(pinned, cmp)
	table.sort(auto, cmp)
	local out = {}
	for _, list in { pinned, auto } do
		for _, d in list do
			if #out >= Layout.Yards.MaxRoamingDogs then
				return out
			end
			table.insert(out, d)
		end
	end
	return out
end

function DogService.RefreshDisplay(player: Player)
	local yard = playerYard[player]
	local state = DataService.Get(player)
	if not yard or not state then
		return
	end
	local now = os.time()
	local list = DogService.DisplayList(state)
	local models = yardModels[yard] or {}
	yardModels[yard] = models
	local keep: { [string]: boolean } = {}
	for spot, dog in list do
		keep[dog.Uid] = true
		local isPuppy = PlayerStats.IsPuppy(dog, now)
		local m = models[dog.Uid]
		if m and (m:GetAttribute("IsPuppy") ~= isPuppy or m:GetAttribute("SpotIndex") ~= spot or m.Parent == nil) then
			m:Destroy()
			m = nil
		end
		if not m then
			local def = DogCatalog.Get(dog.DogId)
			local model = DogService.BuildModel(def, dog.Variant, isPuppy)
			model.Name = dog.Uid
			local pos = spotPosition(yard, spot)
			DogService.PlaceModel(model, pos, math.rad(180 + math.random(-40, 40)))
			model:SetAttribute("OwnerUserId", player.UserId)
			model:SetAttribute("YardIndex", yard)
			model:SetAttribute("SpotIndex", spot)
			model:SetAttribute("DogUid", dog.Uid)
			model:SetAttribute("DogId", dog.DogId)
			model:SetAttribute("DogName", def.Name)
			model:SetAttribute("Rarity", def.Rarity)
			model:SetAttribute("Variant", dog.Variant or "")
			model:SetAttribute("IsPuppy", isPuppy)
			model:SetAttribute("GrownAt", dog.GrownAt)
			model:SetAttribute("HomePosition", pos)
			-- roam reach (radius + half the dog's footprint) <= 8 studs, so neighbouring spots (16 apart)
			-- never overlap and dogs stay clear of the kennel, trophy and corner bushes (QA overlap fix)
			local ext = model:GetExtentsSize()
			model:SetAttribute("RoamRadius", math.clamp(8 - math.max(ext.X, ext.Z) / 2, 1.5, 6))
			local rate = DogCatalog.AdultIncome(def, dog.Variant) * (if isPuppy then Timers.PuppyIncomeFraction else 1)
			local tierColor = (Rarities.Tiers :: any)[def.Rarity].Color
			DogService.AddNameplate(model, def.Name, (if isPuppy then "Puppy • " else "") .. FormatNumber.PerSecond(rate),
				tierColor)
			CollectionService:AddTag(model, "YardDog")
			model.Parent = yardFolder(yard)
			models[dog.Uid] = model
		end
	end
	for uid, m in models do
		if not keep[uid] then
			m:Destroy()
			models[uid] = nil
		end
	end
	local kennel = #state.Dogs - #list
	setLabel("KennelSign", yard, "CountLabel", "Kennel: " .. kennel)
end

local function updateSign(player: Player, income: number)
	local yard = playerYard[player]
	if yard then
		setLabel("YardSign", yard, "OwnerLabel", player.DisplayName .. "'s Yard\n" .. FormatNumber.PerSecond(income))
	end
end

-- Adds a dog. Returns (record, status): status "Added" | "Held" (yard full; waits for a slot) |
-- "PendingSale" (dupe that auto-sells after the Keep window unless DogAction "Keep" is used).
-- opts: { InstantAdult: boolean?, Defer: boolean? (skip the display refresh), Quiet: boolean? (skip the state push
--   and the DogAdded signal: the caller does both later, e.g. ThrowService after firing ThrowResult), SaleDelay: number? }
function DogService.AddDog(player: Player, dogId: string, variant: string?, opts: any?): (any, string)
	local state = DataService.Get(player)
	local def = DogCatalog.Get(dogId)
	if not state or not def then
		return nil, "Invalid"
	end
	opts = opts or {}
	local now = os.time()
	local grow = (Timers.Growth :: any)[def.Rarity] or 60
	local record = {
		Uid = HttpService:GenerateGUID(false),
		DogId = dogId,
		Variant = variant,
		BornAt = now,
		GrownAt = if opts.InstantAdult then now else now + math.ceil(grow / growthSpeed(player)),
	}
	local status = "Added"
	local isDupe = false
	for _, d in state.Dogs do
		if d.DogId == dogId and d.Variant == variant then
			isDupe = true
			break
		end
	end
	if isDupe and not state.Settings.KeepDupes[def.Rarity] then
		record.PendingSale = true
		status = "PendingSale"
		pendingSales[record.Uid] = { Player = player, At = os.clock() + (opts.SaleDelay or Timers.DupeKeepWindow) }
	elseif earningCount(state) >= PlayerStats.EffectiveSlots(state, DataService.Ctx(player)) then
		record.Held = true
		status = "Held"
	end
	table.insert(state.Dogs, record)
	if not opts.Defer then
		DogService.RefreshDisplay(player)
	end
	if not opts.Quiet then
		DataService.Push(player)
		DogService.DogAdded:Fire(player, record, status)
	end
	return record, status
end

-- Sells a dog (manual or auto). Returns the cash paid, or nil.
function DogService.SellDog(player: Player, uid: string, force: boolean?): number?
	local state = DataService.Get(player)
	if not state then
		return nil
	end
	local dog, index = DogService.FindDog(state, uid)
	if not dog or (dog.Locked and not force) then
		return nil
	end
	local value = PlayerStats.SellValue(dog)
	table.remove(state.Dogs, index :: number)
	pendingSales[uid] = nil
	DataService.AddCash(player, value)
	DogService.FillSlots(player)
	DogService.RefreshDisplay(player)
	DataService.Push(player)
	return value
end

function DogService.InstantGrow(player: Player, uid: string?): boolean
	local state = DataService.Get(player)
	if not state then
		return false
	end
	local now = os.time()
	local target = nil
	if uid then
		target = DogService.FindDog(state, uid)
		if target and not PlayerStats.IsPuppy(target, now) then
			target = nil
		end
	end
	if not target then
		-- fallback: the puppy with the most time left
		for _, d in state.Dogs do
			if PlayerStats.IsPuppy(d, now) and (not target or d.GrownAt > target.GrownAt) then
				target = d
			end
		end
	end
	if not target then
		return false
	end
	target.GrownAt = now
	DogService.RefreshDisplay(player)
	DataService.Push(player)
	return true
end

function DogService.GetYardIndex(player: Player): number?
	return playerYard[player]
end

function DogService.GetPlayerByYard(index: number): Player?
	return yardOwner[index]
end

function DogService.CurrentIncome(player: Player): number
	return lastIncome[player] or 0
end

----------------------------------------------------------------------------------------------------
-- Join / leave
----------------------------------------------------------------------------------------------------
local function assignYard(player: Player): number?
	if playerYard[player] then
		return playerYard[player]
	end
	for i = 1, Layout.Yards.Count do
		if not yardOwner[i] then
			yardOwner[i] = player
			playerYard[player] = i
			player:SetAttribute("YardIndex", i)
			player:SetAttribute("PadIndex", i)
			return i
		end
	end
	return nil
end

local function freeYard(player: Player)
	local i = playerYard[player]
	if not i then
		return
	end
	playerYard[player] = nil
	yardOwner[i] = nil
	clearYardModels(i)
	setLabel("YardSign", i, "OwnerLabel", "Free Yard")
	setLabel("KennelSign", i, "CountLabel", "Kennel: 0")
	DogService.YardFreed:Fire(i)
end

local function onLoaded(player: Player, state: any)
	-- dupes still pending from last session: their Keep window is over
	for i = #state.Dogs, 1, -1 do
		local d = state.Dogs[i]
		if d.PendingSale then
			DataService.AddCash(player, PlayerStats.SellValue(d))
			table.remove(state.Dogs, i)
		end
	end
	DogService.FillSlots(player)

	local yard = assignYard(player)
	if not yard then
		warn("[DogService] no free yard for " .. player.Name .. " (server over " .. Layout.Yards.Count .. " players?)")
		BroadcastService.Notify(player, "All yards are taken on this server. Try another server!")
	end

	-- Offline earnings (capped), at the rate the yard has right now.
	local prev = DataService.GetPrevLastSeen(player)
	if prev > 0 then
		local secs = math.clamp(os.time() - prev, 0, Timers.OfflineCapSeconds)
		local rate = PlayerStats.IncomePerSec(state, DataService.Ctx(player))
		local amount = math.floor(rate * secs * Timers.OfflineRate)
		if amount > 0 and secs >= 60 then
			DataService.AddCash(player, amount)
			Remotes.Get("Broadcast"):FireClient(player, {
				Kind = "Offline",
				Text = ("While you were away (%s): +%s"):format(FormatNumber.Duration(secs), FormatNumber.Money(amount)),
				Global = false,
				Amount = amount,
				Seconds = secs,
			})
		end
	end

	if yard then
		DogService.RefreshDisplay(player)
		updateSign(player, PlayerStats.IncomePerSec(state, DataService.Ctx(player)))
		DogService.YardAssigned:Fire(player, yard)
	end
	DataService.Push(player)
end

----------------------------------------------------------------------------------------------------
-- DogAction remote
----------------------------------------------------------------------------------------------------
local ACTIONS = {
	Keep = true, Sell = true, Display = true, Kennel = true, Auto = true,
	SetKeepDupes = true, SetTreatPocketMode = true, Lock = true,
}

local function handleAction(player: Player, action: any, arg: any): (boolean, string)
	if type(action) ~= "string" or not ACTIONS[action] then
		return false, "Unknown action"
	end
	if type(arg) ~= "string" or #arg == 0 or #arg > 64 then
		return false, "Bad argument"
	end
	local state = DataService.Get(player)
	if not state then
		return false, "Still loading"
	end

	if action == "SetKeepDupes" then
		-- arg: "<Rarity>" (toggle) or "<Rarity>=true|false"
		local rarity, value = string.match(arg, "^(%a+)=(%a+)$")
		rarity = rarity or arg
		if not (Rarities.Tiers :: any)[rarity] then
			return false, "Unknown rarity"
		end
		local keep
		if value == "true" then
			keep = true
		elseif value == "false" then
			keep = false
		else
			keep = not state.Settings.KeepDupes[rarity]
		end
		state.Settings.KeepDupes[rarity] = keep
		DataService.Push(player)
		return true, (if keep then "Keeping " else "Auto-selling ") .. rarity .. " dupes"
	elseif action == "SetTreatPocketMode" then
		if not table.find(Shop.TreatPocketModes, arg) then
			return false, "Unknown mode"
		end
		state.Settings.TreatPocketMode = arg
		DataService.Push(player)
		return true, "Treat Pocket: " .. arg
	end

	local dog = DogService.FindDog(state, arg)
	if not dog then
		return false, "Dog not found"
	end
	if action == "Keep" then
		if dog.PendingSale then
			dog.PendingSale = nil
			pendingSales[dog.Uid] = nil
			if earningCount(state) > PlayerStats.EffectiveSlots(state, DataService.Ctx(player)) then
				dog.Held = true
			end
			DogService.RefreshDisplay(player)
			DataService.Push(player)
			return true, if dog.Held then "Kept (yard full: waiting in the kennel for a free slot)" else "Kept!"
		end
		dog.Locked = not dog.Locked or nil
		DataService.Push(player)
		return true, if dog.Locked then "Locked (won't be sold)" else "Unlocked"
	elseif action == "Lock" then
		dog.Locked = not dog.Locked or nil
		DataService.Push(player)
		return true, if dog.Locked then "Locked" else "Unlocked"
	elseif action == "Sell" then
		if dog.Locked then
			return false, "This dog is locked"
		end
		local value = DogService.SellDog(player, dog.Uid)
		if not value then
			return false, "Couldn't sell"
		end
		return true, "Sold for " .. FormatNumber.Money(value)
	elseif action == "Display" then
		local pinned = 0
		for _, d in state.Dogs do
			if d.Displayed == true and d ~= dog then
				pinned += 1
			end
		end
		if pinned >= Layout.Yards.MaxRoamingDogs then
			return false, ("Only %d dogs can roam the yard"):format(Layout.Yards.MaxRoamingDogs)
		end
		dog.Displayed = true
	elseif action == "Kennel" then
		dog.Displayed = false
	elseif action == "Auto" then
		dog.Displayed = nil
	end
	DogService.RefreshDisplay(player)
	DataService.Push(player)
	return true, "OK"
end

----------------------------------------------------------------------------------------------------
-- Loops
----------------------------------------------------------------------------------------------------
local function incomeTick()
	local tick = 0
	while true do
		task.wait(1)
		tick += 1
		local now = os.time()
		for _, player in DataService.Players() do
			local state = DataService.Get(player)
			local ctx = DataService.Ctx(player)
			local rate = PlayerStats.IncomePerSec(state, ctx)
			lastIncome[player] = rate
			if rate > 0 then
				DataService.AddCash(player, rate)
			end
			DataService.SetLiveAttributes(player, rate)
			-- growth transitions
			local puppies = 0
			for _, d in state.Dogs do
				if PlayerStats.IsPuppy(d, now) then
					puppies += 1
				end
			end
			if lastPuppyCount[player] ~= nil and puppies < lastPuppyCount[player] then
				DogService.RefreshDisplay(player)
				DataService.Push(player)
				BroadcastService.Notify(player, "A puppy grew up! Full income unlocked.", "Growth")
			end
			lastPuppyCount[player] = puppies
			if tick % 5 == 0 then
				updateSign(player, rate)
			end
			if tick % 10 == 0 then
				DataService.Push(player) -- periodic resync of the full snapshot
			end
		end
		-- dupe auto-sales whose Keep window ran out
		local clock = os.clock()
		for uid, p in pendingSales do
			if clock >= p.At then
				pendingSales[uid] = nil
				if p.Player.Parent ~= nil then
					local value = DogService.SellDog(p.Player, uid, true)
					if value then
						BroadcastService.Notify(p.Player, "Duplicate auto-sold for " .. FormatNumber.Money(value), "AutoSell")
					end
				end
			end
		end
	end
end

function DogService.Start()
	dogsRoot = workspace:FindFirstChild("YardDogs") :: Folder
	if not dogsRoot then
		dogsRoot = Instance.new("Folder")
		dogsRoot.Name = "YardDogs"
		dogsRoot.Parent = workspace
	end
	for i = 1, Layout.Yards.Count do
		setLabel("YardSign", i, "OwnerLabel", "Free Yard")
	end

	local limiter = RateLimiter.new(Game.RateLimits.DogAction[1], Game.RateLimits.DogAction[2])
	local dogAction = Remotes.Get("DogAction") :: RemoteFunction
	dogAction.OnServerInvoke = function(player: Player, action: any, arg: any)
		if not limiter:Check(player) then
			return false, "Slow down"
		end
		local ok, a, b = pcall(handleAction, player, action, arg)
		if not ok then
			warn("[DogService] DogAction error: " .. tostring(a))
			return false, "Error"
		end
		return a, b
	end

	DataService.OnLoaded(onLoaded)
	DataService.OnReleasing(function(player: Player, state: any)
		-- settle pending dupe sales before the final save
		for i = #state.Dogs, 1, -1 do
			local d = state.Dogs[i]
			if d.PendingSale then
				pendingSales[d.Uid] = nil
				state.Cash += PlayerStats.SellValue(d)
				table.remove(state.Dogs, i)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		freeYard(player)
		lastPuppyCount[player] = nil
		lastIncome[player] = nil
		limiter:Clear(player)
	end)
	task.spawn(incomeTick)
end

return DogService
