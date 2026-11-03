--!strict
-- The always-on HUD. Regions (style guide section 2): top-left currencies, left side menu, top-centre event
-- banner + toasts, top-right boost chips + Lucky Streak, bottom-centre throw cluster, bottom-right ticker.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Game = require(Config:WaitForChild("Game"))
local Zones = require(Config:WaitForChild("Zones"))
local Timers = require(Config:WaitForChild("Timers"))
local Rarities = require(Config:WaitForChild("Rarities"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local Meter = require(Util:WaitForChild("Meter"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local State = require(UI:WaitForChild("State"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))
local Pill = require(Components:WaitForChild("Pill"))
local ProgressBar = require(Components:WaitForChild("ProgressBar"))
local Toast = require(Components:WaitForChild("Toast"))

local HUD = {}

export type HUDDeps = {
	Parent: Instance,
	IsTouch: boolean,
	Open: (screen: string) -> (), -- router
	OnChargeBegin: (() -> ())?,
	OnChargeRelease: (() -> ())?,
	OwnsThrowInput: boolean?, -- false if another module handles input; the HUD then only displays
}

export type HUDHandle = {
	Root: Frame,
	Toasts: Toast.ToastHandle,
	SetCharging: (self: HUDHandle, on: boolean, startClock: number?, isTutorial: boolean?) -> (),
	SetThrowLocked: (self: HUDHandle, locked: boolean, reason: string?) -> (),
	Broadcast: (self: HUDHandle, payload: any) -> (),
	Refresh: (self: HUDHandle) -> (),
	SetBadge: (self: HUDHandle, screen: string, on: boolean) -> (),
	Destroy: (self: HUDHandle) -> (),
}

local SIDE_ITEMS = {
	{ Id = "Shop", Icon = "shop", Caption = "Shop" },
	{ Id = "Dogs", Icon = "dog", Caption = "Dogs" },
	{ Id = "Book", Icon = "book", Caption = "Book" },
	{ Id = "Odds", Icon = "odds", Caption = "Odds" },
	{ Id = "Settings", Icon = "settings", Caption = "Options" },
}

local function zoneById(id: string): any
	for _, z in Zones do
		if z.Id == id then
			return z
		end
	end
	return Zones[1]
end

function HUD.new(deps: HUDDeps): HUDHandle
	local touch = deps.IsTouch
	local E = if touch then Theme.Space.M else Theme.Space.Edge
	local pillH = if touch then 34 else 40
	local sideBtn = if touch then 48 else Theme.Touch.SideButton
	local sideBtnW = if touch then 58 else Theme.Touch.SideButton
	local sideGap = if touch then 6 else Theme.Space.S
	local clusterW = if touch then 350 else 420
	local root: Frame = Make("Frame", {
		Name = "HUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = deps.Parent,
	})

	-- ---------------------------------------------------------------- top-left: currencies
	-- Desktop: a vertical stack. Touch: one horizontal row so the left edge stays clear of the thumbstick.
	local currencies: Frame = Make("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(E + 4, E),
		Size = if touch then UDim2.fromOffset(150 + 110 + 110 + 2 * Theme.Space.S + 8, pillH + 18) else UDim2.fromOffset(190, 3 * pillH + 18 + 3 * Theme.Space.S),
		ZIndex = 2,
		Parent = root,
	})
	local currencyRow: Frame = currencies
	if touch then
		currencyRow = Make("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, pillH), ZIndex = 2, Parent = currencies })
		Decor.List(currencyRow, Enum.FillDirection.Horizontal, Theme.Space.S + 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	else
		Decor.List(currencies, Enum.FillDirection.Vertical, Theme.Space.S)
	end
	local cashPill = Pill.new({ Name = "Cash", Icon = "cash", Palette = "Cash", Format = FormatNumber.Money, Width = if touch then 150 else 180, Height = pillH, LayoutOrder = 1, Parent = currencyRow, OnClick = function()
		deps.Open("Shop")
	end })
	local incomeLabel = Label.Display({
		Name = "Income",
		Text = "+$0/s",
		TextSize = Theme.Text.Caption,
		Size = UDim2.fromOffset(180, 18),
		Position = if touch then UDim2.fromOffset(0, pillH) else UDim2.new(),
		XAlign = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = currencies,
	})
	Make("UIPadding", { PaddingLeft = UDim.new(0, if touch then 36 else 44), Parent = incomeLabel })
	local bonesPill = Pill.new({ Name = "Bones", Icon = "bone", Palette = "Bone", Format = FormatNumber.Compact, Width = if touch then 110 else 150, Height = pillH, LayoutOrder = 3, Parent = currencyRow })
	local powerPill = Pill.new({ Name = "ThrowPower", Icon = "throw_power", Palette = "Tennis", Format = FormatNumber.Compact, Width = if touch then 110 else 150, Height = pillH, LayoutOrder = 4, Parent = currencyRow })

	-- ---------------------------------------------------------------- left: side menu
	local sideTop = E + currencies.Size.Y.Offset + (if touch then Theme.Space.S else Theme.Space.XL)
	local side: Frame = Make("Frame", {
		Name = "SideMenu",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(E, sideTop),
		Size = if touch then UDim2.fromOffset(#SIDE_ITEMS * (sideBtnW + sideGap) - sideGap, sideBtn) else UDim2.fromOffset(sideBtn, #SIDE_ITEMS * (sideBtn + sideGap) - sideGap),
		ZIndex = 2,
		Parent = root,
	})
	Decor.List(side, if touch then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, sideGap)
	local sideButtons: { [string]: Button.ButtonHandle } = {}
	for i, item in SIDE_ITEMS do
		sideButtons[item.Id] = Button.new({
			Name = "Side_" .. item.Id,
			Icon = item.Icon,
			IconSize = if touch then 16 else 32,
			Caption = item.Caption,
			Palette = "Sky",
			Size = UDim2.fromOffset(sideBtnW, sideBtn),
			LayoutOrder = i,
			ZIndex = 3,
			Parent = side,
			OnClick = function()
				deps.Open(item.Id)
			end,
		})
	end

	-- ---------------------------------------------------------------- top-centre: event banner + toasts
	-- Touch: the banner sits left of the top-right stack (the centre is taken by the currency row on
	-- small phones). Desktop: centred.
	local topRightW = 140
	local bannerW = if touch then 300 else 380
	local bannerPos = if touch then UDim2.new(1, -(E + topRightW + Theme.Space.S), 0, E) else UDim2.new(0.5, 0, 0, E)
	local bannerAnchor = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0)
	local banner: Frame = Make("Frame", {
		Name = "EventBanner",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(bannerW, 44),
		Position = bannerPos,
		AnchorPoint = bannerAnchor,
		Visible = false,
		ZIndex = 4,
		Parent = root,
	})
	Decor.Corner(banner, Theme.Radius.Pill)
	Decor.Stroke(banner, Theme.Stroke.Panel)
	local bannerGradient = Decor.PaletteGradient(banner, Theme.Palette.Purple)
	Decor.Shadow(banner, "Hard")
	local bannerIcon = Icon.new({ Name = "squirrel", Size = 32, Position = UDim2.new(0, Theme.Space.S, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 5, Parent = banner })
	local bannerText = Label.Display({ Name = "Text", Text = "", TextSize = Theme.Text.Body, Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(Theme.Space.S + 32 + Theme.Space.S, 0), ZIndex = 5, Parent = banner })
	local bannerTimer = Label.Display({ Name = "Timer", Text = "", TextSize = Theme.Text.Body, Size = UDim2.fromOffset(64, 44), Position = UDim2.new(1, -Theme.Space.M, 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 5, Parent = banner })
	local toasts = Toast.new(root, bannerPos + UDim2.fromOffset(0, 44 + Theme.Space.S), bannerAnchor, if touch then 2 else 3, touch)
	toasts.Root.Size = UDim2.fromOffset(bannerW, toasts.Root.Size.Y.Offset)

	-- ---------------------------------------------------------------- top-right: boosts + lucky streak
	local topRight: Frame = Make("Frame", {
		Name = "TopRight",
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -E, 0, E + (if deps.IsTouch then 0 else Theme.Reserved.TopRight.Y)),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(topRightW, 160),
		ZIndex = 2,
		Parent = root,
	})
	Decor.List(topRight, Enum.FillDirection.Vertical, Theme.Space.S, Enum.HorizontalAlignment.Right)
	local streakPill = Pill.new({ Name = "LuckyStreak", Icon = "bolt", Palette = "Slate", Width = topRightW, Height = 36, LayoutOrder = 1, Parent = topRight, OnClick = function()
		deps.Open("Odds")
	end })
	streakPill:SetText("Streak 0/" .. Rarities.LuckyStreakMisses)
	streakPill.Value.TextSize = Theme.Text.Caption + 1
	local boostChips: { [string]: Pill.PillHandle } = {}
	local chipOrder = 2
	local function chipFor(id: string, kind: string): Pill.PillHandle
		local existing = boostChips[id]
		if existing then
			return existing
		end
		chipOrder += 1
		local chip = Pill.new({ Name = "Boost_" .. id, Icon = if kind == "Luck" then "boost_luck" else "boost_catch", Palette = if kind == "Luck" then "Grass" else "Sky", Width = topRightW, Height = 36, LayoutOrder = chipOrder, Parent = topRight })
		boostChips[id] = chip
		return chip
	end

	-- ---------------------------------------------------------------- bottom-centre: throw cluster
	local cluster: Frame = Make("Frame", {
		Name = "ThrowCluster",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(clusterW, 150),
		Position = UDim2.new(0.5, 0, 1, -E),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 2,
		Parent = root,
	})
	-- Reach + catch line (two chips side by side)
	local infoRow: Frame = Make("Frame", { Name = "InfoRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), ZIndex = 3, Parent = cluster })
	Decor.List(infoRow, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Center)
	local reachChip = Pill.new({ Name = "Reach", Icon = "zone_backyard", Palette = "Paper", Width = if touch then 164 else 190, Height = 36, LayoutOrder = 1, Parent = infoRow })
	local catchChip = Pill.new({ Name = "Catch", Icon = "paw", Palette = "Paper", Width = if touch then 136 else 160, Height = 36, LayoutOrder = 2, Parent = infoRow })
	-- Meter
	local meter = ProgressBar.new({ Name = "Meter", Palette = "Tennis", Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0.5, 0, 0, 46), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3, Label = "Hold to throw", Parent = cluster })
	meter:SetBand(Game.Meter.GoodMin, 1, Theme.Palette.Grass.Top)
	local perfectMark: Frame = Make("Frame", {
		Name = "Perfect",
		BackgroundColor3 = Theme.Palette.Cash.Bottom,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1 - Game.Meter.PerfectMin, 0, 1, 0),
		Position = UDim2.fromScale(Game.Meter.PerfectMin, 0),
		ZIndex = meter.Root.ZIndex + 1,
		Parent = meter.Root,
	})
	perfectMark.Name = "PerfectBand"
	-- Throw button
	local throwButton = Button.new({
		Name = "Throw",
		Icon = "ball_tennis",
		IconSize = 48,
		Palette = "Tennis",
		Size = UDim2.fromOffset(Theme.Touch.ThrowButton, 64),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Radius = 16,
		ZIndex = 3,
		Parent = cluster,
	})
	local throwHint = Label.Display({ Name = "Hint", Text = if deps.IsTouch then "Hold the ball" else "Hold SPACE or the ball", TextSize = Theme.Text.Caption, Size = UDim2.fromOffset(200, 16), Position = UDim2.new(0.5, 0, 0, 74), AnchorPoint = Vector2.new(0.5, 0), XAlign = Enum.TextXAlignment.Center, ZIndex = 3, Parent = cluster })
	throwHint.Name = "ThrowHint"

	-- ---------------------------------------------------------------- bottom-right: ticker (desktop only)
	local ticker: Frame? = nil
	local tickerLines: { TextLabel } = {}
	if not deps.IsTouch then
		ticker = Make("Frame", {
			Name = "Ticker",
			BackgroundColor3 = Theme.Color.Scrim,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(300, 3 * 20 + Theme.Space.S * 2),
			Position = UDim2.new(1, -E, 1, -E),
			AnchorPoint = Vector2.new(1, 1),
			ZIndex = 2,
			Parent = root,
		})
		local t = ticker :: Frame
		Decor.Corner(t, Theme.Radius.Button)
		Decor.Padding(t, Theme.Space.S)
		Decor.List(t, Enum.FillDirection.Vertical, 0)
		for i = 1, 3 do
			local l = Label.Display({ Text = "", TextSize = Theme.Text.Caption + 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i, ZIndex = 3, Parent = t })
			table.insert(tickerLines, l)
		end
	end

	-- ---------------------------------------------------------------- behaviour
	local charging = false
	local chargeStart = 0
	local chargePeriod = Game.Meter.Period
	local locked = false

	local function refreshStatic()
		local s = State.Get()
		cashPill:Set(s.Cash or 0)
		bonesPill:Set(s.Bones or 0)
		powerPill:Set(s.ThrowPower or 0)
		incomeLabel.Text = "+" .. FormatNumber.PerSecond(State.Income())
		local reach = State.ReachZone()
		Icon.Set(reachChip.Icon, Icon.ForZone(reach.Id))
		reachChip:SetText(reach.Name .. "  " .. FormatNumber.Compact(State.MaxDistance()) .. " st")
		local computed = State.Computed()
		local chances = computed.CatchChances or {}
		local legendary = chances.Legendary or Rarities.Tiers.Legendary.Catch
		catchChip:SetText(FormatNumber.Percent(legendary, 0) .. " catch")
		local streak = State.LuckyStreak()
		streakPill:SetText("Streak " .. streak .. "/" .. Rarities.LuckyStreakMisses)
		if streak >= Rarities.LuckyStreakMisses then
			Decor.PaletteGradient(streakPill.Root, Theme.Palette.Cash)
		end
		local ball = State.Ball()
		if throwButton.Icon then
			Icon.Set(throwButton.Icon, Icon.ForBall(ball.Id))
		end
		for id, pill in boostChips do
			pill.Root.Visible = false
		end
		for _, b in State.ActiveBoosts() do
			local chip = chipFor(b.Id, b.Kind)
			chip.Root.Visible = true
			chip:SetText(FormatNumber.Duration(b.ExpiresAt - os.time()))
		end
	end

	local function refreshBanner()
		local ev = State.Server.Events
		local show: any = ev.Squirrel or ev.RunawayDog or ev.DailyWalk
		if not show then
			banner.Visible = false
			return
		end
		banner.Visible = true
		if show.Kind == "Squirrel" then
			Icon.Set(bannerIcon, "squirrel")
			bannerText.Text = "Squirrel in the park!"
			bannerGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Theme.Palette.Purple.Top), ColorSequenceKeypoint.new(1, Theme.Palette.Purple.Bottom) })
		elseif show.Kind == "RunawayDog" then
			Icon.Set(bannerIcon, "dog")
			local who = show.Data and show.Data.PlayerName or "someone"
			bannerText.Text = "A dog ran off from " .. who
			bannerGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Theme.Palette.Danger.Top), ColorSequenceKeypoint.new(1, Theme.Palette.Danger.Bottom) })
		else
			Icon.Set(bannerIcon, "walk")
			bannerText.Text = "Daily walk ready"
			bannerGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Theme.Palette.Grass.Top), ColorSequenceKeypoint.new(1, Theme.Palette.Grass.Bottom) })
		end
		local endsAt = tonumber(show.EndsAt)
		bannerTimer.Text = if endsAt then FormatNumber.Duration(endsAt - os.time()) else ""
	end

	-- Per-frame: meter sweep, boost countdowns, banner timer.
	local acc = 0
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		if charging then
			local pos = Meter.Position(os.clock() - chargeStart, chargePeriod)
			meter:SetFraction(pos)
			local _, band = Meter.QualityForPosition(pos)
			meter:SetLabel(band)
		end
		acc += dt
		if acc >= 1 then
			acc = 0
			for _, b in State.ActiveBoosts() do
				local chip = boostChips[b.Id]
				if chip then
					chip:SetText(FormatNumber.Duration(b.ExpiresAt - os.time()))
				end
			end
			if banner.Visible then
				refreshBanner()
			end
		end
	end)

	local function beginCharge()
		if locked or charging then
			return
		end
		if deps.OnChargeBegin then
			deps.OnChargeBegin()
		end
	end
	local function releaseCharge()
		if not charging then
			return
		end
		if deps.OnChargeRelease then
			deps.OnChargeRelease()
		end
	end

	local connections: { RBXScriptConnection } = { heartbeat }
	if deps.OwnsThrowInput ~= false then
		throwButton.Root.MouseButton1Down:Connect(beginCharge)
		throwButton.Root.MouseButton1Up:Connect(releaseCharge)
		table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 then
				beginCharge()
			end
		end))
		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 then
				releaseCharge()
			end
		end))
	end

	table.insert(connections, State.Changed:Connect(refreshStatic))
	table.insert(connections, State.EventsChanged:Connect(refreshBanner))

	local handle = { Root = root, Toasts = toasts } :: any
	function handle.SetCharging(_, on: boolean, startClock: number?, isTutorial: boolean?)
		charging = on
		if on then
			chargeStart = startClock or os.clock()
			chargePeriod = Meter.Period(isTutorial)
			Motion.Pulse(throwButton.Root, 1.1)
		else
			meter:SetFraction(0)
			meter:SetLabel(if locked then "Fetching..." else "Hold to throw")
		end
	end
	function handle.SetThrowLocked(_, isLocked: boolean, reason: string?)
		locked = isLocked
		throwButton:SetEnabled(not isLocked)
		meter:SetLabel(if isLocked then (reason or "Fetching...") else "Hold to throw")
	end
	function handle.Broadcast(_, payload: any)
		local text = tostring(payload and payload.Text or "")
		local color = Theme.RarityColor(payload and payload.Rarity)
		if ticker then
			for i = #tickerLines, 2, -1 do
				tickerLines[i].Text = tickerLines[i - 1].Text
				tickerLines[i].TextColor3 = tickerLines[i - 1].TextColor3
			end
			tickerLines[1].Text = text
			tickerLines[1].TextColor3 = color
		end
		if payload and payload.Global then
			toasts:Show(text, if payload.Variant then Icon.ForVariant(payload.Variant) else "star", "Purple")
		end
	end
	function handle.Refresh()
		refreshStatic()
		refreshBanner()
	end
	function handle.SetBadge(_, screen: string, on: boolean)
		local b = sideButtons[screen]
		if b then
			b:SetBadge(on)
		end
	end
	function handle.Destroy()
		for _, c in connections do
			c:Disconnect()
		end
		root:Destroy()
	end
	refreshStatic()
	refreshBanner()
	handle:SetCharging(false)
	return handle :: HUDHandle
end

return HUD
