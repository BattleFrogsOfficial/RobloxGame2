--!nocheck
-- End-to-end tests: boots the real server and client code against a fake
-- Roblox engine (tests/harness/Roblox.luau) and plays through the game.
--
-- Run from the repo root:   lune run tests/game.spec.luau

local Harness = require("./harness/Roblox")
local roblox = Harness.roblox
local Vector3 = roblox.Vector3

local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
	end
end
local function eq(name, got, want)
	check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- No coroutine may have thrown since the last call.
local function noErrors(h, label)
	local errs = h:takeErrors()
	check("no runtime errors: " .. label, #errs == 0, #errs .. " error(s)")
	for i = 1, math.min(#errs, 4) do
		print("  ERROR during " .. label .. ":\n    " .. errs[i]:gsub("\n", "\n    "))
	end
end

----------------------------------------------------------------------------
-- World setup
----------------------------------------------------------------------------
local function boot(options)
	local h = Harness.new(options)
	local game = h.game
	local shared = h:mount("src/shared", "Shared", game:GetService("ReplicatedStorage"))
	local server = h:mount("src/server", "Server", game:GetService("ServerScriptService"))
	local starterScripts = roblox.Instance.new("StarterPlayerScripts")
	starterScripts.Parent = game:GetService("StarterPlayer")
	local client = h:mount("src/client", "Client", starterScripts)

	h:run(server, "server")
	h:advance(0.5)

	local world = {
		h = h,
		game = game,
		shared = shared,
		server = server,
		client = client,
	}
	function world.serverModule(name)
		return h:require(server:FindFirstChild(name), "server")
	end
	function world.sharedModule(name, context)
		return h:require(shared:FindFirstChild(name), context or "server")
	end
	function world.clientModule(name)
		local node = client
		for piece in name:gmatch("[^/]+") do
			node = node:FindFirstChild(piece)
		end
		return h:require(node, "client")
	end
	function world.join(userId, name)
		local player = h:addPlayer(userId or 1, name or "Tester")
		h:advance(0.3)
		h:spawnCharacter(player, Vector3.new(0, 3, 30))
		h:advance(0.5)
		return player
	end
	function world.startClient(player)
		h.localPlayer = player
		h.Players.LocalPlayer = player
		h:run(client, "client")
		h:advance(0.5)
	end
	return world
end

----------------------------------------------------------------------------
-- 1. Server boots and builds the world
----------------------------------------------------------------------------
local w = boot()
local h = w.h
noErrors(h, "server boot")
local startupFailures = {}
for _, warning in h.warnings do
	if warning:find("%[Startup%]") then
		table.insert(startupFailures, warning)
	end
end
check("every system started", #startupFailures == 0, startupFailures[1])

local Config = w.sharedModule("Config")
local ws = h.workspace
check("map built", ws:FindFirstChild("Map") ~= nil)
check("template baseplate removed", ws:FindFirstChild("Baseplate") == nil)
check("template spawn removed", ws:FindFirstChild("SpawnLocation") == nil)
check("bases built", ws:FindFirstChild("Pens") ~= nil and #ws.Pens:GetChildren() == Config.MaxPlayers, ws:FindFirstChild("Pens") and #ws.Pens:GetChildren())
local staff = h.game:GetService("StarterPack"):FindFirstChild("Sea Staff")
check("staff tool in StarterPack", staff ~= nil and staff:FindFirstChild("Handle") ~= nil)
check("remotes created", h.ReplicatedStorage:FindFirstChild("Remotes") ~= nil)

----------------------------------------------------------------------------
-- 2. Player joins, gets a pen, client boots
----------------------------------------------------------------------------
local player = w.join(1, "Tester")
noErrors(h, "player join")
local Data = w.serverModule("Data")
local Pens = w.serverModule("Pens")
check("data loaded", Data.get(player) ~= nil)
check("pen assigned", Pens.get(player) ~= nil)

w.startClient(player)
noErrors(h, "client boot")
local State = w.clientModule("State")
check("client received state", State.data ~= nil)

local Ui = w.clientModule("ui/Ui")
local Ocean = w.clientModule("Ocean")
local Guide = w.clientModule("Guide")
local Remotes = w.sharedModule("Remotes", "client")
local Formulas = w.sharedModule("Formulas")
local O = Config.Ocean
local SHORE = O.ShoreZ

local effects = {}
State.effect:Connect(function(kind)
	effects[kind] = (effects[kind] or 0) + 1
end)
local function sawEffect(kind)
	local n = effects[kind] or 0
	effects[kind] = nil
	return n > 0
end

-- UI actions are rate limited by the server, so leave a beat between them.
local function act(...)
	local okAction, message = State.action(...)
	h:advance(0.12)
	return okAction, message
end

local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local WINDOWS = { "Pets", "Eggs", "Sell", "Upgrades", "Index", "Store", "Playtime", "Daily" }
local function openEveryWindow(label)
	for _, name in WINDOWS do
		Ui.open(name)
		h:advance(1.2, 0.2)
		check("window is open: " .. name, Ui.isOpen(name))
		Ui.close(name)
	end
	noErrors(h, "windows " .. label)
end
openEveryWindow("(fresh player)")

local d = Data.get(player)
local pen = Pens.get(player)
eq("fresh player has no cash", d.cash, 0)
check("guide points a new player at the shore", Guide.text ~= nil and Guide.text:find("shoreline") ~= nil, Guide.text)
check("leaderstats created", player:FindFirstChild("leaderstats") ~= nil and player.leaderstats:FindFirstChild("Cash") ~= nil)

-- No emoji or other special glyphs anywhere in the interface.
local function plainText(root, label)
	local bad
	for _, inst in root:GetDescendants() do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			if inst.Text:find("[\128-\255]") then
				bad = inst:GetFullName() .. " = " .. inst.Text
				break
			end
		end
	end
	check("no emoji in " .. label, bad == nil, bad)
end
plainText(player.PlayerGui, "the HUD and windows")
plainText(ws, "world signs and labels")

-- World layout: one shore, five bases in a row, three leaderboards.
eq("five bases", #ws.Pens:GetChildren(), 5)
local boards = 0
for _, m in ws.Map:GetChildren() do
	if m.Name:find("^Leaderboard") then
		boards += 1
	end
end
eq("three leaderboards in the world", boards, 3)
for _, m in ws.Pens:GetChildren() do
	local c = m:GetAttribute("Center")
	check("base " .. m.Name .. " is on the land side", c.Z > SHORE + 40, c.Z)
end

----------------------------------------------------------------------------
-- 3. Part the sea (cutscene), grab an egg, bank it on land, place it in the plot
----------------------------------------------------------------------------
local camera = ws.CurrentCamera

-- Stand at an egg and complete the hold-E prompt on it.
local function eggPromptAt(spot)
	for _, m in ws.LocalOcean:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart then
			local p = m.PrimaryPart.CFrame.Position
			if math.abs(p.X - spot.X) < 0.5 and math.abs(p.Z - spot.Z) < 0.5 then
				return m.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
			end
		end
	end
	return nil
end
local function grabAt(spot)
	h:moveTo(player, spot + Vector3.new(0, 3, 0))
	h:advance(0.3)
	local prompt = eggPromptAt(spot)
	if prompt and prompt.Enabled then
		h:fire(prompt, "Triggered", player)
	end
	h:advance(0.3)
	return prompt
end
local function startSplit(x, holdSeconds)
	h:moveTo(player, Vector3.new(x, 3, SHORE + 6))
	h:advance(0.3)
	Ocean.beginCharge("mouse")
	h:advance(holdSeconds or 1.6)
	Ocean.releaseCharge("mouse")
	h:advance(0.1)
end
local function waitOutCutscene()
	-- Until the cutscene hands control back, then one beat more.
	for _ = 1, 200 do
		if not Ocean.cutscene then
			break
		end
		h:advance(0.1)
	end
	h:advance(0.2)
end
-- Most scenarios use the plain split so they are deterministic; the special
-- casts get their own section.
player:SetAttribute("ForceCast", "Split")

check("no split before charging", Ocean.active == nil)
camera.CFrame = roblox.CFrame.new(10, 12, SHORE + 26) -- the player's own view
local cameraHome = camera.CFrame
h:moveTo(player, Vector3.new(10, 3, SHORE + 6))
h:advance(0.3)
check("in the split zone", Ocean.inZone)
check("staff auto-equipped on the shore", player.Character:FindFirstChild("Sea Staff") ~= nil)
check("can charge", Ocean.canCharge)
Ocean.beginCharge("mouse")
h:advance(0.7)
check("charge fills while held", Ocean.charge > 0.3 and Ocean.charge < 0.8, Ocean.charge)
h:advance(1)
eq("charge caps at full", Ocean.charge, 1)
Ocean.releaseCharge("mouse")
h:advance(0.1)
noErrors(h, "starting a split")

local sp = Ocean.active
check("split started", sp ~= nil)
check("split depth matches formula", sp and math.abs(sp.length - Formulas.splitParams(0, 1).length) < 0.01, sp and sp.length)
check("split has eggs", sp and #sp.eggs >= 2, sp and #sp.eggs)
eq("server counted the split", d.stats.splits, 1)

-- The cutscene owns the camera and holds the player still.
local Poses = w.clientModule("Poses")
check("cutscene is playing", Ocean.cutscene)
check("server published the cast for everyone to animate", player:GetAttribute("CastStart") ~= nil)
check("cutscene takes the camera", camera.CameraType == roblox.Enum.CameraType.Scriptable)
eq("player held still during the cutscene", player.Character.Humanoid.WalkSpeed, 0)
check("split-start effect fired", sawEffect("splitStart"))
-- Before the slam: the character coils and leaps; the sea is untouched.
h:advance(O.OpenAnim * 0.12)
local rootJoint = player.Character:FindFirstChild("Root", true)
check("body drops into a crouch in the coil", rootJoint ~= nil and rootJoint.C0.Position.Y < -0.4, rootJoint and rootJoint.C0.Position.Y)
h:advance(O.OpenAnim * 0.12)
check("body is launched well off the ground in the leap", rootJoint.C0.Position.Y > 1.2, rootJoint.C0.Position.Y)
check("sea still closed before the slam", ws.LocalOcean.UpperL1.Transparency == 1)
check("no shockwave before the slam", ws.Poses:FindFirstChild("Shockwave") == nil)
h:advance(O.OpenAnim * 0.1)
check("shockwave at the slam", ws.Poses:FindFirstChild("Shockwave") ~= nil)
-- After the slam, the sea has torn open near the shore but not yet far out.
h:advance(O.OpenAnim * 0.14)
local seaParts = ws:FindFirstChild("LocalOcean")
check("near wall has risen out of the sea", seaParts.UpperL1.Transparency < 1 and seaParts.UpperL1.Size.Y > 3, seaParts.UpperL1.Size.Y)
check("far end has not torn open yet", seaParts.UpperL2.Transparency == 1)
local splashes = 0
for _, c in seaParts:GetChildren() do
	if c.Name == "Splash" then
		splashes += 1
	end
end
check("water is flung into the air as the sea tears", splashes > 4, splashes)
check("spray fountain rides the tear", seaParts.RipFront.ParticleEmitter.Enabled)
-- The staff arm is driven by joint transforms (limbs actually move).
local shoulder = player.Character.RightUpperArm.RightShoulder
local t1 = shoulder.C0
h:advance(O.OpenAnim * 0.1)
check("the staff arm moves during the cast", shoulder.C0 ~= t1)
local leftRest = player.Character.UpperTorso.LeftShoulderRigAttachment
check("an arm on the newer joint type (AnimationConstraint) moves too", leftRest.CFrame ~= roblox.CFrame.new())
h:advance(O.OpenAnim * 0.2)
local rShoulder, lShoulder = Poses.cast(0.8, 0).rShoulder, Poses.cast(0.8, 0).lShoulder
check("arms spread wide apart as the sea opens", rShoulder.s > 70 and lShoulder.s > 70, rShoulder.s)
check("rises off the ground while parting", Poses.cast(0.8, 0).root.y > 1.2)
check("HUD hidden during the cutscene", player.PlayerGui.Hud.Enabled == false)
check("cutscene banner shown", player.PlayerGui.Overlay:FindFirstChild("Banner") ~= nil)
waitOutCutscene()
check("cutscene ended", not Ocean.cutscene)
check("camera handed back", camera.CameraType ~= roblox.Enum.CameraType.Scriptable)
check("joints return to rest after the cast", player.Character.RightUpperArm.RightShoulder.C0 == roblox.CFrame.new() and leftRest.CFrame == roblox.CFrame.new())
check("camera glides back to exactly where it was", (camera.CFrame.Position - cameraHome.Position).Magnitude < 0.01)
eq("player can walk again", player.Character.Humanoid.WalkSpeed, 16)
check("HUD back after the cutscene", player.PlayerGui.Hud.Enabled == true)

-- While the sea is open: the zone bar replaces Buy/Base/Sell, and a counter
-- floats over your head.
local hud = player.PlayerGui.Hud
check("zone bar shown while the sea is open", hud.ZoneBar.Visible == true and hud.TopBar.Visible == false)
check("head counter shows 0/1", player.PlayerGui.CarryTag.Enabled == true and player.PlayerGui.CarryTag:FindFirstChildOfClass("TextLabel").Text == "0/1")
check("default player list is switched off", h.coreGui.PlayerList == false)

-- The inside of the sea is dressed: kelp, mist, fish in the walls.
local depths = ws.Depths
local function countNamed(name)
	local n = 0
	for _, c in depths:GetChildren() do
		if c.Name == name then
			n += 1
		end
	end
	return n
end
check("fish swim in the walls", countNamed("Fish") >= 6, countNamed("Fish"))
check("floor mist is on", depths:FindFirstChild("Mist") ~= nil and depths.Mist.ParticleEmitter.Enabled)
h:advance(0.6)
check("water falls from the wall tops", countNamed("Drip") > 0, countNamed("Drip"))
noErrors(h, "parting cutscene")

local ocean = ws:FindFirstChild("LocalOcean")
check("closed sea hidden while parted", ocean.Main.Transparency == 1)
check("corridor walls are visible", ocean.WallL1.Transparency < 1 and ocean.WallR1.Transparency < 1)
check("walls are solid for the camera and the player", ocean.WallL1.CanCollide and ocean.WallL1.CanQuery)
check("far wall is visible", ocean.WallEnd.Transparency < 1)
check("walls have a set-back upper tier and foam crest", ocean.UpperL1.Transparency < 1 and ocean.CapL1.Transparency < 1 and ocean.UpperL1.Size.X < ocean.WallL1.Size.X)
check("wall segments past the corridor end stay hidden", ocean.WallL20.Transparency == 1)
check("spray fountain off once open", not ocean.RipFront.ParticleEmitter.Enabled)
check("wet sand shows on the corridor floor", ocean.WetSand.Transparency < 1)
check("the sea reaches the horizon", ocean:FindFirstChild("Sea1") ~= nil and ocean.Sea1.Size.Z > 1000)
local eggSpots = Ocean.eggPositions()
check("eggs appear in the corridor", #eggSpots >= 2, #eggSpots)
check("guide points at an egg", Guide.text ~= nil and Guide.text:find("egg") ~= nil, Guide.text)
for _, m in ocean:GetChildren() do
	if m:IsA("Model") then
		local beams = 0
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") and p.Material == roblox.Enum.Material.Neon and p.Size.Y > 20 then
				beams += 1
			end
		end
		check("no light beam over eggs", beams == 0)
	end
end

-- The walls close in the whole time.
local gapBefore = ocean.WetSand.Size.X
h:advance(1)
local gapAfter = ocean.WetSand.Size.X
check("walls keep closing from both sides", gapAfter < gapBefore - 0.5, gapBefore .. " -> " .. gapAfter)
local phase, left, room = Ocean.timing()
check("HUD timing reports closing", phase == "closing" and left > 0 and room < 1 and room > 0)

-- Walk onto the egg nearest the corridor center.
table.sort(eggSpots, function(a, b)
	return math.abs(a.X - sp.cx) < math.abs(b.X - sp.cx)
end)
h:moveTo(player, eggSpots[1] + Vector3.new(0, 3, 0))
h:advance(0.6)
eq("walking over an egg no longer picks it up", Ocean.carried, 0)
local firstPrompt = eggPromptAt(eggSpots[1])
check("egg has a hold-E prompt", firstPrompt ~= nil and firstPrompt.Enabled and firstPrompt.KeyboardKeyCode == roblox.Enum.KeyCode.E)
check("the prompt needs a short hold", firstPrompt ~= nil and firstPrompt.HoldDuration > 0.2 and firstPrompt.HoldDuration < 1)
grabAt(eggSpots[1])
noErrors(h, "grabbing an egg")
eq("carrying one egg", Ocean.carried, 1)
check("carried egg shown on the character", player.Character:FindFirstChild("CarriedEgg") ~= nil)
check("grab effect received", sawEffect("grabbed"))
eq("guide says run", Guide.text, "Run back to the beach!")
check("egg counter shown", player.PlayerGui.Hud.Carry.Visible == true)

-- A second egg can't be picked up with full hands.
local secondPrompt = grabAt(eggSpots[2])
-- (If the walls already swallowed that egg there is no prompt to check.)
check("prompts switch off with full hands", secondPrompt == nil or secondPrompt.Enabled == false)
eq("still carrying one egg (hands full)", Ocean.carried, 1)

-- Back on the beach the egg goes straight into the inventory.
h:moveTo(player, Vector3.new(sp.cx, 3, SHORE + 8))
h:advance(0.4)
check("safe effect on reaching land", sawEffect("safe"))
check("reaching land shows no banner", player.PlayerGui.Overlay:FindFirstChild("Banner") == nil)
local flashed = false
for _, c in player.PlayerGui.Overlay:GetChildren() do
	if c:IsA("Frame") and c.BackgroundColor3.G > 0.8 and c.BackgroundColor3.R < 0.5 then
		flashed = true
	end
end
check("reaching land flashes the screen green", flashed)
eq("hands empty once on land", Ocean.carried, 0)
check("banked effect received", sawEffect("banked"))
eq("server counted the egg", d.stats.eggsCollected, 1)
eq("the egg is in the inventory", #d.eggs, 1)
eq("nothing placed in the plot yet", count(d.pen), 0)
check("carried egg removed from character", player.Character:FindFirstChild("CarriedEgg") == nil)
check("counter gone once on land", player.PlayerGui.Hud.Carry.Visible == false)
check("guide sends you to your plot", Guide.text ~= nil and Guide.text:find("plot") ~= nil, Guide.text)

-- Place it anywhere in the plot: pick the egg, point at a spot, click.
local Placement = w.clientModule("Placement")
local uis = h.game:GetService("UserInputService")
local function click()
	h:fire(uis, "InputBegan", { UserInputType = roblox.Enum.UserInputType.MouseButton1 }, false)
	h:advance(0.3)
end
local function plotPoint(x, z)
	return pen.cf:PointToWorldSpace(Vector3.new(x, 0, z))
end
local home = pen.cf.Position
h:moveTo(player, Vector3.new(home.X, 3, home.Z - 20))
h:advance(0.4)
check("guide explains placing", Guide.text ~= nil and Guide.text:find("Place") ~= nil, Guide.text)
check("no fixed egg spots are drawn", pen.model:FindFirstChild("Slots") == nil)
check("an egg can't be placed outside the fence", act("PlaceEgg", 1, plotPoint(60, 0)) == false and #d.eggs == 1)
check("a bad position is refused", act("PlaceEgg", 1, "here") == false and act("PlaceEgg", 1) == false and #d.eggs == 1)
Placement.start(1)
h.mouseWorld = plotPoint(12, -9)
h:advance(0.2)
check("a preview egg follows the mouse", ws:FindFirstChild("EggPreview") ~= nil and (ws.EggPreview:GetPivot().Position - plotPoint(12, -9)).Magnitude < 0.1)
check("the placing panel is up", player.PlayerGui.Hud.Place.Visible == true and Placement.ok)
eq("guide is quiet while placing", Guide.text, nil)
click()
eq("the egg left the inventory", #d.eggs, 0)
check("egg is incubating where it was put", d.pen["1"] ~= nil and d.pen["1"].kind == "egg" and math.abs(d.pen["1"].x - 12) < 0.01 and math.abs(d.pen["1"].z + 9) < 0.01)
check("egg model stands on that spot", #pen.contents:GetChildren() == 1 and (pen.contents:GetChildren()[1]:GetPivot().Position - plotPoint(12, -9)).Magnitude < 0.1)
check("placing ends with the last egg", not Placement.active and ws:FindFirstChild("EggPreview") == nil and player.PlayerGui.Hud.Place.Visible == false)
check("egg is not ready straight away", act("HatchAll") == false and d.pen["1"].kind == "egg")
noErrors(h, "bank the egg and place it")

-- Close early (the corridor may already have shut on its own).
Ocean.close()
h:advance(0.5)
check("split is over", Ocean.active == nil)
check("closed sea is back", ocean.Main.Transparency < 1 and ocean.WallL1.Transparency == 1)
check("top bar returns and the zone bar hides", player.PlayerGui.Hud.TopBar.Visible == true and player.PlayerGui.Hud.ZoneBar.Visible == false)
check("interior dressing is cleared", ws.Depths:FindFirstChild("Fish") == nil and ws.Depths:FindFirstChild("Mist") == nil)
check("walls stop colliding when hidden", not ocean.WallL1.CanCollide and not ocean.BarrierL.CanCollide)
noErrors(h, "close ocean")

----------------------------------------------------------------------------
-- 4. The sea catches you
----------------------------------------------------------------------------
-- Standing in the corridor when the walls meet.
h:advance(1)
startSplit(-40)
sp = Ocean.active
check("second split started", sp ~= nil)
waitOutCutscene()
h:moveTo(player, Vector3.new(sp.cx, O.SeabedY + 3, SHORE - 24))
h:advance(sp.duration * 0.5)
check("safe in the middle while there's room", h:positionOf(player).Z < SHORE)
check("wall gap reported", Ocean.wallGap() ~= nil and Ocean.wallGap() > 0)
-- Eggs near the edges are swallowed as the walls pass them.
local alive = #Ocean.eggPositions()
h:advance(sp.duration * 0.38)
check("eggs get covered as the walls close", #Ocean.eggPositions() < alive, #Ocean.eggPositions() .. " of " .. alive)
h:advance(sp.duration * 0.05)
check("caught effect received", sawEffect("caught"))
check("newer joints are switched off for the ragdoll", player.Character.LeftUpperArm.LeftShoulder.Enabled == false)
check("ragdoll flight started (limp + launched upward)", player.Character.Humanoid.PlatformStand == true and player.Character.HumanoidRootPart.AssemblyLinearVelocity.Y > 50)
check("big centered banner shown", player.PlayerGui.Overlay:FindFirstChild("Banner") ~= nil)
check("split ended when the walls met", Ocean.active == nil)
h:advance(3)
check("put safely on the beach", h:positionOf(player).Z >= SHORE, h:positionOf(player).Z)
check("character stands back up", player.Character.Humanoid.PlatformStand == false)
check("newer joints are switched back on", player.Character.LeftUpperArm.LeftShoulder.Enabled == true)
noErrors(h, "caught by the closing walls")

-- Losing a carried egg.
h:advance(1)
startSplit(60)
sp = Ocean.active
waitOutCutscene()
eggSpots = Ocean.eggPositions()
table.sort(eggSpots, function(a, b)
	return math.abs(a.X - sp.cx) < math.abs(b.X - sp.cx)
end)
grabAt(eggSpots[1])
eq("grabbed an egg on the third run", Ocean.carried, 1)
h:advance(sp.duration + 1)
eq("egg lost when caught", Ocean.carried, 0)
eq("lost egg never counted", d.stats.eggsCollected, 1)
sawEffect("caught")
h:advance(3.5)

-- Walking into the closed sea.
h:moveTo(player, Vector3.new(0, O.SeabedY + 3, SHORE - 40))
h:advance(0.3)
check("pushed out of the closed sea", sawEffect("caught"))
h:advance(3.5)
check("back on the beach", h:positionOf(player).Z >= SHORE)
-- Jumping over the water is still "in the ocean".
h:moveTo(player, Vector3.new(0, 9, SHORE - 6))
h:advance(0.3)
check("jumping over closed water still gets you thrown back", sawEffect("caught"))
h:advance(3.5)
noErrors(h, "push-back cases")

-- A split request from the middle of the map is refused.
h:moveTo(player, Vector3.new(0, 3, SHORE + 60))
local refused, reason = Remotes.get("RequestSplit"):InvokeServer(1)
check("split refused away from the shore", refused == nil and type(reason) == "string", reason)

----------------------------------------------------------------------------
-- 5. Hatch the egg: the pet and the news wait for the cutscene
----------------------------------------------------------------------------
h:advance(Config.EggById[d.pen["1"].egg].hatch + 1, 0.25)
local slot = pen.slotModels["1"]
check("pen egg shows Ready!", slot.timer.Text == "Ready!", slot.timer.Text)
check("hatch prompt enabled", slot.prompt.Enabled)
local toasts = {}
State.toast:Connect(function(text)
	table.insert(toasts, text)
end)
h:fire(slot.prompt, "Triggered", player)
h:advance(1)
check("hatch effect received", sawEffect("hatch"))
check("slot 1 is now an animal", d.pen["1"].kind == "animal")
local firstAnimal = d.pen["1"].animal
local animalModel = pen.slotModels["1"].model
local function isHidden(model)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" and p.LocalTransparencyModifier < 1 then
			return false
		end
	end
	return true
end
check("new pet is hidden in the pen during the cutscene", isHidden(animalModel))
local announcedEarly = false
for _, text in toasts do
	if text:find("Index") then
		announcedEarly = true
	end
end
check("Index news waits for the cutscene", not announcedEarly)
h:advance(6)
check("pet revealed in the pen after the cutscene", not isHidden(animalModel))
local announced = false
for _, text in toasts do
	if text:find("Index") then
		announced = true
	end
end
check("Index news announced after the cutscene", announced)
check("animal recorded in the index", d.index[firstAnimal] == 1)
eq("hatch counted", d.stats.hatched, 1)
noErrors(h, "hatching")
local before = d.cash
h:advance(3.2, 0.2)
check("animal earns money", d.cash > before, d.cash)
check("income shown on the pen sign", pen.ownerLabels[2].Text ~= "")
check("leaderboard cash updates", player.leaderstats.Cash.Value ~= "0", player.leaderstats.Cash.Value)
check("animal is marked for client animation", animalModel:GetAttribute("Animal") == true)
h:advance(8, 0.1)
check("server published a walk", animalModel:GetAttribute("WalkStart") ~= nil and animalModel:GetAttribute("WalkDuration") > 0)
noErrors(h, "income and wandering")

-- Index: completing an egg (all three animals, in one variant) boosts income.
eq("no Index bonus with one animal", Formulas.indexBonus(d.index), 1)
local keep = table.clone(d.index)
for _, a in Config.AnimalsByEgg.Shell do
	d.index[a.id] = 1
end
eq("one complete egg is +10%", Formulas.indexBonus(d.index), 1 + Config.IndexBonusPerEgg)
local plain = 0
for _, item in d.pen do
	if item.kind == "animal" then
		plain += Formulas.animalIncome(item.animal, item.variant)
	end
end
check("the Index bonus is applied to income", math.abs(Data.income(player) - plain * (1 + Config.IndexBonusPerEgg)) < 1e-6)
for _, a in Config.AnimalsByEgg.Shell do
	d.index[Formulas.indexKey(a.id, "Gold")] = 1
end
eq("variants count as separate eggs", Formulas.indexCompleted(d.index), 2)
table.clear(d.index)
for k, v in keep do
	d.index[k] = v
end
check("removed claim action is refused", act("ClaimIndex", firstAnimal) == false)

-- Rare animals are far bigger than common ones.
local Voxel = w.sharedModule("Voxel")
local function height(animal)
	local _, size = Voxel.animal(animal, "Normal"):GetBoundingBox()
	return size.Y
end
check("a Secret pet towers over a Common one", height("Golden Kraken") > height("Crab") * 6, height("Golden Kraken") .. " vs " .. height("Crab"))
check("a Mythic pet is bigger than a Legendary one", height("Kraken") > height("Parrot"))

-- Platinum sits between Gold and Rainbow, for eggs and the animals in them.
local platEgg, goldEgg = Voxel.egg("Shell", "Platinum", false), Voxel.egg("Shell", "Gold", false)
local function shell(model)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			return p
		end
	end
end
check("platinum egg is silvery, not gold", shell(platEgg).Color.B > 0.8 and shell(goldEgg).Color.B < 0.6, tostring(shell(platEgg).Color))
check("platinum egg is shinier than gold", shell(platEgg).Reflectance > shell(goldEgg).Reflectance)
local platCrab = Voxel.animal("Crab", "Platinum")
check("platinum animals are recolored", shell(platCrab).Color.B > 0.7, tostring(shell(platCrab).Color))
Pens.addAnimal(player, "Crab", "Platinum")
h:advance(0.8)
check("a platinum pet is recorded under its own Index entry", d.index["Crab|Platinum"] == 1)
local platKey
for key, item in d.pen do
	if item.kind == "animal" and item.variant == "Platinum" then
		platKey = key
	end
end
check("the platinum pet is in the base, labelled", platKey ~= nil and (function()
	for _, l in pen.slotModels[platKey].model:GetDescendants() do
		if l:IsA("TextLabel") and l.Text == "Platinum" then
			return true
		end
	end
	return false
end)())
Ui.open("Index")
h:advance(0.5)
local tabNames = {}
for _, b in player.PlayerGui.Windows.Index:GetChildren() do
	local lbl = b:IsA("TextButton") and b:FindFirstChild("Label")
	if lbl then
		table.insert(tabNames, lbl.Text)
	end
end
check("Index has a PLATINUM tab between GOLD and RAINBOW", table.concat(tabNames, ","):find("GOLD,PLATINUM,RAINBOW") ~= nil, table.concat(tabNames, ","))
Ui.close("Index")
noErrors(h, "platinum variant")

----------------------------------------------------------------------------
-- 6. Training: automatic on the pad, a rep at a time, no staff
----------------------------------------------------------------------------
local padPos = (pen.cf * roblox.CFrame.new(Pens.PadLocal)).Position
h:moveTo(player, Vector3.new(0, 3, SHORE + 6))
h:advance(0.4)
check("holding the staff before training", player.Character:FindFirstChild("Sea Staff") ~= nil)
h:moveTo(player, padPos + Vector3.new(0, 3, 0))
h:advance(0.4)
check("training starts by stepping on the pad", player:GetAttribute("Training") == true)
check("the pad's barbell is picked up (not also left on the ground)", pen.barbell.Parent == nil)
h:advance(0.1)
local bar = ws.Poses:FindFirstChild("TrainingBarbell")
check("barbell appears", bar ~= nil)
local hands = (player.Character.RightHand.CFrame.Position + player.Character.LeftHand.CFrame.Position) / 2
check("barbell is held in the hands", bar ~= nil and (bar.PrimaryPart.CFrame.Position - hands).Magnitude < 0.01)
local elbow = player.Character.RightLowerArm.RightElbow
local e1, s1 = elbow.C0, player.Character.RightUpperArm.RightShoulder.C0
h:advance(Config.Training.RepTime * 0.3)
check("arms bend and straighten through the rep", elbow.C0 ~= e1 and player.Character.RightUpperArm.RightShoulder.C0 ~= s1)
check("newer-joint arm works the rep too", player.Character.UpperTorso.LeftElbowRigAttachment.CFrame ~= roblox.CFrame.new())
check("staff is put away while training", player.Character:FindFirstChild("Sea Staff") == nil and player.Backpack:FindFirstChild("Sea Staff") ~= nil)
check("you can still walk off the pad", player.Character.Humanoid.WalkSpeed > 0)
eq("no strength before the first rep finishes", d.strength, 0)
check("shockwave on the lockout", (function()
	h:advance(Config.Training.RepTime * 0.9)
	return ws.Poses:FindFirstChild("Shockwave") ~= nil
end)())
h:advance(Config.Training.RepTime * 1.8 + 0.3)

-- Standing still, the workout can't nudge you off the pad...
local rootPart = player.Character.HumanoidRootPart
local stood = rootPart.CFrame.Position
rootPart.CFrame = rootPart.CFrame + Vector3.new(1.5, 0, -1)
rootPart.Position = rootPart.CFrame.Position
h:advance(0.1)
check("drift is pinned back while training", (rootPart.CFrame.Position - stood).Magnitude < 0.05, (rootPart.CFrame.Position - stood).Magnitude)
-- ...but steering still moves you.
h.moveVelocity[player.Character.Humanoid] = Vector3.new(16, 0, 0)
rootPart.CFrame = rootPart.CFrame + Vector3.new(1, 0, 0)
rootPart.Position = rootPart.CFrame.Position
h:advance(0.1)
check("walking is not pinned", (rootPart.CFrame.Position - stood).Magnitude > 0.9)
h.moveVelocity[player.Character.Humanoid] = nil
local gain = Config.Weights[1].gain
check("strength comes one rep at a time", d.strength >= gain * 2 and d.strength <= gain * 4, d.strength)
check("lift effect per rep", sawEffect("lift"))
check("training banner shown", player.PlayerGui.Hud.Train.Visible == true)
h:moveTo(player, Vector3.new(home.X, 3, home.Z + 10))
h:advance(0.4)
check("stepping off stops training", player:GetAttribute("Training") == false)
check("the barbell is back on the pad", pen.barbell.Parent == pen.model)
check("the resting barbell sits on top of the pad, not in the ground", pen.barbell:GetPivot().Position.Y > 1.9, pen.barbell:GetPivot().Position.Y)
check("barbell removed", ws.Poses:FindFirstChild("TrainingBarbell") == nil)
check("joints return to rest after training", elbow.C0 == roblox.CFrame.new() and player.Character.RightUpperArm.RightShoulder.C0 == roblox.CFrame.new())

-- The moves are big, full-body ones.
local squat, lockout = Poses.rep(0.3, 0), Poses.rep(0.5, 0)
check("rep drops into a deep squat", squat.rKnee.f < -100 and squat.rHip.f > 80 and squat.root.y < -1.2)
check("rep locks the bar out overhead", lockout.rShoulder.f > 170 and lockout.rElbow.f < 5)
check("rep hops at the lockout", Poses.rep(0.52, 0).root.y > 0.8)
check("arms travel well over 100 degrees in a rep", lockout.rShoulder.f - squat.rShoulder.f > 100)
check("cast winds the staff far back", Poses.cast(0.12, 0).rShoulder.f < -120)
check("cast leaps high", Poses.cast(0.24, 0).root.y > 3)
local slamK = Config.CastByKey.Split.slam
check("cast slams forward into a lunge", Poses.cast(slamK, 0).root.lean > 25 and Poses.cast(slamK, 0).root.y < 0)

-- The three casts escalate.
local super, poseidon = Config.CastByKey.Super, Config.CastByKey.Poseidon
check("casts get longer", super.seconds > Config.CastByKey.Split.seconds and poseidon.seconds > super.seconds)
check("casts raise taller walls", super.wallTop > Config.CastByKey.Split.wallTop and poseidon.wallTop > super.wallTop * 1.5)
eq("Super Split is 5x luck", super.luck, 5)
eq("Poseidon's Wrath is 10x luck", poseidon.luck, 10)
local function peak(key)
	local top = 0
	for k = 0, 1, 0.01 do
		top = math.max(top, Poses.castHeight(k, key))
	end
	return top
end
check("Super Split leaps about twice as high", peak("Super") > peak("Split") * 1.8, peak("Super"))
check("Poseidon's Wrath flies far into the air", peak("Poseidon") > 20, peak("Poseidon"))
check("Poseidon's Wrath hangs in the sky before diving", Poses.castHeight(0.4, "Poseidon") > 20)
check("Poseidon's Wrath lands hard", Poses.cast(poseidon.slam, 0, "Poseidon").root.y < -1.5 and Poses.cast(poseidon.slam, 0, "Poseidon").root.lean > 40)
check("the bigger casts spin", Poses.cast(super.slam, 0, "Super").root.yaw > 300)
local frozen = d.strength
h:advance(3)
eq("no more strength once off the pad", d.strength, frozen)
noErrors(h, "training")

-- The tutorial is done once you've placed an egg, hatched one and trained.
h:moveTo(player, Vector3.new(0, 3, SHORE + 60))
h:advance(0.5)
eq("guide goes quiet after the tutorial", Guide.text, nil)
eq("no guide arrows left on the ground", #ws.GuideArrows:GetChildren(), 0)

d.cash = 1e12
Data.markDirty(player)
h:advance(0.3)
local luckBefore = d.luckLevel
check("buy 5 luck levels", act("BuyLuck", 5) == true and d.luckLevel == luckBefore + 5, d.luckLevel)
check("buy heavier weight", act("BuyWeight") == true and d.weightTier == 2)
check("upgrade base", act("UpgradeBase") == true and d.baseSlots == Config.Base.StartSlots + Config.Base.SlotsPerLevel)
h:advance(0.3)
check("pad label shows the new weight", pen.padLabels[1].Text:find(tostring(Config.Weights[2].gain)) ~= nil, pen.padLabels[1].Text)
check("client luck updated", State.data.luck > 1)
noErrors(h, "upgrades")

----------------------------------------------------------------------------
-- 7. Rewards and the Robux shop (free Studio grants while IDs are 0)
----------------------------------------------------------------------------
check("daily reward claims", act("ClaimDaily") == true)
check("daily reward only once a day", act("ClaimDaily") == false)
eq("daily streak is 1", d.daily.streak, 1)
check("playtime gift not ready early", act("ClaimPlaytime", 12) == false)
h:advance(61, 0.5)
check("first playtime gift claims", act("ClaimPlaytime", 1) == true)
check("playtime gift can't be claimed twice", act("ClaimPlaytime", 1) == false)
for _, product in Config.Products do
	check("studio grant product " .. product.key, act("StudioGrant", "product", product.key) == true)
	h:advance(0.2)
end
for _, pass in Config.Passes do
	check("studio grant pass " .. pass.key, act("StudioGrant", "pass", pass.key) == true)
	h:advance(0.2)
end
check("passes reach the client", State.data.passes.DoubleCash == true and State.data.carry == 2)
check("starter pack recorded", d.starterPackBought == true)
local allClaimed = true
for i in Config.Playtime do
	if not State.data.playtimeClaimed[tostring(i)] then
		allClaimed = false
	end
end
check("skip playtime claimed every gift", allClaimed)
check("luck potion active", d.boosts.luckUntil > 0 and State.data.luck > Formulas.luck(d.luckLevel, true, false))
check("bogus grant refused", act("StudioGrant", "product", "Nope") == false)
noErrors(h, "rewards and shop")

----------------------------------------------------------------------------
-- 8. Inventory management
----------------------------------------------------------------------------
h:advance(1300, 1) -- let every incubating egg finish
act("HatchAll")
h:advance(40, 0.2) -- cutscenes
noErrors(h, "hatching many eggs")
check("pen is in use", count(d.pen) >= 2, count(d.pen))
local incomeBefore = Data.income(player)
check("place best succeeds", act("PlaceBest") == true)
check("place best never lowers income", Data.income(player) >= incomeBefore)

local animalKey
for key, item in d.pen do
	if item.kind == "animal" then
		animalKey = key
		break
	end
end
local storedBefore = #d.animals
check("store an animal", act("StoreAnimal", animalKey) == true and #d.animals == storedBefore + 1)
local uid = d.animals[#d.animals].uid
check("place it back", act("PlaceAnimal", uid) == true and #d.animals == storedBefore)
h:advance(0.3)
check("pen models match pen data", #pen.contents:GetChildren() == count(d.pen), #pen.contents:GetChildren() .. " vs " .. count(d.pen))
act("StoreAnimal", animalKey)
local cashBefore = d.cash
check("sell a stored animal", act("SellAnimal", "storage", d.animals[#d.animals].uid) == true and d.cash > cashBefore)
check("bad sell target refused", act("SellAnimal", "elsewhere", 1) == false)
check("bad argument types refused", act("PlaceEgg", "one") == false)
check("unknown action refused", act("GiveMeEverything") == false)
openEveryWindow("(established player)")
plainText(player.PlayerGui, "the windows with real data")

-- With Double Carry, two eggs can be carried and banked together.
d.strength = 400 -- a deeper, longer-lasting corridor for a two-egg run
h:advance(1)
startSplit(0)
sp = Ocean.active
waitOutCutscene()
-- A corridor this deep crosses into the second luck zone.
check("corridor reaches the Reef zone", sp.length > Config.Zones[2].from, sp.length)
local line = ws.Depths:FindFirstChild("ZoneLine")
check("a glowing line marks the zone on the seabed", line ~= nil and line.Transparency < 1 and line.Size.X > 10)
local sign = line and line:FindFirstChildOfClass("BillboardGui")
local signText = ""
for _, l in (sign and sign:GetChildren() or {}) do
	signText ..= l.Text .. " "
end
check("the zone sign gives its luck", signText:find("x2 LUCK") ~= nil, signText)
check("kelp lines the corridor", ws.Depths:FindFirstChild("Kelp") ~= nil)
local hudNow = player.PlayerGui.Hud
check("zones past the corridor are locked on the bar", (function()
	local locked = 0
	for _, seg in hudNow.ZoneBar:GetDescendants() do
		if seg.Name == "Lock" and seg.Visible then
			locked += 1
		end
	end
	local expected = 0
	for _, zone in Config.Zones do
		if zone.from >= sp.length then
			expected += 1
		end
	end
	return locked == expected and expected > 0
end)())
eggSpots = Ocean.eggPositions()
table.sort(eggSpots, function(a, b)
	return math.abs(a.X - sp.cx) < math.abs(b.X - sp.cx)
end)
grabAt(eggSpots[1])
grabAt(eggSpots[2])
eq("double carry holds two eggs", Ocean.carried, 2)
local eggsBefore, storedBefore = d.stats.eggsCollected, #d.eggs
h:moveTo(player, Vector3.new(sp.cx, 3, SHORE + 8))
h:advance(0.4)
eq("both eggs counted on land", d.stats.eggsCollected, eggsBefore + 2)
eq("both eggs are in the inventory", #d.eggs, storedBefore + 2)
eq("hands empty on land", Ocean.carried, 0)
Ocean.close()
h:advance(0.5)

-- Placing several eggs: starting from anywhere takes you home, eggs keep
-- their distance from each other, and the preview stays inside the fence.
d.baseSlots = math.max(d.baseSlots, count(d.pen) + #d.eggs)
Data.markDirty(player)
h:advance(0.3)
local toPlace, placedBefore = #d.eggs, count(d.pen)
Placement.start(1)
h:advance(0.4)
check("starting to place takes you to your plot", Pens.contains(player, player.Character.HumanoidRootPart.Position))
h.mouseWorld = plotPoint(-20, 20)
h:advance(0.2)
click()
eq("first egg placed", count(d.pen), placedBefore + 1)
check("placing carries on with the next egg", toPlace < 2 or Placement.active)
h:advance(0.2)
check("the same spot is too close to the last egg", toPlace < 2 or (not Placement.ok and Placement.hint:find("close") ~= nil), Placement.hint)
click()
eq("nothing placed on top of another egg", count(d.pen), placedBefore + 1)
h.mouseWorld = plotPoint(500, 20)
h:advance(0.2)
check("the preview stays inside the fence", toPlace < 2 or (Placement.ok and (ws.EggPreview:GetPivot().Position - plotPoint(Config.Pen.Width / 2 - Config.Pen.PlaceMargin, 20)).Magnitude < 0.1))
for _ = 2, toPlace do
	click()
	h.mouseWorld = plotPoint(0, -25 + count(d.pen) * 6)
	h:advance(0.2)
end
eq("every egg placed", #d.eggs, 0)
check("placing is over", not Placement.active and ws:FindFirstChild("EggPreview") == nil)
Placement.start(1)
check("nothing to place with an empty inventory", not Placement.active)
noErrors(h, "double carry run")

-- A player whose backpack has no staff (spawned before it existed) gets one.
player.Backpack:ClearAllChildren()
local held = player.Character:FindFirstChild("Sea Staff")
if held then
	held:Destroy()
end
w.serverModule("Split").ensureStaff(player)
check("missing staff is handed out", player.Backpack:FindFirstChild("Sea Staff") ~= nil)
w.serverModule("Split").ensureStaff(player)
eq("staff is never duplicated", #player.Backpack:GetChildren(), 1)

----------------------------------------------------------------------------
-- 8b. The shops
----------------------------------------------------------------------------
local PromptService = h.game:GetService("ProximityPromptService")

-- Weights stall in the base.
local weightsStall = pen.model:FindFirstChild("WeightsStall")
check("weights stall replaces the yellow pad", weightsStall ~= nil and pen.model:FindFirstChild("UpgradePad") == nil)
-- The pad, the stall and the upgrade sign stand just outside the front fence.
for _, name in { "TrainPad", "WeightsStall", "BaseSign" } do
	local thing = pen.model:FindFirstChild(name)
	local at = pen.cf:PointToObjectSpace(thing:IsA("Model") and thing:GetPivot().Position or thing.CFrame.Position)
	local front = -Config.Pen.Depth / 2
	check(name .. " is outside the fence, by the front", at.Z < front - 2 and at.Z > front - 20 and math.abs(at.X) < Config.Pen.Width / 2 and math.abs(at.X) > Config.Pen.Gate + 2, tostring(at))
	check(name .. " is not in the plot", not Pens.contains(player, pen.cf:PointToWorldSpace(at)))
end
local weightsPrompt = weightsStall and weightsStall.Counter:FindFirstChildOfClass("ProximityPrompt")
check("its prompt opens the Weights menu", weightsPrompt ~= nil and weightsPrompt:GetAttribute("Menu") == "Weights")
h:fire(PromptService, "PromptTriggered", weightsPrompt, player)
h:advance(0.3)
check("Weights menu opens from the stall", Ui.isOpen("Weights"))
local tierBefore = d.weightTier
check("buying the next barbell from the menu", act("BuyWeight") == true and d.weightTier == tierBefore + 1)
h:advance(0.3)
check("the new barbell rests on the pad, above the ground", pen.barbell.Parent == pen.model and pen.barbell:GetPivot().Position.Y > 1.9, pen.barbell:GetPivot().Position.Y)
Ui.close("Weights")
-- Someone else's stall does nothing for us.
weightsPrompt:SetAttribute("OwnerId", 999)
h:fire(PromptService, "PromptTriggered", weightsPrompt, player)
h:advance(0.2)
check("another player's stall doesn't open a menu", not Ui.isOpen("Weights"))
weightsPrompt:SetAttribute("OwnerId", player.UserId)

-- The shop on the beach: Luck and Speed.
local shop = ws.Map:FindFirstChild("Shop")
check("a shop stands on the beach", shop ~= nil and shop:GetPivot().Position.Z > SHORE and shop:GetPivot().Position.Z < SHORE + Config.World.BeachDepth)
local shopPrompt = shop and shop.Counter:FindFirstChildOfClass("ProximityPrompt")
check("the Buy button takes you to the shop", act("TeleportShop") == true and (h:positionOf(player) - shop:GetPivot().Position).Magnitude < 20, (h:positionOf(player) - shop:GetPivot().Position).Magnitude)
h:fire(PromptService, "PromptTriggered", shopPrompt, player)
h:advance(0.3)
check("the shop's prompt opens its menu", Ui.isOpen("Upgrades"))
eq("base walk speed", player.Character.Humanoid.WalkSpeed, Config.Speed.Base)
check("buy Speed", act("BuySpeed") == true and d.speedLevel == 1)
eq("walk speed goes up", player.Character.Humanoid.WalkSpeed, Config.Speed.Base + Config.Speed.PerLevel)
check("client sees the new speed", State.data.walkSpeed == Config.Speed.Base + Config.Speed.PerLevel)
local luckWas = d.luckLevel
check("buy Luck at the shop", act("BuyLuck", 1) == true and d.luckLevel == luckWas + 1)
Ui.close("Upgrades")
noErrors(h, "shops")

----------------------------------------------------------------------------
-- 8c. Super Split and Poseidon's Wrath
----------------------------------------------------------------------------
local function overlayText()
	local texts = {}
	for _, l in player.PlayerGui.Overlay:GetDescendants() do
		if l:IsA("TextLabel") then
			table.insert(texts, l.Text)
		end
	end
	return table.concat(texts, " | ")
end
local function countParts(folder, name)
	local n = 0
	for _, c in folder:GetChildren() do
		if c.Name == name then
			n += 1
		end
	end
	return n
end
local function runCast(key)
	local cast = Config.CastByKey[key]
	player:SetAttribute("ForceCast", key)
	h:advance(1.5)
	startSplit(20)
	local run = Ocean.active
	check(key .. ": split started with that cast", run ~= nil and run.cast == key and run.luck == cast.luck)
	eq(key .. ": cutscene length", run.anim, cast.seconds)
	h:advance(cast.seconds * 0.2)
	check(key .. ": its name fills the screen", overlayText():find(cast.name, 1, true) ~= nil, overlayText())
	check(key .. ": lightning comes down", countParts(ws.Poses, "Lightning") > 0 or countParts(ws.Poses, "LightningFlash") > 0)
	check(key .. ": sea not torn yet", ws.LocalOcean.UpperL1.Transparency == 1)
	local rootJoint2 = player.Character:FindFirstChild("Root", true)
	local top = 0
	for _ = 1, 40 do
		if (State.serverNow() - run.t0) / cast.seconds >= cast.slam - 0.02 then
			break
		end
		h:advance(0.1)
		top = math.max(top, rootJoint2.C0.Position.Y)
	end
	h:advance(cast.seconds * 0.08)
	check(key .. ": luck banner after the slam", overlayText():find(cast.luck .. "x LUCK!", 1, true) ~= nil, overlayText())
	check(key .. ": shockwave", countParts(ws.Poses, "Shockwave") > 0)
	waitOutCutscene()
	check(key .. ": walls rise higher than a basic split", ws.LocalOcean.UpperL1.Size.Y + ws.LocalOcean.WallL1.Size.Y > Config.Ocean.WallTopY + 20, ws.LocalOcean.UpperL1.Size.Y + ws.LocalOcean.WallL1.Size.Y)
	local statusText = ""
	for _, l in player.PlayerGui.Hud.Status:GetDescendants() do
		if l:IsA("TextLabel") then
			statusText ..= l.Text
		end
	end
	check(key .. ": luck shown while the sea is open", statusText:find(cast.luck .. "x LUCK", 1, true) ~= nil, statusText)
	noErrors(h, key .. " cast")
	Ocean.close()
	h:advance(0.5)
	return top, #run.eggs
end
local superTop, superEggs = runCast("Super")
local poseidonTop, poseidonEggs = runCast("Poseidon")
check("Super Split leaps high", superTop > 4, superTop)
check("Poseidon's Wrath flies far higher", poseidonTop > 18, poseidonTop)
check("extra luck reveals more eggs", poseidonEggs >= superEggs and superEggs > 2, superEggs .. " / " .. poseidonEggs)
player:SetAttribute("ForceCast", "Split")

----------------------------------------------------------------------------
-- 9. A full server, and the leaderboards
----------------------------------------------------------------------------
local others = {}
for i = 2, 6 do
	local p = h:addPlayer(i, "Guest" .. i)
	h:advance(0.2)
	h:spawnCharacter(p, Vector3.new(i * 5, 3, SHORE + 30))
	h:advance(0.2)
	others[i] = p
end
noErrors(h, "six players joining")
check("second player has their own base", Pens.get(others[2]) ~= nil and Pens.get(others[2]) ~= pen)
check("fifth player has a base", Pens.get(others[5]) ~= nil)
check("a sixth player has no base but still has data", Pens.get(others[6]) == nil and Data.get(others[6]) ~= nil)

Data.get(others[2]).strength = 5
w.serverModule("Leaderboards").refresh()
h:advance(0.2)
local function boardRows(key)
	local face = ws.Map:FindFirstChild("Leaderboard" .. key).Face
	local rows = {}
	for _, frame in face:FindFirstChildOfClass("SurfaceGui"):GetChildren() do
		local labels = {}
		for _, l in frame:GetChildren() do
			if l:IsA("TextLabel") then
				table.insert(labels, l.Text)
			end
		end
		table.insert(rows, table.concat(labels, " "))
	end
	return table.concat(rows, "\n")
end
check("strength board ranks the stronger player first", boardRows("Strength"):find("1 Tester") ~= nil, boardRows("Strength"))
check("strength board lists the second player", boardRows("Strength"):find("2 Guest2") ~= nil)
check("cash board lists the player", boardRows("Cash"):find("Tester") ~= nil)
check("eggs board lists the player", boardRows("Eggs"):find("Tester") ~= nil)
check("boards saved to the global store", count(h.orderedStores) == 3)
noErrors(h, "leaderboards")

h:removePlayer(others[3])
h:advance(0.3)
local freed = 0
for _, m in ws.Pens:GetChildren() do
	if m:GetAttribute("OwnerId") == 0 or m:GetAttribute("OwnerId") == nil then
		freed += 1
	end
end
eq("leaving frees the base", freed, 1)
noErrors(h, "player leaving")

----------------------------------------------------------------------------
-- 10. Saving and coming back later (carried eggs are kept)
----------------------------------------------------------------------------
h:advance(1)
startSplit(-100)
sp = Ocean.active
waitOutCutscene()
eggSpots = Ocean.eggPositions()
table.sort(eggSpots, function(a, b)
	return math.abs(a.X - sp.cx) < math.abs(b.X - sp.cx)
end)
grabAt(eggSpots[1])
h:moveTo(player, Vector3.new(sp.cx, 3, SHORE + 8))
h:advance(0.4)
eq("the egg went into the inventory before leaving", Ocean.carried, 0)
local eggsOwned = #d.eggs + count(d.pen)

local saved = {
	luckLevel = d.luckLevel,
	weightTier = d.weightTier,
	baseSlots = d.baseSlots,
	strength = d.strength,
	hatched = d.stats.hatched,
}
local stores = h.dataStores
h:stopClient()
h:removePlayer(player)
h:shutdown()
noErrors(h, "save on leave + shutdown")
check("save written", stores.SplitTheOcean_v1 ~= nil and stores.SplitTheOcean_v1.p_1 ~= nil)

local w2 = boot({ dataStores = stores, orderedStores = h.orderedStores, epoch = h.epoch + h.clock + 2 * 3600 })
local h2 = w2.h
local player2 = w2.join(1, "Tester")
w2.startClient(player2)
local State2 = w2.clientModule("State")
local offline = false
State2.effect:Connect(function(kind)
	if kind == "offline" then
		offline = true
	end
end)
h2:advance(6)
noErrors(h2, "rejoin")
local d2 = w2.serverModule("Data").get(player2)
eq("luck level restored", d2.luckLevel, saved.luckLevel)
eq("weight restored", d2.weightTier, saved.weightTier)
eq("base size restored", d2.baseSlots, saved.baseSlots)
eq("strength restored", d2.strength, saved.strength)
eq("stats restored", d2.stats.hatched, saved.hatched)
eq("the egg carried to safety was kept", #d2.eggs + count(d2.pen), eggsOwned)
check("offline earnings granted", offline)
check("passes are per-session until real IDs exist", State2.data.passes.DoubleCash == nil)
eq("pen rebuilt from save", #w2.serverModule("Pens").get(player2).contents:GetChildren(), count(d2.pen))
w2.serverModule("Leaderboards").refresh()
check("global board remembers players who aren't here", (function()
	local face = h2.workspace.Map.LeaderboardStrength.Face
	for _, l in face:GetDescendants() do
		if l:IsA("TextLabel") and l.Text == "User2" then
			return true
		end
	end
	return false
end)())
local Ui2 = w2.clientModule("ui/Ui")
for _, name in WINDOWS do
	Ui2.open(name)
	h2:advance(1.2, 0.2)
	Ui2.close(name)
end
noErrors(h2, "windows after rejoin")

----------------------------------------------------------------------------
-- 11. DataStores unavailable: the game still runs, without saving
----------------------------------------------------------------------------
local w3 = boot({ dataStoreFails = true })
local player3 = w3.join(7, "Offline")
w3.startClient(player3)
w3.h:advance(1)
noErrors(w3.h, "boot without DataStores")
check("playable without DataStores", w3.serverModule("Data").get(player3) ~= nil)
check("client told saving is off", w3.clientModule("State").data.saving == false)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
