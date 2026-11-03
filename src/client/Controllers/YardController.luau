--!strict
-- Yard window (dog cards: Keep / Lock, Sell, Roam (Display) / Kennel, dupe settings) and the LOCAL animation
-- of every dog model in the world: yard dogs wander around their spot, runaway dogs run; Rainbow dogs get
-- their hue cycle. All of it is client-side only (procedural DogAnimator + local PivotTo).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Layout = require(Config:WaitForChild("Layout"))
local Products = require(Config:WaitForChild("Products"))
local Timers = require(Config:WaitForChild("Timers"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local DogFolder = Shared:WaitForChild("Dog")
local DogAnimator = require(DogFolder:WaitForChild("DogAnimator"))
local VariantFX = require(DogFolder:WaitForChild("VariantFX"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Windows = require(UI:WaitForChild("Windows"))
local Components = UI:WaitForChild("Components")
local Create = require(Components:WaitForChild("Create"))
local Button = require(Components:WaitForChild("Button"))
local Window = require(Components:WaitForChild("Window"))
local VirtualGrid = require(Components:WaitForChild("VirtualGrid"))

local StateController = require(script.Parent:WaitForChild("StateController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local YardController = {}

----------------------------------------------------------------------------------------------------
-- World dog animation
----------------------------------------------------------------------------------------------------
type Live = {
	Model: Model,
	Anim: DogAnimator.Animator,
	Unbind: () -> (),
	Roams: boolean,
	Home: Vector3,
	Radius: number,
	Y: number,
	Target: Vector3?,
	IdleUntil: number,
	Speed: number,
}
local live: { [Model]: Live } = {}
local ROAM_DISTANCE = 200 -- only dogs this close to the camera wander

local function track(inst: Instance, roams: boolean)
	if not inst:IsA("Model") or live[inst :: Model] then
		return
	end
	local model = inst :: Model
	-- with streaming the rig's parts may arrive a moment after the model
	if not model:FindFirstChild("Torso") then
		task.spawn(function()
			if model:WaitForChild("Torso", 5) and model.Parent and not live[model] then
				track(model, roams)
			end
		end)
		return
	end
	local ok, anim = pcall(DogAnimator.new, model)
	if not ok then
		return
	end
	local pivot = model:GetPivot()
	local home = model:GetAttribute("HomePosition")
	local variant = model:GetAttribute("Variant")
	local unbind = VariantFX.Bind(model, if type(variant) == "string" and variant ~= "" then variant else nil)
	live[model] = {
		Model = model,
		Anim = anim,
		Unbind = unbind,
		Roams = roams,
		Home = if typeof(home) == "Vector3" then Vector3.new(home.X, pivot.Y, home.Z) else pivot.Position,
		Radius = tonumber(model:GetAttribute("RoamRadius")) or 6,
		Y = pivot.Y,
		Target = nil,
		IdleUntil = os.clock() + math.random() * 4,
		Speed = 4 * model:GetScale(),
	}
	if not roams then
		anim:Play("run")
	end
end

local function untrack(inst: Instance)
	local l = live[inst :: Model]
	if l then
		live[inst :: Model] = nil
		l.Anim:Destroy()
		l.Unbind()
	end
end

local function stepRoam(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, l in live do
		if model.Parent == nil then
			untrack(model)
			continue
		end
		if not l.Roams then
			continue
		end
		local pivot = model:GetPivot()
		if (pivot.Position - camPos).Magnitude > ROAM_DISTANCE then
			continue
		end
		if not l.Target then
			if now >= l.IdleUntil then
				local a = math.random() * math.pi * 2
				local r = math.random() * l.Radius
				l.Target = l.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				l.Anim:Play("run")
				l.Anim.Speed = 0.55
			end
		else
			local target = l.Target :: Vector3
			local pos = Vector3.new(pivot.X, l.Y, pivot.Z)
			local delta = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			if delta.Magnitude < 0.4 then
				l.Target = nil
				l.IdleUntil = now + 2 + math.random() * 5
				l.Anim:Play(if math.random() < 0.25 then "sit" else "idle")
				l.Anim.Speed = 1
			else
				local step = math.min(delta.Magnitude, l.Speed * dt)
				local dir = delta.Unit
				local newPos = pos + dir * step
				-- turn smoothly toward the walking direction (LookVector = dog's forward)
				local desired = CFrame.lookAt(newPos, newPos + dir)
				local current = CFrame.new(newPos) * (pivot - pivot.Position)
				model:PivotTo(current:Lerp(desired, math.min(1, dt * 6)))
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Yard window
----------------------------------------------------------------------------------------------------
local sorted: { any } = {}
local displayed: { [string]: boolean } = {}
local grid: VirtualGrid.Grid? = nil
local header: TextLabel? = nil
local dupeRow: Frame? = nil
local sellArmed: { [string]: number } = {}

local function dogAction(action: string, arg: string)
	local remote = Remotes.Get("DogAction") :: RemoteFunction
	local ok, success, msg = pcall(function()
		return remote:InvokeServer(action, arg)
	end)
	if not ok then
		NotificationController.Toast("Try again", "Error")
	elseif msg ~= "OK" then
		NotificationController.Toast(tostring(msg), if success then "Purchase" else "Error")
	end
end

local function adultRate(dog: any): number
	local def = DogCatalog.Get(dog.DogId)
	return if def then DogCatalog.AdultIncome(def, dog.Variant) else 0
end

-- mirrors DogService.DisplayList: pinned first, then auto, by $/s, capped at the roaming limit
local function computeDisplayed(dogs: { any })
	table.clear(displayed)
	local pinned, auto = {}, {}
	for _, d in dogs do
		if not d.Held and not d.PendingSale and DogCatalog.Get(d.DogId) then
			if d.Displayed == true then
				table.insert(pinned, d)
			elseif d.Displayed == nil then
				table.insert(auto, d)
			end
		end
	end
	local function cmp(a, b)
		return adultRate(a) > adultRate(b)
	end
	table.sort(pinned, cmp)
	table.sort(auto, cmp)
	local n = 0
	for _, group in { pinned, auto } do
		for _, d in group do
			if n >= Layout.Yards.MaxRoamingDogs then
				return
			end
			n += 1
			displayed[d.Uid] = true
		end
	end
end

local function rebuild()
	local state = StateController.Get()
	table.clear(sorted)
	if state and type(state.Dogs) == "table" then
		for _, d in state.Dogs do
			table.insert(sorted, d)
		end
		table.sort(sorted, function(a, b)
			if (a.PendingSale == true) ~= (b.PendingSale == true) then
				return a.PendingSale == true -- pending dupes first so Keep is easy to find
			end
			return adultRate(a) > adultRate(b)
		end)
		computeDisplayed(state.Dogs)
	end
	local h = header
	if h and state then
		local c = StateController.Computed()
		local roaming = 0
		for _ in displayed do
			roaming += 1
		end
		h.Text = ("%d dogs · earning %d/%d slots · %s · %d roaming, %d in kennel"):format(#sorted, c.DogsEarning or 0,
			c.EffectiveSlots or state.SlotCount or 0, FormatNumber.PerSecond(c.IncomePerSec or 0), roaming,
			math.max(0, #sorted - roaming))
	end
	local row = dupeRow
	if row and state then
		for _, tier in Rarities.Order do
			local b = row:FindFirstChild(tier) :: TextButton?
			if b then
				local keep = state.Settings and state.Settings.KeepDupes and state.Settings.KeepDupes[tier] == true
				Button.SetColor(b, if keep then Theme.Rarity(tier) else Theme.Color.PanelInset)
				b.Text = (if keep then "Keep " else "Sell ") .. string.sub(tier, 1, 3)
			end
		end
	end
	if grid then
		grid:SetCount(#sorted)
	end
end

local function createCard(): GuiObject
	local card = Create.New("Frame", { Name = "DogCard", BackgroundColor3 = Theme.Color.PanelLight, BorderSizePixel = 0 },
		{ Create.Corner(Theme.CornerSmall), Create.Stroke(nil, 2) })
	Create.New("Frame", { Name = "Bar", BorderSizePixel = 0, Size = UDim2.new(0, 8, 1, -10), Position = UDim2.fromOffset(5, 5), Parent = card },
		{ Create.Corner(4) })
	Create.Label({ Name = "DogName", Text = "", RichText = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.5, -18, 0.5, -4),
		Position = UDim2.fromOffset(18, 4), Parent = card }, Theme.TextMax.Normal)
	Create.Label({ Name = "Info", Text = "", RichText = true, Font = Theme.Font.Body, TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.5, -18, 0.45, -2), Position = UDim2.new(0, 18, 0.52, 0), Parent = card },
		Theme.TextMax.Small)
	local buttons = Create.New("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(0.5, -8, 1, -12),
		Position = UDim2.new(0.5, 0, 0, 6), Parent = card })
	Create.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center).Parent = buttons
	for i, name in { "Keep", "Sell", "Place" } do
		local b = Button.new({ Name = name, Text = name, Color = Theme.Color.Info, TextMax = 16, LayoutOrder = i,
			Size = UDim2.new(1 / 3, -4, 1, 0), Parent = buttons })
		b.Activated:Connect(function()
			local uid = card:GetAttribute("Uid")
			if type(uid) ~= "string" then
				return
			end
			local action = b:GetAttribute("Action")
			if action == "Sell" then
				local armed = sellArmed[uid]
				if not armed or os.clock() - armed > 3 then
					sellArmed[uid] = os.clock()
					b.Text = "Sure?"
					Button.SetColor(b, Theme.Color.Bad)
					return
				end
				sellArmed[uid] = nil
			end
			if type(action) == "string" and action ~= "" then
				local arg = uid
				if action == "Grow" then
					local remote = Remotes.Get("ShopPurchase") :: RemoteFunction
					pcall(function()
						return remote:InvokeServer("Product:InstantGrow:" .. uid)
					end)
					return
				end
				dogAction(action, arg)
			end
		end)
	end
	return card
end

local function setButton(card: Frame, name: string, text: string?, action: string?, color: Color3?)
	local b = (card:FindFirstChild("Buttons") :: Frame):FindFirstChild(name) :: TextButton
	b.Visible = text ~= nil
	if text then
		b.Text = text
		b:SetAttribute("Action", action or "")
		Button.SetColor(b, color or Theme.Color.Info)
	end
end

local function renderCard(obj: GuiObject, index: number)
	local card = obj :: Frame
	local dog = sorted[index]
	if not dog then
		card.Visible = false
		return
	end
	card:SetAttribute("Uid", dog.Uid)
	local def = DogCatalog.Get(dog.DogId)
	local rarity = if def then def.Rarity else "Common"
	local color = Theme.Rarity(rarity)
	local bar = card:FindFirstChild("Bar") :: Frame
	bar.BackgroundColor3 = color
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if dog.PendingSale then Theme.Color.Purple else Theme.Color.Stroke
	end
	local variantTag = if dog.Variant then (' <font color="#%s">[%s]</font>'):format(VariantFX.BadgeColor(dog.Variant):ToHex(),
		string.upper(dog.Variant)) else ""
	local nameLabel = card:FindFirstChild("DogName") :: TextLabel
	nameLabel.Text = (if def then def.Name else dog.DogId) .. variantTag
	local now = StateController.ServerNow()
	local puppy = PlayerStats.IsPuppy(dog, now)
	local rate = adultRate(dog) * (if puppy then Timers.PuppyIncomeFraction else 1)
	local status
	if dog.PendingSale then
		status = '<font color="#C88CFF">Duplicate: sells soon</font>'
	elseif dog.Held then
		status = '<font color="#FF8080">Waiting for a slot</font>'
	elseif displayed[dog.Uid] then
		status = "Roaming"
	else
		status = "In kennel"
	end
	local info = card:FindFirstChild("Info") :: TextLabel
	info.Text = ('<font color="#%s">%s</font> · %s%s · %s%s'):format(color:ToHex(), rarity, FormatNumber.PerSecond(rate),
		if puppy then (" (puppy, grows in %s)"):format(FormatNumber.Duration((dog.GrownAt or now) - now)) else "", status,
		if dog.Locked then " · Locked" else "")
	-- buttons
	if dog.PendingSale then
		setButton(card, "Keep", "Keep", "Keep", Theme.Color.Good)
	else
		setButton(card, "Keep", if dog.Locked then "Unlock" else "Lock", "Lock", Theme.Color.PanelInset)
	end
	if dog.Locked then
		setButton(card, "Sell", "Locked", "", Theme.Color.PanelInset)
	else
		local armed = sellArmed[dog.Uid] and os.clock() - sellArmed[dog.Uid] <= 3
		setButton(card, "Sell", if armed then "Sure?" else "Sell", "Sell", if armed then Theme.Color.Bad else Theme.Color.Accent)
	end
	if dog.PendingSale or dog.Held then
		if puppy and Products.DeveloperProducts.InstantGrow.Id ~= 0 then
			setButton(card, "Place", "Grow", "Grow", Theme.Color.Purple)
		else
			setButton(card, "Place", nil)
		end
	elseif displayed[dog.Uid] then
		setButton(card, "Place", "Kennel", "Kennel", Theme.Color.Info)
	else
		setButton(card, "Place", "Roam", "Display", Theme.Color.Good)
	end
end

local function buildWindow(): any
	local w = Window.new("Your Yard", Theme.Color.Good, Windows.Close)
	w.Title.TextColor3 = Theme.Color.TextDark
	header = Create.Label({ Name = "Header", Text = "", Font = Theme.Font.Body, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.72, 0, 0, 24), Parent = w.Body }, Theme.TextMax.Small)
	Button.new({ Text = "More slots", Color = Theme.Color.Accent, TextMax = 16, Size = UDim2.new(0.26, 0, 0, 24),
		Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), Parent = w.Body, OnClick = function()
			Windows.Open("Shop", "Yard")
		end })
	local row = Create.New("Frame", { Name = "Dupes", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 28), Parent = w.Body })
	Create.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = row
	Create.Label({ Text = "Dupes:", Font = Theme.Font.Body, TextColor3 = Theme.Color.TextDim, Size = UDim2.new(0.1, 0, 1, 0),
		LayoutOrder = 0, Parent = row }, Theme.TextMax.Small)
	for i, tier in Rarities.Order do
		Button.new({ Name = tier, Text = tier, Color = Theme.Color.PanelInset, TextMax = 14, LayoutOrder = i,
			Size = UDim2.new(0.15, -4, 1, 0), Parent = row, OnClick = function()
				dogAction("SetKeepDupes", tier)
			end })
	end
	dupeRow = row
	grid = VirtualGrid.new({
		Parent = w.Body,
		Size = UDim2.new(1, 0, 1, -60),
		Position = UDim2.fromOffset(0, 60),
		CellMinWidth = 300,
		CellHeight = 58,
		MaxColumns = 2,
		Padding = 6,
		CreateCell = createCard,
		Render = renderCard,
	})
	return {
		Frame = w.Frame,
		OnOpen = function(_arg: any)
			rebuild()
		end,
	}
end

function YardController.Start()
	Windows.Register("Yard", function(_host)
		return buildWindow()
	end)
	StateController.Changed:Connect(function()
		if Windows.IsOpen("Yard") then
			rebuild()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.IsOpen("Yard") and grid then
				grid:Refresh() -- puppy timers / sell confirmations
			end
		end
	end)

	for _, m in CollectionService:GetTagged("YardDog") do
		track(m, true)
	end
	for _, m in CollectionService:GetTagged("RunawayDog") do
		track(m, false)
	end
	CollectionService:GetInstanceAddedSignal("YardDog"):Connect(function(m)
		track(m, true)
	end)
	CollectionService:GetInstanceAddedSignal("RunawayDog"):Connect(function(m)
		track(m, false)
	end)
	CollectionService:GetInstanceRemovedSignal("YardDog"):Connect(untrack)
	CollectionService:GetInstanceRemovedSignal("RunawayDog"):Connect(untrack)
	RunService.Heartbeat:Connect(stepRoam)
end

return YardController
