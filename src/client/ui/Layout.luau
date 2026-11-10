-- Where every HUD element sits. Kept as plain data so a test
-- (tests/layout.spec.luau) can prove nothing overlaps on any screen size,
-- including the areas Roblox's own UI uses.
--
-- All numbers are in "design pixels": the HUD is drawn on a 1280x720 canvas
-- and scaled to the screen (see Layout.scale), so a rect here is the same
-- fraction of the screen everywhere.

local Layout = {}

-- anchor: point of the screen (0..1) the element hangs from
-- pivot:  point of the element (0..1) placed at anchor + offset
-- touch:  overrides for phones/tablets (their corners hold the thumbstick
--         and jump button instead of the player list)
Layout.Elements = {
	Build = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 0 }, size = { 200, 10 } },
	TopBar = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 10 }, size = { 546, 56 } },
	-- Luck zones and your depth; takes the top bar's place while a sea is open.
	ZoneBar = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 10 }, size = { 720, 64 }, touch = { size = { 600, 64 } } },
	Status = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 80 }, size = { 480, 84 } },
	Objective = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 170 }, size = { 680, 30 }, touch = { size = { 560, 30 } } },
	Toasts = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 204 }, size = { 680, 52 } },

	-- Left column.
	Menu = { anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 16, 112 }, size = { 190, 90 }, touch = { offset = { 16, 120 }, size = { 186, 88 } } },
	Stats = { anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 16, 214 }, size = { 240, 144 }, touch = { offset = { 16, 216 }, size = { 230, 108 } } },
	Feed = { anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 16, 364 }, size = { 240, 80 }, touch = { offset = { 210, 120 }, size = { 120, 76 } } },

	-- Right column: round Starter Pack promo, a pass banner, then the tiles.
	Promo = { anchor = { 1, 0 }, pivot = { 1, 0 }, offset = { -16, 64 }, size = { 190, 150 }, touch = { size = { 150, 104 } } },
	Promo2 = { anchor = { 1, 0 }, pivot = { 1, 0 }, offset = { -16, 222 }, size = { 190, 58 }, desktopOnly = true },
	RightGrid = { anchor = { 1, 0 }, pivot = { 1, 0 }, offset = { -16, 292 }, size = { 190, 190 }, touch = { offset = { -16, 176 } } },

	Carry = { anchor = { 0.5, 1 }, pivot = { 0.5, 1 }, offset = { 0, -176 }, size = { 320, 60 } },
	-- Shown while you pick a spot for an egg in your plot.
	Place = { anchor = { 0.5, 1 }, pivot = { 0.5, 1 }, offset = { 0, -176 }, size = { 460, 60 } },
	Train = { anchor = { 0.5, 1 }, pivot = { 0.5, 1 }, offset = { 0, -244 }, size = { 420, 40 } },
	Charge = {
		anchor = { 0.5, 0.5 }, pivot = { 0, 0.5 }, offset = { 120, 26 }, size = { 200, 250 },
		-- On touch: left of the character, clear of the HOLD button and thumbstick.
		touch = { pivot = { 1, 0.5 }, offset = { -90, 26 }, size = { 150, 250 } },
	},
	Hold = { anchor = { 1, 1 }, pivot = { 1, 1 }, offset = { -300, -170 }, size = { 170, 170 }, touchOnly = true },
}

-- Pairs that can never be on screen together, so they may share space:
-- the charge meter and HOLD button only show while you can part the sea,
-- which is never while a sea is open, while carrying an egg, or while
-- training (the pad is by your base, not on the shoreline). The zone bar
-- replaces the top bar for as long as a sea is open.
Layout.NeverTogether = {
	{ "TopBar", "ZoneBar" },
	{ "Charge", "Status" },
	{ "Charge", "ZoneBar" },
	{ "Charge", "Carry" },
	{ "Charge", "Train" },
	{ "Hold", "Status" },
	{ "Hold", "ZoneBar" },
	{ "Hold", "Carry" },
	{ "Hold", "Train" },
	-- Eggs are placed in your plot, far from the shoreline; carried eggs go
	-- into the inventory the moment you are back on land.
	{ "Place", "Carry" },
	{ "Place", "Charge" },
	{ "Place", "Hold" },
	{ "Train", "Status" },
	{ "Train", "ZoneBar" },
}

-- Screen areas used by Roblox's own UI, in real pixels.
function Layout.reserved(width: number, height: number, touch: boolean)
	local list = {
		TopBarButtons = { 0, 0, 220, 58 },
	}
	if touch then
		list.Thumbstick = { 0, height - 190, 250, 190 }
		list.JumpButton = { width - 150, height - 150, 150, 150 }
		list.Hotbar = { width / 2 - 150, height - 80, 300, 80 }
	else
		-- (The default player list is switched off; the world has leaderboards.)
		list.Hotbar = { width / 2 - 160, height - 90, 320, 90 }
	end
	return list
end

function Layout.scale(width: number, height: number): number
	return math.clamp(math.min(width / 1280, height / 720), 0.5, 1.2)
end

local function field(element, touch: boolean, name: string)
	if touch and element.touch and element.touch[name] then
		return element.touch[name]
	end
	return element[name]
end

-- Placement of one element: anchor, pivot, offset, size (design pixels).
function Layout.place(name: string, touch: boolean)
	local e = Layout.Elements[name]
	return field(e, touch, "anchor"), field(e, touch, "pivot"), field(e, touch, "offset"), field(e, touch, "size")
end

-- The element's rectangle {x, y, w, h} in real screen pixels.
function Layout.rect(name: string, width: number, height: number, touch: boolean): { number }
	local anchor, pivot, offset, size = Layout.place(name, touch)
	local s = Layout.scale(width, height)
	local w, h = size[1] * s, size[2] * s
	local x = anchor[1] * width + offset[1] * s - pivot[1] * w
	local y = anchor[2] * height + offset[2] * s - pivot[2] * h
	return { x, y, w, h }
end

return Layout
