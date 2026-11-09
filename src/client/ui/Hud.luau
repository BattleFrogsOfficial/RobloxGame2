-- Always-on HUD. Every element's position comes from Layout.luau, which a
-- test checks for overlaps on desktop, tablet and phone screens. Icons are
-- small 3D models (Voxel.icon) shown in viewports; no emoji anywhere.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local Layout = require(script.Parent.Layout)
local State = require(script.Parent.Parent.State)
local Ocean = require(script.Parent.Parent.Ocean)
local Guide = require(script.Parent.Parent.Guide)

local Hud = {}

local player = Players.LocalPlayer
local C = Ui.Colors
local SEA_BLUE = Color3.fromRGB(120, 200, 255)

local gui: ScreenGui
local overlay: ScreenGui -- cutscene bars, flash and big banners
local touch = false
local refs: { [string]: any } = {}
local cashShown, cashTarget = 0, 0

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

-- An invisible frame placed where Layout says `name` goes.
local function slot(name: string): Frame
	local anchor, pivot, offset, size = Layout.place(name, touch)
	return Ui.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(pivot[1], pivot[2]),
		Position = UDim2.new(anchor[1], offset[1], anchor[2], offset[2]),
		Size = UDim2.fromOffset(size[1], size[2]),
		Parent = gui,
	})
end

local function fadeOut(label: TextLabel, seconds: number)
	TweenService:Create(label, TweenInfo.new(seconds), { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	end
end

----------------------------------------------------------------------------
-- Toasts, pops, banners
----------------------------------------------------------------------------
function Hud.toast(text: string, color: Color3?)
	local holder = refs.toasts
	local labels = {}
	for _, c in holder:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels >= 2 then
		labels[1]:Destroy() -- only two lines fit; drop the oldest
	end
	local label = Ui.text({
		Text = text,
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = color or C.White,
		StrokeThickness = 3,
		ZIndex = 50,
		Parent = holder,
	})
	task.delay(3.2, function()
		if not label.Parent then
			return
		end
		fadeOut(label, 0.5)
		task.wait(0.55)
		label:Destroy()
	end)
end

-- Text that pops at a screen position and floats up.
function Hud.pop(text: string, color: Color3, pos: UDim2, size: number?)
	local label = Ui.text({
		Text = text,
		Size = UDim2.fromOffset(360, size or 44),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = color,
		StrokeThickness = 3,
		Rotation = math.random(-8, 8),
		ZIndex = 40,
		Parent = gui,
	})
	local scale = Ui.new("UIScale", { Scale = 0.4, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(1.1), { Position = pos - UDim2.fromOffset(0, 70) }):Play()
	task.delay(0.7, function()
		if not label.Parent then
			return
		end
		fadeOut(label, 0.4)
		task.wait(0.45)
		label:Destroy()
	end)
end

-- A big message across the middle of the screen for the moments that matter.
function Hud.banner(title: string, subtitle: string?, color: Color3, seconds: number?)
	if refs.banner then
		refs.banner:Destroy()
	end
	local strip = Ui.new("Frame", {
		Name = "Banner",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, 0, 0, subtitle and 170 or 120),
		ZIndex = 70,
		Parent = overlay,
	})
	refs.banner = strip
	local big = Ui.text({
		Text = title,
		Size = UDim2.new(1, -80, 0, 96),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = color,
		StrokeThickness = 5,
		ZIndex = 71,
		Parent = strip,
	})
	local small
	if subtitle then
		small = Ui.text({
			Text = subtitle,
			Size = UDim2.new(1, -80, 0, 40),
			Position = UDim2.new(0.5, 0, 0, 114),
			AnchorPoint = Vector2.new(0.5, 0),
			StrokeThickness = 3,
			ZIndex = 71,
			Parent = strip,
		})
	end
	local scale = Ui.new("UIScale", { Scale = 1.6, Parent = big })
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(strip, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
	task.delay(seconds or 2.4, function()
		if not strip.Parent then
			return
		end
		TweenService:Create(strip, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		fadeOut(big, 0.4)
		if small then
			fadeOut(small, 0.4)
		end
		task.wait(0.45)
		if refs.banner == strip then
			refs.banner = nil
		end
		strip:Destroy()
	end)
end

-- Brief full-screen wash of color (the sea hitting you, or a flash).
function Hud.flash(color: Color3, opacity: number?, seconds: number?)
	local f = Ui.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - (opacity or 0.65),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 65,
		Parent = overlay,
	})
	TweenService:Create(f, TweenInfo.new(seconds or 0.7), { BackgroundTransparency = 1 }):Play()
	task.delay((seconds or 0.7) + 0.05, function()
		f:Destroy()
	end)
end

local function feed(amount: number)
	local holder = refs.feed
	local labels = {}
	for _, c in holder:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels >= 3 then
		labels[1]:Destroy()
	end
	local label = Ui.text({
		Text = "+" .. Format.cash(amount),
		Size = UDim2.new(1, 0, 0, 24),
		TextColor3 = C.Cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = holder,
	})
	task.delay(2.4, function()
		if not label.Parent then
			return
		end
		fadeOut(label, 0.4)
		task.wait(0.45)
		label:Destroy()
	end)
end

----------------------------------------------------------------------------
-- The parting cutscene's screen layer: letterbox bars, a flash, a title.
----------------------------------------------------------------------------
local function playCutsceneOverlay(sp)
	local seconds = Config.Ocean.OpenAnim
	local bars = {}
	for _, top in { true, false } do
		local bar = Ui.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, top and 0 or 1),
			Position = UDim2.fromScale(0, top and 0 or 1),
			Size = UDim2.new(1, 0, 0, 0),
			ZIndex = 60,
			Parent = overlay,
		})
		TweenService:Create(bar, TweenInfo.new(0.35), { Size = UDim2.new(1, 0, 0, 84) }):Play()
		table.insert(bars, bar)
	end
	gui.Enabled = false
	task.delay(seconds * 0.28, function()
		Hud.flash(Color3.new(1, 1, 1), 0.85, 0.6)
		local eggs = #sp.eggs
		Hud.banner("THE SEA PARTS!", string.format("%d studs deep   -   %d egg%s revealed", math.floor(sp.length), eggs, eggs == 1 and "" or "s"), SEA_BLUE, seconds * 0.6)
	end)
	task.delay(seconds - 0.3, function()
		for _, bar in bars do
			TweenService:Create(bar, TweenInfo.new(0.3), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		end
	end)
	task.delay(seconds, function()
		for _, bar in bars do
			bar:Destroy()
		end
		gui.Enabled = true
	end)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------
local function buildTopBar()
	local bar = slot("TopBar")
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	local function top(text: string, color: Color3, order: number, onClick: () -> ())
		Ui.button({ Text = text, Color = color, Size = UDim2.fromOffset(170, 56), LayoutOrder = order, Radius = 4, Parent = bar, OnClick = onClick })
	end
	top("Buy", C.Blue, 1, function()
		Ui.toggle("Upgrades")
	end)
	top("Base", C.Brown, 2, function()
		State.action("TeleportHome")
	end)
	top("Sell", C.Orange, 3, function()
		Ui.toggle("Sell")
	end)
end

-- Shown while your sea is parted: a bar that drains as the walls close in,
-- and (on land) the Close Ocean button.
local function buildStatus()
	local status = slot("Status")
	status.Visible = false
	local track = Ui.new("Frame", {
		BackgroundColor3 = C.Darker,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = status,
	})
	Ui.corner(track, 8)
	Ui.stroke(track, 3)
	local fill = Ui.new("Frame", {
		BackgroundColor3 = SEA_BLUE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	})
	Ui.corner(fill, 8)
	refs.statusFill = fill
	refs.statusText = Ui.text({
		Text = "",
		Size = UDim2.new(1, -12, 1, -6),
		Position = UDim2.fromOffset(6, 3),
		ZIndex = 3,
		StrokeThickness = 3,
		Parent = track,
	})
	refs.closeBtn = Ui.button({
		Text = "Close Ocean!",
		Color = C.Red,
		Size = UDim2.fromOffset(220, 40),
		Position = UDim2.new(0.5, 0, 0, 42),
		AnchorPoint = Vector2.new(0.5, 0),
		Radius = 4,
		Parent = status,
		OnClick = function()
			Ocean.close()
		end,
	})
	refs.status = status

	refs.objective = Ui.text({
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextColor3 = SEA_BLUE,
		StrokeThickness = 3,
		Visible = false,
		Parent = slot("Objective"),
	})

	refs.toasts = slot("Toasts")
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = refs.toasts })
end

local function buildLeft()
	-- Starter pack promo.
	local promo = slot("Promo")
	refs.starter = Ui.button({
		Text = "Starter Pack  R$" .. Config.Products[1].price,
		Icon = "gift",
		Color = C.Red,
		Size = UDim2.fromScale(1, 1),
		Parent = promo,
		OnClick = function()
			Ui.open("Store")
		end,
	})

	local menu = slot("Menu")
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	local pets = Ui.button({ Text = "Pets", Icon = "pets", Color = C.Orange, Size = UDim2.fromOffset(88, 88), LayoutOrder = 1, Parent = menu, OnClick = function()
		Ui.toggle("Pets")
	end })
	local eggs = Ui.button({ Text = "Eggs", Icon = "egg", Color = C.Teal, Size = UDim2.fromOffset(88, 88), LayoutOrder = 2, Parent = menu, OnClick = function()
		Ui.toggle("Eggs")
	end })
	refs.petsBadge = Ui.badge(pets, "!")
	refs.eggsBadge = Ui.badge(eggs, "!")

	-- Cash, Strength and Luck, each with its icon.
	local stats = slot("Stats")
	local _, _, _, size = Layout.place("Stats", touch)
	local rowHeight = size[2] / 3
	local function stat(icon: string, color: Color3, row: number)
		local frame = Ui.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, rowHeight),
			Position = UDim2.fromOffset(0, (row - 1) * rowHeight),
			Parent = stats,
		})
		local holder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(rowHeight, rowHeight), Parent = frame })
		Ui.icon(holder, icon)
		return Ui.text({
			Text = "0",
			Size = UDim2.new(1, -rowHeight - 8, 1, -6),
			Position = UDim2.fromOffset(rowHeight + 8, 3),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			StrokeThickness = 3.5,
			Parent = frame,
		})
	end
	refs.cash = stat("cash", C.Cash, 1)
	refs.strength = stat("strength", C.Yellow, 2)
	refs.luck = stat("luck", Color3.fromRGB(150, 255, 150), 3)

	refs.feed = slot("Feed")
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Top, Parent = refs.feed })
end

local function buildRight()
	local grid = slot("RightGrid")
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(88, 88),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = grid,
	})
	local index = Ui.button({ Text = "Index", Icon = "book", Color = C.Blue, LayoutOrder = 1, Parent = grid, OnClick = function()
		Ui.toggle("Index")
	end })
	Ui.button({ Text = "Shop", Icon = "chest", Color = C.Yellow, LayoutOrder = 2, Parent = grid, OnClick = function()
		Ui.toggle("Store")
	end })
	local gift = Ui.button({ Text = "Gifts", Icon = "gift", Color = C.Pink, LayoutOrder = 3, Parent = grid, OnClick = function()
		Ui.toggle("Playtime")
	end })
	local daily = Ui.button({ Text = "Daily", Icon = "calendar", Color = C.Purple, LayoutOrder = 4, Parent = grid, OnClick = function()
		Ui.toggle("Daily")
	end })
	refs.indexBadge = Ui.badge(index, "!")
	refs.giftLabel = gift:FindFirstChild("Label")
	refs.giftBadge = Ui.badge(gift, "!")
	refs.dailyBadge = Ui.badge(daily, "!")
end

-- "Eggs 1/1": stays up from the moment you grab an egg until it's planted.
local function buildCarry()
	local frame = slot("Carry")
	frame.Visible = false
	local panel = Ui.new("Frame", { BackgroundColor3 = C.Darker, Size = UDim2.fromScale(1, 1), Parent = frame })
	Ui.corner(panel, 12)
	refs.carryStroke = Ui.stroke(panel, 4, C.Yellow)
	local holder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(6, 2), ZIndex = 2, Parent = panel })
	Ui.icon(holder, "egg", { ZIndex = 2 })
	refs.carryCount = Ui.text({
		Text = "1/1",
		Size = UDim2.fromOffset(84, 46),
		Position = UDim2.fromOffset(64, 7),
		TextColor3 = C.Yellow,
		StrokeThickness = 3.5,
		ZIndex = 2,
		Parent = panel,
	})
	refs.carryHint = Ui.text({
		Text = "",
		Size = UDim2.new(1, -160, 0, 40),
		Position = UDim2.fromOffset(152, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = panel,
	})
	refs.carry = frame
end

local function buildTrain()
	local frame = slot("Train")
	frame.Visible = false
	local panel = Ui.new("Frame", { BackgroundColor3 = C.Darker, Size = UDim2.fromScale(1, 1), Parent = frame })
	Ui.corner(panel, 10)
	Ui.stroke(panel, 3, C.Orange)
	refs.trainText = Ui.text({
		Text = "",
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextColor3 = C.Yellow,
		Parent = panel,
	})
	refs.train = frame
end

local function buildCharge()
	local frame = slot("Charge")
	frame.Visible = false
	local bar = Ui.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		Size = UDim2.fromOffset(42, 214),
		Parent = frame,
	})
	Ui.corner(bar, 14)
	Ui.stroke(bar, 5)
	local fill = Ui.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(190, 240, 120),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		Parent = bar,
	})
	Ui.corner(fill, 14)
	for i = 1, 7 do
		Ui.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(60, 60, 60),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.fromScale(0, i / 8),
			ZIndex = 2,
			Parent = bar,
		})
	end
	-- Marker that rides the fill level: a small diamond pointer plus text.
	local marker = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -52, 0, 24),
		Position = UDim2.fromOffset(50, 202),
		Parent = frame,
	})
	local pointer = Ui.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(190, 255, 130),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(12, 12),
		Position = UDim2.fromOffset(0, 6),
		Rotation = 45,
		Parent = marker,
	})
	Ui.stroke(pointer, 2)
	refs.chargeMarkerText = Ui.text({
		Text = "+0s",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(20, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 255, 130),
		Parent = marker,
	})
	Ui.text({
		Text = "Hold to Charge",
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 224),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	refs.charge = frame
	refs.chargeFill = fill
	refs.chargeMarker = marker
end

-- Touch players get a big hold button so charging doesn't fight the camera.
local function buildHoldButton()
	if not Layout.Elements.Hold or not touch then
		return
	end
	local holder = slot("Hold")
	local btn = Ui.button({
		Name = "HoldToPart",
		Text = "HOLD\nto part the sea",
		Color = C.Blue,
		Size = UDim2.fromScale(1, 1),
		Radius = 85,
		NoShine = true,
		Parent = holder,
	})
	-- The press starts here; the release is caught globally (Ocean listens to
	-- UserInputService.InputEnded), so sliding off the button still releases.
	btn.InputBegan:Connect(function(input)
		local source = Ocean.sourceOf(input)
		if source ~= nil then
			Ocean.beginCharge(source)
		end
	end)
	holder.Visible = false
	refs.hold = holder
end

-- Red glow around the screen edge that pulses as the walls close on you.
local function buildDanger()
	local frame = Ui.new("Frame", {
		Name = "Danger",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -70, 1, -70),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = gui,
	})
	refs.dangerStroke = Ui.new("UIStroke", {
		Thickness = 36,
		Color = Color3.fromRGB(255, 40, 40),
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	refs.danger = frame
end

----------------------------------------------------------------------------
-- Updates
----------------------------------------------------------------------------
local function onState(d)
	if cashTarget == 0 and cashShown == 0 then
		cashShown = d.cash -- first state: no count-up from zero
	end
	cashTarget = d.cash
	refs.strength.Text = Format.short(d.strength)
	local luckText = "x" .. string.format("%.2f", d.luck):gsub("%.?0+$", "") .. " Luck"
	if d.boosts and d.boosts.luckUntil > d.osTime then
		luckText ..= " (potion)"
	end
	refs.luck.Text = luckText
	refs.eggsBadge.Visible = #d.eggs > 0
	refs.petsBadge.Visible = #d.animals > 0
	local unclaimed = false
	for _, v in d.index do
		if v == 1 then
			unclaimed = true
			break
		end
	end
	refs.indexBadge.Visible = unclaimed
	refs.dailyBadge.Visible = d.daily.last < d.serverDay
	refs.starter.Visible = not d.starterPackBought
end

local function playtimeStatus(): (boolean, number?)
	local d = State.data
	if not d then
		return false, nil
	end
	local elapsed = State.serverNow() - d.sessionStart
	local soonest
	for i, r in Config.Playtime do
		if not d.playtimeClaimed[tostring(i)] then
			local left = r.minutes * 60 - elapsed
			if left <= 0 then
				return true, 0
			end
			soonest = soonest and math.min(soonest, left) or left
		end
	end
	return false, soonest
end

local function perFrame(dt: number)
	local now = os.clock()

	-- Cash counts up/down toward its real value.
	if cashShown ~= cashTarget then
		local diff = cashTarget - cashShown
		if math.abs(diff) < math.max(1, math.abs(cashTarget) * 0.0005) then
			cashShown = cashTarget
		else
			cashShown += diff * math.min(1, (dt or 0.016) * 10)
		end
	end
	refs.cash.Text = Format.cash(cashShown)

	-- Charge meter
	refs.charge.Visible = Ocean.canCharge
	if refs.hold then
		refs.hold.Visible = Ocean.canCharge
	end
	if Ocean.canCharge then
		local c = Ocean.charge
		refs.chargeFill.Size = UDim2.fromScale(1, c)
		refs.chargeMarker.Position = UDim2.fromOffset(50, 214 * (1 - c) - 12)
		refs.chargeMarkerText.Text = "+" .. math.floor(c * Config.Split.ChargeOpenBonus * 10 + 0.5) / 10 .. "s"
	end

	-- Sea status: the bar drains from both ends, like the walls closing in.
	local phase, left, room = Ocean.timing()
	refs.status.Visible = phase ~= nil and not Ocean.cutscene
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local onLand = root ~= nil and root.Position.Z >= Config.Ocean.ShoreZ
	if phase then
		local urgent = left <= 5 or room < 0.25
		refs.statusFill.Size = UDim2.fromScale(math.clamp(room, 0, 1), 1)
		refs.statusFill.BackgroundColor3 = urgent and Color3.fromRGB(255, 90, 80) or SEA_BLUE
		refs.statusText.Text = string.format("Sea closing in %.1fs", left)
		refs.closeBtn.Visible = onLand
	end

	-- Danger glow while you're between the walls and they're getting close.
	local gap = phase == "closing" and Ocean.wallGap() or nil
	if gap and (gap < 8 or left <= 5) then
		local danger = math.clamp(math.max(1 - gap / 8, 1 - left / 5), 0.2, 1)
		refs.danger.Visible = true
		refs.dangerStroke.Transparency = 1 - danger * (0.45 + 0.2 * math.sin(now * 9))
	else
		refs.danger.Visible = false
	end

	-- Egg counter: from the grab until the egg is planted in your base.
	local carried = Ocean.carried
	local cap = State.data and State.data.carry or 1
	refs.carry.Visible = carried > 0
	if carried > 0 then
		refs.carryCount.Text = carried .. "/" .. cap
		if onLand then
			refs.carryHint.Text = "Plant it in your base!"
			refs.carryHint.TextColor3 = C.Cash
			refs.carryStroke.Color = C.Cash
		else
			refs.carryHint.Text = "Get back to the beach!"
			refs.carryHint.TextColor3 = Color3.fromRGB(255, 120, 100)
			refs.carryStroke.Color = Color3.fromRGB(255, 120, 100)
		end
	end

	-- Objective line.
	local text = Guide.text
	if not text then
		if Ocean.inZone and Ocean.handsFull and not phase then
			text = "Your hands are full. Plant your egg in your base first."
		elseif Ocean.inZone and not Ocean.canCharge and not phase then
			text = "Equip your Sea Staff to part the ocean!"
		elseif Ocean.canCharge and not Ocean.charging then
			text = "Hold to charge, release to part the sea!"
		end
	end
	refs.objective.Visible = text ~= nil and not Ocean.cutscene
	if text then
		refs.objective.Text = text
		refs.objective.TextColor3 = Guide.urgent and Color3.fromRGB(255, 120, 100) or SEA_BLUE
	end

	-- Training banner.
	local training = player:GetAttribute("Training") == true
	refs.train.Visible = training
	if training and State.data then
		local gain = Config.Weights[State.data.weightTier].gain * (State.data.passes.DoubleStrength and 2 or 1)
		refs.trainText.Text = "TRAINING   +" .. Format.short(gain) .. " Strength per rep   -   step off to stop"
	end
end

local function perSecond()
	local ready, left = playtimeStatus()
	refs.giftBadge.Visible = ready
	if refs.giftLabel then
		if ready then
			refs.giftLabel.Text = "Ready!"
		elseif left then
			refs.giftLabel.Text = Format.time(left)
		else
			refs.giftLabel.Text = "Gifts"
		end
	end
end

local function onEffect(kind: string, payload: any)
	if kind == "income" then
		feed(payload)
	elseif kind == "lift" then
		Hud.pop("+" .. Format.short(payload.gain) .. " Strength", C.Yellow, UDim2.new(0.5, math.random(-120, 120), 0.5, math.random(-40, 40)))
	elseif kind == "offline" then
		Hud.banner("+" .. Format.cash(payload.cash), "earned while you were away", C.Cash, 3)
	elseif kind == "splitStart" then
		playCutsceneOverlay(payload)
	elseif kind == "grabbed" then
		local e = Config.EggById[payload.egg]
		Hud.pop((payload.variant ~= "Normal" and payload.variant .. " " or "") .. e.name .. "!", Config.Rarities[e.tier].color, UDim2.fromScale(0.5, 0.36), 52)
	elseif kind == "safe" then
		Hud.banner("SAFE!", "Carry your egg to your base to plant it", C.Cash, 2.2)
	elseif kind == "planted" then
		for _, b in payload do
			local e = Config.EggById[b.egg]
			local name = (b.variant ~= "Normal" and b.variant .. " " or "") .. e.name
			local where = b.where == "pen" and " planted! It's incubating." or b.where == "storage" and " stored (your base is full)." or " sold (storage is full)."
			Hud.toast(name .. where, Config.Rarities[e.tier].color)
		end
	elseif kind == "caught" then
		Hud.flash(Color3.fromRGB(40, 130, 230), 0.7, 0.9)
		if payload.reason == "swept" then
			local lost = payload.lost or 0
			local sub = lost > 1 and ("You lost " .. lost .. " eggs") or lost == 1 and "You lost your egg" or "The sea closed on you"
			Hud.banner("SWEPT AWAY!", sub, Color3.fromRGB(255, 110, 100), 2.8)
		else
			Hud.banner("THE SEA THROWS YOU BACK!", "Part it with your Sea Staff first", SEA_BLUE, 2.6)
		end
	elseif kind == "seaClosed" then
		Hud.flash(Color3.fromRGB(40, 130, 230), 0.25, 0.5)
	end
end

function Hud.init()
	touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	gui = Ui.screen("Hud", 1)
	overlay = Ui.screen("Overlay", 8)

	buildTopBar()
	buildStatus()
	buildLeft()
	buildRight()
	buildCarry()
	buildTrain()
	buildCharge()
	buildHoldButton()
	buildDanger()

	State.toast:Connect(Hud.toast)
	State.changed:Connect(onState)
	if State.data then
		onState(State.data)
	end
	State.effect:Connect(onEffect)

	RunService.RenderStepped:Connect(perFrame)
	task.spawn(function()
		while true do
			perSecond()
			task.wait(1)
		end
	end)

	-- Hide prompts (hatch, upgrades) that belong to other players' bases.
	-- Done with the activation distance, not Enabled: the server toggles
	-- Enabled itself, and a local override there could stick forever.
	local promptRange: { [Instance]: number } = {}
	local function filterPrompt(p: Instance)
		if p:IsA("ProximityPrompt") then
			promptRange[p] = p.MaxActivationDistance
			local function apply()
				local owner = p:GetAttribute("OwnerId")
				local mine = owner == nil or owner == player.UserId
				p.MaxActivationDistance = mine and promptRange[p] or 0
			end
			apply()
			p:GetAttributeChangedSignal("OwnerId"):Connect(apply)
			p.Destroying:Connect(function()
				promptRange[p] = nil
			end)
		end
	end
	local pensFolder = workspace:WaitForChild("Pens")
	for _, d in pensFolder:GetDescendants() do
		filterPrompt(d)
	end
	pensFolder.DescendantAdded:Connect(filterPrompt)
end

Hud.touch = function(): boolean
	return touch
end

return Hud
