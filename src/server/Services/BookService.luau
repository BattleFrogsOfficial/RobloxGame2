--!nonstrict
-- Kennel Book: records every catch forever (Book[DogId] = {Count, FirstAt, Variants = {"Gold", ...}}),
-- per-zone milestone rewards at 25/50/75/100% of the zone's base dogs (cash -> permanent luck ->
-- yard trophy statue -> title), and variant completion badges (one per zone per variant).
local BadgeService = game:GetService("BadgeService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Zones = require(Config:WaitForChild("Zones"))
local Shop = require(Config:WaitForChild("Shop"))
local Products = require(Config:WaitForChild("Products"))
local Game = require(Config:WaitForChild("Game"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local RateLimiter = require(Util:WaitForChild("RateLimiter"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local DogService = require(script.Parent:WaitForChild("DogService"))
local BroadcastService = require(script.Parent:WaitForChild("BroadcastService"))

local BookService = {}

local trophyRoot: Folder = nil

local function zoneById(id: string): any
	for _, z in Zones do
		if z.Id == id then
			return z
		end
	end
	return nil
end

local function awardBadge(player: Player, badgeId: number)
	if badgeId == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not ok then
			warn("[BookService] AwardBadge failed: " .. tostring(err))
		end
	end)
end

local function hasVariant(entry: any, variant: string): boolean
	return entry ~= nil and type(entry.Variants) == "table" and table.find(entry.Variants, variant) ~= nil
end

local function checkVariantBadges(player: Player, state: any, zoneId: string, variant: string)
	local key = zoneId .. ":" .. variant
	if state.VariantBadges[key] then
		return
	end
	for _, def in DogCatalog.ZoneDogs(zoneId) do
		if def.Rarity ~= "Common" and not hasVariant(state.Book[def.Id], variant) then
			return
		end
	end
	state.VariantBadges[key] = true
	local zoneBadges = Products.Badges.Variant[zoneId]
	awardBadge(player, if zoneBadges then zoneBadges[variant] or 0 else 0)
	local z = zoneById(zoneId)
	BroadcastService.Notify(player, ("Badge earned: every %s dog in %s!"):format(variant, if z then z.Name else zoneId),
		"Badge")
	if variant == "Rainbow" and not state.VariantBadges.AllRainbows then
		for _, def in DogCatalog.All() do
			if def.Rarity ~= "Common" and not hasVariant(state.Book[def.Id], "Rainbow") then
				return
			end
		end
		state.VariantBadges.AllRainbows = true
		awardBadge(player, Products.Badges.AllRainbows)
		BroadcastService.Notify(player, "Badge earned: ALL RAINBOWS!", "Badge")
	end
end

-- Record a catch (including auto-sold dupes and whistle recalls). Returns isNewDog, isNewForm.
function BookService.Record(player: Player, dogId: string, variant: string?): (boolean, boolean)
	local state = DataService.Get(player)
	local def = DogCatalog.Get(dogId)
	if not state or not def then
		return false, false
	end
	local entry = state.Book[dogId]
	local isNew = false
	if not entry then
		entry = { Count = 0, FirstAt = os.time(), Variants = {} }
		state.Book[dogId] = entry
		isNew = true
	end
	entry.Count = (entry.Count or 0) + 1
	local newForm = isNew
	if variant and not hasVariant(entry, variant) then
		table.insert(entry.Variants, variant)
		newForm = true
		checkVariantBadges(player, state, def.Zone, variant)
	end
	DataService.Push(player)
	return isNew, newForm
end

function BookService.Progress(state: any, zoneId: string): (number, number)
	local caught, total = 0, 0
	for _, def in DogCatalog.ZoneDogs(zoneId) do
		total += 1
		if state.Book[def.Id] then
			caught += 1
		end
	end
	return caught, total
end

----------------------------------------------------------------------------------------------------
-- Trophies
----------------------------------------------------------------------------------------------------
local function trophyFolder(yard: number): Folder
	local name = "Yard_" .. yard
	local f = trophyRoot:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = trophyRoot
	end
	return f :: Folder
end

local function trophyBase(yard: number): CFrame
	for _, inst in CollectionService:GetTagged("TrophySpot") do
		if inst:GetAttribute("YardIndex") == yard and inst:IsA("BasePart") then
			return inst.CFrame * CFrame.new(0, inst.Size.Y / 2, 0)
		end
	end
	local c = DogService.GetYardCenter(yard)
	return CFrame.new(c + Vector3.new(0, 0, -45))
end

function BookService.RefreshTrophies(player: Player)
	local yard = DogService.GetYardIndex(player)
	local state = DataService.Get(player)
	if not yard or not state then
		return
	end
	local folder = trophyFolder(yard)
	folder:ClearAllChildren()
	local list = {}
	for _, z in Zones do
		if state.Trophies[z.Id] then
			table.insert(list, z)
		end
	end
	local base = trophyBase(yard)
	for i, z in list do
		local offset = (i - (#list + 1) / 2) * 5
		local model = Instance.new("Model")
		model.Name = "Trophy_" .. z.Id
		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal"
		pedestal.Anchored = true
		pedestal.Size = Vector3.new(3, 2, 3)
		pedestal.CFrame = base * CFrame.new(offset, 1, 0)
		pedestal.Color = Color3.fromRGB(235, 235, 235)
		pedestal.Material = Enum.Material.Marble
		pedestal.Parent = model
		local statue = Instance.new("Part")
		statue.Name = "Statue"
		statue.Anchored = true
		statue.Shape = Enum.PartType.Ball
		statue.Size = Vector3.new(2.2, 2.2, 2.2)
		statue.CFrame = base * CFrame.new(offset, 3.1, 0)
		statue.Color = z.Theme.Accent
		statue.Material = Enum.Material.Neon
		statue.Parent = model
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(120, 30)
		gui.StudsOffset = Vector3.new(0, 2.2, 0)
		gui.MaxDistance = 60
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.Text = z.Name .. " 75%"
		t.Parent = gui
		gui.Parent = statue
		model.PrimaryPart = pedestal
		model.Parent = folder
	end
end

----------------------------------------------------------------------------------------------------
-- Claims
----------------------------------------------------------------------------------------------------
local function claim(player: Player, zoneId: any, milestone: any): (boolean, string)
	local state = DataService.Get(player)
	if not state then
		return false, "Still loading"
	end
	if type(zoneId) ~= "string" then
		return false, "Bad zone"
	end
	local zone = zoneById(zoneId)
	local m = tonumber(milestone)
	if not zone or not m or not table.find(Shop.BookMilestones, m) then
		return false, "Bad milestone"
	end
	local key = tostring(m)
	state.BookRewards[zoneId] = state.BookRewards[zoneId] or {}
	if state.BookRewards[zoneId][key] then
		return false, "Already claimed"
	end
	local caught, total = BookService.Progress(state, zoneId)
	if total == 0 or caught < math.ceil(total * m / 100) then
		return false, ("Need %d/%d dogs"):format(math.ceil(total * m / 100), total)
	end
	local reward = Shop.BookRewards[m]
	state.BookRewards[zoneId][key] = true
	local msg
	if reward.Kind == "Cash" then
		local amount = zone.BaseIncome * reward.ZoneIncomeSeconds
		DataService.AddCash(player, amount)
		msg = "+" .. FormatNumber.Money(amount)
	elseif reward.Kind == "Luck" then
		state.PermanentLuck += reward.Luck
		msg = ("+%s permanent Luck"):format(tostring(reward.Luck))
	elseif reward.Kind == "Trophy" then
		state.Trophies[zoneId] = true
		BookService.RefreshTrophies(player)
		msg = zone.Name .. " trophy added to your yard"
	else
		local title = zone.Name .. " Legend"
		state.Titles[title] = true
		state.EquippedTitle = title
		player:SetAttribute("Title", title)
		msg = "Title unlocked: " .. title
	end
	if reward.Bones then
		DataService.AddBones(player, reward.Bones)
		msg ..= (" (+%d Bones)"):format(reward.Bones)
	end
	DataService.Push(player)
	return true, msg
end

function BookService.Start()
	trophyRoot = Instance.new("Folder")
	trophyRoot.Name = "YardTrophies"
	trophyRoot.Parent = workspace

	local limiter = RateLimiter.new(Game.RateLimits.Claim[1], Game.RateLimits.Claim[2])
	local remote = Remotes.Get("ClaimBookReward") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, zoneId: any, milestone: any)
		if not limiter:Check(player) then
			return false, "Slow down"
		end
		local ok, a, b = pcall(claim, player, zoneId, milestone)
		if not ok then
			warn("[BookService] claim error: " .. tostring(a))
			return false, "Error"
		end
		return a, b
	end

	local function onYard(player: Player)
		BookService.RefreshTrophies(player)
		local st = DataService.Get(player)
		if st and st.EquippedTitle ~= "" then
			player:SetAttribute("Title", st.EquippedTitle)
		end
	end
	DogService.YardAssigned:Connect(onYard)
	for _, player in DataService.Players() do
		if DogService.GetYardIndex(player) then
			task.spawn(onYard, player) -- yards assigned before this service started
		end
	end
	DogService.YardFreed:Connect(function(yard: number)
		local f = trophyRoot:FindFirstChild("Yard_" .. yard)
		if f then
			f:ClearAllChildren()
		end
	end)
end

return BookService
