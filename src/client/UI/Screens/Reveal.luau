--!strict
-- Reveal end card: the prize screen at the end of the cutscene (the cutscene itself is another module).
-- Reveal.Show(result, opts) -> closes itself (EndCard.AutoClose) or on a button; every way out calls OnClose once.
--
--   +------------------------------------------------------------+
--   | RARITY TAG                                  [variant] GOLD |  rarity band
--   | +--------------------------------------+  Dog Name         |
--   | |                                      |  Dog Name (2 ln)  |
--   | |   live dog (DogViewport, 60 % of     |  [zone] ZONE      |
--   | |   the card width) on its pedestal    |  [ball] 412 studs |
--   | |                                      |  ---------------  |
--   | |                                      |  $12/s base x50.. |
--   | |          [ CAUGHT ] stamp            |  [cash] $1.2K/s   |
--   | +--------------------------------------+  [Keep] / [OK]    |
--   +------------------------------------------------------------+
-- Frame (overhaul): the panel look: dark body, heavy Ink outline, a rarity-coloured header band with diagonal
-- highlight stripes and the outlined rarity word, white outlined name, a rarity-coloured income plate.
-- Behind it: a darkening scrim, light rays for Epic+ (beams with UIGradient falloff in a frame that turns),
-- and a rarity-coloured flash on entry; the card pops in (scale) and the $/s number counts up.
-- Reduced motion: no pop, no ray spin, no dog turning, no count-up. The card and its viewport are built on
-- Show and destroyed on close (every connection disconnected, the dog's idle loop stopped).
-- Every timing: Config/Cutscene.luau EndCard.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local Zones = require(Config:WaitForChild("Zones"))
local CutsceneConfig = require(Config:WaitForChild("Cutscene")) -- EndCard (AutoClose is also the server timeout)
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))

local UI = script.Parent.Parent
local Make = require(UI:WaitForChild("Make"))
local Theme = require(UI:WaitForChild("Theme"))
local Motion = require(UI:WaitForChild("Motion"))
local Components = UI:WaitForChild("Components")
local Decor = require(Components:WaitForChild("Decor"))
local Icon = require(Components:WaitForChild("Icon"))
local Label = require(Components:WaitForChild("Label"))
local Button = require(Components:WaitForChild("Button"))
local DogViewport = require(Components:WaitForChild("DogViewport"))

local Reveal = {}

export type RevealOpts = {
	OnClose: (() -> ())?,
	OnWhistle: (() -> ())?, -- shown only when result.WhistleOwned and not Caught
	OnKeep: (() -> ())?, -- shown when IsDupe
	IsDupe: boolean?,
	AutoCloseSeconds: number?, -- default by rarity
	Spectator: boolean?, -- compact version for other players' throws
}

-- Card geometry (canvas px, before the root UIScale). The phone (scale 0.75) shows it at 450 x 300.
local SIZE = { Full = Vector2.new(600, 400), Spectator = Vector2.new(480, 320) }
local BAND = 44
local PAD = Theme.Space.M
local BUTTON_H = Theme.Touch.MinTarget

local function zoneName(id: string): string
	for _, z in Zones do
		if z.Id == id then
			return z.Name
		end
	end
	return id
end

-- Display-font width estimate with capitals and wide letters counted wider (names are Title Case).
local function displayWidth(text: string, size: number): number
	local w = 0
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		w += size * 0.56 * (if string.match(ch, "[mwMW]") then 1.35 elseif string.match(ch, "%u") then 1.1 elseif string.match(ch, "[iljtf]") then 0.6 else 1)
	end
	return w
end

-- Largest display size (of the steps) at which `text` fits in `width` on at most two lines.
local function nameSize(text: string, width: number, steps: { number }): number
	local longest = ""
	for word in string.gmatch(text, "%S+") do
		if #word > #longest then
			longest = word
		end
	end
	for _, s in steps do
		local lines = math.ceil(Label.EstimateWidth(text, s, Theme.Font.Display) * 1.12 / width)
		local wordFits = displayWidth(longest, s) <= width
		if lines <= 2 and wordFits then
			return s
		end
	end
	return steps[#steps]
end

-- The card on screen: its frame, the dog viewport, the connections and the rays (all per Show).
type Current = { Card: Frame, Rays: Frame?, Stage: any, Conns: { RBXScriptConnection }, Closing: boolean }

function Reveal.new(parent: Instance)
	local root: Frame = Make("Frame", { Name = "Reveal", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 60, Parent = parent })
	local scrim: Frame = Make("Frame", { Name = "Scrim", BackgroundColor3 = Theme.Color.Scrim, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 60, Parent = root })
	local flash: Frame = Make("Frame", { Name = "Flash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = root })

	local closeTimer = 0
	local handle = { Root = root } :: any
	local current: Current? = nil

	local function teardown(cur: Current)
		for _, c in cur.Conns do
			c:Disconnect()
		end
		table.clear(cur.Conns)
		if cur.Stage then
			cur.Stage:Destroy()
			cur.Stage = nil
		end
		if cur.Rays then
			cur.Rays:Destroy()
			cur.Rays = nil
		end
		cur.Card:Destroy()
	end

	function handle.Hide()
		local cur = current
		if not root.Visible or not cur or cur.Closing then
			return
		end
		cur.Closing = true
		for _, c in cur.Conns do
			c:Disconnect()
		end
		table.clear(cur.Conns)
		Motion.Tween(scrim, { BackgroundTransparency = 1 }, 0.12)
		if cur.Rays then
			Motion.Tween(cur.Rays, { BackgroundTransparency = 1 }, 0.12)
		end
		Motion.PanelClose(cur.Card, function()
			teardown(cur)
			if current == cur then
				current = nil
				root.Visible = false
			end
		end)
	end

	-- Light rays: RaysCount long beams through the card centre, each with a UIGradient that fades it out toward
	-- both ends (and in the middle, under the card), inside one big transparent frame that turns slowly.
	local function buildRays(color: Color3, dim: boolean): Frame
		local ec = CutsceneConfig.EndCard :: any
		local rays: Frame = Make("Frame", {
			Name = "Rays",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(1500, 1500),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 60,
			Parent = root,
		})
		rays:SetAttribute("Bleed", true) -- full-bleed decoration: meant to run off-screen (tools/uicheck)
		local n = ec.RaysCount or 8
		local base = if dim then 0.9 else 0.82
		for i = 1, n do
			local beam: Frame = Make("Frame", {
				Name = "Beam" .. i,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 90),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Rotation = (i - 1) * 180 / n,
				ZIndex = 60,
				Parent = rays,
			})
			Make("UIGradient", {
				Color = ColorSequence.new(color:Lerp(Theme.Color.White, 0.35), color),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.2, base),
					NumberSequenceKeypoint.new(0.42, base + 0.1),
					NumberSequenceKeypoint.new(0.5, 1),
					NumberSequenceKeypoint.new(0.58, base + 0.1),
					NumberSequenceKeypoint.new(0.8, base),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 0,
				Parent = beam,
			})
		end
		return rays
	end

	function handle.Show(_, result: any, opts: RevealOpts?)
		local o: RevealOpts = opts or {}
		local ec = CutsceneConfig.EndCard :: any
		closeTimer += 1
		local myTimer = closeTimer
		if current then
			-- a new card replaces the one on screen (its timer is cancelled by closeTimer)
			teardown(current)
			current = nil
		end
		-- Every way out (OK, Whistle, Keep, the auto-close timer) hides the card and calls OnClose exactly once,
		-- so the cutscene waiting on it always gets its RETURN beat.
		local closed = false
		local function close()
			if closed then
				return
			end
			closed = true
			handle:Hide()
			if o.OnClose then
				o.OnClose()
			end
		end
		local def = DogCatalog.Get(result.DogId)
		local rarity = result.Rarity or (def and def.Rarity) or "Common"
		local color = Theme.RarityColor(rarity)
		local name = if def then def.Name else tostring(result.DogId)
		local tier = table.find(Rarities.Order, rarity) or 1
		local caught = result.Caught == true
		local reduced = Motion.ReducedMotion

		local size = if o.Spectator then SIZE.Spectator else SIZE.Full
		local W, H = size.X, size.Y
		local stageW = math.floor(W * (ec.StageShare or 0.6))
		local stageH = H - BAND - PAD * 2
		local colX = PAD + stageW + PAD
		local colW = W - colX - PAD
		local top = BAND + PAD

		-- Card ------------------------------------------------------------------------------------------
		local card: Frame = Make("Frame", {
			Name = "Card",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(W, H),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 61,
			Parent = root,
		})
		Decor.Corner(card, Theme.Radius.Panel)
		Decor.Stroke(card, Theme.Stroke.Panel)
		card.BackgroundColor3 = Theme.Color.Body
		Decor.Shadow(card, "Soft")
		local cur: Current = { Card = card, Rays = nil, Stage = nil, Conns = {}, Closing = false }
		current = cur

		-- Rarity band: tag left, variant badge right.
		local band: Frame = Make("Frame", { Name = "Band", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, BAND), ZIndex = 62, Parent = card })
		Decor.TopCorners(band, Theme.Radius.Panel)
		Decor.Gradient(band, color:Lerp(Theme.Color.White, 0.25), color:Lerp(Theme.Color.Ink, 0.2))
		Decor.Stripes(band, { Bands = 4, Strength = 0.75, Rotation = -25, ZIndex = 62 })
		Make("Frame", { Name = "Rule", BackgroundColor3 = Theme.Color.Ink, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, Theme.Stroke.Panel), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), ZIndex = 63, Parent = band })
		Label.Display({ Name = "RarityTag", Text = string.upper(rarity), TextSize = 28, Size = UDim2.new(0.6, 0, 1, -2), Position = UDim2.fromOffset(Theme.Space.L, 0), ZIndex = 63, Parent = band })
		local vIcon = Icon.ForVariant(result.Variant)
		if vIcon then
			Icon.new({ Name = vIcon, Size = 32, Position = UDim2.new(1, -Theme.Space.M, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 63, Parent = band }).Name = "VariantIcon"
			Label.Display({ Name = "VariantText", Text = string.upper(result.Variant), TextSize = Theme.Text.Body + 2, Size = UDim2.fromOffset(110, BAND), Position = UDim2.new(1, -(Theme.Space.M + 32 + Theme.Space.S), 0, 0), AnchorPoint = Vector2.new(1, 0), XAlign = Enum.TextXAlignment.Right, ZIndex = 63, Parent = band })
		end

		-- The live dog (hero) --------------------------------------------------------------------------
		cur.Stage = DogViewport.new({
			Name = "DogStage",
			Parent = card,
			Size = UDim2.fromOffset(stageW, stageH),
			Position = UDim2.fromOffset(PAD, top),
			ZIndex = 62,
			Dog = def,
			Variant = result.Variant,
			Rarity = rarity,
			Caught = caught,
			BottomReserve = (if o.Spectator then 22 else 26) + 12, -- the stamp overlaps the pedestal, not the dog
		})

		-- CAUGHT / RAN OFF stamp across the bottom of the stage (slightly rotated, like a rubber stamp).
		local outcomeText = if caught
			then (if result.LuckyStreakTriggered then "CAUGHT  (Lucky Streak)" elseif result.TreatPocketUsed then "CAUGHT  (Treat Pocket)" else "CAUGHT")
			else "RAN OFF"
		local stampSize = if o.Spectator then 22 else 26
		local stampW = math.min(stageW - PAD * 2, math.floor(Label.EstimateWidth(outcomeText, stampSize, Theme.Font.Display) * 1.12) + 40)
		local stampH = stampSize + 18
		local stampPos = UDim2.fromOffset(PAD + stageW / 2, top + stageH - PAD)
		local stamp: Frame = Make("Frame", { Name = "Stamp", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(stampW, stampH), Position = stampPos, AnchorPoint = Vector2.new(0.5, 1), Rotation = -5, ZIndex = 66, Parent = card })
		Decor.Corner(stamp, Theme.Radius.Button)
		Decor.Stroke(stamp, Theme.Stroke.Panel)
		Decor.PaletteGradient(stamp, if caught then Theme.Palette.Grass else Theme.Palette.Danger)
		Decor.Shadow(stamp, "Hard")
		local outcome = Label.Display({ Name = "Outcome", Text = outcomeText, TextSize = stampSize, Size = UDim2.fromOffset(stampW, stampH), Position = stampPos, AnchorPoint = Vector2.new(0.5, 1), XAlign = Enum.TextXAlignment.Center, ZIndex = 67, Parent = card })
		outcome.Rotation = stamp.Rotation

		-- Info column ----------------------------------------------------------------------------------
		local col: Frame = Make("Frame", { Name = "Info", BackgroundTransparency = 1, Size = UDim2.fromOffset(colW, stageH), Position = UDim2.fromOffset(colX, top), ZIndex = 62, Parent = card })
		local info: Frame = Make("Frame", { Name = "Stats", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 62, Parent = col })
		Decor.List(info, Enum.FillDirection.Vertical, Theme.Space.XS)

		local nSize = nameSize(name, colW, if o.Spectator then { 24, 20, 18 } else { 30, 26, 22, 18 })
		local oneLine = displayWidth(name, nSize) <= colW
		Label.Display({ Name = "DogName", Text = name, TextSize = nSize, Wrap = not oneLine, YAlign = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, math.ceil(nSize * 1.2 * (if oneLine then 1 else 2))), LayoutOrder = 1, ZIndex = 62, Parent = info })

		-- rarity pips: one star per tier, lit up to this dog's tier (a collectible's "grade")
		local pips: Frame = Make("Frame", { Name = "Pips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, ZIndex = 62, Parent = info })
		Decor.List(pips, Enum.FillDirection.Horizontal, 2)
		for i = 1, #Rarities.Order do
			Icon.new({ Name = "star", Size = 16, LayoutOrder = i, ZIndex = 62, Parent = pips, Tint = if i <= tier then nil else Theme.Stage.PipOff, Transparency = if i <= tier then 0 else 0.55 })
		end

		local function iconRow(order: number, iconName: string, text: string, rowName: string): TextLabel
			local row: Frame = Make("Frame", { Name = rowName, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, ZIndex = 62, Parent = info })
			Icon.new({ Name = iconName, Size = 16, Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 62, Parent = row })
			return Label.Display({ Name = "Text", Text = text, TextSize = 15, Color = Theme.Color.TextMuted, Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(22, 0), ZIndex = 62, Parent = row })
		end
		iconRow(2, Icon.ForZone(result.ZoneId or ""), string.upper(zoneName(result.ZoneId or "")), "Zone")
		iconRow(3, "ball_tennis", FormatNumber.Compact(result.Distance or 0) .. " studs", "Distance")

		Make("Frame", { Name = "Rule", BackgroundColor3 = Theme.Color.Track, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 4, ZIndex = 62, Parent = info })

		-- income cascade: base, then each multiplier on its own line
		local base = if def then def.Income else 0
		local vm = if result.Variant then ((Rarities.Variants :: any)[result.Variant].IncomeMult) else 1
		local cascadeText = string.format("%s base  x%s %s", FormatNumber.PerSecond(base), tostring((Rarities.Tiers :: any)[rarity].IncomeMult), string.lower(rarity))
		if vm ~= 1 then
			cascadeText ..= string.format("  x%d %s", vm, string.lower(result.Variant))
		end
		if not o.Spectator then
			local cascadeLines = math.ceil(Label.EstimateWidth(cascadeText, Theme.Text.Caption, Theme.Font.Body) * 1.1 / colW)
			Label.Caption({ Name = "Cascade", Text = cascadeText, Wrap = true, Size = UDim2.new(1, 0, 0, math.max(1, cascadeLines) * 18), LayoutOrder = 5, ZIndex = 62, Parent = info })
		end

		-- Income plate (above the buttons): what the dog earns, big, counting up. A missed dog shows what it
		-- would have earned, greyed.
		local adult = if def then DogCatalog.AdultIncome(def, result.Variant) else 0
		local totalSize = if o.Spectator then 26 else 34
		local plateH = totalSize + 30
		local plate: Frame = Make("Frame", { Name = "Income", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(colW, plateH), ZIndex = 62, Parent = card })
		Decor.Corner(plate, Theme.Radius.Card)
		Decor.Stroke(plate, Theme.Stroke.Card)
		if caught then
			Decor.Gradient(plate, color:Lerp(Theme.Color.White, 0.25), color:Lerp(Theme.Color.Ink, 0.15))
		else
			Decor.PaletteGradient(plate, Theme.Palette.Dark)
		end
		Label.Display({ Name = "Caption", Text = if caught then "EARNS" else "WOULD HAVE EARNED", TextSize = 14, Color = if caught then Theme.Color.White else Theme.Color.TextMuted, Size = UDim2.new(1, -Theme.Space.M * 2, 0, 16), Position = UDim2.fromOffset(Theme.Space.M, 5), ZIndex = 63, Parent = plate })
		Icon.new({ Name = "cash", Size = 32, Position = UDim2.new(0, Theme.Space.S, 1, -5), AnchorPoint = Vector2.new(0, 1), ZIndex = 63, Parent = plate })
		local total = Label.Display({ Name = "Total", Text = FormatNumber.PerSecond(adult), TextSize = totalSize, Color = if caught then Theme.Color.White else Theme.Color.TextMuted, Size = UDim2.new(1, -(Theme.Space.S + 32 + Theme.Space.S + Theme.Space.S), 0, totalSize + 6), Position = UDim2.new(0, Theme.Space.S + 32 + Theme.Space.S, 1, -3), AnchorPoint = Vector2.new(0, 1), ZIndex = 63, Parent = plate })

		-- Buttons (bottom of the column; same buttons and callbacks as always) ------------------------
		local buttons: Frame = Make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(0, colW, 0, BUTTON_H), Position = UDim2.fromOffset(colX, top + stageH), AnchorPoint = Vector2.new(0, 1), ZIndex = 62, Parent = card })
		Decor.List(buttons, Enum.FillDirection.Vertical, Theme.Space.S, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
		local count = 1
		if caught then
			if o.IsDupe and o.OnKeep then
				count += 1
				Button.new({ Text = "Keep", Icon = "check", IconSize = 32, Palette = "Grass", Size = UDim2.new(1, 0, 0, BUTTON_H), LayoutOrder = 1, ZIndex = 63, Parent = buttons, OnClick = function()
					(o.OnKeep :: () -> ())()
					close()
				end })
			end
		else
			if result.WhistleOwned and o.OnWhistle and not o.Spectator then
				count += 1
				Button.new({ Text = "Whistle (" .. tostring(result.WhistleCount or 0) .. ")", Icon = "whistle", IconSize = 32, Palette = "Cash", Size = UDim2.new(1, 0, 0, BUTTON_H), LayoutOrder = 1, ZIndex = 63, Parent = buttons, OnClick = function()
					(o.OnWhistle :: () -> ())()
					close()
				end })
			end
		end
		Button.new({ Text = if o.Spectator then "Nice" else "OK", Palette = "Sky", Size = UDim2.new(1, 0, 0, BUTTON_H), LayoutOrder = 2, ZIndex = 63, Parent = buttons, OnClick = close })
		local buttonsH = count * BUTTON_H + (count - 1) * Theme.Space.S
		buttons.Size = UDim2.new(0, colW, 0, buttonsH)
		plate.Position = UDim2.fromOffset(colX, top + stageH - buttonsH - Theme.Space.S)
		plate.AnchorPoint = Vector2.new(0, 1)

		-- Entry: scrim, rays (Epic+), flash, pop, count-up ---------------------------------------------
		root.Visible = true
		scrim.BackgroundTransparency = 1
		Motion.Tween(scrim, { BackgroundTransparency = ec.ScrimTransparency or 0.4 }, ec.ScrimTime or 0.25)
		local raysFrom = table.find(Rarities.Order, ec.RaysFrom or "Epic") or 4
		if tier >= raysFrom then
			local rays = buildRays(color, not caught)
			cur.Rays = rays
			if not reduced then
				local period = ec.RaysPeriod or 16
				local t0 = os.clock()
				table.insert(cur.Conns, RunService.RenderStepped:Connect(function()
					rays.Rotation = ((os.clock() - t0) / period * 360) % 360
				end))
			end
		end
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = if caught then (ec.FlashFrom or 0.3) else math.min(1, (ec.FlashFrom or 0.3) + 0.35)
		Motion.Tween(flash, { BackgroundTransparency = 1 }, ec.FlashTime or 0.5)
		local scale = Make("UIScale", { Name = "MotionScale", Scale = 1, Parent = card })
		if not reduced then
			scale.Scale = ec.PopFrom or 0.6
			Motion.Tween(scale, { Scale = 1 }, ec.PopTime or 0.38, Enum.EasingStyle.Back)
		end
		if reduced then
			total.Text = FormatNumber.PerSecond(adult)
		else
			total.Text = FormatNumber.PerSecond(0)
			task.delay(ec.CountUpDelay or 0.3, function()
				if current == cur and not cur.Closing then
					Motion.CountUp(total, 0, adult, FormatNumber.PerSecond, ec.CountUpTime or 1)
				end
			end)
		end

		local seconds = o.AutoCloseSeconds
			or (if o.Spectator then ec.SpectatorAutoClose else ((ec.AutoClose :: any)[rarity] or ec.AutoClose.Common))
		task.delay(seconds, function()
			if closeTimer == myTimer then
				close()
			end
		end)
	end

	return handle
end

return Reveal
