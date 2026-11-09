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
	TopBar = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 10 }, size = { 546, 56 } },
	Status = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 74 }, size = { 480, 84 } },
	Objective = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 164 }, size = { 680, 30 }, touch = { size = { 560, 30 } } },
	Toasts = { anchor = { 0.5, 0 }, pivot = { 0.5, 0 }, offset = { 0, 198 }, size = { 680, 52 } },
	Promo = {
		anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 16, 112 }, size = { 150, 92 },
		touch = { anchor = { 1, 0 }, pivot = { 1, 0 }, offset = { -16, 112 } },
	},
	Menu = { anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 16, 214 }, size = { 186, 88 }, touch = { offset = { 16, 120 } } },
	Stats = { anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 16, 312 }, size = { 230, 132 }, touch = { offset = { 16, 216 }, size = { 230, 108 } } },
	Feed = { anchor = { 0, 0 }, pivot = { 0, 0 }, offset = { 254, 312 }, size = { 120, 132 }, touch = { offset = { 210, 120 }, size = { 120, 76 } } },
	RightGrid = {
		anchor = { 1, 0.5 }, pivot = { 1, 0 }, offset = { -16, -40 }, size = { 186, 186 },
		touch = { anchor = { 1, 0 }, offset = { -16, 214 } },
	},
	Carry = { anchor = { 0.5, 1 }, pivot = { 0.5, 1 }, offset = { 0, -176 }, size = { 320, 60 } },
	Train = { anchor = { 0.5, 1 }, pivot = { 0.5, 1 }, offset = { 0, -244 }, size = { 420, 40 } },
	Charge = {
		anchor = { 0.5, 0.5 }, pivot = { 0, 0.5 }, offset = { 120, 20 }, size = { 200, 250 },
		-- On touch: left of the character, clear of the HOLD button and thumbstick.
		touch = { pivot = { 1, 0.5 }, offset = { -90, 20 }, size = { 150, 250 } },
	},
	Hold = { anchor = { 1, 1 }, pivot = { 1, 1 }, offset = { -300, -170 }, size = { 170, 170 }, touchOnly = true },
}

-- Pairs that can never be on screen together, so they may share space:
-- the charge meter and HOLD button only show while you can part the sea,
-- which is never while a sea is open, while carrying an egg, or while
-- training (the pad is inside your base, not on the shoreline).
Layout.NeverTogether = {
	{ "Charge", "Status" },
	{ "Charge", "Carry" },
	{ "Charge", "Train" },
	{ "Hold", "Status" },
	{ "Hold", "Carry" },
	{ "Hold", "Train" },
	{ "Train", "Status" },
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
		list.PlayerList = { width - 200, 58, 200, 230 }
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
