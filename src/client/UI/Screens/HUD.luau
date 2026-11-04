--!strict
-- The always-on HUD (style guide section 2). Regions: top-left currencies (cash biggest), left side menu, top-centre
-- event banner + toasts, top-right Lucky Streak + boost chips, bottom-centre ball hotbar, the throw bar above it
-- (only in the throw zone), and the strength stat (flexed arm + ThrowPower, big blue number) bottom-left on desktop
-- (touch: the end of the currency row, because the bottom-left belongs to the thumbstick).
--
-- Throw flow (one tap, no turns): the bar appears by itself when the server sets the local player's attribute
-- "InThrowZone" (fallback "OnPlatform" if InThrowZone is nil) and nothing is in flight and no panel is open. On
-- appearing the HUD calls deps.OnChargeBegin (fires ChargeBegin; the marker sweeps by itself on Meter.Period, the
-- same clock as the server). One tap / click / Space / R2 calls deps.OnChargeRelease (fires ChargeRelease). If the
-- player never taps, the sweep is restarted with another OnChargeBegin on a period boundary before
-- Game.Throw.MaxChargeSeconds (the server cancels idle charges silently). Leaving the zone hides the bar (no remote).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Game = require(Config:WaitForChild("Game"))
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
	OnChargeBegin: (() -> ())?, -- the bar appeared (or the sweep restarts): fires ChargeBegin
	OnChargeRelease: (() -> ())?, -- the one tap: fires ChargeRelease
	OwnsThrowInput: boolean?, -- false if another module handles input; the HUD then only displays
	ClaimDailyWalk: (() -> ())?, -- clicking the "Claim daily walk" banner
	EquipBall: ((ballId: string) -> ())?, -- hotbar slot clicked / number key pressed
	ScreenHeight: number?, -- usable height in canvas px (sizes the throw bar on touch screens)
}

export type HUDHandle = {
	Root: Frame,
	Toasts: Toast.ToastHandle,
	SetCharging: (self: HUDHandle, on: boolean, startClock: number?, isTutorial: boolean?) -> (),
	SetThrowLocked: (self: HUDHandle, locked: boolean, reason: string?) -> (),
	SetSuppressed: (self: HUDHandle, on: boolean) -> (), -- hides the throw bar and ignores input (modal open)
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

local SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }

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

-- When to restart an untapped sweep: the last period boundary before MaxChargeSeconds (the marker is at the bottom
-- there, so the restart is seamless).
local function restartAfter(period: number): number
	local max = Game.Throw.MaxChargeSeconds
	local n = math.ceil(max / period) - 1
	if n >= 1 and n * period < max then
		return n * period
	end
	return max * 0.9
end

function HUD.new(deps: HUDDeps): HUDHandle
	local touch = deps.IsTouch
	local E = if touch then Theme.Space.M else Theme.Space.Edge
	local root: Frame = Make("Frame", {
		Name = "HUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = deps.Parent,
	})

	-- ---------------------------------------------------------------- top-left: currencies
	-- Desktop: a vertical stack (cash biggest). Touch: one row so the left edge stays clear of the thumbstick.
	local cashH = if touch then 40 else 52
	local bonesH = if touch then 36 else 40
	local hang = 14 -- the icon hangs off the pill's left end
	local currencies: Frame = Make("Frame", {
		Name = "Currencies",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(E + hang, E),
		Size = if touch then UDim2.fromOffset(170 + 110 + 100 + 2 * Theme.Space.M + hang, cashH + 18) else UDim2.fromOffset(240, cashH + 20 + Theme.Space.XS + bonesH),
		ZIndex = 2,
		Parent = root,
	})
	local cashPill = Pill.new({ Name = "Cash", Icon = "cash", Palette = "Cash", Format = FormatNumber.Money, Width = if touch then 170 else 230, Height = cashH, TextSize = if touch then 26 else 32, ZIndex = 3, Parent = currencies, OnClick = function()
		deps.Open("Shop")
	end })
	local incomeLabel = Label.Display({
		Name = "Income",
		Text = "+$0/s",
		TextSize = Theme.Text.Body,
		Color = Theme.Palette.Cash.Top,
		Size = UDim2.fromOffset(180, 20),
		Position = UDim2.fromOffset(if touch then 26 else 34, cashH),
		ZIndex = 3,
		Parent = currencies,
	})
	local bonesPill = Pill.new({ Name = "Bones", Icon = "bone", Palette = "Bone", Format = FormatNumber.Compact, Width = if touch then 110 else 160, Height = bonesH, TextSize = if touch then 20 else 24, ZIndex = 3, Parent = currencies })
	bonesPill.Root.Position = if touch then UDim2.fromOffset(170 + Theme.Space.M + hang, (cashH - bonesH) / 2) else UDim2.fromOffset(0, cashH + 20 + Theme.Space.XS)

	-- ---------------------------------------------------------------- left: side menu
	local sideBtn = if touch then 52 else 68
	local sideBtnW = if touch then 60 else 68
	local sideGap = if touch then 6 else Theme.Space.S
	local sideTop = E + currencies.Size.Y.Offset + (if touch then Theme.Space.S else Theme.Space.L)
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
			IconSize = if touch then 32 else 48,
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
	local topRightW = if touch then 150 else 170
	local bannerW = if touch then 260 else 400
	local bannerH = 48
	local bannerPos = if touch then UDim2.new(1, -(E + topRightW + Theme.Space.S), 0, E) else UDim2.new(0.5, 0, 0, E)
	local bannerAnchor = if touch then Vector2.new(1, 0) else Vector2.new(0.5, 0)
	local banner: Frame = Make("Frame", {
		Name = "EventBanner",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(bannerW, bannerH),
		Position = bannerPos,
		AnchorPoint = bannerAnchor,
		Visible = false,
		ZIndex = 4,
		Parent = root,
	})
	Decor.Corner(banner, Theme.Radius.Card)
	Decor.Stroke(banner, Theme.Stroke.Panel)
	local bannerGradient = Decor.PaletteGradient(banner, Theme.Palette.Purple)
	Decor.Stripes(banner, { Bands = 3, Strength = 0.8, Rotation = -25, ZIndex = 4 })
	Decor.Shadow(banner, "Hard")
	local bannerIcon = Icon.new({ Name = "squirrel", Size = 32, Position = UDim2.new(0, Theme.Space.S, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 5, Parent = banner })
	local bannerText = Label.Display({ Name = "Text", Text = "", TextSize = if touch then 16 else 20, Size = UDim2.new(1, -(Theme.Space.S + 32 + Theme.Space.S + (if touch then 52 else 64)), 1, 0), Position = UDim2.fromOffset(Theme.Space.S + 32 + Theme.Space.S, 0), ZIndex = 5, Parent = banner })
	local bannerTimer = Label.Display({ Name = "Timer", Text = "", TextSize = if touch then 18 else 20, Size = UDim2.fromOffset(if touch then 44 else 60, bannerH), Position = UDim2.new(1, -Theme.Space.M, 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 5, Parent = banner })
	-- the banner is clickable only while it shows the daily walk (claims it through deps.ClaimDailyWalk)
	local bannerKind: string? = nil
	local bannerHit: TextButton = Make("TextButton", {
		Name = "Hit",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Active = false,
		Parent = banner,
	})
	bannerHit.Activated:Connect(function()
		if bannerKind == "DailyWalk" and deps.ClaimDailyWalk then
			deps.ClaimDailyWalk()
		end
	end)
	local toasts = Toast.new(root, bannerPos + UDim2.fromOffset(0, bannerH + Theme.Space.S), bannerAnchor, if touch then 2 else 3, touch)
	toasts.Root.Size = UDim2.fromOffset(bannerW, toasts.Root.Size.Y.Offset)

	-- ---------------------------------------------------------------- top-right: lucky streak + boosts
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
	local chipW = topRightW - hang
	local streakPill = Pill.new({ Name = "LuckyStreak", Icon = "bolt", Palette = "Slate", Width = chipW, Height = 38, LayoutOrder = 1, Parent = topRight, OnClick = function()
		deps.Open("Odds")
	end })
	streakPill:SetText("Streak 0/" .. Rarities.LuckyStreakMisses)
	local boostChips: { [string]: Pill.PillHandle } = {}
	local chipOrder = 2
	local function chipFor(id: string, kind: string): Pill.PillHandle
		local existing = boostChips[id]
		if existing then
			return existing
		end
		chipOrder += 1
		local chip = Pill.new({ Name = "Boost_" .. id, Icon = if kind == "Luck" then "boost_luck" else "boost_catch", Palette = if kind == "Luck" then "Grass" else "Sky", Width = chipW, Height = 38, LayoutOrder = chipOrder, Parent = topRight })
		boostChips[id] = chip
		return chip
	end

	-- ---------------------------------------------------------------- bottom-centre: ball hotbar
	local slot = if touch then 56 else 64
	local slotGap = if touch then 6 else Theme.Space.S
	local hotbar: Frame = Make("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(#Balls.Order * (slot + slotGap) - slotGap, slot),
		Position = UDim2.new(0.5, 0, 1, -E),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 2,
		Parent = root,
	})
	Decor.List(hotbar, Enum.FillDirection.Horizontal, slotGap, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	type Slot = { Root: TextButton, Icon: Frame, Number: TextLabel, Count: TextLabel, Stroke: UIStroke, BallId: string? }
	local slots: { Slot } = {}
	local slotBall: { string } = {} -- slot index -> ball id currently shown
	local function equipSlot(i: number)
		local id = slotBall[i]
		if id and deps.EquipBall and State.Ball().Id ~= id then
			deps.EquipBall(id)
		end
	end
	for i = 1, #Balls.Order do
		local b: TextButton = Make("TextButton", {
			Name = "Slot" .. i,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Color.BodyDeep,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(slot, slot),
			LayoutOrder = i,
			Visible = false,
			ZIndex = 3,
			Parent = hotbar,
		})
		Decor.Corner(b, Theme.Radius.Slot)
		local stroke = Decor.Stroke(b, Theme.Stroke.Button)
		local ic = Icon.new({ Name = "ball_tennis", Size = if touch then 32 else 48, Position = UDim2.fromScale(0.5, 0.54), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Parent = b })
		local num = Label.Display({ Name = "Number", Text = tostring(i), TextSize = 16, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(4, 2), ZIndex = 5, Parent = b })
		local cnt = Label.Display({ Name = "Count", Text = "", TextSize = 15, Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 0, 1, -1), AnchorPoint = Vector2.new(0, 1), XAlign = Enum.TextXAlignment.Right, ZIndex = 5, Parent = b })
		b.Activated:Connect(function()
			Motion.Press(b)
			equipSlot(i)
		end)
		slots[i] = { Root = b, Icon = ic, Number = num, Count = cnt, Stroke = stroke }
	end

	-- ---------------------------------------------------------------- strength (flexed arm + ThrowPower)
	local strengthIcon = if touch then 32 else 64
	local strength: Frame = Make("Frame", {
		Name = "Strength",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(strengthIcon + (if touch then 66 else 130), if touch then cashH else strengthIcon),
		ZIndex = 2,
		Parent = if touch then currencies else root,
	})
	Icon.new({ Name = "throw_power", Size = strengthIcon, Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3, Parent = strength })
	local strengthValue = Label.Shout({ Name = "Value", Text = "0", TextSize = if touch then 24 else 40, Color = Theme.Color.Strength, Size = UDim2.new(1, -(strengthIcon + 4), 1, 0), Position = UDim2.fromOffset(strengthIcon + 4, 2), ZIndex = 3, Parent = strength })
	if touch then
		strength.Position = UDim2.fromOffset(170 + 110 + 2 * Theme.Space.M + hang - 4, 0)
	else
		strength.Position = UDim2.new(0, E, 1, -E)
		strength.AnchorPoint = Vector2.new(0, 1)
	end

	-- ---------------------------------------------------------------- the throw bar (above the hotbar)
	local barLen = if touch then math.clamp(math.floor((deps.ScreenHeight or 420) - 300), 120, 230) else 230
	local tapSize = if touch then 26 else 36
	local infoH = 22
	local hotbarTop = E + slot + Theme.Space.S
	local meter = PowerMeter.new({ Name = "PowerMeter", Length = barLen, Thickness = if touch then 44 else 56, ZIndex = 3 })
	local clusterH = meter.Height + 4 + tapSize + 8 + infoH
	local cluster: Frame = Make("Frame", {
		Name = "ThrowCluster",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(math.max(meter.Width, 360), clusterH),
		Position = UDim2.new(0.5, 0, 1, -hotbarTop),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	meter.Root.Position = UDim2.new(0.5, 0, 0, 0)
	meter.Root.AnchorPoint = Vector2.new(0.5, 0)
	meter.Root.Parent = cluster
	local tapLabel = Label.Shout({
		Name = "TapToThrow",
		Text = if touch then "TAP TO THROW!" else "CLICK TO THROW!",
		TextSize = tapSize,
		Size = UDim2.new(1, 0, 0, tapSize + 6),
		Position = UDim2.fromOffset(0, meter.Height + 4),
		XAlign = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = cluster,
	})
	-- reach + catch: one small line
	local infoRow: Frame = Make("Frame", { Name = "InfoRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, infoH), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), ZIndex = 3, Parent = cluster })
	Decor.List(infoRow, Enum.FillDirection.Horizontal, Theme.Space.XS, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local reachIcon = Icon.new({ Name = "zone_backyard", Size = 16, LayoutOrder = 1, ZIndex = 4, Parent = infoRow })
	local reachText = Label.Display({ Name = "Reach", Text = "", TextSize = 16, Size = UDim2.fromOffset(140, infoH), AutoSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 4, Parent = infoRow })
	Icon.new({ Name = "paw", Size = 16, LayoutOrder = 3, ZIndex = 4, Parent = infoRow })
	local catchText = Label.Display({ Name = "Catch", Text = "", TextSize = 16, Size = UDim2.fromOffset(90, infoH), AutoSize = Enum.AutomaticSize.X, LayoutOrder = 4, ZIndex = 4, Parent = infoRow })
	reachText.Size = UDim2.fromOffset(0, infoH)
	catchText.Size = UDim2.fromOffset(0, infoH)

	-- ---------------------------------------------------------------- behaviour
	local charging = false
	local chargeStart = 0
	local chargePeriod = Game.Meter.Period
	local restartAt = restartAfter(chargePeriod)
	local locked = false
	local suppressed = false -- a modal panel is open
	local frozenUntil = 0 -- keep the released marker on screen briefly
	local lastRelease = -math.huge
	local beginQueued = false
	local player = Players.LocalPlayer

	local handle = { Root = root, Toasts = toasts, Meter = meter } :: any

	local function inZone(): boolean
		if not player then
			return false
		end
		local z = player:GetAttribute("InThrowZone")
		if z == nil then
			z = player:GetAttribute("OnPlatform")
		end
		return z == true
	end
	local function ownsInput(): boolean
		return deps.OwnsThrowInput ~= false
	end
	-- may the bar run right now?
	local function canThrow(): boolean
		return inZone() and not locked and not suppressed and root.Visible
	end

	local function refreshHotbar()
		local active = State.Ball().Id
		local list = { Balls.Default }
		for _, id in Balls.Order do
			local ball = Balls.ById[id]
			if ball and ball.Consumable and (ballCount(id) or 0) > 0 then
				table.insert(list, id)
			end
		end
		for i, s in slots do
			local id = list[i]
			slotBall[i] = id
			s.Root.Visible = id ~= nil
			if id then
				Icon.Set(s.Icon, Icon.ForBall(id))
				local n = ballCount(id)
				s.Count.Text = if id == Balls.Default or n == nil then "" else "x" .. FormatNumber.Compact(n)
				local selected = id == active
				s.Stroke.Color = if selected then Theme.Color.SlotSelected else Theme.Color.Ink
				s.Stroke.Thickness = if selected then 4 else Theme.Stroke.Button
				s.Root.BackgroundColor3 = if selected then Theme.Color.BodyRaised else Theme.Color.BodyDeep
			end
		end
	end

	local function refreshStatic()
		local s = State.Get()
		cashPill:Set(s.Cash or 0)
		bonesPill:Set(s.Bones or 0)
		strengthValue.Text = FormatNumber.Compact(s.ThrowPower or 0)
		incomeLabel.Text = "+" .. FormatNumber.PerSecond(State.Income())
		local reach = State.ReachZone()
		Icon.Set(reachIcon, Icon.ForZone(reach.Id))
		reachText.Text = reach.Name .. " " .. FormatNumber.Compact(State.MaxDistance()) .. " st"
		local computed = State.Computed()
		local chances = computed.CatchChances or {}
		local legendary = chances.Legendary or Rarities.Tiers.Legendary.Catch
		catchText.Text = FormatNumber.Percent(legendary, 0) .. " catch"
		local streak = State.LuckyStreak()
		streakPill:SetText("Streak " .. streak .. "/" .. Rarities.LuckyStreakMisses)
		local streakGradient = streakPill.Root:FindFirstChildOfClass("UIGradient")
		if streakGradient then
			local full = streak >= Rarities.LuckyStreakMisses
			local p = if full then Theme.Palette.Cash else Theme.Palette.Slate
			streakGradient.Color = if full
				then ColorSequence.new({ ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(1, p.Bottom) })
				else ColorSequence.new({ ColorSequenceKeypoint.new(0, Theme.Palette.Dark.Top), ColorSequenceKeypoint.new(1, Theme.Palette.Dark.Bottom) })
		end
		for _, pill in boostChips do
			pill.Root.Visible = false
		end
		for _, b in State.ActiveBoosts() do
			local chip = chipFor(b.Id, b.Kind)
			chip.Root.Visible = true
			chip:SetText(FormatNumber.Duration(b.ExpiresAt - os.time()))
		end
		refreshHotbar()
	end

	local function refreshBanner()
		local ev = State.Server.Events
		local show: any = ev.Squirrel or ev.RunawayDog or ev.DailyWalk
		bannerKind = if show then show.Kind else nil
		bannerHit.Active = bannerKind == "DailyWalk"
		bannerHit.AutoButtonColor = false
		if not show then
			banner.Visible = false
			return
		end
		banner.Visible = true
		local p = Theme.Palette.Purple
		if show.Kind == "Squirrel" then
			Icon.Set(bannerIcon, "squirrel")
			bannerText.Text = "Squirrel in the park!"
		elseif show.Kind == "RunawayDog" then
			Icon.Set(bannerIcon, "dog")
			local who = show.Data and show.Data.PlayerName or "someone"
			bannerText.Text = "A dog ran off from " .. who
			p = Theme.Palette.Danger
		else
			Icon.Set(bannerIcon, "walk")
			bannerText.Text = "Claim daily walk"
			p = Theme.Palette.Grass
		end
		bannerGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, p.Top), ColorSequenceKeypoint.new(1, p.Bottom) })
		local endsAt = tonumber(show.EndsAt)
		bannerTimer.Text = if endsAt then FormatNumber.Duration(endsAt - os.time()) else ""
	end

	local function renderMeter()
		meter:SetFraction(Meter.Position(os.clock() - chargeStart, chargePeriod))
	end

	-- Start (or restart) the sweep through the owner (UI init fires ChargeBegin and calls SetCharging back).
	local function begin()
		if deps.OnChargeBegin then
			deps.OnChargeBegin()
		end
	end

	local refreshThrow: () -> ()
	-- Ask for a sweep once the frame settles (never re-entrantly from inside SetCharging).
	local function queueBegin()
		if beginQueued or not ownsInput() then
			return
		end
		beginQueued = true
		task.defer(function()
			-- the server refuses a ChargeBegin within MinSecondsBetweenThrows of the last release
			local wait = (Game.Throw :: any).MinSecondsBetweenThrows or 0
			local left = lastRelease + wait + 0.05 - os.clock()
			if left > 0 then
				task.wait(left)
			end
			beginQueued = false
			if canThrow() and not charging then
				begin()
			end
		end)
	end

	-- What the throw cluster shows: the bar while it sweeps (and briefly after the tap), nothing otherwise.
	refreshThrow = function()
		if charging and not inZone() then
			charging = false -- left the zone: hide, no remote (the server cancels the idle charge)
		end
		local frozen = os.clock() < frozenUntil
		cluster.Visible = not suppressed and (charging or frozen)
		if canThrow() and not charging then
			queueBegin()
		end
	end

	-- Per-frame: the sweep (and its restart), boost countdowns, banner timer.
	local acc = 0
	local wasFrozen = false
	local heartbeat = RunService.Heartbeat:Connect(function(dt)
		if charging then
			renderMeter()
			if ownsInput() and os.clock() - chargeStart >= restartAt then
				begin() -- restart the sweep before the server cancels the idle charge
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

	-- The one tap: throws while the bar sweeps; starts it if it somehow is not running yet.
	local function press()
		if suppressed or not root.Visible then
			return
		end
		if charging then
			lastRelease = os.clock()
			if deps.OnChargeRelease then
				deps.OnChargeRelease()
			end
		elseif canThrow() then
			begin()
		end
	end

	local connections: { RBXScriptConnection } = { heartbeat }
	if ownsInput() then
		table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				press()
				return
			elseif processed then
				return
			end
			local key = table.find(SLOT_KEYS, input.KeyCode)
			if key then
				equipSlot(key)
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
		for _, attr in { "InThrowZone", "OnPlatform" } do
			table.insert(connections, player:GetAttributeChangedSignal(attr):Connect(function()
				refreshThrow()
			end))
		end
	end
	table.insert(connections, root:GetPropertyChangedSignal("Visible"):Connect(function()
		if not root.Visible and charging then
			charging = false -- the cutscene took the screen
		end
		refreshThrow()
	end))

	table.insert(connections, State.Changed:Connect(refreshStatic))
	table.insert(connections, State.EventsChanged:Connect(refreshBanner))

	function handle.SetCharging(_, on: boolean, startClock: number?, isTutorial: boolean?)
		local was = charging
		charging = on
		if on then
			chargeStart = startClock or os.clock()
			chargePeriod = Meter.Period(isTutorial)
			restartAt = restartAfter(chargePeriod)
			frozenUntil = 0
			renderMeter()
			if not was then
				Motion.Pulse(tapLabel, 1.08)
			end
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
		if on and charging then
			charging = false -- a panel opened: stop the sweep; it starts again when the panel closes
		end
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
		if text == "" then
			return
		end
		local rarity = payload and payload.Rarity
		local palette = if rarity and Theme.Palette[rarity] then rarity else "Purple"
		toasts:Show(text, if payload and payload.Variant then Icon.ForVariant(payload.Variant) else "star", palette)
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
