-- Always-on HUD: top bar (Buy / Base / Sell), side buttons, stats, the
-- ocean status bar with "Close Ocean!", the hold-to-charge meter, the
-- training button, toasts and floating numbers.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local Ui = require(script.Parent.Ui)
local State = require(script.Parent.Parent.State)
local Ocean = require(script.Parent.Parent.Ocean)

local Hud = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui: ScreenGui
local toastHolder: Frame
local feedHolder: Frame
local refs: { [string]: any } = {}

----------------------------------------------------------------------------
-- Toasts & floating text
----------------------------------------------------------------------------
function Hud.toast(text: string, color: Color3?)
	local label = Ui.text({
		Text = text,
		Size = UDim2.new(1, 0, 0, 34),
		TextColor3 = color or C.White,
		StrokeThickness = 3,
		ZIndex = 50,
		Parent = toastHolder,
	})
	label.TextTransparency = 1
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(3, function()
		local tw = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 })
		tw:Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		tw.Completed:Wait()
		label:Destroy()
	end)
	local items = toastHolder:GetChildren()
	local labels = {}
	for _, c in items do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels > 4 then
		labels[1]:Destroy()
	end
end

-- Big text that pops at a screen position and floats up.
function Hud.pop(text: string, color: Color3, pos: UDim2, size: number?)
	local label = Ui.text({
		Text = text,
		Size = UDim2.fromOffset(320, size or 44),
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
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		label:Destroy()
	end)
end

local function feed(amount: number)
	local label = Ui.text({
		Text = "+" .. Format.cash(amount),
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = C.Cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Rotation = -4,
		ZIndex = 5,
		Parent = feedHolder,
	})
	task.delay(2.6, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		label:Destroy()
	end)
	local n = 0
	for _, c in feedHolder:GetChildren() do
		if c:IsA("TextLabel") then
			n += 1
		end
	end
	if n > 4 then
		for _, c in feedHolder:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------
local function buildTopBar()
	local bar = Ui.new("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(660, 72),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	Ui.button({ Text = "Buy", Color = C.Blue, Size = UDim2.fromOffset(200, 66), LayoutOrder = 1, Radius = 4, Parent = bar, OnClick = function()
		Ui.toggle("Upgrades")
	end })
	Ui.button({ Text = "Base", Color = C.Brown, Size = UDim2.fromOffset(200, 66), LayoutOrder = 2, Radius = 4, Parent = bar, OnClick = function()
		State.action("TeleportHome")
	end })
	Ui.button({ Text = "Sell", Color = C.Orange, Size = UDim2.fromOffset(200, 66), LayoutOrder = 3, Radius = 4, Parent = bar, OnClick = function()
		Ui.toggle("Sell")
	end })

	-- Ocean status: shown while your sea is parted.
	local status = Ui.new("Frame", {
		Name = "OceanStatus",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(420, 100),
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = gui,
	})
	refs.statusTimer = Ui.text({
		Text = "",
		Size = UDim2.new(1, 0, 0, 36),
		TextColor3 = C.White,
		StrokeThickness = 3,
		Parent = status,
	})
	refs.closeBtn = Ui.button({
		Text = "Close Ocean! 🌊",
		Color = C.Red,
		Size = UDim2.fromOffset(260, 50),
		Position = UDim2.new(0.5, 0, 0, 42),
		AnchorPoint = Vector2.new(0.5, 0),
		Radius = 4,
		Parent = status,
		OnClick = function()
			Ocean.close()
		end,
	})
	refs.status = status
	refs.goPrompt = Ui.text({
		Text = "",
		Size = UDim2.fromOffset(600, 34),
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Color3.fromRGB(150, 230, 255),
		StrokeThickness = 3,
		Visible = false,
		Parent = gui,
	})
end

local function buildLeft()
	local col = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, 110),
		Position = UDim2.new(0, 16, 0.5, -150),
		Parent = gui,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = col,
	})
	local pets = Ui.button({ Text = "Pets", Icon = "🐾", Color = C.Orange, Size = UDim2.fromOffset(100, 100), LayoutOrder = 1, Parent = col, OnClick = function()
		Ui.toggle("Pets")
	end })
	local eggs = Ui.button({ Text = "Eggs", Icon = "🥚", Color = C.Teal, Size = UDim2.fromOffset(100, 100), LayoutOrder = 2, Parent = col, OnClick = function()
		Ui.toggle("Eggs")
	end })
	refs.eggsBadge = Ui.badge(eggs, "!")
	refs.petsBadge = Ui.badge(pets, "!")

	feedHolder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 150),
		Position = UDim2.new(0, 26, 0.5, -30),
		Parent = gui,
	})
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Parent = feedHolder })

	-- Stats, bottom-left.
	local stats = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(360, 170),
		Position = UDim2.new(0, 18, 1, -186),
		Parent = gui,
	})
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = stats })
	local function stat(icon: string, color: Color3, order: number, height: number)
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), LayoutOrder = order, Parent = stats })
		Ui.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = icon,
			TextScaled = true,
			Size = UDim2.fromOffset(height, height),
			Parent = row,
		})
		return Ui.text({
			Text = "0",
			Size = UDim2.new(1, -height - 8, 1, 0),
			Position = UDim2.fromOffset(height + 8, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			StrokeThickness = 3.5,
			Parent = row,
		})
	end
	refs.cash = stat("💵", C.Cash, 1, 62)
	refs.strength = stat("💪", C.Yellow, 2, 46)
	refs.luck = stat("🍀", Color3.fromRGB(150, 255, 150), 3, 40)
end

local function buildRight()
	local grid = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, 230),
		Position = UDim2.new(1, -16, 0.5, -70),
		AnchorPoint = Vector2.new(1, 0),
		Parent = gui,
	})
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(100, 100),
		CellPadding = UDim2.fromOffset(12, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Parent = grid,
	})
	local index = Ui.button({ Text = "Index", Icon = "📖", Color = C.Blue, LayoutOrder = 1, Parent = grid, OnClick = function()
		Ui.toggle("Index")
	end })
	local shop = Ui.button({ Text = "Shop", Icon = "🛒", Color = C.Yellow, LayoutOrder = 2, Parent = grid, OnClick = function()
		Ui.toggle("Store")
	end })
	local gift = Ui.button({ Text = "Gifts", Icon = "🎁", Color = C.Pink, LayoutOrder = 3, Parent = grid, OnClick = function()
		Ui.toggle("Playtime")
	end })
	local daily = Ui.button({ Text = "Daily", Icon = "📅", Color = C.Purple, LayoutOrder = 4, Parent = grid, OnClick = function()
		Ui.toggle("Daily")
	end })
	refs.indexBadge = Ui.badge(index, "!")
	refs.giftLabel = gift:FindFirstChild("Label")
	refs.giftBadge = Ui.badge(gift, "!")
	refs.dailyBadge = Ui.badge(daily, "!")
	local free = Ui.badge(shop, "R$")
	free.Visible = true
	free.Size = UDim2.fromOffset(40, 28)
	free.BackgroundColor3 = C.Green

	-- Starter pack promo, top-right.
	refs.starter = Ui.button({
		Text = "STARTER PACK!\nR$" .. Config.Products[1].price,
		Icon = "🎁",
		Color = C.Red,
		Size = UDim2.fromOffset(170, 130),
		Position = UDim2.new(1, -16, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Parent = gui,
		OnClick = function()
			Ui.open("Store")
		end,
	})
	local lbl = refs.starter:FindFirstChild("Label") :: TextLabel
	lbl.Size = UDim2.new(1, -8, 0.4, 0)
end

local function buildCharge()
	local frame = Ui.new("Frame", {
		Name = "Charge",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 300),
		Position = UDim2.new(0.5, 110, 0.5, -150),
		Visible = false,
		Parent = gui,
	})
	local bar = Ui.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		Size = UDim2.fromOffset(46, 260),
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
	local marker = Ui.text({
		Text = "◀ +0s Open Time",
		Size = UDim2.fromOffset(180, 24),
		Position = UDim2.fromOffset(54, 248),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 255, 130),
		Parent = frame,
	})
	Ui.text({
		Text = "Hold to Charge",
		Size = UDim2.fromOffset(160, 26),
		Position = UDim2.new(0, 23, 0, 266),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = frame,
	})
	refs.charge = frame
	refs.chargeFill = fill
	refs.chargeMarker = marker
end

local function buildTrain()
	refs.trainBtn = Ui.button({
		Text = "TRAIN 💪",
		Color = C.Orange,
		Size = UDim2.fromOffset(300, 70),
		Position = UDim2.new(0.5, 0, 1, -110),
		AnchorPoint = Vector2.new(0.5, 0),
		Radius = 4,
		Visible = false,
		Parent = gui,
		OnClick = function()
			if player:GetAttribute("Training") then
				Remotes.get("Train"):FireServer("stop")
			else
				Remotes.get("Train"):FireServer("start")
			end
		end,
	})
	refs.trainHint = Ui.text({
		Text = "Click / tap anywhere to lift faster!",
		Size = UDim2.fromOffset(420, 26),
		Position = UDim2.new(0.5, 0, 1, -140),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Color3.fromRGB(255, 240, 160),
		Visible = false,
		Parent = gui,
	})
end

----------------------------------------------------------------------------
-- Updates
----------------------------------------------------------------------------
local function onState(d)
	refs.cash.Text = Format.short(d.cash) .. "$"
	refs.strength.Text = Format.short(d.strength)
	local luckText = "x" .. string.format("%.2f", d.luck):gsub("%.?0+$", "") .. " Luck"
	if d.boosts and d.boosts.luckUntil > d.osTime then
		luckText ..= " 🧪"
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

local function perFrame()
	-- Charge meter
	refs.charge.Visible = Ocean.canCharge
	if Ocean.canCharge then
		local c = Ocean.charge
		refs.chargeFill.Size = UDim2.fromScale(1, c)
		refs.chargeMarker.Position = UDim2.fromOffset(54, 260 * (1 - c) - 12)
		refs.chargeMarker.Text = "◀ +" .. math.floor(c * Config.Split.ChargeOpenBonus * 10 + 0.5) / 10 .. "s Open Time"
	end

	-- Ocean status / prompts
	local phase, left = Ocean.timing()
	refs.status.Visible = phase ~= nil
	if phase == "open" then
		refs.statusTimer.Text = "🌊 Ocean open: " .. string.format("%.1f", left) .. "s"
		refs.statusTimer.TextColor3 = Color3.fromRGB(150, 230, 255)
	elseif phase == "closing" then
		refs.statusTimer.Text = "⚠️ CLOSING! Get back to the beach!"
		refs.statusTimer.TextColor3 = Color3.fromRGB(255, 110, 100)
	end
	if phase then
		local cap = State.data and State.data.carry or 1
		refs.statusTimer.Text ..= "   🥚 " .. Ocean.carried .. "/" .. cap
	end
	-- Only offer "Close Ocean!" while you're safely on land.
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local onLand = root and (math.abs(root.Position.Z) >= Config.Ocean.ShoreZ or math.abs(root.Position.X) >= Config.Ocean.HalfX)
	refs.closeBtn.Visible = phase ~= nil and onLand == true
	if Ocean.inZone and not Ocean.canCharge and not phase then
		refs.goPrompt.Text = "Equip your Sea Staff to part the ocean!"
		refs.goPrompt.Visible = true
	elseif Ocean.canCharge and not Ocean.charging then
		refs.goPrompt.Text = "Hold click / tap to charge, release to part the sea!"
		refs.goPrompt.Visible = true
	else
		refs.goPrompt.Visible = false
	end

	-- Training
	local onPad = player:GetAttribute("OnTrainPad") == true
	local training = player:GetAttribute("Training") == true
	refs.trainBtn.Visible = onPad or training
	refs.trainHint.Visible = training
	Ui.setButtonText(refs.trainBtn, training and "STOP TRAIN" or "TRAIN 💪")
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

function Hud.init()
	gui = Ui.screen("Hud", 1)
	toastHolder = Ui.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(700, 200),
		Position = UDim2.new(0.5, 0, 0.26, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = gui,
	})
	Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = toastHolder })

	buildTopBar()
	buildLeft()
	buildRight()
	buildCharge()
	buildTrain()

	State.toast:Connect(Hud.toast)
	State.changed:Connect(onState)
	if State.data then
		onState(State.data)
	end

	State.effect:Connect(function(kind, payload)
		if kind == "income" then
			feed(payload)
		elseif kind == "lift" then
			Hud.pop("+" .. Format.short(payload.gain) .. " Power 💪", C.Yellow, UDim2.new(0.5, math.random(-120, 120), 0.55, math.random(-40, 40)))
		elseif kind == "offline" then
			Hud.pop("+" .. Format.cash(payload.cash) .. " offline! 🤑", C.Cash, UDim2.fromScale(0.5, 0.4), 60)
			Hud.toast("You earned " .. Format.cash(payload.cash) .. " while you were away!", C.Cash)
		elseif kind == "banked" then
			for _, b in payload do
				local e = Config.EggById[b.egg]
				local where = b.where == "pen" and " → incubating in your base!" or b.where == "storage" and " → stored (base full)" or " → sold (storage full)"
				Hud.toast("🥚 " .. (b.variant ~= "Normal" and b.variant .. " " or "") .. e.name .. where, Config.Rarities[e.tier].color)
			end
			Hud.pop("SAFE! 🥚", C.Cash, UDim2.fromScale(0.5, 0.45), 64)
		elseif kind == "caught" then
			Hud.pop("SPLASH! 🌊", Color3.fromRGB(120, 200, 255), UDim2.fromScale(0.5, 0.45), 64)
		elseif kind == "discover" then
			Hud.toast("📖 New Index entry: " .. payload.animal .. "!", C.Yellow)
		end
	end)

	-- Clicking anywhere while training lifts faster.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and player:GetAttribute("Training") then
			Remotes.get("Train"):FireServer("lift")
		end
	end)

	RunService.RenderStepped:Connect(perFrame)
	task.spawn(function()
		while true do
			perSecond()
			task.wait(1)
		end
	end)

	-- Hide prompts (hatch, upgrades) that belong to other players' bases.
	local function filterPrompt(p: Instance)
		if p:IsA("ProximityPrompt") then
			local function apply()
				local owner = p:GetAttribute("OwnerId")
				if owner ~= nil and owner ~= player.UserId then
					p.Enabled = false
				end
			end
			apply()
			p:GetAttributeChangedSignal("OwnerId"):Connect(apply)
			p:GetPropertyChangedSignal("Enabled"):Connect(function()
				local owner = p:GetAttribute("OwnerId")
				if p.Enabled and owner ~= nil and owner ~= player.UserId then
					p.Enabled = false
				end
			end)
		end
	end
	local pensFolder = workspace:WaitForChild("Pens")
	for _, d in pensFolder:GetDescendants() do
		filterPrompt(d)
	end
	pensFolder.DescendantAdded:Connect(filterPrompt)
end

return Hud
