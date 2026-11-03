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
local Balls = require(Config:WaitForChild("Balls"))
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
local PowerMeter = require(Components:WaitForChild("PowerMeter"))
local Toast = require(Components:WaitForChild("Toast"))

local HUD = {}

export type HUDDeps = {
	Parent: Instance,
	IsTouch: boolean,
	Open: (screen: string) -> (), -- router
	OnChargeBegin: (() -> ())?, -- first press (only fired on the platform, on your turn, nothing in flight)
	OnChargeRelease: (() -> ())?, -- second press
	OwnsThrowInput: boolean?, -- false if another module handles input; the HUD then only displays
}

export type HUDHandle = {
	Root: Frame,
	Toasts: Toast.ToastHandle,
	SetCharging: (self: HUDHandle, on: boolean, startClock: number?, isTutorial: boolean?) -> (),
	SetThrowLocked: (self: HUDHandle, locked: boolean, reason: string?) -> (),
	SetSuppressed: (self: HUDHandle, on: boolean) -> (), -- hides throw prompt/meter and ignores input (modal open)
	IsCharging: (self: HUDHandle) -> boolean,
	RefreshThrow: (self: HUDHandle) -> (),
	Meter: PowerMeter.MeterHandle,
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

-- Remaining count of a consumable ball. State.BallCount is the contract; older snapshots stored true.
local function ballCount(id: string): number?
	local fn = (State :: any).BallCount
	local n: any = nil
	if type(fn) == "function" then
		local ok, v = pcall(fn, id)
		n = if ok then v else nil
	else
		n = (State.Get().Balls or {})[id]
	end
	return if type(n) == "number" then n else nil
end

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
	-- Bottom to top: reach + catch chips, the prompt row (equipped ball + "Click to throw" or the queue
	-- line), and the vertical power meter (only while charging). Only shown while the server says the local
	-- player is on the platform (attribute OnPlatform) and it is their turn (ThrowQueuePos == 1).
	local meterLen = if touch then 132 else 190
	local infoH, promptH, gap = 36, 48, Theme.Space.S
	local cluster: Frame = Make("Frame", {
		Name = "ThrowCluster",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(clusterW, infoH + gap + promptH + Theme.Space.M + meterLen + 32),
		Position = UDim2.new(0.5, 0, 1, -E),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 2,
		Parent = root,
	})
	-- Reach + catch line (two chips side by side)
	local infoRow: Frame = Make("Frame", { Name = "InfoRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, infoH), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = cluster })
	Decor.List(infoRow, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Center)
	local reachChip = Pill.new({ Name = "Reach", Icon = "zone_backyard", Palette = "Paper", Width = if touch then 164 else 190, Height = infoH, LayoutOrder = 1, Parent = infoRow })
	local catchChip = Pill.new({ Name = "Catch", Icon = "paw", Palette = "Paper", Width = if touch then 136 else 160, Height = infoH, LayoutOrder = 2, Parent = infoRow })
	-- Prompt row: equipped ball chip + the prompt button.
	local promptRow: Frame = Make("Frame", { Name = "PromptRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, promptH), Position = UDim2.new(0, 0, 1, -(infoH + gap)), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = cluster })
	Decor.List(promptRow, Enum.FillDirection.Horizontal, Theme.Space.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local ballChip = Pill.new({ Name = "BallChip", Icon = "ball_tennis", Palette = "Paper", Width = 84, Height = 40, LayoutOrder = 1, Parent = promptRow })
	local idleText = if touch then "Tap to throw" else "Click to throw"
	local chargeText = if touch then "Tap to release" else "Click to release"
	local throwButton = Button.new({
		Name = "Throw",
		Text = idleText,
		Palette = "Tennis",
		Size = UDim2.fromOffset(if touch then 180 else 200, promptH),
		Radius = 16,
		LayoutOrder = 2,
		ZIndex = 4,
		Parent = promptRow,
	})
	local waitLabel = Label.Display({
		Name = "QueueLine",
		Text = "",
		TextSize = Theme.Text.Body,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0.5, 0, 1, -(infoH + gap + promptH / 2)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		XAlign = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
		Parent = cluster,
	})
	-- Power meter
	local meter = PowerMeter.new({
		Name = "PowerMeter",
		Length = meterLen,
		Position = UDim2.new(0.5, 0, 1, -(infoH + gap + promptH + Theme.Space.XS)),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Parent = cluster,
	})
	meter.Root.Visible = false

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
	local suppressed = false -- a modal panel is open
	local frozenUntil = 0 -- keep the released meter on screen briefly
	local player = Players.LocalPlayer

	local handle = { Root = root, Toasts = toasts, Meter = meter } :: any

	local function onPlatform(): boolean
		return player ~= nil and player:GetAttribute("OnPlatform") == true
	end
	local function queuePos(): number
		local q = if player then player:GetAttribute("ThrowQueuePos") else nil
		return if type(q) == "number" then q else 0
	end
	local function myTurn(): boolean
		return onPlatform() and queuePos() == 1
	end

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
		local streakGradient = streakPill.Root:FindFirstChildOfClass("UIGradient")
		if streakGradient then
			local p = if streak >= Rarities.LuckyStreakMisses then Theme.Palette.Cash else Theme.Palette.Slate
			streakGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(1, p.Bottom) })
		end
		-- Equipped ball + remaining count (Tennis is unlimited: icon only).
		local ball = State.Ball()
		Icon.Set(ballChip.Icon, Icon.ForBall(ball.Id))
		local count = ballCount(ball.Id)
		if ball.Id == Balls.Default or count == nil then
			ballChip:SetText("")
			ballChip.Root.Size = UDim2.fromOffset(40, 40)
		else
			ballChip:SetText("x" .. FormatNumber.Compact(count))
			ballChip.Root.Size = UDim2.fromOffset(92, 40)
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

	local function renderMeter()
		local pos = Meter.Position(os.clock() - chargeStart, chargePeriod)
		meter:SetFraction(pos)
	end

	-- What the throw cluster shows, from the platform attributes and the throw state.
	local function refreshThrow()
		local turn = myTurn()
		local showPrompt = (turn and not locked) or charging
		throwButton.Root.Visible = showPrompt
		ballChip.Root.Visible = showPrompt
		throwButton:SetText(if charging then chargeText else idleText)
		throwButton:SetPalette(if charging then "Cash" else "Tennis")
		local q = queuePos()
		waitLabel.Visible = onPlatform() and q >= 2 and not charging
		waitLabel.Text = "Waiting for your turn (#" .. tostring(q) .. ")"
		meter.Root.Visible = charging or os.clock() < frozenUntil
		promptRow.Visible = not suppressed
		waitLabel.Visible = waitLabel.Visible and not suppressed
		meter.Root.Visible = meter.Root.Visible and not suppressed
	end

	-- Per-frame: meter sweep, boost countdowns, banner timer.
	local acc = 0
	local wasFrozen = false
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		if charging then
			renderMeter()
			if os.clock() - chargeStart > Game.Throw.MaxChargeSeconds and deps.OnChargeRelease then
				deps.OnChargeRelease() -- the server auto-releases at the same moment
			end
		end
		local frozen = os.clock() < frozenUntil
		if wasFrozen and not frozen then
			refreshThrow()
		end
		wasFrozen = frozen
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

	-- One press toggles: first press starts the meter (ChargeBegin), the second releases (ChargeRelease).
	local function press()
		if suppressed then
			return
		end
		if charging then
			if deps.OnChargeRelease then
				deps.OnChargeRelease()
			end
		elseif myTurn() and not locked then
			if deps.OnChargeBegin then
				deps.OnChargeBegin()
			end
		end
	end

	local connections: { RBXScriptConnection } = { heartbeat }
	if deps.OwnsThrowInput ~= false then
		throwButton.Root.Activated:Connect(press)
		table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				press()
			elseif processed then
				return
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Space then
				press()
			end
		end))
		-- Touch: a tap on the world (not a drag, not a GUI button) counts as a click.
		pcall(function()
			table.insert(connections, (UserInputService :: any).TouchTapInWorld:Connect(function(_pos: Vector2, processedByUI: boolean)
				if not processedByUI then
					press()
				end
			end))
		end)
	end
	if player then
		table.insert(connections, player:GetAttributeChangedSignal("OnPlatform"):Connect(function()
			if charging and not myTurn() then
				handle:SetCharging(false)
			end
			refreshThrow()
		end))
		table.insert(connections, player:GetAttributeChangedSignal("ThrowQueuePos"):Connect(function()
			if charging and not myTurn() then
				handle:SetCharging(false)
			end
			refreshThrow()
		end))
	end

	table.insert(connections, State.Changed:Connect(refreshStatic))
	table.insert(connections, State.EventsChanged:Connect(refreshBanner))

	function handle.SetCharging(_, on: boolean, startClock: number?, isTutorial: boolean?)
		local was = charging
		charging = on
		if on then
			chargeStart = startClock or os.clock()
			chargePeriod = Meter.Period(isTutorial)
			frozenUntil = 0
			renderMeter()
			Motion.Pulse(throwButton.Root, 1.06)
		else
			-- Freeze the released value on screen for a moment, then hide.
			frozenUntil = if was then os.clock() + 0.6 else 0
			if not was then
				meter:SetFraction(0)
			end
		end
		refreshThrow()
	end
	function handle.SetThrowLocked(_, isLocked: boolean, _reason: string?)
		locked = isLocked
		refreshThrow()
	end
	function handle.SetSuppressed(_, on: boolean)
		suppressed = on
		refreshThrow()
	end
	function handle.IsCharging(): boolean
		return charging
	end
	function handle.RefreshThrow()
		refreshThrow()
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
	refreshThrow()
	return handle :: HUDHandle
end

return HUD
