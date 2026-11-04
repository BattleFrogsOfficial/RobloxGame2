--!nocheck
-- End-to-end harness for the client cutscene (src/client/Cutscene) under the Roblox emulator
-- (tools/uicheck/roblox.luau) with real Vector3 / CFrame (@lune/roblox), a virtual clock and a frame pump.
--   lune run tools/tests/cutscene_director.luau
-- Plays every branch (caught / missed, skip allowed / refused, short Common, no result -> fallback, late
-- result during the hold, result mid-flight, death mid-flight, runtime error, fake test outcome, result
-- without a local release, spectator throw) and proves after each: the camera is back (Custom, subject, FOV),
-- the HUD is visible, every cutscene instance / render binding is gone, every Motor6D C0 is restored, and
-- CutsceneFinished went to the server exactly once for an answered real throw (never for fakes / unanswered).
-- K: every Rig animation path (KeyframeSequence on the Animator with idle muted + restored and the id cached,
-- a track that never loads -> C0, AnimationConstraint joints, R6 C0, no joints). The main runs have no Animator
-- or KeyframeSequenceProvider, so they also prove the C0 fallback.
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
local Path = R.Require(Shared.Cutscene.Path)

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
local seen = { counter = {}, counterVisible = false, message = nil, maxFov = 0, scriptable = false, phases = {} }
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
	local dogNow = balls ~= nil and balls:FindFirstChild("CutsceneDog") ~= nil
	if dogNow then
		seen.dog = true
		seen.dogLastAt = vclock
	elseif seen.dog and not seen.dogGoneAt then
		seen.dogGoneAt = vclock -- first frame without the dog
	end
	local blur = R.Services.Lighting:FindFirstChild("CutsceneBlur")
	if blur then
		seen.blur = true
		seen.blurMax = math.max(seen.blurMax or 0, blur.Size)
	end
	local cur = Cutscene.Current()
	if cur then
		seen.director = cur
		if cur.Phase ~= seen.lastPhase then
			seen.lastPhase = cur.Phase
			table.insert(seen.phases, cur.Phase)
			if cur.Phase == "Counter" then
				seen.dogAtCounter = dogNow
			end
		end
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
	check(R.Services.Lighting:FindFirstChild("CutsceneBlur") == nil, label .. ": motion blur removed")
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
	seen = { counter = {}, counterVisible = false, message = nil, maxFov = 0, scriptable = false, phases = {} }
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
	local blurAtDeath = false
	local hooks = { [1.6] = function()
		blurAtDeath = R.Services.Lighting:FindFirstChild("CutsceneBlur") ~= nil
		humanoid.Died:Fire()
	end }
	local took = runUntilIdle(60, hooks)
	check(took ~= nil, "G: finished after death")
	check(blurAtDeath, "G: the motion blur was up mid-flight (and is cleaned after the abort)")
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
	check(seen.maxFov <= math.max(70, C.ReducedMotion.PovFov) + 1e-6, "M: no wide POV FOV (no FOV punch)", tostring(seen.maxFov))
	local st = seen.director and seen.director.Stats
	check(st ~= nil and st.ImpactShake == 0 and st.SpeedShake == 0, "M: reduced motion: no release / POV shake")
	check(st ~= nil and st.FovPunch == 0, "M: reduced motion: no FOV punch")
	check(st ~= nil and st.Blur == false and not seen.blur, "M: reduced motion: no motion blur")
	cleanState("M", 1, r.ThrowId)
end

-- ------------------------------------------------------------------ K: the rig's animation paths
-- KeyframeSequence on the Animator (registered once per rig type, Action4, lower tracks muted + restored), a track
-- that never loads (falls back to C0), AnimationConstraint joints (Avatar Joint Upgrade), R6, and no joints at all.
do
	local Rig = R.Require(cutsceneModule:FindFirstChild("Rig"))
	local registeredSeqs = {}
	M.RegisterKeyframeSequence = function(_, kfs)
		table.insert(registeredSeqs, kfs)
		return "rbxtemp://" .. #registeredSeqs
	end
	local trackLength = Path.PoseLength()
	local loaded = {}
	M.LoadAnimation = function(_, anim)
		local tr = { AnimationId = anim.AnimationId, Length = trackLength, Priority = Enum.AnimationPriority.Core, Looped = true,
			IsPlaying = false, WeightTarget = 1, Plays = 0 }
		function tr.Play(self, _fade, w)
			self.IsPlaying = true
			self.Plays += 1
			self.PlayWeight = w
		end
		function tr.Stop(self)
			self.IsPlaying = false
		end
		function tr.AdjustWeight(self, w)
			self.WeightTarget = w
		end
		table.insert(loaded, tr)
		return tr
	end
	local idle = { Priority = Enum.AnimationPriority.Core, IsPlaying = true, WeightTarget = 1 }
	function idle.AdjustWeight(self, w)
		self.WeightTarget = w
	end
	local action = { Priority = Enum.AnimationPriority.Action, IsPlaying = true, WeightTarget = 1 }
	function action.AdjustWeight(self, w)
		self.WeightTarget = w
	end
	M.GetPlayingAnimationTracks = function()
		return { idle, action }
	end
	local function runFor(seconds)
		for _ = 1, math.ceil(seconds / DT) do
			frame()
		end
	end

	-- K1: R15 + Animator -> KeyframeSequence
	local who = Instance.new("Player")
	who.Name = "AnimR15"
	local c1, h1, m1 = buildCharacter(who)
	local animator = Instance.new("Animator")
	animator.Parent = h1
	local ballPart = Instance.new("Part")
	ballPart.Parent = R.Services.Workspace
	local rig = Rig.Play(c1, ballPart, V3.new(), { Assets = true })
	check(rig.Path == "KeyframeSequence (R15)", "K1: R15 + Animator plays the KeyframeSequence", rig.Path)
	check(Rig._printed[rig.Path] == true, "K1: the path is reported once (Studio diagnostic)")
	check(#registeredSeqs == 1, "K1: registered one KeyframeSequence")
	local kfs = registeredSeqs[1]
	check(kfs and kfs.ClassName == "KeyframeSequence" and #kfs:GetChildren() == #C.Pose, "K1: one Keyframe per pose key")
	check(kfs and kfs.Priority == Enum.AnimationPriority.Action4 and kfs.Loop == false, "K1: sequence is Action4, not looped")
	local firstKey = kfs and kfs:GetChildren()[1]
	local rootPose = firstKey and firstKey:FindFirstChild("HumanoidRootPart")
	local lower = rootPose and rootPose:FindFirstChild("LowerTorso")
	local upper = lower and lower:FindFirstChild("UpperTorso")
	check(upper and upper:FindFirstChild("RightUpperArm") and upper.RightUpperArm:FindFirstChild("RightLowerArm") ~= nil
		and lower:FindFirstChild("LeftUpperLeg") and lower.LeftUpperLeg:FindFirstChild("LeftLowerLeg") ~= nil, "K1: R15 pose hierarchy")
	check(upper and upper.EasingStyle == Enum.PoseEasingStyle.Cubic and upper.EasingDirection == Enum.PoseEasingDirection.InOut,
		"K1: poses ease Cubic InOut")
	local tr = loaded[#loaded]
	check(tr and tr.AnimationId == "rbxtemp://1" and tr.IsPlaying and tr.Plays == 1, "K1: the registered id is loaded and played")
	check(tr and tr.Priority == Enum.AnimationPriority.Action4 and tr.Looped == false and tr.PlayWeight == 1, "K1: track Action4, weight 1, not looped")
	check(idle.WeightTarget == 0, "K1: the idle track is muted while the throw plays")
	check(action.WeightTarget == 1, "K1: Action tracks are left alone")
	runFor(0.5)
	check((ballPart.Position - rig:HandPosition()).Magnitude < 1e-4, "K1: the ball follows the hand")
	for _, pair in m1 do
		check(pair[1].C0 == pair[2], "K1: C0 untouched on the KeyframeSequence path " .. pair[1].Name)
	end
	rig:Release()
	runFor(Path.PoseLength())
	check(idle.WeightTarget == 1, "K1: the idle track weight is restored after the throw")
	check(tr and not tr.IsPlaying, "K1: the throw track stopped")
	rig:Stop()
	-- second avatar of the same rig type reuses the cached id
	local who2 = Instance.new("Player")
	who2.Name = "AnimR15b"
	local c2, h2 = buildCharacter(who2)
	Instance.new("Animator").Parent = h2
	local rig2 = Rig.Play(c2, nil, V3.new(), { Assets = false })
	check(rig2.Path == "KeyframeSequence (R15)" and #registeredSeqs == 1, "K1: the registered id is cached per rig type", tostring(#registeredSeqs))
	rig2:Stop()
	c1:Destroy()
	c2:Destroy()

	-- K2: the track never loads (Length 0) -> Motor6D C0 fallback
	trackLength = 0
	local who3 = Instance.new("Player")
	who3.Name = "AnimNoLoad"
	local c3, h3, m3 = buildCharacter(who3)
	Instance.new("Animator").Parent = h3
	local rig3 = Rig.Play(c3, nil, V3.new(), {})
	runFor(0.7)
	check(string.find(rig3.Path, "fell back to Motor6D C0", 1, true) ~= nil, "K2: an unloaded track falls back to C0", rig3.Path)
	local moved = false
	for _, pair in m3 do
		if pair[1].C0 ~= pair[2] then
			moved = true
		end
	end
	check(moved, "K2: the C0 fallback moves the joints")
	rig3:Stop()
	for _, pair in m3 do
		check(pair[1].C0 == pair[2], "K2: C0 restored " .. pair[1].Name)
	end
	check(idle.WeightTarget == 1, "K2: idle restored")
	trackLength = Path.PoseLength()
	c3:Destroy()

	-- K3: AnimationConstraint joints (Avatar Joint Upgrade), no Animator -> Transform each frame
	local c4 = Instance.new("Model")
	c4.Name = "Upgraded"
	local hrp = part("HumanoidRootPart", c4, CF.new(0, 3, 0))
	local hum4 = Instance.new("Humanoid")
	hum4.RigType = Enum.HumanoidRigType.R15
	hum4.Parent = c4
	local parts = { HumanoidRootPart = hrp }
	local constraints = {}
	for _, spec in { { "LowerTorso", "HumanoidRootPart", "Root" }, { "UpperTorso", "LowerTorso", "Waist" }, { "RightUpperArm", "UpperTorso", "RightShoulder" },
		{ "RightLowerArm", "RightUpperArm", "RightElbow" }, { "LeftUpperArm", "UpperTorso", "LeftShoulder" }, { "LeftUpperLeg", "LowerTorso", "LeftHip" },
		{ "LeftLowerLeg", "LeftUpperLeg", "LeftKnee" }, { "RightUpperLeg", "LowerTorso", "RightHip" }, { "RightLowerLeg", "RightUpperLeg", "RightKnee" } } do
		local p = part(spec[1], c4, hrp.CFrame)
		parts[spec[1]] = p
		local a0 = Instance.new("Attachment")
		a0.Name = spec[3] .. "RigAttachment"
		a0.CFrame = CF.new(0, 0.5, 0)
		a0.Parent = parts[spec[2]]
		local a1 = Instance.new("Attachment")
		a1.Name = spec[3] .. "RigAttachment"
		a1.Parent = p
		local ac = Instance.new("AnimationConstraint")
		ac.Name = spec[3]
		ac.Attachment0 = a0
		ac.Attachment1 = a1
		ac.Transform = CF.new()
		ac.Parent = p
		local bs = Instance.new("BallSocketConstraint")
		bs.Name = spec[3] .. "BallSocket"
		bs.Parent = p
		constraints[spec[3]] = ac
	end
	part("RightHand", c4, hrp.CFrame * CF.new(1.5, -1, 0))
	c4.Parent = R.Services.Workspace
	local rig4 = Rig.Play(c4, nil, V3.new(), {})
	check(string.find(rig4.Path, "AnimationConstraint", 1, true) == 1, "K3: AnimationConstraint joints are driven", rig4.Path)
	runFor(0.8)
	check(constraints.RightShoulder.Transform ~= CF.new() and constraints.LeftHip.Transform ~= CF.new(), "K3: Transform written during the wind-up")
	check(constraints.Root.Transform == CF.new(), "K3: the root joint is left at rest")
	rig4:Stop()
	for name, ac in constraints do
		check(ac.Transform == CF.new(), "K3: Transform restored " .. name)
	end
	c4:Destroy()

	-- K4: R6 Motor6Ds, no Animator; K5: no joints at all
	local c5 = Instance.new("Model")
	c5.Name = "Classic"
	local hrp5 = part("HumanoidRootPart", c5, CF.new(0, 3, 0))
	local hum5 = Instance.new("Humanoid")
	hum5.RigType = Enum.HumanoidRigType.R6
	hum5.Parent = c5
	local torso = part("Torso", c5, hrp5.CFrame)
	part("Right Arm", c5, hrp5.CFrame * CF.new(1.5, 0, 0))
	local r6m = {}
	for _, spec in { { hrp5, "RootJoint" }, { torso, "Right Shoulder" }, { torso, "Left Shoulder" }, { torso, "Left Hip" }, { torso, "Right Hip" } } do
		local m = Instance.new("Motor6D")
		m.Name = spec[2]
		m.C0 = CF.new(1, 0.5, 0) * CF.Angles(0, math.pi / 2, 0)
		m.Parent = spec[1]
		table.insert(r6m, { m, m.C0 })
	end
	local rig5 = Rig.Play(c5, nil, V3.new(), {})
	check(string.find(rig5.Path, "Motor6D C0", 1, true) == 1, "K4: R6 without an Animator uses C0", rig5.Path)
	runFor(0.8)
	check(r6m[2][1].C0 ~= r6m[2][2], "K4: R6 shoulder moves")
	check((rig5:HandPosition() - (c5["Right Arm"].CFrame * CF.new(0, -C.WindUp.BallGrip, 0)).Position).Magnitude < 1e-4, "K4: R6 hand grip")
	rig5:Stop()
	for _, pair in r6m do
		check(pair[1].C0 == pair[2], "K4: R6 C0 restored " .. pair[1].Name)
	end
	c5:Destroy()
	local c6 = Instance.new("Model")
	c6.Name = "Statue"
	part("HumanoidRootPart", c6, CF.new())
	local rig6 = Rig.Play(c6, nil, V3.new(1, 2, 3), {})
	check(rig6.Path == "NONE: no joints found on Statue (R6)", "K5: no joints is reported", rig6.Path)
	check(rig6:HandPosition() == V3.new(1, 2, 3), "K5: no hand -> fallback position")
	rig6:Stop()

	M.RegisterKeyframeSequence = nil
	M.GetPlayingAnimationTracks = nil
	M.LoadAnimation = function()
		error("no uploaded animations in the harness")
	end
	table.clear(warnings)
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

-- ------------------------------------------------------------------ N / O: catch + miss beat order, release impact,
-- the leaving dog's removal rule (time + distance, never before Outcome.HopAwayMinSeconds)
local function logAt(dir, name)
	for _, e in dir.Log do
		if e.Name == name then
			return e.At
		end
	end
	return nil
end
local function phaseIndex(name)
	return table.find(seen.phases, name)
end
for _, spec in {
	{ Label = "N", Rarity = "Rare", Caught = true, Zone = "Park", Distance = 220, Quality = 1, Variant = "Rainbow" },
	{ Label = "N2", Rarity = "Common", Caught = true, Zone = "Backyard", Distance = 40, Quality = 0.6 },
	{ Label = "O", Rarity = "Epic", Caught = false, Zone = "Beach", Distance = 330, Quality = 0.35 },
	{ Label = "O2", Rarity = "Common", Caught = false, Zone = "Backyard", Distance = 40, Quality = 0.8 },
} do
	reset()
	local L = spec.Label
	local r = resultFor(spec.Rarity, spec.Caught, spec.Variant, spec.Zone, spec.Distance)
	r.Quality = spec.Quality
	release()
	serverSends(r)
	local took = runUntilIdle(60)
	check(took ~= nil, L .. ": finished")
	local dir = seen.director
	check(dir ~= nil, L .. ": director observed")
	if dir then
		local st = dir.Stats
		-- release impact
		local Shots = R.Require(Shared.Cutscene.Shots)
		check(math.abs(st.Quality - Shots.QualityScale(spec.Quality)) < 1e-9, L .. ": shake scaled by result.Quality", tostring(st.Quality))
		check(st.ImpactShake > 0.5 * st.Quality, L .. ": release shake starts hard", tostring(st.ImpactShake))
		check(st.SpeedShake > 0, L .. ": ball-speed POV shake")
		check(st.FovPunch > (C.Impact.FovPeak - C.Impact.FovFrom) * 0.8, L .. ": FOV punch", tostring(st.FovPunch))
		check(st.Blur and seen.blur and seen.blurMax <= C.Flight.BlurSize + 1e-6 and seen.blurMax > 0, L .. ": motion blur up to BlurSize",
			tostring(seen.blurMax))
		-- beat order
		local order = if spec.Caught then { "DogArrive", "Grab", "Victory", "Counter", "CounterHold", "HopAway" }
			else { "DogArrive", "Counter", "CounterHold", "Sniff", "Bolt" }
		local last = 0
		for _, ph in order do
			local i = phaseIndex(ph)
			check(i ~= nil and i > last, L .. ": phase " .. ph .. " in order", table.concat(seen.phases, ","))
			last = i or last
		end
		if spec.Caught then
			check(phaseIndex("Sniff") == nil and phaseIndex("Bolt") == nil, L .. ": no sniff / bolt on a catch")
			check(st.Confetti == C.Victory.Jumps, L .. ": one confetti burst per victory jump", tostring(st.Confetti))
			check(seen.dogAtCounter == true, L .. ": the dog is still there when the counter starts (celebrated first)")
			local g, v, c, h = logAt(dir, "Grab"), logAt(dir, "Victory"), logAt(dir, "Counter"), logAt(dir, "HopAway")
			check(g and v and c and h and g < v and v < c and c < h, L .. ": grab -> victory -> counter -> hop away")
			if v and c then
				check(math.abs((c - v) - C.Beats.Victory[spec.Rarity]) < 2 * DT, L .. ": the victory beat lasts Beats.Victory", tostring(c - v))
			end
		else
			check(phaseIndex("Grab") == nil and phaseIndex("Victory") == nil, L .. ": no grab / victory on a miss")
			local c, sn, sad, b = logAt(dir, "Counter"), logAt(dir, "Sniff"), logAt(dir, "SadLook"), logAt(dir, "Bolt")
			check(c and sn and sad and b and c < sn and sn < sad and sad < b, L .. ": counter -> sniff -> look -> bolt (rarity before the loss)")
			if sn and b then
				check(math.abs((b - sn) - C.Beats.Sniff[spec.Rarity]) < 2 * DT, L .. ": the sniff beat lasts Beats.Sniff", tostring(b - sn))
			end
			check(st.Confetti == 0, L .. ": no confetti on a miss")
		end
		-- the leaving dog: removed by time + distance, never before HopAwayMinSeconds after it starts leaving
		local leave, removed = logAt(dir, "LeaveStart"), logAt(dir, "DogRemoved")
		check(leave ~= nil and removed ~= nil, L .. ": dog left and was removed")
		if leave and removed then
			check(removed - leave >= C.Outcome.HopAwayMinSeconds - 1e-6, L .. ": dog kept >= HopAwayMinSeconds", ("%.3f"):format(removed - leave))
			check(removed - leave <= C.Outcome.HopAwayMaxSeconds + DT, L .. ": dog removed by HopAwayMaxSeconds")
			check(seen.dogGoneAt ~= nil and seen.dogGoneAt - leave >= C.Outcome.HopAwayMinSeconds - 1e-6,
				L .. ": the dog model stayed in the world >= HopAwayMinSeconds", tostring(seen.dogGoneAt and seen.dogGoneAt - leave))
		end
	end
	cleanState(L, 1, r.ThrowId)
end

-- ------------------------------------------------------------------ P: the dog rig on every body type
-- Every body type has the joints the procedural victory / sniff / Idle need (RootJoint, Neck, TailJoint, EarL, EarR),
-- every Mythic UniquePart follows the body (a Weld / Motor6D chain back to the Torso), the "victory" pose moves
-- body, tail and ears with the ears lagging, and DogAnimator.Idle drives C0s (WorldModel-safe) and restores them.
do
	local BodyTypes = R.Require(Shared.Dog.BodyTypes)
	local DogFactory = R.Require(Shared.Dog.DogFactory)
	local DogAnimator = R.Require(Shared.Dog.DogAnimator)
	local function joints(model)
		local byName, list = {}, {}
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				byName[d.Name] = d
				table.insert(list, d)
			end
		end
		return byName, list
	end
	local function followsBody(model)
		local torso = model:FindFirstChild("Torso", true)
		local edges = {}
		for _, d in model:GetDescendants() do
			if (d:IsA("Weld") or d:IsA("Motor6D")) and d.Part0 and d.Part1 then
				edges[d.Part0] = edges[d.Part0] or {}
				table.insert(edges[d.Part0], d.Part1)
			end
		end
		local reached = { [torso] = true }
		local stack = { torso }
		while #stack > 0 do
			local p = table.remove(stack)
			for _, q in edges[p] or {} do
				if not reached[q] then
					reached[q] = true
					table.insert(stack, q)
				end
			end
		end
		local loose = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Root" and not reached[d] then
				table.insert(loose, d.Name)
			end
		end
		return loose
	end
	check(#BodyTypes.Order == 14, "P: 14 body types")
	for _, bodyId in BodyTypes.Order do
		local model = DogFactory.Build({ Id = "p_" .. bodyId, Name = bodyId, Body = bodyId, Rarity = "Rare" })
		local j = joints(model)
		for _, need in { "RootJoint", "Neck", "TailJoint", "EarL", "EarR" } do
			check(j[need] ~= nil and j[need].Part0 ~= nil and j[need].Part1 ~= nil, "P: " .. bodyId .. " has " .. need)
		end
		local loose = followsBody(model)
		check(#loose == 0, "P: " .. bodyId .. ": every part follows the body", table.concat(loose, ","))
	end
	-- Mythic unique parts: every one follows the body
	local uniques = {}
	for name in DogFactory.UniqueParts do
		table.insert(uniques, name)
	end
	table.sort(uniques)
	for _, u in uniques do
		local model = DogFactory.Build({ Id = "m_" .. u, Name = u, Body = "medium_lean", Rarity = "Mythic", UniqueParts = { u } })
		local loose = followsBody(model)
		check(#loose == 0, "P: Mythic " .. u .. " follows the body", table.concat(loose, ","))
		local j = joints(model)
		if u == "two_heads" or u == "three_heads" then
			check(j.Neck2 ~= nil and j.EarL2 ~= nil, "P: " .. u .. ": extra head has its own neck + ears (animated with the body)")
		elseif u == "wings" then
			check(j.WingL ~= nil and j.WingR ~= nil, "P: wings are jointed to the torso")
		end
	end
	-- the victory pose (pure): body bounces Jumps times, ears lag the body by EarLag
	local V = C.Victory
	local shape = { Jumps = V.Jumps, JumpTime = V.JumpTime, JumpGap = V.JumpGap, Height = V.Height, WagHz = V.WagHz,
		WagDegrees = V.WagDegrees, EarLag = V.EarLag, EarFlapDegrees = V.EarFlapDegrees }
	local peaks, prevY, rising = 0, 0, false
	for i = 0, math.floor(C.Beats.Victory.Common * 120) do
		local y = DogAnimator.VictoryY(shape, i / 120)
		if y < prevY and rising and prevY > V.Height * 0.8 then
			peaks += 1
		end
		rising = y > prevY
		prevY = y
	end
	check(peaks == V.Jumps, "P: victory = " .. V.Jumps .. " jumps", tostring(peaks))
	check(V.Jumps * (V.JumpTime + V.JumpGap) <= C.Beats.Victory.Common + 1e-9, "P: the jumps fit the shortest victory beat")
	-- run the real pose on a giant_fluffy and a three-headed winged Mythic for a beat: tail wags, ears move, motors stay finite
	for _, def in { { Id = "v1", Body = "giant_fluffy", Rarity = "Epic" },
		{ Id = "v2", Body = "toy", Rarity = "Mythic", UniqueParts = { "three_heads", "wings", "nine_tails" } } } do
		local model = DogFactory.Build(def)
		model.Parent = R.Services.Workspace
		local anim = DogAnimator.new(model, { AlwaysAnimate = true })
		anim.Victory = shape
		anim:StartOnce("victory", C.Beats.Victory.Common)
		local byName = joints(model)
		local tailSeen, earSeen, rootUp = {}, {}, 0
		for _ = 1, math.ceil(C.Beats.Victory.Common / DT) do
			vclock += DT
			RS.PreSimulation:Fire(DT)
			local tz = select(3, byName.TailJoint.Transform:ToEulerAnglesXYZ())
			tailSeen[tz > 0.1 and "pos" or tz < -0.1 and "neg" or "mid"] = true
			local ex = byName.EarL.Transform:ToEulerAnglesXYZ()
			earSeen[ex > 0.1 and "up" or ex < -0.1 and "down" or "mid"] = true
			rootUp = math.max(rootUp, byName.RootJoint.Transform.Position.Y)
		end
		check(tailSeen.pos and tailSeen.neg, "P: " .. def.Body .. ": tail wags during the victory beat")
		check(earSeen.up and earSeen.down, "P: " .. def.Body .. ": ears flap on the jumps")
		check(rootUp > V.Height * 0.8 * model:GetScale(), "P: " .. def.Body .. ": body jumps", tostring(rootUp))
		if def.UniqueParts then
			check(byName.Neck2.Transform ~= CF.new() and byName.TailJoint5 ~= nil and byName.TailJoint5.Transform ~= CF.new()
				and byName.WingL.Transform ~= CF.new(), "P: extra heads / tails / wings animate with the body")
		end
		anim:Destroy()
		model:Destroy()
	end
	-- DogAnimator.Idle (the end card's API): C0-driven, Happy wags + hops, Sad holds still, Stop restores every C0
	for _, mood in { "Happy", "Sad" } do
		local model = DogFactory.Build({ Id = "idle_" .. mood, Body = "corgi_type", Rarity = "Legendary", UniqueParts = { "two_heads" } })
		model.Parent = R.Services.Workspace
		local byName, list = joints(model)
		local base = {}
		for _, m in list do
			base[m] = m.C0
		end
		local h = DogAnimator.Idle(model, { WagHz = 6, HopEvery = 1, HopHeight = 0.6, Ears = true, Mood = mood })
		check(type(h) == "table" and type(h.Stop) == "function", "P: Idle(" .. mood .. ") returns { Stop }")
		local tails, rootMax, transformsUntouched = {}, -1e9, true
		for i = 1, 60 do
			RS.RenderStepped:Fire(DT)
			RS.Heartbeat:Fire(DT)
			local off = base[byName.TailJoint]:Inverse() * byName.TailJoint.C0
			tails[i] = select(3, off:ToEulerAnglesXYZ())
			rootMax = math.max(rootMax, (base[byName.RootJoint]:Inverse() * byName.RootJoint.C0).Position.Y)
			for _, m in list do
				if m.Transform ~= CF.new() then
					transformsUntouched = false
				end
			end
		end
		check(transformsUntouched, "P: Idle(" .. mood .. ") drives C0, not Transform")
		local minT, maxT = math.huge, -math.huge
		for _, v in tails do
			minT, maxT = math.min(minT, v), math.max(maxT, v)
		end
		if mood == "Happy" then
			check(maxT - minT > 0.5, "P: Idle Happy: tail wags", ("%.2f"):format(maxT - minT))
			check(rootMax > 0.3 * model:GetScale(), "P: Idle Happy: hops", tostring(rootMax))
		else
			check(maxT - minT < 1e-6, "P: Idle Sad: tail still")
			local neckOff = base[byName.Neck]:Inverse() * byName.Neck.C0
			local _, yaw = neckOff:ToEulerAnglesYXZ()
			check(math.abs(yaw) > math.rad(45), "P: Idle Sad: head turned to look back over the shoulder", tostring(math.deg(yaw)))
			local earOff = base[byName.EarL]:Inverse() * byName.EarL.C0
			check(earOff:ToEulerAnglesXYZ() > math.rad(30), "P: Idle Sad: ears down")
			check(rootMax < 0.05, "P: Idle Sad: no hops")
		end
		h.Stop()
		local restored = true
		for m, c0 in base do
			if m.C0 ~= c0 then
				restored = false
			end
		end
		check(restored, "P: Idle(" .. mood .. ") Stop restores every C0")
		RS.RenderStepped:Fire(DT)
		check(byName.TailJoint.C0 == base[byName.TailJoint], "P: Idle(" .. mood .. ") stopped: no more writes")
		h.Stop() -- idempotent
		model:Destroy()
	end
end

process.exit(Loader.Done("cutscene_director") > 0 and 1 or 0)
