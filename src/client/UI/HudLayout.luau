--!strict
-- EVERY HUD position/size lives here so the layout can be audited in one place.
--
-- The HUD ScreenGui uses ScreenInsets = CoreUISafeInsets, so (0,0) is already BELOW the Roblox top bar
-- (top-left menu / chat buttons) and inside notches / the home indicator. All numbers below are pixels
-- inside that safe area and are recomputed whenever it resizes (HudLayout.Compute(w, h)).
--
-- Regions (never overlap; HudLayout.Validate checks it in Studio):
--   Currencies   top-left            Cash, Bones, $/s
--   Feed         top-centre          server/global broadcast feed (2 lines)
--   Messages     centre, under feed  spectator banners + personal toasts (stack, trimmed to fit)
--   Rail         right side          Shop, Kennel Book, Yard, Boosts, Odds (kept above the mobile jump button;
--                                    wraps into 2 columns on short screens so buttons never drop below MinButton)
--   Boosts       left-middle         active boost timers
--   ThrowPanel   bottom-centre       meter, Throw Power, ball, catch chance, Lucky Streak pips, THROW button
--   Debug        bottom-left         CutsceneTestMode button (only when enabled)
--   JumpReserve  bottom-right        reserved for the Roblox mobile jump button (nothing is placed here)
-- Modal windows (Modal) and the Whistle prompt are centred overlays above everything else.
export type Rect = { X: number, Y: number, W: number, H: number }
export type Layout = {
	Scale: number,
	Margin: number,
	Currencies: Rect,
	Feed: Rect,
	FeedLine: number,
	Messages: Rect,
	Rail: Rect,
	RailButton: number,
	RailButtonW: number,
	RailColumns: number,
	RailGap: number,
	Boosts: Rect,
	BoostRow: number,
	ThrowPanel: Rect,
	Debug: Rect,
	JumpReserve: Rect,
	Modal: Rect,
	Whistle: Rect,
}

local HudLayout = {}

HudLayout.Margin = 8
HudLayout.BaseResolution = Vector2.new(1280, 720)
HudLayout.ScaleMin = 0.62
HudLayout.ScaleMax = 1.25

HudLayout.Currencies = { W = 200, H = 100 } -- x scale
HudLayout.Feed = { WidthFrac = 0.42, MinW = 260, MaxW = 560, Line = 26, MinLine = 20, Lines = 2, Gap = 4 }
HudLayout.Messages = { WidthFrac = 0.38, MinW = 260, MaxW = 460, GapBelowFeed = 6 }
HudLayout.Rail = { Count = 5, Button = 56, MinButton = 36, MaxButton = 70, Gap = 8, MinGap = 4, MaxGap = 10, WidthMult = 1.45 }
HudLayout.Boosts = { W = 190, MinW = 170, MaxW = 220, Row = 30, MinRow = 26, MaxRows = 6, TopFrac = 0.32, GapBelowCurrencies = 12 }
HudLayout.Throw = { WidthFrac = 0.5, MinW = 330, MaxW = 560, H = 120, MinH = 100, MaxH = 150 }
HudLayout.Debug = { W = 120, H = 28 }
-- Roblox's touch jump button sits in the bottom-right corner of the FULL screen (TouchGui ignores the safe
-- area): phones (short side <= 500 px) 70 px button ending 20-25 px from the edges, tablets 120 px button
-- ending 50/20 px from the edges. Keep that corner empty: 140x140 on phones, 180x150 on tablets
-- (measured in safe-area pixels, which is a superset of the screen corner). Desktop keeps a small reserve.
HudLayout.JumpReserve = { W = 96, H = 92, PhoneW = 140, PhoneH = 140, TabletW = 180, TabletH = 150, SmallScreen = 500 }
HudLayout.Modal = { WidthFrac = 0.8, MinW = 320, MaxW = 760, HeightFrac = 0.95, MinH = 250, MaxH = 540 }
HudLayout.Whistle = { WidthFrac = 0.4, MinW = 280, MaxW = 420, H = 120, MinH = 100, MaxH = 150 }
HudLayout.Toast = { H = 34, MinH = 28 }

local function clamp(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, v))
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { X = math.floor(x + 0.5), Y = math.floor(y + 0.5), W = math.floor(w + 0.5), H = math.floor(h + 0.5) }
end

function HudLayout.UIScale(w: number, h: number): number
	local s = math.min(w / HudLayout.BaseResolution.X, h / HudLayout.BaseResolution.Y)
	return clamp(s, HudLayout.ScaleMin, HudLayout.ScaleMax)
end

-- Jump-button reserve size for this screen (touch devices only get the large phone/tablet reserve).
function HudLayout.JumpReserveSize(w: number, h: number, touch: boolean?): (number, number)
	local J = HudLayout.JumpReserve
	if not touch then
		return J.W, J.H
	end
	if math.min(w, h) <= J.SmallScreen then
		return J.PhoneW, J.PhoneH
	end
	return J.TabletW, J.TabletH
end

-- w, h = safe-area size in pixels; touch = the device shows Roblox's touch controls (jump button).
function HudLayout.Compute(w: number, h: number, touch: boolean?): Layout
	local m = HudLayout.Margin
	local s = HudLayout.UIScale(w, h)

	-- top-left currencies
	local cur = rect(m, m, HudLayout.Currencies.W * s, HudLayout.Currencies.H * s)

	-- bottom-right jump reserve
	local jw, jh = HudLayout.JumpReserveSize(w, h, touch)
	local jump = rect(w - jw, h - jh, jw, jh)

	-- right rail, shrunk if needed so it ends above the jump reserve; if one column would make the buttons
	-- smaller than MinButton (phones), wrap into two columns instead
	local R = HudLayout.Rail
	local gap = math.floor(clamp(R.Gap * s, R.MinGap, R.MaxGap) + 0.5)
	local btn = clamp(R.Button * s, R.MinButton, R.MaxButton)
	local railTop = m
	local railMaxH = jump.Y - m - railTop
	local cols = 1
	local fit = (railMaxH - (R.Count - 1) * gap) / R.Count
	if fit < R.MinButton then
		cols = 2
		local rowsFit = math.ceil(R.Count / cols)
		fit = (railMaxH - (rowsFit - 1) * gap) / rowsFit
	end
	btn = math.floor(math.max(math.min(btn, fit), 24))
	local railRows = math.ceil(R.Count / cols)
	local btnW = math.floor(btn * R.WidthMult)
	local railH = railRows * btn + (railRows - 1) * gap
	local railW = cols * btnW + (cols - 1) * gap
	local rail = rect(w - m - railW, railTop, railW, railH)

	-- top-centre feed, never wider than the space between currencies and rail
	local F = HudLayout.Feed
	local sideBlock = math.max(cur.X + cur.W, w - rail.X) + m
	local feedW = math.min(clamp(F.WidthFrac * w, F.MinW, F.MaxW), w - 2 * sideBlock)
	local line = math.max(F.MinLine, F.Line * s)
	local feedH = F.Lines * line + (F.Lines - 1) * F.Gap
	local feed = rect((w - feedW) / 2, m, feedW, feedH)

	-- bottom-centre throw panel, clear of the jump reserve
	local T = HudLayout.Throw
	local tw = clamp(T.WidthFrac * w, T.MinW, T.MaxW)
	tw = math.min(tw, 2 * (jump.X - m - w / 2)) -- symmetric about the centre, right edge left of the jump reserve
	local th = clamp(T.H * s, T.MinH, T.MaxH)
	local throw = rect((w - tw) / 2, h - m - th, tw, th)

	-- centre message stack between feed and throw panel
	local M = HudLayout.Messages
	local msgY = feed.Y + feed.H + M.GapBelowFeed
	local msgW = math.min(clamp(M.WidthFrac * w, M.MinW, M.MaxW), w - 2 * sideBlock)
	local msgs = rect((w - msgW) / 2, msgY, msgW, math.max(0, throw.Y - m - msgY))

	-- left-middle boosts: below the currencies, left of the throw panel
	local B = HudLayout.Boosts
	local bw = math.min(clamp(B.W * s, B.MinW, B.MaxW), throw.X - 2 * m)
	local row = math.max(B.MinRow, B.Row * s)
	local by = math.max(cur.Y + cur.H + B.GapBelowCurrencies, h * B.TopFrac)
	local bh = math.min(B.MaxRows * row + (B.MaxRows - 1) * 4, h - m - HudLayout.Debug.H - m - by)
	local boosts = rect(m, by, bw, math.max(row, bh))

	local debug = rect(m, h - m - HudLayout.Debug.H, math.min(HudLayout.Debug.W, throw.X - 2 * m), HudLayout.Debug.H)

	local MD = HudLayout.Modal
	local mw = clamp(MD.WidthFrac * w, MD.MinW, MD.MaxW)
	local mh = clamp(MD.HeightFrac * h, MD.MinH, MD.MaxH)
	mw, mh = math.min(mw, w - 2 * m), math.min(mh, h - 2 * m)
	local modal = rect((w - mw) / 2, (h - mh) / 2, mw, mh)

	local WH = HudLayout.Whistle
	local ww = math.min(clamp(WH.WidthFrac * w, WH.MinW, WH.MaxW), w - 2 * m)
	local wh = clamp(WH.H * s, WH.MinH, WH.MaxH)
	local whistle = rect((w - ww) / 2, (h - wh) / 2, ww, wh)

	return {
		Scale = s,
		Margin = m,
		Currencies = cur,
		Feed = feed,
		FeedLine = math.floor(line),
		Messages = msgs,
		Rail = rail,
		RailButton = btn,
		RailButtonW = btnW,
		RailColumns = cols,
		RailGap = gap,
		Boosts = boosts,
		BoostRow = math.floor(row),
		ThrowPanel = throw,
		Debug = debug,
		JumpReserve = jump,
		Modal = modal,
		Whistle = whistle,
	}
end

-- Regions that must never overlap each other (modal/whistle are overlays and excluded).
HudLayout.ExclusiveRegions = { "Currencies", "Feed", "Messages", "Rail", "Boosts", "ThrowPanel", "Debug", "JumpReserve" }

local function intersects(a: Rect, b: Rect): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

-- Returns a list of "A x B" overlap descriptions (empty = clean). Also flags regions outside the safe area.
function HudLayout.Validate(layout: Layout, w: number, h: number): { string }
	local problems = {}
	local L = layout :: any
	for i, a in HudLayout.ExclusiveRegions do
		local ra: Rect = L[a]
		if ra.W > 0 and ra.H > 0 then
			if ra.X < 0 or ra.Y < 0 or ra.X + ra.W > w or ra.Y + ra.H > h then
				table.insert(problems, a .. " outside safe area")
			end
			for j = i + 1, #HudLayout.ExclusiveRegions do
				local b = HudLayout.ExclusiveRegions[j]
				local rb: Rect = L[b]
				if rb.W > 0 and rb.H > 0 and intersects(ra, rb) then
					table.insert(problems, a .. " x " .. b)
				end
			end
		end
	end
	return problems
end

function HudLayout.Apply(gui: GuiObject, r: Rect)
	gui.AnchorPoint = Vector2.zero
	gui.Position = UDim2.fromOffset(r.X, r.Y)
	gui.Size = UDim2.fromOffset(r.W, r.H)
end

return HudLayout
