--!strict
-- Throw input + meter UI + ball flight visual.
--   Hold (THROW button / mouse on your pad / gamepad R2 / F key) -> ChargeBegin; release -> ChargeRelease.
--   The client NEVER sends distance or timing: the server times ChargeBegin->ChargeRelease itself. The needle
--   here runs the same deterministic triangle wave (Util/Meter, period 1.6 s; slower for the tutorial throw)
--   from the moment of the press, so what you see is what the server computes (modulo network jitter).
--   Before throwing the panel shows reach (zone at a Perfect release) and the catch chance per rarity.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Game = require(Config:WaitForChild("Game"))
local Layout = require(Config:WaitForChild("Layout"))
local Rarities = require(Config:WaitForChild("Rarities"))
local Balls = require(Config:WaitForChild("Balls"))
local Meter = require(Util:WaitForChild("Meter"))
local Signal = require(Util:WaitForChild("Signal"))
local PlayerStats = require(Util:WaitForChild("PlayerStats"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local CutsceneContract = require(Shared:WaitForChild("Cutscene"):WaitForChild("CutsceneContract"))

local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local HudLayout = require(UI:WaitForChild("HudLayout"))
local Create = require(UI:WaitForChild("Components"):WaitForChild("Create"))
local Button = require(UI:WaitForChild("Components"):WaitForChild("Button"))

local StateController = require(script.Parent:WaitForChild("StateController"))
local HudController = require(script.Parent:WaitForChild("HudController"))

local ThrowController = {}
ThrowController.Released = Signal.new()

type Mode = "Idle" | "Charging" | "Waiting" | "Cutscene"
local mode: Mode = "Idle"
local chargeStart = 0
local chargeTutorial = false
local lastRelease = -math.huge
local waitToken = 0
local holdInput: InputObject? = nil

local player = Players.LocalPlayer

-- UI refs
local summary: TextLabel = nil :: any
local streakPips: { Frame } = {}
local streakLabel: TextLabel = nil :: any
local meterFrame: Frame = nil :: any
local needle: Frame = nil :: any
local meterHint: TextLabel = nil :: any
local chips: { [string]: TextLabel } = {}
local throwButton: TextButton = nil :: any
local padBillboard: BillboardGui? = nil

----------------------------------------------------------------------------------------------------
-- Pad helpers
----------------------------------------------------------------------------------------------------
local function padIndex(): number?
	local i = player:GetAttribute("PadIndex")
	return if type(i) == "number" then i else nil
end

local function padPart(i: number): BasePart?
	for _, inst in CollectionService:GetTagged("ThrowPad") do
		if inst:IsA("BasePart") and inst:GetAttribute("PadIndex") == i then
			return inst
		end
	end
	return nil
end

function ThrowController.PadPosition(i: number): Vector3
	local p = padPart(i)
	if p then
		return p.Position
	end
	return Vector3.new(Layout.ThrowLine.PadsX[i] or 0, Layout.GroundY, Layout.ThrowLine.Z)
end

local function onPad(): boolean
	local i = padIndex()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not i or not hrp or not hrp:IsA("BasePart") then
		return false
	end
	if not Game.Throw.RequireOnPad then
		return true
	end
	local p = ThrowController.PadPosition(i)
	return Vector2.new(hrp.Position.X - p.X, hrp.Position.Z - p.Z).Magnitude <= Game.Throw.PadRadius - 0.5
end

local function isTutorial(): boolean
	local s = StateController.Get()
	return Game.Tutorial.Enabled and s ~= nil and s.TutorialThrowDone ~= true
end

local function cooldownLeft(): number
	return math.max(0, Game.Throw.MinSecondsBetweenThrows - (os.clock() - lastRelease))
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------
local function idleSummary(): (string, Color3)
	local s = StateController.Get()
	if not s then
		return "Loading...", Theme.Color.TextDim
	end
	local i = padIndex()
	if mode == "Cutscene" or mode == "Waiting" then
		return "Fetching...", Theme.Color.TextDim
	end
	if i and not onPad() then
		return ("Walk to your throw pad (#%d)"):format(i), Theme.Color.Accent
	end
	if isTutorial() then
		return "Hold THROW, release in the gold zone!", Theme.Color.Accent
	end
	local ball = PlayerStats.Ball(s)
	local c = StateController.Computed()
	local reach = PlayerStats.ZoneForDistance(c.MaxDistance or PlayerStats.MaxDistance(s))
	local cap = tonumber(c.PowerCap)
	local power = FormatNumber.Compact(s.ThrowPower or 0)
	if cap and (s.ThrowPower or 0) < cap then
		power ..= "/" .. FormatNumber.Compact(cap)
	end
	local text = ("Power %s · %s · Reach %s"):format(power, ball.Name, reach.Name)
	if s.TutorialDone ~= true and s.TutorialThrowDone == true then
		return "Next: buy a Training upgrade in the Shop!", Theme.Color.Accent
	end
	return text, Theme.Color.Text
end

local function refreshIdle()
	if not summary then
		return
	end
	if mode ~= "Charging" then
		local text, color = idleSummary()
		summary.Text = text
		summary.TextColor3 = color
	end
	local s = StateController.Get()
	local c = StateController.Computed()
	local streak = if s then (s.LuckyStreak or 0) else 0
	local armed = c.LuckyStreakArmed == true
	for i, pip in streakPips do
		pip.BackgroundColor3 = if armed then Theme.Color.MeterPerfect elseif i <= streak then Theme.Color.Accent else Theme.Color.PanelInset
	end
	streakLabel.Text = if armed then "LUCKY!" else "Streak"
	streakLabel.TextColor3 = if armed then Theme.Color.MeterPerfect else Theme.Color.TextDim
	local chances = c.CatchChances or {}
	for _, tier in Rarities.Order do
		local chip = chips[tier]
		if chip then
			local guaranteed = armed and (table.find(Rarities.Order, tier) or 0) >= (table.find(Rarities.Order, "Legendary") or 5)
			local p = chances[tier] or (Rarities.Tiers :: any)[tier].Catch
			chip.Text = if guaranteed then "100%" else FormatNumber.Percent(p, 0)
		end
	end
	local canHold = mode == "Idle" and cooldownLeft() <= 0 and onPad()
	Button.SetColor(throwButton, if canHold then Theme.Color.Accent elseif mode == "Charging" then Theme.Color.MeterPerfect
		else Theme.Color.PanelLight)
	meterHint.Visible = mode ~= "Charging"
	meterHint.Text = if mode == "Idle" and canHold then "Hold to charge" elseif mode == "Idle" and cooldownLeft() > 0 then "Ready soon..."
		elseif mode == "Idle" then "Stand on your pad" else "..."
	if padBillboard then
		padBillboard.Enabled = mode == "Idle" and not onPad()
	end
end

----------------------------------------------------------------------------------------------------
-- Charge / release
----------------------------------------------------------------------------------------------------
local function setNeedle(pos: number)
	needle.Position = UDim2.new(math.clamp(pos, 0, 1), 0, 0.5, 0)
end

local function begin(input: InputObject?)
	if mode ~= "Idle" or not StateController.IsReady() then
		return
	end
	if cooldownLeft() > 0 then
		return
	end
	if not onPad() then
		local i = padIndex()
		summary.Text = if i then ("Walk to your throw pad (#%d) first!"):format(i) else "Waiting for a yard..."
		summary.TextColor3 = Theme.Color.Bad
		return
	end
	mode = "Charging"
	holdInput = input
	chargeStart = os.clock()
	chargeTutorial = isTutorial()
	local beginRemote = Remotes.Get("ChargeBegin") :: RemoteEvent
	beginRemote:FireServer()
	local started = chargeStart
	task.delay(Game.Throw.MaxChargeSeconds, function()
		if mode == "Charging" and chargeStart == started then
			ThrowController.Release()
		end
	end)
	refreshIdle()
end

function ThrowController.Release()
	if mode ~= "Charging" then
		return
	end
	local elapsed = os.clock() - chargeStart
	local releaseRemote = Remotes.Get("ChargeRelease") :: RemoteEvent
	releaseRemote:FireServer()
	lastRelease = os.clock()
	holdInput = nil
	mode = "Waiting"
	waitToken += 1
	local token = waitToken
	local _, quality, band = Meter.Evaluate(elapsed, chargeTutorial)
	summary.Text = if band == "Flub" then "Too quick!" else ("%s throw!"):format(string.upper(band))
	summary.TextColor3 = if band == "Perfect" then Theme.Color.MeterPerfect elseif band == "Good" then Theme.Color.MeterGood else Theme.Color.Text
	ThrowController.Released:Fire(quality, band)
	-- the server may refuse (cooldown / not on pad); fall back to Idle if no ThrowResult arrives
	task.delay(4, function()
		if mode == "Waiting" and waitToken == token then
			mode = "Idle"
			refreshIdle()
		end
	end)
	refreshIdle()
end

local function renderCharging()
	if mode ~= "Charging" then
		return
	end
	local elapsed = os.clock() - chargeStart
	local period = Meter.Period(chargeTutorial)
	local pos = Meter.Position(elapsed, period)
	setNeedle(pos)
	local _, quality, band = Meter.Evaluate(elapsed, chargeTutorial)
	local s = StateController.Get()
	if s then
		local ball = PlayerStats.Ball(s)
		local dist = math.min((s.ThrowPower or 0) * ball.RangeMult * quality, PlayerStats.MaxFieldDistance())
		local zone = PlayerStats.ZoneForDistance(dist)
		summary.Text = ("%s → %s (%d studs)"):format(if band == "Flub" then "HOLD" else string.upper(band), zone.Name, math.floor(dist))
		summary.TextColor3 = if band == "Perfect" then Theme.Color.MeterPerfect elseif band == "Good" then Theme.Color.MeterGood
			else Theme.Color.Text
	end
end

-- Cutscene lifecycle (CutsceneController): blocks throwing while the local thrower's cutscene plays.
function ThrowController.SetCutsceneActive(on: boolean)
	if on then
		mode = "Cutscene"
		waitToken += 1
	elseif mode == "Cutscene" or mode == "Waiting" then
		mode = "Idle"
		-- 0.5 s after the cutscene, but never before the server's own release->ChargeBegin floor (a skipped
		-- Common cutscene can end < MinSecondsBetweenThrows after the release; the server would ignore the press)
		lastRelease = math.max(lastRelease + 0.25, os.clock() - Game.Throw.MinSecondsBetweenThrows + 0.5)
	end
	refreshIdle()
end

----------------------------------------------------------------------------------------------------
-- Ball flight (everyone sees every throw)
----------------------------------------------------------------------------------------------------
function ThrowController.PlayBallFlight(result: any)
	local distance = tonumber(result.Distance) or 0
	local padPos = ThrowController.PadPosition(tonumber(result.PadIndex) or 1)
	local start = (if typeof(result.StartPosition) == "Vector3" then result.StartPosition else padPos) + Vector3.new(0, 4, 0)
	local land: Vector3 = if typeof(result.LandingPosition) == "Vector3" then result.LandingPosition
		else Vector3.new(padPos.X, Layout.GroundY, Layout.DistanceToZ(distance))
	land += Vector3.new(0, 0.6, 0)
	local ballDef = Balls.ById[result.BallId or Balls.Default] or Balls.ById[Balls.Default]
	local ball: Part = Create.New("Part", { Name = "ThrownBall", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, Anchored = true,
		CanCollide = false, CanQuery = false, CanTouch = false, Color = ballDef.Color,
		Material = if ballDef.Id == "Glow" then Enum.Material.Neon elseif ballDef.Id == "Golden" then Enum.Material.Foil
			else Enum.Material.SmoothPlastic, CFrame = CFrame.new(start), Parent = workspace })
	local a0 = Create.New("Attachment", { Position = Vector3.new(0, 0.4, 0), Parent = ball })
	local a1 = Create.New("Attachment", { Position = Vector3.new(0, -0.4, 0), Parent = ball })
	Create.New("Trail", { Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(ballDef.Color), Lifetime = 0.5,
		LightEmission = 0.5, Transparency = NumberSequence.new(0.2, 1), Parent = ball })
	local dur = CutsceneContract.FlightTime(distance)
	local apex = math.clamp(distance * 0.22, 15, 260)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - t0) / dur)
		ball.CFrame = CFrame.new(start:Lerp(land, t) + Vector3.new(0, 4 * apex * t * (1 - t), 0))
		if t >= 1 then
			conn:Disconnect()
			TweenService:Create(ball, TweenInfo.new(0.5, Enum.EasingStyle.Bounce), { CFrame = CFrame.new(land + Vector3.new(1.5, 0, 1.5)) }):Play()
			task.delay(2, function()
				ball:Destroy()
			end)
		end
	end)
	return dur
end

----------------------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------------------
local function zoneBand(parent: Instance, from: number, to: number, color: Color3, name: string)
	Create.New("Frame", { Name = name, BackgroundColor3 = color, BorderSizePixel = 0, Position = UDim2.fromScale(from, 0),
		Size = UDim2.fromScale(to - from, 1), Parent = parent })
end

local function buildPanel(region: Frame)
	local panel = Create.Panel({ Name = "ThrowPanel", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.05, Parent = region })
	Create.Padding(6).Parent = panel

	-- THROW button (right, square)
	throwButton = Button.new({ Name = "Throw", Text = "THROW", Color = Theme.Color.Accent, TextMax = 26, Corner = Theme.Corner,
		Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), Parent = panel })
	Create.New("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = throwButton })

	local left = Create.New("Frame", { Name = "Left", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, 0), Parent = panel })
	local function fitLeft()
		left.Size = UDim2.new(1, -(throwButton.AbsoluteSize.X + 8), 1, 0)
	end
	throwButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLeft)
	fitLeft()

	-- Row A: summary + Lucky Streak pips
	-- wraps to 2 lines on phones for the long idle hints ("Next: buy a Training upgrade in the Shop!")
	summary = Create.Label({ Name = "Summary", Text = "", Font = Theme.Font.Body, TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true, Size = UDim2.new(0.62, 0, 0.28, 0), Parent = left }, Theme.TextMax.Normal)
	-- Lucky Streak: label + pips; the pip holder is wide enough for LuckyStreakMisses pips at 70% row height
	local streak = Create.New("Frame", { Name = "Streak", BackgroundTransparency = 1, Size = UDim2.new(0.37, 0, 0.28, 0),
		Position = UDim2.fromScale(0.63, 0), Parent = left })
	streakLabel = Create.Label({ Name = "Label", Text = "Streak", Font = Theme.Font.Body, TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, Size = UDim2.new(0.5, -4, 1, 0), Parent = streak }, Theme.TextMax.Small)
	local pipHolder = Create.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0),
		Parent = streak })
	Create.List(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center).Parent = pipHolder
	for i = 1, Rarities.LuckyStreakMisses do
		local pip = Create.New("Frame", { Name = "Pip" .. i, BackgroundColor3 = Theme.Color.PanelInset, Size = UDim2.fromScale(0.7, 0.7),
			SizeConstraint = Enum.SizeConstraint.RelativeYY, LayoutOrder = i, Parent = pipHolder }, { Create.Corner(100),
			Create.Stroke(nil, 2) })
		table.insert(streakPips, pip)
	end

	-- Row B: meter (OK -> Good -> Perfect, sweet spot at the right end; needle sweeps 0->1->0)
	meterFrame = Create.New("Frame", { Name = "Meter", BackgroundColor3 = Theme.Color.MeterTrack, BorderSizePixel = 0, ClipsDescendants = false,
		Size = UDim2.new(1, 0, 0.32, 0), Position = UDim2.fromScale(0, 0.32), Parent = left }, { Create.Corner(Theme.CornerSmall),
		Create.Stroke(nil, 2) })
	local bands = Create.New("Frame", { Name = "Bands", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(1, 1),
		Parent = meterFrame }, { Create.Corner(Theme.CornerSmall) })
	zoneBand(bands, 0, Game.Meter.GoodMin, Theme.Color.MeterOk, "Ok")
	zoneBand(bands, Game.Meter.GoodMin, Game.Meter.PerfectMin, Theme.Color.MeterGood, "Good")
	zoneBand(bands, Game.Meter.PerfectMin, 1, Theme.Color.MeterPerfect, "Perfect")
	local okBand = bands:FindFirstChild("Ok") :: Frame
	Create.New("UIGradient", { Transparency = NumberSequence.new(0.7, 0.1), Parent = okBand })
	needle = Create.New("Frame", { Name = "Needle", BackgroundColor3 = Theme.Color.Needle, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 6, 1, 10), Position = UDim2.fromScale(0, 0.5), ZIndex = 3, Parent = meterFrame }, { Create.Corner(3),
		Create.Stroke(nil, 2) })
	meterHint = Create.Label({ Name = "Hint", Text = "Hold to charge", Font = Theme.Font.Body, TextStrokeTransparency = 0.3,
		Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), ZIndex = 4, Parent = meterFrame }, Theme.TextMax.Small)

	-- Row C: catch chance per rarity (shown BEFORE throwing; updates with boosts / Lucky Streak)
	local chipRow = Create.New("Frame", { Name = "CatchChances", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.fromScale(0, 0.7), Parent = left })
	Create.List(Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center).Parent = chipRow
	Create.Label({ Name = "Title", Text = "Catch", Font = Theme.Font.Body, TextColor3 = Theme.Color.TextDim, LayoutOrder = 0,
		Size = UDim2.new(0.13, 0, 1, 0), Parent = chipRow }, Theme.TextMax.Small)
	for i, tier in Rarities.Order do
		local chip = Create.New("Frame", { Name = tier, BackgroundColor3 = Theme.Color.PanelInset, BorderSizePixel = 0, LayoutOrder = i,
			Size = UDim2.new(0.87 / #Rarities.Order, -3, 1, 0), Parent = chipRow }, { Create.Corner(6),
			Create.Stroke(Theme.Rarity(tier), 2) })
		chips[tier] = Create.Label({ Text = "-", Font = Theme.Font.Body, TextColor3 = Theme.Lighten(Theme.Rarity(tier), 0.3),
			Size = UDim2.new(1, -4, 1, -2), Position = UDim2.fromOffset(2, 1), Parent = chip }, Theme.TextMax.Small)
	end

	-- input on the button (mouse + touch); release anywhere
	throwButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			begin(input)
		end
	end)
end

local function buildPadMarker()
	local i = padIndex()
	if not i then
		return
	end
	if padBillboard then
		padBillboard:Destroy()
	end
	local adornee: BasePart? = padPart(i)
	if not adornee then
		local anchor = Create.New("Part", { Name = "PadMarkerAnchor", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(ThrowController.PadPosition(i)), Parent = workspace })
		adornee = anchor
	end
	local bb = Create.New("BillboardGui", { Name = "YourPadMarker", Adornee = adornee, AlwaysOnTop = true, Size = UDim2.fromOffset(150, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0), MaxDistance = 600, ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui") })
	Create.Label({ Text = ("YOUR PAD #%d\n▼"):format(i), TextColor3 = Theme.Color.Accent, TextStrokeTransparency = 0,
		TextStrokeColor3 = Theme.Color.Stroke, Parent = bb }, 26)
	padBillboard = bb
end

function ThrowController.Start()
	local region = HudController.Region("ThrowPanel")
	buildPanel(region)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			-- desktop: click-and-hold anywhere in the world while standing on your pad
			if onPad() then
				begin(input)
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 or (input.KeyCode == Enum.KeyCode.F and not processed) then
			begin(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if mode ~= "Charging" then
			return
		end
		local h = holdInput
		if h == nil or input == h or (input.UserInputType == h.UserInputType and input.KeyCode == h.KeyCode
			and input.UserInputType ~= Enum.UserInputType.Touch) then
			ThrowController.Release()
		end
	end)
	-- a finger that started on the THROW button ends via TouchEnded on the same InputObject
	UserInputService.TouchEnded:Connect(function(input)
		if mode == "Charging" and holdInput == input then
			ThrowController.Release()
		end
	end)

	RunService.RenderStepped:Connect(renderCharging)
	StateController.Changed:Connect(refreshIdle)
	player:GetAttributeChangedSignal("PadIndex"):Connect(function()
		buildPadMarker()
		refreshIdle()
	end)
	CollectionService:GetInstanceAddedSignal("ThrowPad"):Connect(function()
		task.defer(buildPadMarker)
	end)
	buildPadMarker()
	HudController.LayoutChanged:Connect(function(_layout: HudLayout.Layout)
		refreshIdle()
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if mode ~= "Charging" then
				refreshIdle()
			end
		end
	end)
	setNeedle(0)
	refreshIdle()
end

return ThrowController
