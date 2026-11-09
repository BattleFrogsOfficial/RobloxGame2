--!nocheck
-- Proves no two HUD elements overlap each other, the edges of the screen, or
-- the areas Roblox's own UI occupies, on desktop, tablet and phone screens.
--
-- Run from the repo root:   lune run tests/layout.spec.luau

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Layout = luau.load(fs.readFile("src/client/ui/Layout.luau"), { debugName = "Layout" })()

local SCREENS = {
	{ "desktop 1920x1080", 1920, 1080, false },
	{ "desktop 1366x768", 1366, 768, false },
	{ "desktop 1280x720", 1280, 720, false },
	{ "desktop 1024x768", 1024, 768, false },
	{ "ultrawide 2560x1080", 2560, 1080, false },
	{ "tablet 1180x820", 1180, 820, true },
	{ "tablet 1024x768", 1024, 768, true },
	{ "phone 932x430", 932, 430, true },
	{ "phone 844x390", 844, 390, true },
	{ "phone 740x360", 740, 360, true },
}

local never = {}
for _, pair in Layout.NeverTogether do
	never[pair[1] .. "|" .. pair[2]] = true
	never[pair[2] .. "|" .. pair[1]] = true
end

local function overlap(a, b)
	return a[1] < b[1] + b[3] - 0.5 and b[1] < a[1] + a[3] - 0.5 and a[2] < b[2] + b[4] - 0.5 and b[2] < a[2] + a[4] - 0.5
end

local passed, failed = 0, 0
local function check(name, cond)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name)
	end
end

for _, screen in SCREENS do
	local label, w, h, touch = screen[1], screen[2], screen[3], screen[4]
	local rects = {}
	for name, element in Layout.Elements do
		if touch or not element.touchOnly then
			rects[name] = Layout.rect(name, w, h, touch)
		end
	end
	local names = {}
	for name in rects do
		table.insert(names, name)
	end
	table.sort(names)

	for _, name in names do
		local r = rects[name]
		check(label .. ": " .. name .. " is on screen", r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= w and r[2] + r[4] <= h)
		for zone, z in Layout.reserved(w, h, touch) do
			check(label .. ": " .. name .. " clear of Roblox's " .. zone, not overlap(r, z))
		end
	end
	for i = 1, #names do
		for j = i + 1, #names do
			local a, b = names[i], names[j]
			if not never[a .. "|" .. b] then
				check(label .. ": " .. a .. " and " .. b .. " don't overlap", not overlap(rects[a], rects[b]))
			end
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("layout overlaps found")
end
