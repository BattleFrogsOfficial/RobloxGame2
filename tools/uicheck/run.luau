--!nocheck
-- UI layout check. Builds the real client UI under the Roblox emulator at several viewports and scenarios,
-- lays it out, runs the checks from docs/UI_STYLE_GUIDE.md section 9, renders SVG previews and writes a report.
--   lune run tools/uicheck/run.luau            -> build/ui-preview/*.svg + report.json; exit 1 on errors
--   lune run tools/uicheck/run.luau --quiet    -> no per-record output
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")
local R = require("./roblox")

local ROOT = string.gsub(process.cwd, "/$", "")
local OUT = ROOT .. "/build/ui-preview"
if not fs.isDir(ROOT .. "/build") then
	fs.writeDir(ROOT .. "/build")
end
if fs.isDir(OUT) then
	fs.removeDir(OUT)
end
fs.writeDir(OUT)

local Enum = R.Enum
local Vector2 = R.Types.Vector2

-- Mount the source tree.
local Shared = R.MountTree(ROOT .. "/src/shared", R.ReplicatedStorage, "Shared")
local clientFolder = R.Instance.new("Folder")
clientFolder.Name = "Client"
R.MountTree(ROOT .. "/src/client/UI", clientFolder, "UI")
-- The cutscene's screen pieces (Overlay = odds counter / Skip / fallback text, TestPanel) use the UI kit.
-- (only those two children are required; the controller init module never runs here)
local cutsceneFolder = R.MountTree(ROOT .. "/src/client/Cutscene", clientFolder, "Cutscene")
clientFolder.Parent = R.PlayerGui -- anywhere; script.Parent chains stay inside UI

local Remotes = R.Require(Shared:FindFirstChild("Remotes"))
local remotesFolder = R.MakeRemotes(Remotes.Events, Remotes.Functions)
local remoteByName = {}
for _, c in remotesFolder:GetChildren() do
	remoteByName[c.Name] = c
end

local DogCatalog = R.Require(Shared.Util.DogCatalog)
local Zones = R.Require(Shared.Config.Zones)
local Rarities = R.Require(Shared.Config.Rarities)

-- ------------------------------------------------------------------------------------------ fake state
local function fakeState()
	local now = os.time()
	local dogs = {}
	local all = DogCatalog.All()
	local book = {}
	for i = 1, 40 do
		local def = all[((i * 37) % #all) + 1]
		local variant = if i % 11 == 0 then "Gold" elseif i % 17 == 0 then "Rainbow" else nil
		table.insert(dogs, { Uid = "dog" .. i, DogId = def.Id, Variant = variant, BornAt = now - i * 60, GrownAt = now + (if i % 3 == 0 then 600 else -10), Displayed = i <= 12, Held = i > 36 })
		book[def.Id] = { Variants = if variant then { [variant] = true } else {} }
	end
	-- Own most of the Backyard book so milestones light up
	for i, def in DogCatalog.ZoneDogs(Zones[1].Id) do
		if i % 4 ~= 0 then
			book[def.Id] = book[def.Id] or { Variants = {} }
		end
	end
	return {
		Cash = 1234567,
		Bones = 420,
		ThrowPower = 385,
		Balls = { Tennis = 1, Rubber = 3 }, -- PlayerState.Balls = {[id] = count}; Tennis is unlimited
		EquippedBall = "Rubber",
		SlotCount = 40,
		Dogs = dogs,
		Book = book,
		BookRewards = { Backyard = { ["25"] = true } },
		Boosts = { StickyBall = now + 700, LuckyBiscuit = now + 65 },
		Whistles = 2,
		TreatPockets = 1,
		LuckyStreak = 1,
		LastDailyWalk = 0,
		TutorialDone = true,
		TrainingLevel = 3,
		PermanentLuck = 0.04,
		Cosmetics = { RedCollar = true },
	}
end

-- ------------------------------------------------------------------------------------------ build
local VIEWPORTS = {
	{ name = "phone", size = Vector2.new(667, 375), touch = true },
	{ name = "phone-large", size = Vector2.new(844, 390), touch = true },
	{ name = "tablet", size = Vector2.new(1024, 768), touch = true },
	{ name = "laptop", size = Vector2.new(1366, 768), touch = false },
	{ name = "desktop", size = Vector2.new(1920, 1080), touch = false },
}

-- Platform / queue attributes the server sets on the LocalPlayer (ThrowService). Every scenario starts
-- off the platform; throw scenarios set them.
local function setPlatform(onPlatform, queuePos)
	R.LocalPlayer:SetAttribute("OnPlatform", onPlatform)
	R.LocalPlayer:SetAttribute("ThrowQueuePos", queuePos)
end
local Meter = R.Require(Shared.Util.Meter)
-- Charging with the meter at `frac` (0..1) on the way up: start time chosen so Meter.Position == frac.
local function chargeAt(ui, frac)
	setPlatform(true, 1)
	local period = Meter.Period(false)
	ui.HUD:SetCharging(true, os.clock() - frac * period / 2, false)
end

-- Cutscene overlay scenarios: the HUD is hidden while the cutscene plays (as in game).
local OddsCounter = R.Require(Shared.Cutscene.OddsCounter)
local CutsceneConfig = R.Require(Shared.Config.Cutscene)
local function overlay(ui)
	ui.HUD.Root.Visible = false
	local Overlay = R.Require(cutsceneFolder:FindFirstChild("Overlay"))
	local o = Overlay.new(ui.Root, ui.IsTouch == true)
	o:ShowCounter()
	return o
end
local function longestName(zoneId, rarity)
	local best = nil
	for _, d in DogCatalog.ZoneTierList(zoneId, rarity) do
		if not best or #d.Name > #best.Name then
			best = d
		end
	end
	return best or DogCatalog.All()[1]
end
-- counter mid-count at value v (colour from the real thresholds of a Backyard Mythic count)
local function midCount(v, skip)
	return function(ui)
		local o = overlay(ui)
		local th = OddsCounter.Thresholds("Backyard", 0)
		o:SetCount(v, OddsCounter.TierAt(v, th, "Mythic"), false)
		if skip then
			o:SetSkip(true, function() end)
		end
	end
end
local function testPanel(open)
	return function(ui)
		local TestPanel = R.Require(cutsceneFolder:FindFirstChild("TestPanel"))
		ui.CutsceneTest = TestPanel.new({ Parent = ui.Root, IsTouch = ui.IsTouch == true, Router = ui.Router, OnPlay = function() end, OnLoop = function() end })
		if open then
			ui.Router.Open("CutsceneTest")
		end
	end
end

local SCENARIOS = {
	{ name = "hud", setup = function(ui) end },
	{ name = "throw-off-platform", setup = function(ui)
		setPlatform(false, 0)
	end },
	{ name = "throw-idle", setup = function(ui)
		setPlatform(true, 1)
	end },
	{ name = "throw-waiting", setup = function(ui)
		setPlatform(true, 3)
	end },
	{ name = "throw-charge-0", setup = function(ui)
		chargeAt(ui, 0)
	end },
	{ name = "throw-charge-50", setup = function(ui)
		chargeAt(ui, 0.5)
	end },
	{ name = "throw-charge-100", setup = function(ui)
		chargeAt(ui, 1)
	end },
	{ name = "throw-tennis", setup = function(ui)
		local s = fakeState()
		s.EquippedBall = "Tennis"
		ui.State.Set(s)
		chargeAt(ui, 0.8)
	end },
	{ name = "hud-events", setup = function(ui)
		ui.State.SetEvent("Squirrel", { Kind = "Squirrel", Active = true, EndsAt = os.time() + 30 })
		ui.HUD.Toasts:Show("Bought Rubber Ball", "check", "Grass")
		ui.HUD.Toasts:Show("Tester caught a LEGENDARY Husky!", "star", "Purple")
		ui.HUD:Broadcast({ Kind = "Catch", Text = "Tester caught a RARE Beagle!", Rarity = "Rare", Global = false })
		chargeAt(ui, 0.7)
		ui.Spectator:Show("Rival", { DogId = DogCatalog.All()[5].Id, Rarity = "Epic", Variant = "Gold", Caught = false })
	end },
	{ name = "shop", setup = function(ui)
		ui.Router.Open("Shop", "Balls")
	end },
	{ name = "shop-robux", setup = function(ui)
		ui.Router.Open("Shop", "Robux")
	end },
	{ name = "dogs", setup = function(ui)
		ui.Router.Open("Dogs")
	end },
	{ name = "book", setup = function(ui)
		ui.Router.Open("Book", Zones[1].Id)
	end },
	{ name = "odds", setup = function(ui)
		ui.Router.Open("Odds")
	end },
	{ name = "settings", setup = function(ui)
		ui.Router.Open("Settings")
	end },
	{ name = "reveal-caught", setup = function(ui)
		local def = DogCatalog.ZoneTierList(Zones[3].Id, "Legendary")[1] or DogCatalog.All()[1]
		ui:ShowReveal({ ThrowId = "t1", ThrowerUserId = 1, Distance = 412, ZoneId = Zones[3].Id, DogId = def.Id, Rarity = def.Rarity, Variant = "Rainbow", Caught = true, CatchChance = 0.45, WhistleOwned = true, WhistleCount = 2 }, { IsDupe = true })
	end },
	{ name = "cutscene-counter-white", setup = midCount(17) },
	{ name = "cutscene-counter-grey", setup = midCount(73) },
	{ name = "cutscene-counter-green", setup = midCount(101) },
	{ name = "cutscene-counter-blue", setup = midCount(133) },
	{ name = "cutscene-counter-purple", setup = midCount(321) },
	{ name = "cutscene-counter-orange", setup = midCount(777) },
	{ name = "cutscene-counter-skip", setup = midCount(142, true) },
	{ name = "cutscene-stopped-mythic", setup = function(ui)
		local o = overlay(ui)
		local def = longestName("MythicMeadow", "Mythic")
		local target = OddsCounter.Target(def.Zone, "Mythic", 0)
		o:SetCount(target, "Mythic", false)
		o:SetStopped(def.Name, "Mythic", "Rainbow")
		o:SetFlourish(CutsceneConfig.Outcome.FlourishLucky)
	end },
	{ name = "cutscene-stopped-epic-skip", setup = function(ui)
		local o = overlay(ui)
		local def = longestName("SnowyPeaks", "Epic")
		o:SetCount(OddsCounter.Target(def.Zone, "Epic", 0.5), "Epic", false)
		o:SetStopped(def.Name, "Epic", "Gold")
		o:SetFlourish(CutsceneConfig.Outcome.FlourishTreat)
		o:SetSkip(true, function() end)
	end },
	{ name = "cutscene-stopped-common", setup = function(ui)
		local o = overlay(ui)
		local def = longestName("Backyard", "Common")
		o:SetCount(OddsCounter.Target(def.Zone, "Common", 0), "Common", false)
		o:SetStopped(def.Name, "Common", nil)
		o:SetSkip(true, function() end)
	end },
	{ name = "cutscene-fallback", setup = function(ui)
		local o = overlay(ui)
		o:ShowMessage(CutsceneConfig.Fallback.Text)
	end },
	{ name = "cutscene-testmode-hud", setup = testPanel(false) },
	{ name = "cutscene-testpanel", setup = testPanel(true) },
	{ name = "reveal-missed", setup = function(ui)
		local def = DogCatalog.ZoneTierList(Zones[1].Id, "Mythic")[1] or DogCatalog.All()[1]
		ui:ShowReveal({ ThrowId = "t2", ThrowerUserId = 1, Distance = 80, ZoneId = Zones[1].Id, DogId = def.Id, Rarity = def.Rarity, Caught = false, CatchChance = 0.3, WhistleOwned = true, WhistleCount = 1 })
	end },
}

local quiet = table.find(process.args, "--quiet") ~= nil
local report = { errors = {}, warnings = {}, scenarios = {} }

local function addError(scenario, msg)
	table.insert(report.errors, scenario .. ": " .. msg)
end
local function addWarning(scenario, msg)
	table.insert(report.warnings, scenario .. ": " .. msg)
end

local function rectStr(r)
	return string.format("[%d,%d %dx%d]", math.floor(r.x), math.floor(r.y), math.floor(r.w), math.floor(r.h))
end

local function pathOf(inst, stopAt)
	local parts = {}
	local p = inst
	while p and p ~= stopAt do
		table.insert(parts, 1, p.Name)
		p = p.Parent
	end
	return table.concat(parts, "/")
end

-- ------------------------------------------------------------------------------------------ checks
local HUD_REGIONS = { Currencies = true, SideMenu = true, EventBanner = true, Toasts = true, TopRight = true, ThrowCluster = true, Ticker = true }

local function runChecks(name, records, screen, vp, ui)
	local scale = ui.Root:FindFirstChildOfClass("UIScale").Scale
	local touch = vp.touch
	-- 1. Visible elements inside the screen (unless clipped by an ancestor).
	for _, rec in records do
		if rec.visible and rec.rect.w > 0 and rec.rect.h > 0 then
			local inside = R.Intersect(rec.rect, screen)
			local clipped = rec.clip and (rec.clip.w < screen.w or rec.clip.h < screen.h)
			if not clipped then
				if not inside or inside.w < rec.rect.w - 1 or inside.h < rec.rect.h - 1 then
					-- The panel close button hangs over the corner by design; a 12 px tolerance for pills' rings.
					local overflowX = rec.rect.w - (inside and inside.w or 0)
					local overflowY = rec.rect.h - (inside and inside.h or 0)
					if overflowX > 2 or overflowY > 2 then
						addError(name, string.format("off-screen: %s %s (viewport %dx%d)", pathOf(rec.inst, ui.Gui), rectStr(rec.rect), vp.size.X, vp.size.Y))
					end
				end
			end
		end
	end
	-- 2. HUD region overlaps and reserved zones.
	local hud = ui.HUD.Root
	local regions = {}
	for _, rec in records do
		if rec.inst.Parent == hud and rec.visible and HUD_REGIONS[rec.inst.Name] then
			-- Use the union of visible descendants rather than the container frame (containers are generous).
			local union = nil
			for _, r2 in records do
				if r2.visible and r2.inst ~= rec.inst and r2.inst:IsDescendantOf(rec.inst) and r2.rect.w > 0 and r2.rect.h > 0 then
					local isDecor = r2.inst.Name == "px" or r2.inst.Name == "ScrimClick" or r2.inst.Name == "Click"
					if not isDecor and (r2.inst.BackgroundTransparency < 1 or r2.inst:IsA("TextLabel")) then
						if not union then
							union = { x = r2.rect.x, y = r2.rect.y, w = r2.rect.w, h = r2.rect.h }
						else
							local x1, y1 = math.min(union.x, r2.rect.x), math.min(union.y, r2.rect.y)
							local x2, y2 = math.max(union.x + union.w, r2.rect.x + r2.rect.w), math.max(union.y + union.h, r2.rect.y + r2.rect.h)
							union = { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
						end
					end
				end
			end
			if union then
				table.insert(regions, { name = rec.inst.Name, rect = union })
			end
		end
	end
	-- Spectator banner counts as a region too
	for _, rec in records do
		if rec.visible and rec.inst.Name == "SpectatorBanner" then
			table.insert(regions, { name = "SpectatorBanner", rect = rec.rect })
		end
	end
	for i = 1, #regions do
		for j = i + 1, #regions do
			local a, b = regions[i], regions[j]
			local x = R.Intersect(a.rect, b.rect)
			if x and x.w > 2 and x.h > 2 then
				-- Toasts sit under the banner by design and SpectatorBanner shares that slot: only one shows at a time.
				local pair = a.name .. "+" .. b.name
				if pair ~= "Toasts+SpectatorBanner" and pair ~= "SpectatorBanner+Toasts" then
					addError(name, string.format("HUD regions overlap: %s %s and %s %s by %dx%d", a.name, rectStr(a.rect), b.name, rectStr(b.rect), x.w, x.h))
				end
			end
		end
	end
	if touch then
		local left = { x = 0, y = screen.y + screen.h - 180, w = 180, h = 180 }
		local right = { x = screen.w - 200, y = screen.y + screen.h - 200, w = 200, h = 200 }
		for _, reg in regions do
			for zoneName, zone in { thumbstick = left, jump = right } do
				local x = R.Intersect(reg.rect, zone)
				if x and x.w > 2 and x.h > 2 then
					addError(name, string.format("%s %s covers the touch %s zone by %dx%d", reg.name, rectStr(reg.rect), zoneName, x.w, x.h))
				end
			end
		end
	end
	-- 3. Text fit and touch targets.
	local minTarget = if touch then 32 else 24
	for _, rec in records do
		local inst = rec.inst
		if rec.visible and rec.rect.w > 0 then
			if inst:IsA("TextLabel") and (inst.Text or "") ~= "" then
				local w = R.TextWidth(inst.Text, inst.TextSize * rec.scale, inst.Font)
				local lineH = inst.TextSize * rec.scale * 1.2
				if inst.TextWrapped then
					local lines = math.max(1, math.ceil(w / math.max(1, rec.rect.w)))
					if lines * lineH > rec.rect.h + 2 then
						addWarning(name, string.format("wrapped text clipped: %s %q needs %d lines in %dpx", pathOf(inst, ui.Gui), inst.Text, lines, rec.rect.h))
					end
				elseif not inst.TextScaled and w > rec.rect.w + 1 then
					if inst.TextTruncate == Enum.TextTruncate.None then
						addError(name, string.format("text overflow: %s %q %dpx in %dpx", pathOf(inst, ui.Gui), inst.Text, w, rec.rect.w))
					else
						addWarning(name, string.format("text truncated: %s %q %dpx in %dpx", pathOf(inst, ui.Gui), inst.Text, w, rec.rect.w))
					end
				end
				if inst.TextSize * rec.scale < 10 then
					addError(name, string.format("text too small: %s %q %.1fpx", pathOf(inst, ui.Gui), inst.Text, inst.TextSize * rec.scale))
				end
			end
			if inst:IsA("TextButton") and inst.Name ~= "Click" and inst.Name ~= "ScrimClick" and (inst.BackgroundTransparency or 0) < 0.5 then
				local m = math.min(rec.rect.w, rec.rect.h)
				if m < minTarget then
					addError(name, string.format("touch target too small: %s %s (min %d)", pathOf(inst, ui.Gui), rectStr(rec.rect), minTarget))
				end
			end
		end
	end
	-- 4. List containers: children must not overflow a fixed-size parent with a UIListLayout.
	for _, rec in records do
		local inst = rec.inst
		if rec.visible and inst:IsA("GuiObject") and inst:FindFirstChildOfClass("UIListLayout") and inst.AutomaticSize == Enum.AutomaticSize.None and not inst:IsA("ScrollingFrame") then
			for _, r2 in records do
				if r2.visible and r2.inst.Parent == inst and r2.rect.w > 0 then
					local x = R.Intersect(r2.rect, rec.rect)
					local ox = r2.rect.w - (x and x.w or 0)
					local oy = r2.rect.h - (x and x.h or 0)
					if ox > 2 or oy > 2 then
						addError(name, string.format("list overflow: %s %s outside %s %s", pathOf(r2.inst, ui.Gui), rectStr(r2.rect), pathOf(inst, ui.Gui), rectStr(rec.rect)))
					end
				end
			end
		end
	end
	-- 5. Modal frames keep a margin and the header title does not run under the header's right-side label.
	for _, rec in records do
		if rec.visible and rec.inst.Name == "Frame" and rec.inst.Parent and rec.inst.Parent:FindFirstChild("ScrimClick") then
			local m = 8
			if rec.rect.x < screen.x + m or rec.rect.y < screen.y + m or rec.rect.x + rec.rect.w > screen.x + screen.w - m or rec.rect.y + rec.rect.h > screen.y + screen.h - m then
				addError(name, string.format("modal too close to the edge: %s %s", pathOf(rec.inst, ui.Gui), rectStr(rec.rect)))
			end
		end
	end
	return scale
end

-- ------------------------------------------------------------------------------------------ SVG render
local FONT_FAMILY = { FredokaOne = "'Fredoka One', 'Arial Rounded MT Bold', Arial, sans-serif", GothamMedium = "Montserrat, Arial, sans-serif", GothamBold = "Montserrat, Arial, sans-serif", Arcade = "'Press Start 2P', monospace" }

local function hex(c)
	return "#" .. c:ToHex()
end

local function esc(s)
	return (string.gsub(s, "[<>&\"]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;" }))
end

local function renderSVG(records, screen, vp, ui)
	local parts = {}
	local defs = {}
	local gradId = 0
	table.insert(parts, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="Arial">', vp.size.X, vp.size.Y, vp.size.X, vp.size.Y))
	table.insert(parts, '<style>@import url("https://fonts.googleapis.com/css2?family=Fredoka+One&amp;family=Montserrat:wght@500;700&amp;family=Press+Start+2P&amp;display=swap");</style>')
	-- Background: a field-ish gradient so white UI reads like in game, plus the top bar.
	table.insert(parts, string.format('<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8fd3ff"/><stop offset="0.55" stop-color="#bfe8ff"/><stop offset="0.56" stop-color="#6fb860"/><stop offset="1" stop-color="#3f8f3f"/></linearGradient></defs><rect width="%d" height="%d" fill="url(#bg)"/>', vp.size.X, vp.size.Y))
	table.insert(parts, string.format('<rect width="%d" height="%d" fill="#0b0a12" opacity="0.55"/><text x="12" y="%d" fill="#fff" font-size="14">Roblox top bar (%dpx)</text>', vp.size.X, screen.y, math.floor(screen.y * 0.7), screen.y))
	if vp.touch then
		table.insert(parts, string.format('<rect x="0" y="%d" width="180" height="180" fill="none" stroke="#ff00aa" stroke-dasharray="6 4"/><rect x="%d" y="%d" width="200" height="200" fill="none" stroke="#ff00aa" stroke-dasharray="6 4"/>', vp.size.Y - 180, vp.size.X - 200, vp.size.Y - 200))
	end
	local ordered = table.clone(records)
	table.sort(ordered, function(a, b)
		if a.depth ~= b.depth then
			return a.depth < b.depth
		end
		return (a.inst.ZIndex or 1) < (b.inst.ZIndex or 1)
	end)
	-- Render in tree order but respect ZIndex among siblings: a simple global sort by (ZIndex, depth) keeps
	-- modals (ZIndex 50+) above the HUD and children above parents in practice.
	table.sort(ordered, function(a, b)
		local za, zb = a.inst.ZIndex or 1, b.inst.ZIndex or 1
		if za ~= zb then
			return za < zb
		end
		if a.depth ~= b.depth then
			return a.depth < b.depth
		end
		return (a.inst.__raw.seq or 0) < (b.inst.__raw.seq or 0)
	end)
	local clipIds = {}
	local clipCount = 0
	for _, rec in ordered do
		local inst = rec.inst
		if rec.visible and rec.rect.w > 0 and rec.rect.h > 0 then
			local r = rec.rect
			local clipAttr = ""
			if rec.clip and (rec.clip.w < screen.w or rec.clip.h < screen.h) then
				local key = string.format("%d_%d_%d_%d", rec.clip.x, rec.clip.y, rec.clip.w, rec.clip.h)
				if not clipIds[key] then
					clipCount += 1
					clipIds[key] = "c" .. clipCount
					table.insert(defs, string.format('<clipPath id="%s"><rect x="%g" y="%g" width="%g" height="%g"/></clipPath>', clipIds[key], rec.clip.x, rec.clip.y, rec.clip.w, rec.clip.h))
				end
				clipAttr = string.format(' clip-path="url(#%s)"', clipIds[key])
				table.insert(parts, string.format("<g%s>", clipAttr))
			end
			local alpha = 1 - (inst.BackgroundTransparency or 0)
			local corner = inst:FindFirstChildOfClass("UICorner")
			local rx = 0
			if corner then
				rx = math.min(corner.CornerRadius.Offset * rec.scale + corner.CornerRadius.Scale * math.min(r.w, r.h), math.min(r.w, r.h) / 2)
			end
			local fill = hex(inst.BackgroundColor3)
			local grad = inst:FindFirstChildOfClass("UIGradient")
			if grad and alpha > 0 then
				gradId += 1
				local kps = grad.Color.Keypoints
				local stops = {}
				for _, kp in kps do
					table.insert(stops, string.format('<stop offset="%g" stop-color="%s"/>', kp.Time, hex(kp.Value)))
				end
				local rot = grad.Rotation or 0
				local x2, y2 = math.cos(math.rad(rot)), math.sin(math.rad(rot))
				table.insert(defs, string.format('<linearGradient id="g%d" x1="%g" y1="%g" x2="%g" y2="%g">%s</linearGradient>', gradId, 0.5 - x2 / 2, 0.5 - y2 / 2, 0.5 + x2 / 2, 0.5 + y2 / 2, table.concat(stops)))
				fill = string.format("url(#g%d)", gradId)
			end
			local stroke = inst:FindFirstChildOfClass("UIStroke")
			local strokeAttr = ""
			if stroke and stroke.Enabled ~= false and (stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Border or not inst:IsA("TextLabel")) and alpha > 0 then
				strokeAttr = string.format(' stroke="%s" stroke-width="%g" stroke-opacity="%g"', hex(stroke.Color), stroke.Thickness * rec.scale, 1 - (stroke.Transparency or 0))
			end
			local shadow = inst:FindFirstChildOfClass("UIShadow")
			if shadow and alpha > 0 then
				table.insert(parts, string.format('<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="#1b1a26" opacity="0.35"/>', r.x, r.y + 4 * rec.scale, r.w, r.h, rx))
			end
			if alpha > 0 then
				table.insert(parts, string.format('<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" fill-opacity="%g"%s/>', r.x, r.y, r.w, r.h, rx, fill, alpha, strokeAttr))
			end
			if inst:IsA("ImageLabel") and inst.Image ~= "" then
				table.insert(parts, string.format('<rect x="%g" y="%g" width="%g" height="%g" fill="#3a9" opacity="0.7"/>', r.x, r.y, r.w, r.h))
			end
			if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and (inst.Text or "") ~= "" and (inst.TextTransparency or 0) < 1 then
				local size = inst.TextSize * rec.scale
				local fam = FONT_FAMILY[inst.Font and inst.Font.Name or ""] or "Arial"
				local anchor, tx = "start", r.x
				if inst.TextXAlignment == Enum.TextXAlignment.Center then
					anchor, tx = "middle", r.x + r.w / 2
				elseif inst.TextXAlignment == Enum.TextXAlignment.Right then
					anchor, tx = "end", r.x + r.w
				end
				local ty = r.y + r.h / 2 + size * 0.35
				if inst.TextYAlignment == Enum.TextYAlignment.Top then
					ty = r.y + size
				elseif inst.TextYAlignment == Enum.TextYAlignment.Bottom then
					ty = r.y + r.h - size * 0.25
				end
				local tstroke = inst:FindFirstChildOfClass("UIStroke")
				local strokeText = ""
				if tstroke and tstroke.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Border then
					strokeText = string.format(' stroke="%s" stroke-width="%g" paint-order="stroke" stroke-linejoin="round"', hex(tstroke.Color), tstroke.Thickness * 2 * rec.scale)
				end
				local text = inst.Text
				if inst.TextWrapped then
					-- naive wrap
					local lines, line = {}, ""
					for word in string.gmatch(text, "%S+") do
						local tryLine = if line == "" then word else line .. " " .. word
						if R.TextWidth(tryLine, size, inst.Font) > r.w and line ~= "" then
							table.insert(lines, line)
							line = word
						else
							line = tryLine
						end
					end
					table.insert(lines, line)
					local lh = size * 1.2
					local startY = r.y + size + (r.h - lh * #lines) / 2
					for i, l in lines do
						table.insert(parts, string.format('<text x="%g" y="%g" font-size="%g" font-family="%s" fill="%s" text-anchor="%s" opacity="%g"%s>%s</text>', tx, startY + (i - 1) * lh - size * 0.2, size, fam, hex(inst.TextColor3), anchor, 1 - (inst.TextTransparency or 0), strokeText, esc(l)))
					end
				else
					local shown = text
					if inst.TextTruncate ~= Enum.TextTruncate.None then
						while #shown > 1 and R.TextWidth(shown .. "...", size, inst.Font) > r.w and R.TextWidth(text, size, inst.Font) > r.w do
							shown = string.sub(shown, 1, -2)
						end
						if shown ~= text then
							shown ..= "..."
						end
					end
					table.insert(parts, string.format('<text x="%g" y="%g" font-size="%g" font-family="%s" fill="%s" text-anchor="%s" opacity="%g"%s>%s</text>', tx, ty, size, fam, hex(inst.TextColor3), anchor, 1 - (inst.TextTransparency or 0), strokeText, esc(shown)))
				end
			end
			if clipAttr ~= "" then
				table.insert(parts, "</g>")
			end
		end
	end
	table.insert(parts, "</svg>")
	local svg = table.concat(parts, "\n")
	svg = string.gsub(svg, "<defs>", "<defs>" .. table.concat(defs), 1)
	return svg
end

-- ------------------------------------------------------------------------------------------ main
local UIModule = R.Require(clientFolder:FindFirstChild("UI"))
local total = 0
for _, vp in VIEWPORTS do
	for _, sc in SCENARIOS do
		local name = vp.name .. "/" .. sc.name
		total += 1
		R.Camera.ViewportSize = vp.size
		R.Services.UserInputService.TouchEnabled = vp.touch
		R.Services.UserInputService.KeyboardEnabled = not vp.touch
		R.Services.UserInputService.MouseEnabled = not vp.touch
		local ok, err = pcall(function()
			-- The UI module caches State across starts; reset the parts a scenario touches.
			setPlatform(false, 0)
			local ui = UIModule.Start({ Parent = R.PlayerGui, IsTouch = vp.touch, Viewport = vp.size, Remotes = remoteByName })
			ui.State.Server.Events = {}
			ui.State.Set(fakeState())
			ui.Router.Close()
			sc.setup(ui)
			task.wait(0.05)
			task.wait(0.05)
			local records, screen = R.Layout(ui.Gui, vp.size)
			-- Virtual grids lay out from AbsoluteSize: run a second pass so pooled cells exist, then re-layout.
			for _, rec in records do
				if rec.inst.Name == "VirtualGrid" then
					rec.inst.CanvasPosition = Vector2.new(0, 0)
				end
			end
			task.wait(0.05)
			records, screen = R.Layout(ui.Gui, vp.size)
			task.wait(0.05)
			records, screen = R.Layout(ui.Gui, vp.size)
			for _, a in process.args do
				local pat = string.match(a, "^%-%-dump=(.+)$")
				if pat and string.find(name, pat, 1, true) then
					for _, rec in records do
						if rec.visible and rec.rect.w > 0 then
							print(string.format("%s%-60s %s clip=%s", string.rep(" ", rec.depth), pathOf(rec.inst, ui.Gui), rectStr(rec.rect), rec.clip and rectStr(rec.clip) or "-"))
						end
					end
				end
			end
			local scale = runChecks(name, records, screen, vp, ui)
			local svg = renderSVG(records, screen, vp, ui)
			fs.writeFile(string.format("%s/%s--%s.svg", OUT, vp.name, sc.name), svg)
			table.insert(report.scenarios, { name = name, scale = scale, instances = #records })
			if not quiet then
				print(string.format("%-28s scale %.2f  %4d instances", name, scale, #records))
			end
			ui:Destroy()
		end)
		if not ok then
			addError(name, "crash: " .. tostring(err))
			print("CRASH " .. name .. ": " .. tostring(err))
		end
	end
end

-- Emoji / non-ASCII scan over src/ (icons are drawn, never typed).
local function scanEmoji(dir)
	for _, entry in fs.readDir(dir) do
		local full = dir .. "/" .. entry
		if fs.isDir(full) then
			scanEmoji(full)
		elseif string.match(entry, "%.luau?$") then
			local src = fs.readFile(full)
			local lineNo = 0
			for line in string.gmatch(src .. "\n", "(.-)\n") do
				lineNo += 1
				for _, cp in utf8.codes(line) do
					if cp >= 0x1F000 or (cp >= 0x2600 and cp <= 0x27BF) or cp == 0xFE0F or (cp >= 0x2B00 and cp <= 0x2BFF) then
						addError("emoji-scan", string.format("%s:%d contains an emoji/symbol codepoint U+%X", string.sub(full, #ROOT + 2), lineNo, cp))
						break
					end
				end
			end
		end
	end
end
scanEmoji(ROOT .. "/src")

report.warningsFromCode = R.Warnings or {}
fs.writeFile(OUT .. "/report.json", serde.encode("json", report, true))
print(string.format("\n%d scenarios, %d errors, %d warnings -> %s", total, #report.errors, #report.warnings, OUT))
for _, e in report.errors do
	print("ERROR   " .. e)
end
for _, w in report.warnings do
	print("warning " .. w)
end
if #report.errors > 0 then
	process.exit(1)
end
