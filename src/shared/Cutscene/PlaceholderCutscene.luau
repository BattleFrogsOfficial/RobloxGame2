--!strict
-- ===========================================================================================
--  PLACEHOLDER CUTSCENE — deliberately simple. The real cutscene will be designed by the user
--  and installed via CutsceneContract.SetImplementation(). Keep this module's API identical:
--      PlaceholderCutscene.Play(input: CutsceneContract.Input) -> CutsceneContract.Handle
-- ===========================================================================================
-- Thrower: letterboxed camera tweens + DogFactory rig + DogAnimator poses, beats in contract order:
--   1 Suspense (ball flight + distance/zone callout + rustling bush; rarity NOT shown)
--   2 RevealDog (dog pops in, name + rarity banner in the rarity colour)
--   3 RevealVariant (VariantFX applied + badge) — only if the dog has a variant
--   4 Catch (leap -> catch + wag, or fumble -> bolts off toward the plaza)
--   5 EndCard (dog preview, name, rarity colour, variant badge, multiplied $/s / ran-off info); skipped when
--     Input.EndCard == false because the client UI's Reveal card takes over
-- Spectators: a small camera-less banner card (~50% length), never blocks input.
-- CLIENT ONLY.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent
local Config = Shared:WaitForChild("Config")
local Util = Shared:WaitForChild("Util")
local Rarities = require(Config:WaitForChild("Rarities"))
local Layout = require(Config:WaitForChild("Layout"))
local Zones = require(Config:WaitForChild("Zones"))
local Balls = require(Config:WaitForChild("Balls"))
local Timers = require(Config:WaitForChild("Timers"))
local DogCatalog = require(Util:WaitForChild("DogCatalog"))
local FormatNumber = require(Util:WaitForChild("FormatNumber"))
local DogFolder = Shared:WaitForChild("Dog")
local DogFactory = require(DogFolder:WaitForChild("DogFactory"))
local DogAnimator = require(DogFolder:WaitForChild("DogAnimator"))
local VariantFX = require(DogFolder:WaitForChild("VariantFX"))
local Contract = require(script.Parent:WaitForChild("CutsceneContract"))

local PlaceholderCutscene = {}
PlaceholderCutscene.IsPlaceholder = true

local FONT_HEAD = Enum.Font.FredokaOne
local FONT_BODY = Enum.Font.GothamBold
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(30, 26, 40)

local zoneById: { [string]: any } = {}
for _, z in Zones do
	zoneById[z.Id] = z
end

local function tierColor(rarity: string): Color3
	local t = (Rarities.Tiers :: any)[rarity]
	return if t then t.Color else WHITE
end

----------------------------------------------------------------------------------------------------
-- tiny UI helpers (the shared cutscene can't use the client UI kit)
----------------------------------------------------------------------------------------------------
local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(c: Color3, t: number): UIStroke
	return new("UIStroke", { Color = c, Thickness = t, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FONT_HEAD,
		TextColor3 = WHITE,
		TextScaled = true,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = INK,
	}
	for k, v in props do
		if k ~= "MaxText" then
			base[k] = v
		end
	end
	local l = new("TextLabel", base)
	new("UITextSizeConstraint", { MaxTextSize = props.MaxText or 64, MinTextSize = 10, Parent = l })
	return l
end

local function pop(gui: GuiObject, time: number?)
	local scale = gui:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = gui })
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(time or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Wait `d` seconds unless the handle asks to skip. Returns true if skipped.
local function hold(handle: Contract.Handle, d: number): boolean
	local t0 = os.clock()
	while os.clock() - t0 < d do
		if handle._skipRequested then
			return true
		end
		task.wait(0.03)
	end
	return handle._skipRequested
end

local function groundAt(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(pos.X, Layout.GroundY + 300, pos.Z), Vector3.new(0, -600, 0), params)
	return if hit then hit.Position else Vector3.new(pos.X, Layout.GroundY, pos.Z)
end

local function placeOnGround(model: Model, pos: Vector3, yaw: number)
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, pos.Y - bottom, 0))
end

local function positions(result: Contract.ThrowResult): (Vector3, Vector3)
	-- One shared raised platform: the ball leaves the deck (ThrowLine.Y) and lands on the field (GroundY).
	local r = result :: any
	local x = Layout.ThrowLine.X or 0
	local start = r.LaunchPos or result.StartPosition or Vector3.new(x, Layout.ThrowLine.Y or Layout.GroundY, Layout.ThrowLine.Z)
	local landing = r.LandPos
		or result.LandingPosition
		or Vector3.new(x, Layout.GroundY, Layout.DistanceToZ(result.Distance))
	return start, landing
end

local function throwerName(result: Contract.ThrowResult): string
	if result.ThrowerName then
		return result.ThrowerName
	end
	local p = Players:GetPlayerByUserId(result.ThrowerUserId)
	return if p then p.DisplayName else "Someone"
end

local function variantBadge(parent: Instance, variant: string, size: UDim2, pos: UDim2, anchor: Vector2): Frame
	local f = new("Frame", {
		Name = "VariantBadge",
		Size = size,
		Position = pos,
		AnchorPoint = anchor,
		BackgroundColor3 = WHITE,
		Parent = parent,
	}, { corner(10), stroke(INK, 3) })
	new("UIGradient", { Color = VariantFX.BadgeGradient(variant), Parent = f })
	label({ Text = string.upper(variant) .. " FORM", Size = UDim2.fromScale(1, 1), TextColor3 = WHITE, Parent = f })
	return f
end

----------------------------------------------------------------------------------------------------
-- End card preview (ViewportFrame + WorldModel so the rig's joints resolve)
----------------------------------------------------------------------------------------------------
local function preview(parent: Instance, def: any, variant: string?): (Frame, () -> ())
	local holder = new("Frame", { Name = "Preview", BackgroundColor3 = Color3.fromRGB(240, 236, 250), Size = UDim2.fromScale(0.42, 0.8),
		Position = UDim2.fromScale(0.04, 0.1), Parent = parent }, { corner(14) })
	local vp = new("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(180, 180, 190),
		LightColor = WHITE, LightDirection = Vector3.new(-1, -1, -1), Parent = holder })
	local world = new("WorldModel", { Parent = vp })
	local model = DogFactory.Build(def, { Variant = variant, NoVfx = true })
	model.Parent = world
	local cf, size = model:GetBoundingBox()
	local cam = new("Camera", { FieldOfView = 30, Parent = vp })
	vp.CurrentCamera = cam
	local dist = math.max(size.X, size.Y, size.Z) * 2.4
	local target = cf.Position
	local unbind = VariantFX.Bind(model, variant)
	local angle = math.pi * 0.85
	local conn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * 0.6
		cam.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(angle) * dist, size.Y * 0.35, math.cos(angle) * dist), target)
	end)
	return holder, function()
		conn:Disconnect()
		unbind()
	end
end

----------------------------------------------------------------------------------------------------
-- THROWER
----------------------------------------------------------------------------------------------------
local function runThrower(input: Contract.Input, handle: Contract.Handle)
	local result = input.Result
	local player = Players.LocalPlayer
	local def = DogCatalog.Get(result.DogId) or { Id = result.DogId, Name = result.DogName or "Dog", Rarity = result.Rarity }
	local timing = Contract.Timing(result.Rarity, result.Variant ~= nil, result.Distance)
	local color = tierColor(result.Rarity)
	local zone = zoneById[result.ZoneId]
	local start, landing = positions(result)
	local cleanup: { () -> () } = {}
	local camera = workspace.CurrentCamera
	local savedType = camera.CameraType
	local savedCF = camera.CFrame

	local gui = new("ScreenGui", { Name = "PlaceholderCutsceneGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	table.insert(cleanup, function()
		gui:Destroy()
	end)
	-- letterbox
	local topBar = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.09, 0),
		Position = UDim2.fromScale(0, -0.09), Parent = gui })
	local botBar = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.09, 0),
		Position = UDim2.fromScale(0, 1), Parent = gui })
	TweenService:Create(topBar, TweenInfo.new(0.25), { Position = UDim2.fromScale(0, 0) }):Play()
	TweenService:Create(botBar, TweenInfo.new(0.25), { Position = UDim2.fromScale(0, 0.91) }):Play()
	label({ Text = "PLACEHOLDER CUTSCENE", Font = FONT_BODY, TextTransparency = 0.4, TextStrokeTransparency = 1,
		Size = UDim2.fromScale(0.4, 0.4), Position = UDim2.fromScale(0.02, 0.3), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14,
		Parent = botBar })

	local callout = label({ Name = "Callout", Text = "", Size = UDim2.fromScale(0.8, 0.09), Position = UDim2.fromScale(0.5, 0.12),
		AnchorPoint = Vector2.new(0.5, 0), MaxText = 48, Parent = gui })
	local big = label({ Name = "Big", Text = "", Size = UDim2.fromScale(0.8, 0.14), Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5), MaxText = 90, Parent = gui })

	local skipButton: TextButton? = nil
	if handle:CanSkip() then
		local b = new("TextButton", { Name = "Skip", Text = "SKIP  >>", Font = FONT_HEAD, TextScaled = true, TextColor3 = INK,
			BackgroundColor3 = WHITE, AutoButtonColor = true, Size = UDim2.fromScale(0.14, 0.06), Position = UDim2.fromScale(0.5, 0.895),
			AnchorPoint = Vector2.new(0.5, 1), Parent = gui }, { corner(12), stroke(INK, 3),
			new("UISizeConstraint", { MinSize = Vector2.new(96, 34), MaxSize = Vector2.new(180, 52) }) })
		b.Activated:Connect(function()
			handle:Skip()
		end)
		skipButton = b
	end

	camera.CameraType = Enum.CameraType.Scriptable
	table.insert(cleanup, function()
		camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraSubject = hum
		end
		if savedType == Enum.CameraType.Scriptable then
			camera.CFrame = savedCF
		end
	end)
	local function camTo(cf: CFrame, t: number, style: Enum.EasingStyle?)
		TweenService:Create(camera, TweenInfo.new(t, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = cf }):Play()
	end

	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local ground = groundAt(landing, ignore)

	local skipped = false
	local phase = "Suspense"

	-- 1. SUSPENSE ------------------------------------------------------------------------------
	camera.CFrame = CFrame.lookAt(start + Vector3.new(0, 10, -24), start + Vector3.new(0, 4, 40))
	camTo(CFrame.lookAt(ground + Vector3.new(0, 22, -38), ground), timing.Flight, Enum.EasingStyle.Quad)
	callout.Text = "Throw!"
	skipped = hold(handle, timing.Flight)
	if not skipped then
		callout.Text = ("%d studs!"):format(math.floor(result.Distance))
		pop(callout)
		big.Text = if zone then zone.Name else result.ZoneId
		big.TextColor3 = if zone then zone.Theme.Accent:Lerp(WHITE, 0.35) else WHITE
		pop(big)
		-- rustling bush (rarity is NOT revealed here; teaser is TBD-2)
		local bush = new("Part", { Name = "CutsceneBush", Shape = Enum.PartType.Ball, Size = Vector3.one * 5, Anchored = true,
			CanCollide = false, CanQuery = false, Color = Color3.fromRGB(70, 150, 60), Material = Enum.Material.LeafyGrass,
			CFrame = CFrame.new(ground + Vector3.new(0, 2, 0)), Parent = workspace })
		table.insert(ignore, bush)
		local shake = RunService.RenderStepped:Connect(function()
			local t = os.clock()
			bush.CFrame = CFrame.new(ground + Vector3.new(math.sin(t * 40) * 0.25, 2 + math.abs(math.sin(t * 13)) * 0.3, 0))
		end)
		camTo(CFrame.lookAt(ground + Vector3.new(4, 9, -20), ground + Vector3.new(0, 2, 0)), timing.Suspense - timing.Flight)
		task.delay(0.5, function()
			if big.Parent and phase == "Suspense" then
				big.Text = "Something's coming..."
				big.TextColor3 = WHITE
			end
		end)
		skipped = hold(handle, timing.Suspense - timing.Flight)
		shake:Disconnect()
		bush:Destroy()
	end

	-- 2. REVEAL DOG + RARITY ------------------------------------------------------------------
	phase = "RevealDog"
	local m = DogFactory.Build(def, nil, false)
	m.Name = "CutsceneDog"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
		end
	end
	placeOnGround(m, ground, 0) -- faces -Z, toward the throw line / camera
	m.Parent = workspace
	table.insert(cleanup, function()
		m:Destroy()
	end)
	local a = DogAnimator.new(m, { AlwaysAnimate = true })
	table.insert(cleanup, function()
		a:Destroy()
	end)
	local fullScale = m:GetScale()
	local dogCF, dogSize = m:GetBoundingBox()
	local focus = dogCF.Position
	local closeCam = CFrame.lookAt(focus + Vector3.new(dogSize.X * 0.6 + 2, dogSize.Y * 0.6 + 1.5, -(dogSize.Z * 1.2 + 9)),
		focus + Vector3.new(0, dogSize.Y * 0.1, 0))

	if not skipped then
		-- pop-in
		m:ScaleTo(fullScale * 0.05)
		placeOnGround(m, ground, 0)
		camTo(closeCam, math.min(0.6, timing.RevealDog * 0.5), Enum.EasingStyle.Back)
		local steps = 10
		for i = 1, steps do
			m:ScaleTo(fullScale * (0.05 + 0.95 * (i / steps)))
			placeOnGround(m, ground, 0)
			task.wait(0.02)
		end
		a.Scale = m:GetScale()
		callout.Text = string.upper(result.Rarity) .. "!"
		callout.TextColor3 = color
		pop(callout)
		big.Text = def.Name or result.DogName or "Dog"
		big.TextColor3 = WHITE
		pop(big)
		local flash = new("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
			ZIndex = 0, Parent = gui })
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		skipped = hold(handle, timing.RevealDog)
	else
		camera.CFrame = closeCam
	end

	-- 3. VARIANT BADGE ----------------------------------------------------------------------
	local unbindFx: () -> () = function() end
	if result.Variant then
		VariantFX.Apply(m, result.Variant)
		unbindFx = VariantFX.Bind(m, result.Variant)
		table.insert(cleanup, unbindFx)
		if not skipped then
			local badge = variantBadge(gui, result.Variant, UDim2.fromScale(0.26, 0.07), UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0))
			new("UISizeConstraint", { MinSize = Vector2.new(150, 34), MaxSize = Vector2.new(320, 60), Parent = badge })
			pop(badge, 0.35)
			table.insert(cleanup, function()
				badge:Destroy()
			end)
			skipped = hold(handle, timing.RevealVariant)
		end
	end

	-- 4. CATCH BEAT -------------------------------------------------------------------------
	if not skipped then
		big.Text = ""
		callout.Text = ("Catch chance %s"):format(FormatNumber.Percent(result.CatchChance, 0))
		callout.TextColor3 = WHITE
		local ballDef = Balls.ById[result.BallId or Balls.Default] or Balls.ById[Balls.Default]
		local headPart = m:FindFirstChild("Head", true) :: BasePart?
		local headPos = if headPart then headPart.Position else focus + Vector3.new(0, dogSize.Y * 0.4, -dogSize.Z * 0.4)
		local ball = new("Part", { Name = "CutsceneBall", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9 * math.max(1, fullScale * 0.8),
			Anchored = true, CanCollide = false, CanQuery = false, Color = ballDef.Color, Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(headPos + Vector3.new(0, 12, -6)), Parent = workspace })
		table.insert(cleanup, function()
			ball:Destroy()
		end)
		local fall = timing.Catch * 0.35
		TweenService:Create(ball, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = CFrame.new(headPos + Vector3.new(0, dogSize.Y * 0.4, 0)) }):Play()
		task.spawn(function()
			a:PlayOnce("leap", math.min(0.9, fall * 1.6))
		end)
		skipped = hold(handle, fall)
		if not skipped then
			local usedTreat = result.TreatPocketUsed == true
			if result.Caught and usedTreat then
				-- show the near-miss first, then the Treat Pocket save
				big.Text = "Fumble..."
				big.TextColor3 = Color3.fromRGB(255, 120, 120)
				task.spawn(function()
					a:PlayOnce("fumble", 0.5)
				end)
				skipped = hold(handle, 0.5)
				big.Text = "TREAT POCKET!"
				big.TextColor3 = Color3.fromRGB(255, 220, 120)
				pop(big)
				skipped = hold(handle, 0.4) or skipped
			end
			if result.Caught then
				local snout = m:FindFirstChild("Nose", true) :: BasePart?
				if snout then
					ball.CFrame = CFrame.new(snout.Position + Vector3.new(0, -0.2, -0.3))
					new("WeldConstraint", { Part0 = snout, Part1 = ball, Parent = ball })
					ball.Anchored = false
					ball.Massless = true
				end
				big.Text = "CAUGHT!"
				big.TextColor3 = Color3.fromRGB(120, 255, 140)
				pop(big)
				if result.LuckyStreakTriggered then
					callout.Text = "LUCKY STREAK! Guaranteed catch"
					callout.TextColor3 = Color3.fromRGB(255, 210, 70)
					pop(callout)
				end
				task.spawn(function()
					a:PlayOnce("catch", math.min(0.9, timing.Catch * 0.5))
				end)
				skipped = hold(handle, timing.Catch - fall) or skipped
			else
				-- fumble -> ball bounces away -> dog bolts toward the plaza (-Z)
				TweenService:Create(ball, TweenInfo.new(0.6, Enum.EasingStyle.Bounce),
					{ CFrame = CFrame.new(ground + Vector3.new(4, ball.Size.Y / 2, 3)) }):Play()
				big.Text = "FUMBLE!"
				big.TextColor3 = Color3.fromRGB(255, 110, 110)
				pop(big)
				if result.TreatPocketUsed then
					callout.Text = "Treat Pocket used... still slipped away"
				end
				a:PlayOnce("fumble", math.min(1.1, (timing.Catch - fall) * 0.45))
				a:Play("bolt")
				big.Text = "It ran off!"
				local runTime = math.max(0.4, (timing.Catch - fall) * 0.55)
				local startPivot = m:GetPivot()
				local speed = 36 * math.max(0.8, fullScale)
				local t0 = os.clock()
				local runConn = RunService.RenderStepped:Connect(function()
					local el = os.clock() - t0
					m:PivotTo(startPivot + Vector3.new(0, 0, -speed * el))
					camera.CFrame = CFrame.lookAt(camera.CFrame.Position, m:GetPivot().Position)
				end)
				skipped = hold(handle, runTime) or skipped
				runConn:Disconnect()
			end
		end
	end
	if skipButton then
		skipButton.Visible = false
	end

	-- 5. END CARD ---------------------------------------------------------------------------
	-- Skipped when the client UI shows its own Reveal card (Input.EndCard == false).
	if input.EndCard ~= false then
		callout.Text = ""
		big.Text = ""
		local card = new("Frame", { Name = "EndCard", BackgroundColor3 = WHITE, Size = UDim2.fromScale(0.6, 0.56), Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5), Parent = gui }, { corner(18), stroke(color, 5),
			new("UISizeConstraint", { MinSize = Vector2.new(320, 190), MaxSize = Vector2.new(620, 340) }) })
		pop(card, 0.3)
		local _, stopPreview = preview(card, def, result.Variant)
		table.insert(cleanup, stopPreview)
		local right = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.5, 0.84), Position = UDim2.fromScale(0.48, 0.08),
			Parent = card }, { new("UIListLayout", { Padding = UDim.new(0.03, 0), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local function row(text: string, h: number, col: Color3, font: Enum.Font?, order: number): TextLabel
			return label({ Text = text, Size = UDim2.fromScale(1, h), TextColor3 = col, Font = font or FONT_HEAD, TextStrokeTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = right })
		end
		local rarityBar = new("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(1, 0.14), LayoutOrder = 1, Parent = right }, { corner(8) })
		label({ Text = string.upper(result.Rarity), Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 0.6, Parent = rarityBar })
		row(def.Name or result.DogName or "Dog", 0.2, INK, nil, 2)
		if result.Variant then
			local vb = variantBadge(right, result.Variant, UDim2.fromScale(0.6, 0.12), UDim2.new(), Vector2.zero)
			vb.LayoutOrder = 3
		end
		if result.Caught then
			local income = result.Income or (def.Income or 0)
			row(FormatNumber.PerSecond(income), 0.18, Color3.fromRGB(40, 160, 70), nil, 4)
			local note = ("Puppy: earns %d%% for now while it grows"):format(math.floor(Timers.PuppyIncomeFraction * 100))
			if result.Status == "Held" then
				note = "Yard full: it waits in the kennel for a free slot"
			elseif result.Status == "PendingSale" then
				note = "Duplicate: auto-sells soon unless you press Keep"
			end
			row(note, 0.12, Color3.fromRGB(90, 90, 110), FONT_BODY, 5)
		else
			row("RAN OFF!", 0.18, Color3.fromRGB(220, 60, 60), nil, 4)
			row("It's roaming the plaza for " .. Timers.RunawaySeconds .. "s", 0.11, Color3.fromRGB(90, 90, 110), FONT_BODY, 5)
			local idx = table.find(Rarities.Order, result.Rarity) or 1
			if idx >= (table.find(Rarities.Order, "Legendary") or 5) then
				local streak = math.clamp(result.LuckyStreak or 0, 0, Rarities.LuckyStreakMisses)
				local armed = streak >= Rarities.LuckyStreakMisses
				row(if armed then "Lucky Streak ARMED: next Legendary+ is a guaranteed catch!"
					else ("Lucky Streak %d/%d"):format(streak, Rarities.LuckyStreakMisses), 0.11, Color3.fromRGB(200, 140, 20), FONT_BODY, 6)
			end
		end
		hold(handle, if skipped then Contract.MinEndCard else timing.EndCard)
	end

	TweenService:Create(topBar, TweenInfo.new(0.2), { Position = UDim2.fromScale(0, -0.09) }):Play()
	TweenService:Create(botBar, TweenInfo.new(0.2), { Position = UDim2.fromScale(0, 1) }):Play()
	for i = #cleanup, 1, -1 do
		local ok, err = pcall(cleanup[i])
		if not ok then
			warn("[PlaceholderCutscene] cleanup: " .. tostring(err))
		end
	end
end

----------------------------------------------------------------------------------------------------
-- SPECTATOR (camera-less banner)
----------------------------------------------------------------------------------------------------
local fallbackGui: ScreenGui? = nil
local function bannerParent(input: Contract.Input): Instance
	if input.BannerParent and input.BannerParent.Parent then
		return input.BannerParent
	end
	if not fallbackGui or not fallbackGui.Parent then
		local g = new("ScreenGui", { Name = "SpectatorBanners", ResetOnSpawn = false, DisplayOrder = 5,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
		new("Frame", { Name = "Stack", BackgroundTransparency = 1, Size = UDim2.new(0.36, 0, 0.3, 0),
			Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), Parent = g },
			{ new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder }) })
		fallbackGui = g
	end
	return ((fallbackGui :: ScreenGui):FindFirstChild("Stack") :: Instance)
end

local function runSpectator(input: Contract.Input, handle: Contract.Handle)
	local result = input.Result
	local timing = Contract.Timing(result.Rarity, result.Variant ~= nil, result.Distance)
	local length = math.max(2.5, timing.Total * Contract.SpectatorLengthMult)
	local large = Contract.IsLarge(result.Rarity)
	local color = tierColor(result.Rarity)
	local zone = zoneById[result.ZoneId]
	local parent = bannerParent(input)

	local cardStroke = stroke(WHITE, 2)
	local card = new("Frame", { Name = "Banner_" .. result.ThrowId, BackgroundColor3 = Color3.fromRGB(34, 30, 48), BackgroundTransparency = 0.08,
		Size = UDim2.new(1, 0, 0, if large then 58 else 40), LayoutOrder = -math.floor(os.clock() * 10), Parent = parent },
		{ corner(12), cardStroke })
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4), Parent = card })
	local line = label({ Text = ("%s threw %d studs → %s"):format(throwerName(result), math.floor(result.Distance),
		if zone then zone.Name else result.ZoneId), Font = FONT_BODY, Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left, MaxText = if large then 22 else 17, Parent = card })
	pop(card, 0.2)
	local beat = length / 3
	task.wait(beat)
	cardStroke.Color = color
	cardStroke.Thickness = if large then 4 else 3
	line.RichText = true
	local variantText = if result.Variant then (" [%s]"):format(string.upper(result.Variant)) else ""
	line.Text = ('<font color="#%s">%s</font> %s%s'):format(color:ToHex(), string.upper(result.Rarity), result.DogName or result.DogId,
		variantText)
	task.wait(beat)
	if result.Caught then
		line.Text = line.Text .. '  <font color="#7CFF8C">CAUGHT</font>'
	else
		line.Text = line.Text .. '  <font color="#FF6E6E">RAN OFF</font>'
	end
	task.wait(beat)
	TweenService:Create(card, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(line, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(cardStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	task.wait(0.3)
	card:Destroy()
	local _ = handle
end

----------------------------------------------------------------------------------------------------
function PlaceholderCutscene.Play(input: Contract.Input): Contract.Handle
	local handle = Contract.NewHandle(Contract.CanSkip(input.Result, input.IsThrower))
	task.spawn(function()
		local runner = if input.IsThrower then runThrower else runSpectator
		local ok, err = pcall(runner, input, handle)
		if not ok then
			warn("[PlaceholderCutscene] " .. tostring(err))
			-- never leave the camera stuck
			if input.IsThrower then
				local cam = workspace.CurrentCamera
				cam.CameraType = Enum.CameraType.Custom
				local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
				local g = gui and gui:FindFirstChild("PlaceholderCutsceneGui")
				if g then
					g:Destroy()
				end
			end
		end
		handle:_finish()
	end)
	return handle
end

return PlaceholderCutscene
