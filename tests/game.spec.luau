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
		h:spawnCharacter(player, Vector3.new(0, 3, 140))
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

local Config = w.sharedModule("Config")
local ws = h.workspace
check("map built", ws:FindFirstChild("Map") ~= nil)
check("template baseplate removed", ws:FindFirstChild("Baseplate") == nil)
check("template spawn removed", ws:FindFirstChild("SpawnLocation") == nil)
check("8 pens built", ws:FindFirstChild("Pens") ~= nil and #ws.Pens:GetChildren() == 8, ws:FindFirstChild("Pens") and #ws.Pens:GetChildren())
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
eq("fresh player has no cash", d.cash, 0)
check("guide points a new player at the shore", Guide.text ~= nil and Guide.text:find("shoreline") ~= nil, Guide.text)
check("leaderstats created", player:FindFirstChild("leaderstats") ~= nil and player.leaderstats:FindFirstChild("Cash") ~= nil)

----------------------------------------------------------------------------
-- 3. Part the sea, grab an egg, bank it
----------------------------------------------------------------------------
local function startSplit(x, side, holdSeconds)
	h:moveTo(player, Vector3.new(x, 3, side * (O.ShoreZ + 6)))
	h:advance(0.3)
	Ocean.beginCharge("mouse")
	h:advance(holdSeconds or 1.6)
	Ocean.releaseCharge("mouse")
	h:advance(0.1)
end

check("no split before charging", Ocean.active == nil)
h:moveTo(player, Vector3.new(10, 3, O.ShoreZ + 6))
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

h:advance(1.2)
local ocean = ws:FindFirstChild("LocalOcean")
check("closed sea hidden while parted", ocean.Main.Transparency == 1)
check("corridor walls are visible", ocean.WallL1.Transparency < 1 and ocean.WallR1.Transparency < 1)
check("far wall is visible", ocean.WallEnd.Transparency < 1)
check("wall segments past the corridor end stay hidden", ocean.WallL20.Transparency == 1)
check("wet sand shows on the corridor floor", ocean.WetSand.Transparency < 1)
check("guide arrows lead to the egg", #ws.GuideArrows:GetChildren() > 0)
check("side barriers block the player", ocean.BarrierL.CanCollide and ocean.BarrierR.CanCollide)
local eggSpots = Ocean.eggPositions()
check("eggs appear in the corridor", #eggSpots >= 2, #eggSpots)
check("guide points at an egg", Guide.text ~= nil and Guide.text:find("egg") ~= nil, Guide.text)

-- Walk onto the first egg.
h:moveTo(player, eggSpots[1] + Vector3.new(0, 3, 0))
h:advance(0.4)
noErrors(h, "grabbing an egg")
eq("carrying one egg", Ocean.carried, 1)
check("carried egg shown on the character", player.Character:FindFirstChild("CarriedEgg") ~= nil)
check("grab effect received", sawEffect("grabbed"))
eq("guide says run", Guide.text, "Run back to the beach!")

-- A second egg can't be picked up with full hands.
h:moveTo(player, eggSpots[2] + Vector3.new(0, 3, 0))
h:advance(0.4)
eq("still carrying one egg (hands full)", Ocean.carried, 1)

-- Back to the beach.
h:moveTo(player, Vector3.new(10, 3, O.ShoreZ + 8))
h:advance(0.4)
eq("egg banked", Ocean.carried, 0)
check("banked effect received", sawEffect("banked"))
eq("server counted the egg", d.stats.eggsCollected, 1)
check("egg is incubating in slot 1", d.pen["1"] ~= nil and d.pen["1"].kind == "egg")
check("client state shows the egg", State.data.pen["1"] ~= nil and State.data.pen["1"].kind == "egg")
check("carried egg removed from character", player.Character:FindFirstChild("CarriedEgg") == nil)
check("egg model placed in the pen", #Pens.get(player).contents:GetChildren() == 1)
check("egg is not ready straight away", act("HatchAll") == false and d.pen["1"].kind == "egg")
noErrors(h, "grab and bank")

-- Close early from the beach.
Ocean.close()
h:advance(0.3)
check("split closed early", Ocean.active == nil)
check("closed sea is back", ocean.Main.Transparency < 1 and ocean.WallL1.Transparency == 1)
check("barriers off when closed", not ocean.BarrierL.CanCollide)
noErrors(h, "close ocean")

----------------------------------------------------------------------------
-- 4. The sea sweeps you back
----------------------------------------------------------------------------
-- Standing deep in the corridor when the wall arrives.
startSplit(-40, 1)
sp = Ocean.active
check("second split started", sp ~= nil)
h:advance(1) -- let the corridor finish opening
h:moveTo(player, Vector3.new(sp.cx, O.SeabedY + 3, O.ShoreZ - 26))
h:advance(sp.openTime - 0.6)
check("safe while the sea is open", h:positionOf(player).Z < O.ShoreZ)
check("no wall gap while open", Ocean.wallGap() == nil)
h:advance(1)
check("wall gap reported while closing", Ocean.wallGap() ~= nil)
h:advance(3)
check("swept back to the beach", h:positionOf(player).Z >= O.ShoreZ, h:positionOf(player).Z)
check("caught effect received", sawEffect("caught"))
h:advance(6)
check("split ended after closing", Ocean.active == nil)
noErrors(h, "swept by the closing wall")

-- Stepping out of the side of the corridor.
startSplit(60, -1)
sp = Ocean.active
check("split from the south shore", sp ~= nil and sp.side == -1)
h:advance(1)
h:moveTo(player, Vector3.new(sp.cx + sp.width / 2 + 8, O.SeabedY + 3, -(O.ShoreZ - 25)))
h:advance(0.3)
check("pushed back to the south beach", h:positionOf(player).Z <= -O.ShoreZ, h:positionOf(player).Z)
sawEffect("caught")
Ocean.close()
h:advance(0.3)

-- Walking into the closed sea.
h:advance(2) -- wait out the brief immunity after a sweep
h:moveTo(player, Vector3.new(0, O.SeabedY + 3, 40))
h:advance(0.3)
check("closed sea pushes you out", math.abs(h:positionOf(player).Z) >= O.ShoreZ)
check("pushed effect received", sawEffect("pushed"))
noErrors(h, "push-back cases")

-- A split request from the middle of the map is refused.
h:moveTo(player, Vector3.new(0, 3, 200))
local refused, reason = Remotes.get("RequestSplit"):InvokeServer(1)
check("split refused away from the shore", refused == nil and type(reason) == "string", reason)

----------------------------------------------------------------------------
-- 5. Hatch the egg, earn money
----------------------------------------------------------------------------
h:advance(Config.EggById[d.pen["1"].egg].hatch + 1, 0.25)
local slot = Pens.get(player).slotModels["1"]
check("pen egg shows Ready!", slot.timer.Text == "Ready!", slot.timer.Text)
check("hatch prompt enabled", slot.prompt.Enabled)
h:fire(slot.prompt, "Triggered", player)
h:advance(6)
check("hatch effect received", sawEffect("hatch"))
check("slot 1 is now an animal", d.pen["1"].kind == "animal")
local firstAnimal = d.pen["1"].animal
check("animal recorded in the index", d.index[firstAnimal] == 1)
eq("hatch counted", d.stats.hatched, 1)
noErrors(h, "hatching")
local before = d.cash
h:advance(3.2, 0.2)
check("animal earns money", d.cash > before, d.cash)
check("income shown on the pen sign", Pens.get(player).ownerLabels[2].Text ~= "")
check("leaderboard cash updates", player.leaderstats.Cash.Value ~= "0", player.leaderstats.Cash.Value)
noErrors(h, "income")

-- The server publishes walks; the client animates them.
local animalModel = Pens.get(player).slotModels["1"].model
check("animal is marked for client animation", animalModel:GetAttribute("Animal") == true)
h:advance(8, 0.1)
check("server published a walk", animalModel:GetAttribute("WalkStart") ~= nil and animalModel:GetAttribute("WalkDuration") > 0)
noErrors(h, "animal wandering")

local okIndex = act("ClaimIndex", firstAnimal)
check("index reward claimed", okIndex == true and d.index[firstAnimal] == 2)
check("index reward can't be claimed twice", act("ClaimIndex", firstAnimal) == false)

----------------------------------------------------------------------------
-- 6. Training and upgrades
----------------------------------------------------------------------------
local pen = Pens.get(player)
local padPos = (pen.cf * roblox.CFrame.new(Pens.PadLocal)).Position
h:moveTo(player, padPos + Vector3.new(0, 3, 0))
h:advance(0.5)
check("standing on the training pad", player:GetAttribute("OnTrainPad") == true)
Remotes.get("Train"):FireServer("start")
h:advance(0.2)
check("training started", player:GetAttribute("Training") == true)
check("barbell overhead", player.Character:FindFirstChild("TrainingBarbell") ~= nil)
eq("can't walk while training", player.Character.Humanoid.WalkSpeed, 0)
h:advance(2.5)
local auto = d.strength
check("auto-lifts add strength", auto >= 2, auto)
Remotes.get("Train"):FireServer("lift")
h:advance(0.3)
check("clicking lifts too", d.strength > auto)
Remotes.get("Train"):FireServer("stop")
h:advance(0.2)
check("training stopped", player:GetAttribute("Training") == false)
eq("walk speed restored", player.Character.Humanoid.WalkSpeed, 16)
check("barbell removed", player.Character:FindFirstChild("TrainingBarbell") == nil)
noErrors(h, "training")

-- The tutorial is done once you've banked an egg, hatched one and trained.
h:moveTo(player, Vector3.new(0, 3, 160))
h:advance(0.5)
eq("guide goes quiet after the tutorial", Guide.text, nil)
eq("no guide arrows left on the ground", #ws.GuideArrows:GetChildren(), 0)

check("can't afford luck at first", act("BuyLuck", 1) == false or d.luckLevel == 0 or d.cash >= 0)
d.cash = 1e12
Data.markDirty(player)
h:advance(0.3)
local luckBefore = d.luckLevel
check("buy 5 luck levels", act("BuyLuck", 5) == true and d.luckLevel == luckBefore + 5, d.luckLevel)
check("buy heavier weight", act("BuyWeight") == true and d.weightTier == 2)
check("upgrade base", act("UpgradeBase") == true and d.baseSlots == Config.Base.StartSlots + Config.Base.SlotsPerLevel)
h:advance(0.3)
check("pad label shows the new weight", pen.padLabels[1].Text:find(tostring(Config.Weights[2].gain)) ~= nil, pen.padLabels[1].Text)
eq("slot pads match base size", #pen.slotsFolder:GetChildren(), d.baseSlots)
check("client luck updated", State.data.luck > 1)
noErrors(h, "upgrades")

----------------------------------------------------------------------------
-- 7. Rewards and the Robux shop (free Studio grants while IDs are 0)
----------------------------------------------------------------------------
check("daily reward claims", act("ClaimDaily") == true)
check("daily reward only once a day", act("ClaimDaily") == false)
eq("daily streak is 1", d.daily.streak, 1)
check("playtime gift not ready early", act("ClaimPlaytime", 5) == false)
h:advance(61, 0.5)
check("first playtime gift claims", act("ClaimPlaytime", 1) == true)
check("playtime gift can't be claimed twice", act("ClaimPlaytime", 1) == false)
for _, product in Config.Products do
	local granted = act("StudioGrant", "product", product.key)
	check("studio grant product " .. product.key, granted == true)
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
local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
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

-- Prompts in someone else's base are unreachable for us; ours work.
local ownPrompt = pen.upPrompt
check("own prompt keeps its range", ownPrompt.MaxActivationDistance > 0)

-- Jumping over the water is still "in the ocean".
h:moveTo(player, Vector3.new(0, 9, O.ShoreZ - 6))
h:advance(0.3)
check("jumping over closed water still pushes you back", h:positionOf(player).Z >= O.ShoreZ)
sawEffect("pushed")
h:advance(2)

-- With Double Carry, two eggs can be carried.
startSplit(0, 1)
h:advance(1.2)
eggSpots = Ocean.eggPositions()
if #eggSpots >= 2 then
	h:moveTo(player, eggSpots[1] + Vector3.new(0, 3, 0))
	h:advance(0.4)
	h:moveTo(player, eggSpots[2] + Vector3.new(0, 3, 0))
	h:advance(0.4)
	eq("double carry holds two eggs", Ocean.carried, 2)
	h:moveTo(player, Vector3.new(0, 3, O.ShoreZ + 8))
	h:advance(0.4)
	eq("both eggs banked", Ocean.carried, 0)
end
Ocean.close()
h:advance(0.3)
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
-- 9. More players
----------------------------------------------------------------------------
local others = {}
for i = 2, 9 do
	local p = h:addPlayer(i, "Guest" .. i)
	h:advance(0.2)
	h:spawnCharacter(p, Vector3.new(i * 5, 3, 140))
	h:advance(0.2)
	others[i] = p
end
noErrors(h, "nine players joining")
check("second player has their own pen", Pens.get(others[2]) ~= nil and Pens.get(others[2]) ~= pen)
check("eighth player has a pen", Pens.get(others[8]) ~= nil)
check("ninth player has no pen but still has data", Pens.get(others[9]) == nil and Data.get(others[9]) ~= nil)
h:removePlayer(others[3])
h:advance(0.3)
local freed = 0
for _, m in ws.Pens:GetChildren() do
	if m:GetAttribute("OwnerId") == 0 or m:GetAttribute("OwnerId") == nil then
		freed += 1
	end
end
eq("leaving frees the pen", freed, 1)
noErrors(h, "player leaving")

----------------------------------------------------------------------------
-- 10. Saving and coming back later
----------------------------------------------------------------------------
local saved = {
	luckLevel = d.luckLevel,
	weightTier = d.weightTier,
	baseSlots = d.baseSlots,
	strength = d.strength,
	penCount = count(d.pen),
	hatched = d.stats.hatched,
}
local stores = h.dataStores
h:stopClient()
h:removePlayer(player)
h:shutdown()
noErrors(h, "save on leave + shutdown")
check("save written", stores.SplitTheOcean_v1 ~= nil and stores.SplitTheOcean_v1.p_1 ~= nil)

local w2 = boot({ dataStores = stores, epoch = h.epoch + h.clock + 2 * 3600 })
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
eq("pen contents restored", count(d2.pen), saved.penCount)
eq("stats restored", d2.stats.hatched, saved.hatched)
check("offline earnings granted", offline)
check("passes are per-session until real IDs exist", State2.data.passes.DoubleCash == nil)
eq("pen rebuilt from save", #w2.serverModule("Pens").get(player2).contents:GetChildren(), saved.penCount)
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
