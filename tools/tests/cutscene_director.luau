--!nocheck
-- End-to-end harness for the client cutscene (src/client/Cutscene) under the Roblox emulator
-- (tools/uicheck/roblox.luau) with real Vector3 / CFrame (@lune/roblox), a virtual clock and a frame pump.
--   lune run tools/tests/cutscene_director.luau
-- Plays every branch (caught / missed, skip allowed / refused, short Common, no result -> fallback, late
-- result during the hold, result mid-flight, death mid-flight, runtime error, fake test outcome, result
-- without a local release, spectator throw) and proves after each: the camera is back (Custom, subject, FOV),
-- the HUD is visible, every cutscene instance / render binding is gone, every Motor6D C0 is restored, and
-- CutsceneFinished went to the server exactly once for an answered real throw (never for fakes / unanswered).
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local task = require("@lune/task")
local Loader = require("./loader")
local R = require("../uicheck/roblox")
local check = Loader.Check

local ROOT = string.gsub(process.cwd, "/$", "")
local V3, CF = roblox.Vector3, roblox.CFrame

-- ------------------------------------------------------------------ environment: 3D types, virtual clock
local vclock = 1000
local env = R.BaseEnv
env.Vector3 = V3
env.CFrame = CF
env.RaycastParams = { new = function()
	return {}
end }
env.os = setmetatable({ clock = function()
	return vclock
end }, { __index = os })
local baseTypeof = env.typeof
env.typeof = function(v)
	if type(v) == "userdata" then
		return typeof(v)
	end
	return baseTypeof(v)
end
local warnings = {}
env.warn = function(...)
	local parts = {}
	for _, v in { ... } do
		table.insert(parts, tostring(v))
	end
	table.insert(warnings, table.concat(parts, " "))
end

-- Instance defaults the emulator does not know for 3D classes
local Instance0 = R.Instance
env.Instance = { new = function(cls, parent)
	local i = Instance0.new(cls)
	if cls == "Weld" or cls == "Motor6D" or cls == "ManualWeld" then
		i.C0 = CF.new()
		i.C1 = CF.new()
		i.Transform = CF.new()
		i.Part0 = nil
		i.Part1 = nil
	elseif cls == "Part" or cls == "MeshPart" or cls == "WedgePart" or cls == "CornerWedgePart" then
		i.CFrame = CF.new()
		i.Size = V3.new(4, 1, 2)
		i.Anchored = false
		i.Transparency = 0
		i.Color = env.Color3.new(0.6, 0.6, 0.6)
	elseif cls == "Model" then
		i.PrimaryPart = nil
		i.WorldPivot = CF.new()
	elseif cls == "Attachment" then
		i.CFrame = CF.new()
		i.Position = V3.new()
	end
	if parent then
		i.Parent = parent
	end
	return i
end }

-- 3D stubs
local M = R.Methods
local binds = {}
M.BindToRenderStep = function(_, name, _prio, fn)
	binds[name] = fn
end
M.UnbindFromRenderStep = function(_, name)
	binds[name] = nil
end
M.PivotTo = function(self, cf)
	rawget(self, "__raw").pivot = cf
end
M.GetPivot = function(self)
	return rawget(self, "__raw").pivot or CF.new()
end
M.GetBoundingBox = function(self)
	return M.GetPivot(self), V3.new(2, 2, 3)
end
M.ScaleTo = function() end
M.GetScale = function()
	return 1
end
M.Emit = function() end
M.Play = function(self)
	rawget(self, "__raw").playing = true
end
M.Stop = function(self)
	rawget(self, "__raw").playing = false
end
M.AddItem = function() end
M.Raycast = function()
	return nil
end
M.GetServerTimeNow = function()
	return vclock
end
M.WorldToViewportPoint = function(_, p)
	return p, false
end
local streamed = {}
M.RequestStreamAroundAsync = function(_, pos)
	table.insert(streamed, pos)
end
M.LoadAnimation = function()
	error("no uploaded animations in the harness")
end

-- ------------------------------------------------------------------ mount + UI
local Shared = R.MountTree(ROOT .. "/src/shared", R.ReplicatedStorage, "Shared")
local clientFolder = R.Instance.new("Folder")
clientFolder.Name = "Client"
R.MountTree(ROOT .. "/src/client/UI", clientFolder, "UI")
local cutsceneModule = R.MountTree(ROOT .. "/src/client/Cutscene", clientFolder, "Cutscene")
clientFolder.Parent = R.PlayerGui
local Remotes = R.Require(Shared:FindFirstChild("Remotes"))
local remotesFolder = R.MakeRemotes(Remotes.Events, Remotes.Functions)
local remoteByName = {}
for _, c in remotesFolder:GetChildren() do
	remoteByName[c.Name] = c
end
local C = R.Require(Shared.Config.Cutscene)
local Layout = R.Require(Shared.Config.Layout)
local Game = R.Require(Shared.Config.Game)
local DogCatalog = R.Require(Shared.Util.DogCatalog)
local BallFlight = R.Require(Shared.Util.BallFlight)
local OddsCounter = R.Require(Shared.Cutscene.OddsCounter)

local Enum = R.Enum
local Instance = R.Instance

-- the local character (R15)
local player = R.LocalPlayer
local function part(name, parent, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.CFrame = cf
	p.Size = V3.new(1, 1, 1)
	p.Parent = parent
	return p
end
local motors = {}
local humanoid
local function buildCharacter(owner)
	local char = Instance.new("Model")
	char.Name = owner.Name
	local spot = Layout.Platform.ThrowSpot
	local hrp = part("HumanoidRootPart", char, CF.new(spot.X, spot.Y + 3, spot.Z))
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.AutoRotate = true
	hum.Parent = char
	local list = {}
	for _, spec in {
		{ "UpperTorso", "Waist", CF.new(0, 0.2, 0) }, { "RightUpperArm", "RightShoulder", CF.new(1, 0.56, 0) },
		{ "RightLowerArm", "RightElbow", CF.new(0, -0.33, 0) }, { "LeftUpperArm", "LeftShoulder", CF.new(-1, 0.56, 0) },
		{ "LeftUpperLeg", "LeftHip", CF.new(-0.5, -0.2, 0) }, { "LeftLowerLeg", "LeftKnee", CF.new(0, -0.4, 0) },
		{ "RightUpperLeg", "RightHip", CF.new(0.5, -0.2, 0) }, { "RightLowerLeg", "RightKnee", CF.new(0, -0.4, 0) },
	} do
		local p = part(spec[1], char, hrp.CFrame)
		local m = Instance.new("Motor6D")
		m.Name = spec[2]
		m.C0 = spec[3]
		m.Parent = p
		table.insert(list, { m, spec[3] })
	end
	part("RightHand", char, hrp.CFrame * CF.new(1.5, -1, 0))
	char.Parent = R.Services.Workspace
	return char, hum, list
end
local char
char, humanoid, motors = buildCharacter(player)
player.Character = char

local cam = R.Camera
local defaultCF = CF.new(0, 50, 40) -- behind the player, above
local function resetCamera()
	cam.CFrame = defaultCF
	cam.FieldOfView = 70
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = humanoid
end
resetCamera()

local UIModule = R.Require(clientFolder:FindFirstChild("UI"))
local ui = UIModule.Start({ Parent = R.PlayerGui, IsTouch = false, Viewport = R.Types.Vector2.new(1366, 768), Remotes = remoteByName })
ui.State.Set({ Cash = 100, Bones = 0, ThrowPower = 400, Balls = {}, EquippedBall = "Tennis", SlotCount = 10, Dogs = {}, Book = {},
	BookRewards = {}, Boosts = {}, Whistles = 1, TreatPockets = 0, LuckyStreak = 0, TutorialDone = true, TutorialThrowDone = true,
	PermanentLuck = 0 })
local Cutscene = R.Require(cutsceneModule)
Cutscene.Start(ui)
ui.Cutscene = Cutscene
check(ui.Config.PlaceholderCutscene == false, "cutscene takes over the reveal (PlaceholderCutscene = false)")

-- ------------------------------------------------------------------ frame pump + observers
local RS = R.Services.RunService
local DT = 1 / 30
local seen = { counter = {}, counterVisible = false, message = nil, maxFov = 0, scriptable = false }
local function overlayRoot()
	return ui.Root:FindFirstChild("CutsceneOverlay")
end
local function observe()
	local o = overlayRoot()
	if o then
		local block = o:FindFirstChild("CounterBlock")
		if block and block.Visible then
			seen.counterVisible = true
			local label = block:FindFirstChild("CountHolder"):FindFirstChild("Count")
			table.insert(seen.counter, { text = label.Text, color = label.TextColor3 })
		end
		local msg = o:FindFirstChild("Message")
		if msg and msg.Visible then
			seen.message = msg.Text
		end
		local skip = o:FindFirstChild("Skip")
		if skip and skip.Visible then
			seen.skipVisible = true
		end
	end
	if cam.CameraType == Enum.CameraType.Scriptable then
		seen.scriptable = true
	end
	local balls = R.Services.Workspace:FindFirstChild("CutsceneBalls")
	if balls and balls:FindFirstChild("CutsceneDog") then
		seen.dog = true
	end
	seen.maxFov = math.max(seen.maxFov, cam.FieldOfView)
end
local function frame()
	vclock += DT
	for _, fn in table.clone(binds) do
		fn(DT)
	end
	RS.RenderStepped:Fire(DT)
	task.wait()
	observe()
end
local function revealOk(): boolean
	local reveal = ui.Reveal.Root
	if not reveal.Visible then
		return false
	end
	local card = reveal:FindFirstChild("Card")
	local buttons = card and card:FindFirstChild("Buttons")
	for _, b in buttons and buttons:GetChildren() or {} do
		if b.Name == (seen.pressButton or "Button_OK") then
			seen.revealOutcome = card:FindFirstChild("Outcome").Text
			seen.revealWhistle = buttons:FindFirstChild("Button_Whistle (1)") ~= nil
			b.Activated:Fire()
			return true
		end
	end
	return false
end
-- run frames until the cutscene is idle again (clicks OK on the end card when it shows)
local function runUntilIdle(maxSeconds, hooks)
	local t0 = vclock
	local clicked = false
	while vclock - t0 < maxSeconds do
		frame()
		if hooks then
			for at, fn in hooks do
				if type(at) == "number" and vclock - t0 >= at then
					hooks[at] = nil
					fn()
				end
			end
			if hooks.Counter and seen.counterVisible then
				local fn = hooks.Counter
				hooks.Counter = nil
				fn()
			end
		end
		if not clicked and revealOk() then
			clicked = true
			seen.endCardAt = vclock - t0
		end
		if Cutscene.Current() == nil and (clicked or seen.message or seen.allowNoCard) then
			-- let the return finish
			for _ = 1, 3 do
				frame()
			end
			return vclock - t0
		end
	end
	return nil
end

local finishedRemote = remoteByName.CutsceneFinished
local function finishedCount(id)
	local n = 0
	for _, entry in R.RemoteLog(finishedRemote) do
		if entry[1] == id then
			n += 1
		end
	end
	return n
end
local function totalFinished()
	return #R.RemoteLog(finishedRemote)
end

local function resultFor(rarity, caught, variant, zoneId, distance)
	local dogs = DogCatalog.ZoneTierList(zoneId, rarity)
	local spot = Layout.Platform.ThrowSpot
	local launch, land = BallFlight.Endpoints(spot, spot.Y + Game.Throw.LaunchHeight, Layout.ThrowLine.Z, Layout.GroundY, distance, 8)
	return {
		ThrowId = "T-" .. rarity .. "-" .. tostring(caught) .. "-" .. math.random(1, 1e6),
		ThrowerUserId = player.UserId,
		PadIndex = 1,
		Distance = distance,
		ZoneId = zoneId,
		DogId = dogs[1].Id,
		Rarity = rarity,
		Variant = variant,
		Caught = caught,
		CatchChance = 0.5,
		Boosts = {},
		LuckyStreakTriggered = false,
		TreatPocketUsed = false,
		WhistleOwned = not caught,
		WhistleCount = if caught then 0 else 1,
		IsTutorial = false,
		BallId = "Tennis",
		LaunchPos = launch,
		LandPos = land,
		FlightTime = BallFlight.ForThrow(launch, land).Duration,
		Status = if caught then "Added" else nil,
		ServerTime = vclock,
	}
end

local function serverSends(result)
	remoteByName.ThrowResult.OnClientEvent:Fire(result)
end
local function release()
	-- what the HUD does on the second click (UI init OnChargeRelease)
	ui.ThrowReleased:Fire({ Clock = vclock, Elapsed = 0.8, Tutorial = false })
end

local function cleanState(label, expectFinished, id)
	check(Cutscene.Current() == nil, label .. ": session over")
	check(cam.CameraType == Enum.CameraType.Custom, label .. ": camera back to Custom", tostring(cam.CameraType))
	check(cam.CameraSubject == humanoid, label .. ": camera subject restored")
	check(cam.FieldOfView == 70, label .. ": FOV restored", tostring(cam.FieldOfView))
	check(ui.HUD.Root.Visible == true, label .. ": HUD visible again")
	check(next(binds) == nil, label .. ": render binding removed")
	check(overlayRoot() == nil, label .. ": overlay destroyed")
	local balls = R.Services.Workspace:FindFirstChild("CutsceneBalls")
	check(balls == nil or #balls:GetChildren() == 0, label .. ": every ball / dog / FX instance cleaned",
		balls and tostring(#balls:GetChildren()) or "")
	for _, pair in motors do
		check(pair[1].C0 == pair[2], label .. ": C0 restored " .. pair[1].Name)
	end
	check(humanoid.AutoRotate == true, label .. ": AutoRotate restored")
	if id then
		check(finishedCount(id) == expectFinished, label .. ": CutsceneFinished x" .. expectFinished, tostring(finishedCount(id)))
	end
	for _, w in warnings do
		if not seen.expectWarn then
			check(false, label .. ": no warnings", w)
		end
	end
	table.clear(warnings)
	check(seen.scriptable, label .. ": camera was scripted during the cutscene")
end

local function reset()
	seen = { counter = {}, counterVisible = false, message = nil, maxFov = 0, scriptable = false }
	resetCamera()
	ui.State.Settings.HideCommonReveals = false
end

local function lastCount()
	local e = seen.counter[#seen.counter]
	return e and e.text
end

-- ------------------------------------------------------------------ A: Epic caught, Gold, result during the wind-up
do
	reset()
	local r = resultFor("Epic", true, "Gold", "Beach", 330)
	release()
	local hooks = { [0.3] = function()
		serverSends(r)
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil, "A: finished")
	local target = OddsCounter.Target("Beach", "Epic", ui.State.Luck())
	check(lastCount() == OddsCounter.Text(target), "A: counter lands exactly on the target", tostring(lastCount()) .. " vs " .. target)
	check(seen.counter[1] and seen.counter[1].text == "1 out of 1", "A: counter starts at 1 out of 1")
	check(seen.skipVisible == true, "A: Epic shows Skip")
	check(seen.revealOutcome == "CAUGHT", "A: end card CAUGHT", tostring(seen.revealOutcome))
	check(seen.dog == true, "A: the real dog model was built and shown")
	local colors = {}
	for _, e in seen.counter do
		local key = e.color:ToHex()
		if colors[#colors] ~= key then
			table.insert(colors, key)
		end
	end
	check(colors[1] == "FFFFFF", "A: counter starts white", tostring(colors[1]))
	check(colors[#colors] == R.Require(Shared.Config.Rarities).Tiers.Epic.Color:ToHex(), "A: counter stops on the Epic colour")
	check(#colors >= 3, "A: colour climbs through rarities", table.concat(colors, ","))
	check(#streamed >= 1 and (streamed[#streamed] - r.LandPos).Magnitude < 1e-3, "A: streamed around LandPos")
	check(seen.maxFov >= C.Flight.PovFov - 0.5, "A: POV FOV used")
	-- total from the release to the end card ~ budget + (flight - reference)
	local plan = R.Require(Shared.Cutscene.Timeline).Build("Epic", R.Require(Shared.Cutscene.Timeline).FlightSeconds(r.FlightTime))
	check(math.abs((seen.endCardAt or 0) - plan.Total) < 0.5, "A: end card after the planned total", ("%.2f vs %.2f"):format(seen.endCardAt or -1, plan.Total))
	cleanState("A", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ B: Legendary missed: Skip refused, whistle prompt
do
	reset()
	local r = resultFor("Legendary", false, nil, "Farm", 600)
	seen.pressButton = "Button_Whistle (1)" -- leave through the whistle prompt
	release()
	serverSends(r)
	local hooks = { Counter = function()
		Cutscene.Skip()
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil, "B: finished")
	check(not seen.skipVisible, "B: Legendary has no Skip button")
	local target = OddsCounter.Target("Farm", "Legendary", ui.State.Luck())
	check(lastCount() == OddsCounter.Text(target), "B: skip refused, the count still lands", tostring(lastCount()))
	check(seen.revealOutcome == "RAN OFF" and seen.revealWhistle, "B: RAN OFF + whistle prompt (owns one)")
	cleanState("B", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ C: Common: Skip during the counter jumps to the end card
do
	reset()
	local r = resultFor("Common", true, nil, "Backyard", 40)
	release()
	serverSends(r)
	local skippedAt = nil
	local hooks = { Counter = function()
		skippedAt = vclock
		Cutscene.Skip()
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil and skippedAt ~= nil, "C: finished")
	check(#seen.counter <= 3, "C: counter stopped at once", tostring(#seen.counter))
	check(seen.revealOutcome == "CAUGHT", "C: skipped to the end card with the right outcome")
	cleanState("C", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ D: HideCommonReveals: no counter
do
	reset()
	ui.State.Settings.HideCommonReveals = true
	local r = resultFor("Common", false, nil, "Park", 180)
	release()
	serverSends(r)
	local took = runUntilIdle(60)
	check(took ~= nil, "D: finished")
	check(not seen.counterVisible, "D: short Common shows no counter")
	check(seen.revealOutcome == "RAN OFF", "D: end card still shown")
	cleanState("D", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ E: no ThrowResult: fallback, unlock, no CutsceneFinished
do
	reset()
	local before = totalFinished()
	release()
	local took = runUntilIdle(30)
	check(took ~= nil, "E: finished")
	check(seen.message == C.Fallback.Text, "E: fallback text", tostring(seen.message))
	check(totalFinished() == before, "E: no CutsceneFinished for an unanswered throw")
	check(took < C.WindUp.ReleaseAt + C.Flight.Max + C.Fallback.HoldMax + C.Fallback.ShowFor + C.Return.Time + 1, "E: within the hold limit", tostring(took))
	cleanState("E", 0, nil)
	-- a very late result for it only shows the end card, then reports once
	local late = resultFor("Rare", true, nil, "Beach", 300)
	serverSends(late)
	seen.allowNoCard = false
	local ok = false
	for _ = 1, 30 do
		frame()
		if revealOk() then
			ok = true
			break
		end
	end
	for _ = 1, 5 do
		frame()
	end
	check(ok and Cutscene.Current() == nil, "E: late result -> end card only")
	check(finishedCount(late.ThrowId) == 1, "E: late result reported once")
end

-- ------------------------------------------------------------------ F: result arrives during the landing hold
do
	reset()
	local r = resultFor("Rare", false, "Shadow", "Forest", 850)
	release()
	-- the estimate the cutscene flies while it waits (Elapsed 0.8 = a perfect release)
	local Path = R.Require(Shared.Cutscene:FindFirstChild("Path"))
	local Timeline = R.Require(Shared.Cutscene.Timeline)
	local Meter = R.Require(Shared.Util.Meter)
	local el, ela = Path.Estimate(400, 1, Meter.Evaluate(0.8, false), Layout.Platform.ThrowSpot.X)
	local estFlight = Timeline.FlightSeconds(BallFlight.ForThrow(el, ela).Duration)
	local hooks = { [C.WindUp.ReleaseAt + estFlight + 1.0] = function()
		serverSends(r)
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil, "F: finished")
	check(seen.message == nil, "F: no fallback text")
	check(lastCount() == OddsCounter.Text(OddsCounter.Target("Forest", "Rare", ui.State.Luck())), "F: counter after a late result")
	cleanState("F", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ K: result arrives mid-flight (estimate -> real arc)
do
	reset()
	local r = resultFor("Uncommon", true, "Rainbow", "Park", 200)
	release()
	local hooks = { [1.4] = function()
		serverSends(r)
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil, "K: finished")
	cleanState("K", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ G: death mid-flight
do
	reset()
	local r = resultFor("Mythic", true, nil, "MythicMeadow", 2900)
	release()
	serverSends(r)
	local hooks = { [1.6] = function()
		humanoid.Died:Fire()
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil, "G: finished after death")
	check(seen.revealOutcome == "CAUGHT", "G: outcome still shown")
	cleanState("G", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ I: runtime error inside the sequence
do
	reset()
	local Overlay = R.Require(cutsceneModule:FindFirstChild("Overlay"))
	local realNew = Overlay.new
	Overlay.new = function(...)
		local h = realNew(...)
		h.SetCount = function()
			error("injected test error")
		end
		return h
	end
	seen.expectWarn = true
	local r = resultFor("Epic", false, nil, "SnowyPeaks", 1200)
	release()
	serverSends(r)
	local took = runUntilIdle(60)
	Overlay.new = realNew
	check(took ~= nil, "I: recovered from a runtime error")
	local warned = false
	for _, w in warnings do
		if string.find(w, "injected test error", 1, true) then
			warned = true
		end
	end
	check(warned, "I: the error was reported")
	cleanState("I", 1, r.ThrowId)
	seen.expectWarn = false
end

-- ------------------------------------------------------------------ H: CutsceneTestMode fake
do
	reset()
	local before = totalFinished()
	Cutscene.PlayFake({ Rarity = "Mythic", Caught = true, Variant = "Rainbow" })
	local took = runUntilIdle(60)
	check(took ~= nil, "H: fake finished")
	check(totalFinished() == before, "H: fakes never send CutsceneFinished")
	check(seen.counterVisible, "H: fake shows the counter")
	cleanState("H", 0, nil)
end

-- ------------------------------------------------------------------ J: result without a local release (server auto-release)
do
	reset()
	local r = resultFor("Common", true, nil, "Backyard", 70)
	serverSends(r)
	local took = runUntilIdle(60)
	check(took ~= nil, "J: finished")
	cleanState("J", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ M: reduced motion (hard cuts, calmer FOV)
do
	reset()
	ui.State.Settings.ReducedMotion = true
	local r = resultFor("Rare", true, nil, "Beach", 300)
	release()
	serverSends(r)
	local firstCF = nil
	local Shots = R.Require(Shared.Cutscene.Shots)
	local hooks = { [0.05] = function()
		firstCF = cam.CFrame
	end }
	local took = runUntilIdle(60, hooks)
	ui.State.Settings.ReducedMotion = false
	check(took ~= nil, "M: finished")
	local spot = Layout.Platform.ThrowSpot
	local front = Shots.Front(V3.new(spot.X, spot.Y + 3, spot.Z), V3.new(0, 0, 1))
	check(firstCF ~= nil and (firstCF.Position - front.Position).Magnitude < 1e-3, "M: hard cut straight to the front shot (no sweep)")
	check(seen.maxFov <= math.max(70, C.ReducedMotion.PovFov) + 1e-6, "M: no wide POV FOV", tostring(seen.maxFov))
	cleanState("M", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ L: spectator (someone else's throw)
do
	local other = Instance.new("Player")
	other.Name = "Rival"
	other.DisplayName = "Rival"
	other.UserId = 77
	local otherChar, _, otherMotors = buildCharacter(other)
	other.Character = otherChar
	local oldGet = M.GetPlayerByUserId
	M.GetPlayerByUserId = function(_, id)
		if id == 77 then
			return other
		end
		return oldGet(_, id)
	end
	local Spectator = R.Require(cutsceneModule:FindFirstChild("Spectator"))
	local r = resultFor("Rare", true, nil, "Beach", 300)
	r.ThrowerUserId = 77
	local camBefore = cam.CFrame
	Spectator.Play(r)
	local sawBall, movedMotor = false, false
	for _ = 1, math.ceil((C.WindUp.ReleaseAt + C.Flight.Max + C.Spectator.BallRest + 1) / DT) do
		frame()
		local balls = R.Services.Workspace:FindFirstChild("CutsceneBalls")
		if balls and #balls:GetChildren() > 0 then
			sawBall = true
		end
		for _, pair in otherMotors do
			if pair[1].C0 ~= pair[2] then
				movedMotor = true
			end
		end
	end
	check(sawBall, "L: spectators see the ball")
	check(movedMotor, "L: the thrower's avatar winds up on the spectator's client")
	check(cam.CFrame == camBefore, "L: the spectator camera is untouched")
	local balls = R.Services.Workspace:FindFirstChild("CutsceneBalls")
	check(balls == nil or #balls:GetChildren() == 0, "L: spectator ball removed after its rest")
	for _, pair in otherMotors do
		check(pair[1].C0 == pair[2], "L: thrower C0 restored " .. pair[1].Name)
	end
	M.GetPlayerByUserId = oldGet
end

process.exit(Loader.Done("cutscene_director") > 0 and 1 or 0)
