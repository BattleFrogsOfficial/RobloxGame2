#!/usr/bin/env node
// HUD layout preview / audit.
//
//   node tools/hud_preview.js            -> docs/qa/hud/*.png + a text report on stdout (exit 1 on layout problems)
//
// Reproduces the Roblox HUD as HTML using the REAL numbers from:
//   src/client/UI/HudLayout.luau   (all region constants are parsed from the file; Compute() is ported 1:1 below,
//                                   keep computeLayout() in sync when HudLayout.Compute changes)
//   src/client/UI/Theme.luau       (colours, corner radii, stroke, text caps parsed from the file)
//   the component code (Create/Button/Window/Tabs/RowList/VirtualGrid + HudController/ThrowController/
//   NotificationController/ShopController/BookController), mirrored as a small UDim2 layout engine:
//   Size/Position scale+offset, AnchorPoint, UIPadding, UIListLayout (padding/alignment/LayoutOrder),
//   SizeConstraint RelativeYY/XX, UIAspectRatioConstraint (FitWithinMaxSize), TextScaled + UITextSizeConstraint.
//
// Device model:
//   * HUD ScreenGuis use ScreenInsets = CoreUISafeInsets -> the safe area starts BELOW the 58 px Roblox top bar
//     (and inside the notch / home-indicator insets on phones).
//   * Phone: Roblox TouchGui jump button lives in the bottom-right corner of the FULL screen (not the safe area);
//     we reserve a 140x140 screen-corner box for it and fail the audit if any HUD element enters it.
//
// Checks (Node side, on resolved rects): region overlaps, regions inside the safe area, nothing under the top bar
// or the jump reserve, children escaping their region. Browser side: TextScaled fitting -> any text that does not
// fit at MinTextSize (truncation) and any text rendered under 10 px are reported.
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'docs', 'qa', 'hud');
const HUD_LAYOUT = fs.readFileSync(path.join(ROOT, 'src/client/UI/HudLayout.luau'), 'utf8');
const THEME = fs.readFileSync(path.join(ROOT, 'src/client/UI/Theme.luau'), 'utf8');

// ------------------------------------------------------------------------------------------------
// Parse Luau constants
// ------------------------------------------------------------------------------------------------
function luaTableToJs(src) {
  // { A = 1, B = { C = 2 } } -> JS object (numbers / nested tables only)
  const js = src
    .replace(/--[^\n]*/g, '')
    .replace(/Vector2\.new\(([^)]*)\)/g, '[$1]')
    .replace(/([A-Za-z_]\w*)\s*=/g, '"$1":')
    .replace(/,\s*}/g, '}');
  return JSON.parse(js);
}

function parseHudLayout(text) {
  const out = {};
  const re = /^HudLayout\.(\w+)\s*=\s*(.+?)\s*(?:--.*)?$/gm;
  let m;
  while ((m = re.exec(text))) {
    const [, key, raw] = m;
    if (raw.startsWith('function')) continue;
    if (raw.startsWith('{') && raw.includes('=')) out[key] = luaTableToJs(raw);
    else if (raw.startsWith('Vector2.new')) out[key] = luaTableToJs(raw);
    else if (/^-?[\d.]+$/.test(raw)) out[key] = Number(raw);
  }
  for (const k of ['Margin', 'BaseResolution', 'ScaleMin', 'ScaleMax', 'Currencies', 'Feed', 'Messages', 'Rail', 'Boosts',
    'Throw', 'Debug', 'JumpReserve', 'Modal', 'Whistle', 'Toast']) {
    if (out[k] === undefined) throw new Error('HudLayout.' + k + ' not parsed');
  }
  return out;
}

function parseTheme(text) {
  const rgb = (s) => s.match(/(\d+),\s*(\d+),\s*(\d+)/).slice(1).map(Number);
  const color = {};
  const block = text.split('Theme.Color = {')[1].split('\n}')[0];
  for (const m of block.matchAll(/(\w+)\s*=\s*Color3\.fromRGB\(([^)]*)\)/g)) color[m[1]] = rgb(m[2]);
  const num = (k) => Number(text.match(new RegExp('Theme\\.' + k + '\\s*=\\s*([\\d.]+)'))[1]);
  const textMax = luaTableToJs(text.match(/Theme\.TextMax\s*=\s*({[^}]*})/)[1]);
  const spacing = luaTableToJs(text.match(/Theme\.Spacing\s*=\s*({[^}]*})/)[1]);
  return { Color: color, Corner: num('Corner'), CornerSmall: num('CornerSmall'), Stroke: num('StrokeThickness'),
    Backdrop: num('BackdropTransparency'), TextMax: textMax, TextMin: num('TextMin'), Spacing: spacing };
}

const H = parseHudLayout(HUD_LAYOUT);
const T = parseTheme(THEME);
const RARITY = { Common: [200, 200, 200], Uncommon: [90, 200, 90], Rare: [70, 140, 255], Epic: [170, 80, 230],
  Legendary: [255, 170, 30], Mythic: [255, 60, 120] };
const RARITY_ORDER = Object.keys(RARITY);

// ------------------------------------------------------------------------------------------------
// HudLayout.Compute port (KEEP IN SYNC with src/client/UI/HudLayout.luau)
// ------------------------------------------------------------------------------------------------
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const rect = (x, y, w, h) => ({ X: Math.floor(x + 0.5), Y: Math.floor(y + 0.5), W: Math.floor(w + 0.5), H: Math.floor(h + 0.5) });
function uiScale(w, h) {
  return clamp(Math.min(w / H.BaseResolution[0], h / H.BaseResolution[1]), H.ScaleMin, H.ScaleMax);
}
function jumpReserveSize(w, h, touch) {
  const J = H.JumpReserve;
  if (!touch) return [J.W, J.H];
  return Math.min(w, h) <= J.SmallScreen ? [J.PhoneW, J.PhoneH] : [J.TabletW, J.TabletH];
}
function computeLayout(w, h, touch) {
  const m = H.Margin;
  const s = uiScale(w, h);
  const cur = rect(m, m, H.Currencies.W * s, H.Currencies.H * s);
  const [jw, jh] = jumpReserveSize(w, h, touch);
  const jump = rect(w - jw, h - jh, jw, jh);
  const R = H.Rail;
  const gap = Math.floor(clamp(R.Gap * s, R.MinGap, R.MaxGap) + 0.5);
  let btn = clamp(R.Button * s, R.MinButton, R.MaxButton);
  const railTop = m;
  const railMaxH = jump.Y - m - railTop;
  let cols = 1;
  let fit = (railMaxH - (R.Count - 1) * gap) / R.Count;
  if (fit < R.MinButton) {
    cols = 2;
    const rowsFit = Math.ceil(R.Count / cols);
    fit = (railMaxH - (rowsFit - 1) * gap) / rowsFit;
  }
  btn = Math.floor(Math.max(Math.min(btn, fit), 24));
  const railRows = Math.ceil(R.Count / cols);
  const btnW = Math.floor(btn * R.WidthMult);
  const railH = railRows * btn + (railRows - 1) * gap;
  const railW = cols * btnW + (cols - 1) * gap;
  const rail = rect(w - m - railW, railTop, railW, railH);
  const F = H.Feed;
  const sideBlock = Math.max(cur.X + cur.W, w - rail.X) + m;
  const feedW = Math.min(clamp(F.WidthFrac * w, F.MinW, F.MaxW), w - 2 * sideBlock);
  const line = Math.max(F.MinLine, F.Line * s);
  const feedH = F.Lines * line + (F.Lines - 1) * F.Gap;
  const feed = rect((w - feedW) / 2, m, feedW, feedH);
  const TH = H.Throw;
  let tw = clamp(TH.WidthFrac * w, TH.MinW, TH.MaxW);
  tw = Math.min(tw, 2 * (jump.X - m - w / 2));
  const th = clamp(TH.H * s, TH.MinH, TH.MaxH);
  const throwP = rect((w - tw) / 2, h - m - th, tw, th);
  const M = H.Messages;
  const msgY = feed.Y + feed.H + M.GapBelowFeed;
  const msgW = Math.min(clamp(M.WidthFrac * w, M.MinW, M.MaxW), w - 2 * sideBlock);
  const msgs = rect((w - msgW) / 2, msgY, msgW, Math.max(0, throwP.Y - m - msgY));
  const B = H.Boosts;
  const bw = Math.min(clamp(B.W * s, B.MinW, B.MaxW), throwP.X - 2 * m);
  const row = Math.max(B.MinRow, B.Row * s);
  const by = Math.max(cur.Y + cur.H + B.GapBelowCurrencies, h * B.TopFrac);
  const bh = Math.min(B.MaxRows * row + (B.MaxRows - 1) * 4, h - m - H.Debug.H - m - by);
  const boosts = rect(m, by, bw, Math.max(row, bh));
  const debug = rect(m, h - m - H.Debug.H, Math.min(H.Debug.W, throwP.X - 2 * m), H.Debug.H);
  const MD = H.Modal;
  let mw = clamp(MD.WidthFrac * w, MD.MinW, MD.MaxW);
  let mh = clamp(MD.HeightFrac * h, MD.MinH, MD.MaxH);
  mw = Math.min(mw, w - 2 * m); mh = Math.min(mh, h - 2 * m);
  const modal = rect((w - mw) / 2, (h - mh) / 2, mw, mh);
  const WH = H.Whistle;
  const ww = Math.min(clamp(WH.WidthFrac * w, WH.MinW, WH.MaxW), w - 2 * m);
  const wh = clamp(WH.H * s, WH.MinH, WH.MaxH);
  const whistle = rect((w - ww) / 2, (h - wh) / 2, ww, wh);
  return { Scale: s, Margin: m, Currencies: cur, Feed: feed, FeedLine: Math.floor(line), Messages: msgs, Rail: rail,
    RailButton: btn, RailButtonW: btnW, RailColumns: cols, RailGap: gap, Boosts: boosts, BoostRow: Math.floor(row), ThrowPanel: throwP,
    Debug: debug, JumpReserve: jump, Modal: modal, Whistle: whistle };
}

// ------------------------------------------------------------------------------------------------
// Tiny Roblox-GUI layout engine
// ------------------------------------------------------------------------------------------------
// node: { name, size:[sx,ox,sy,oy], pos:[sx,ox,sy,oy], anchor:[ax,ay], yy, xx, aspect, pad:[t,b,l,r],
//         list:{dir:'v'|'h', pad, h:'l'|'c'|'r', v:'t'|'c'|'b'}, order, bg, bgT, corner, stroke:[color,th], clip,
//         text, font:'title'|'body', color, max, wrap, xa, ya, rich, strokeText, children:[], visible }
const U = (sx, ox, sy, oy) => [sx, ox, sy, oy];
const off = (w, h) => [0, w, 0, h];
const sc = (x, y) => [x, 0, y, 0];
function N(props, children) { return Object.assign({ children: children || [] }, props); }

function resolve(node, parent, flowPos) {
  // parent: {x,y,w,h} content box in absolute px
  const sz = node.size || [0, 0, 0, 0];
  let w = sz[0] * (node.yy ? parent.h : parent.w) + sz[1];
  let h = sz[2] * (node.xx ? parent.w : parent.h) + sz[3];
  if (node.aspect) { // FitWithinMaxSize
    const r = node.aspect;
    if (w / h > r) w = h * r; else h = w / r;
  }
  let x, y;
  if (flowPos) { x = flowPos.x; y = flowPos.y; }
  else {
    const p = node.pos || [0, 0, 0, 0];
    const a = node.anchor || [0, 0];
    x = parent.x + p[0] * parent.w + p[1] - a[0] * w;
    y = parent.y + p[2] * parent.h + p[3] - a[1] * h;
  }
  node.r = { x, y, w, h };
  const pd = node.pad || [0, 0, 0, 0];
  const content = { x: x + pd[2], y: y + pd[0], w: w - pd[2] - pd[3], h: h - pd[0] - pd[1] };
  if (node.scrollY) content.h = Math.max(content.h, 1);
  node.content = content;
  const kids = node.children.filter((c) => c.visible !== false);
  if (node.list) {
    const L = node.list;
    // first pass sizes
    const sized = kids.map((c, i) => ({ c, i, order: c.order ?? 0 })).sort((a, b) => a.order - b.order || a.i - b.i);
    sized.forEach(({ c }) => resolve(c, content, { x: 0, y: 0 }));
    const gap = L.pad || 0;
    if (L.dir === 'h') {
      const total = sized.reduce((t, { c }) => t + c.r.w, 0) + gap * Math.max(0, sized.length - 1);
      let cx = content.x + (L.h === 'r' ? content.w - total : L.h === 'c' ? (content.w - total) / 2 : 0);
      for (const { c } of sized) {
        const cy = content.y + (L.v === 'c' ? (content.h - c.r.h) / 2 : L.v === 'b' ? content.h - c.r.h : 0);
        resolve(c, content, { x: cx, y: cy });
        cx += c.r.w + gap;
      }
    } else {
      const total = sized.reduce((t, { c }) => t + c.r.h, 0) + gap * Math.max(0, sized.length - 1);
      let cy = content.y + (L.v === 'b' ? content.h - total : L.v === 'c' ? (content.h - total) / 2 : 0);
      for (const { c } of sized) {
        const cx = content.x + (L.h === 'c' ? (content.w - c.r.w) / 2 : L.h === 'r' ? content.w - c.r.w : 0);
        resolve(c, content, { x: cx, y: cy });
        cy += c.r.h + gap;
      }
    }
    node.listContent = { total: 0 };
  } else {
    for (const c of kids) resolve(c, content, null);
  }
  return node;
}

const css = (c, t) => `rgba(${c[0]},${c[1]},${c[2]},${(1 - (t || 0)).toFixed(3)})`;
const esc = (s) => String(s).replace(/&(?!\w+;)/g, '&amp;');
let uid = 0;
function emit(node, parentAbs, depth) {
  if (node.visible === false) return '';
  const r = node.r;
  const st = [`left:${(r.x - parentAbs.x).toFixed(2)}px`, `top:${(r.y - parentAbs.y).toFixed(2)}px`,
    `width:${r.w.toFixed(2)}px`, `height:${r.h.toFixed(2)}px`];
  if (node.bg) st.push(`background:${node.bgCss || css(node.bg, node.bgT)}`);
  if (node.corner !== undefined) st.push(`border-radius:${Math.min(node.corner, Math.min(r.w, r.h) / 2)}px`);
  if (node.stroke) st.push(`box-shadow:0 0 0 ${node.stroke[1]}px ${css(node.stroke[0], node.stroke[2])}`);
  if (node.clip) st.push('overflow:hidden');
  if (node.z) st.push(`z-index:${node.z}`);
  if (node.extraCss) st.push(node.extraCss);
  let inner = '';
  if (node.text !== undefined) {
    const id = 't' + (uid++);
    const pd = node.pad || [0, 0, 0, 0];
    const tst = [`left:${pd[2]}px`, `top:${pd[0]}px`, `width:${r.w - pd[2] - pd[3]}px`, `height:${r.h - pd[0] - pd[1]}px`,
      `color:${css(node.color || T.Color.Text)}`, `font-family:${node.font === 'body' ? "'Montserrat', 'DejaVu Sans', sans-serif;font-weight:700" : "'Fredoka One', 'DejaVu Sans', sans-serif"}`,
      `justify-content:${node.xa === 'l' ? 'flex-start' : node.xa === 'r' ? 'flex-end' : 'center'}`,
      `text-align:${node.xa === 'l' ? 'left' : node.xa === 'r' ? 'right' : 'center'}`,
      `align-items:${node.ya === 't' ? 'flex-start' : node.ya === 'b' ? 'flex-end' : 'center'}`,
      `white-space:${node.wrap === false ? 'pre' : 'pre-wrap'}`];
    if (node.strokeText !== undefined) tst.push(`text-shadow:0 0 2px rgba(0,0,0,${1 - node.strokeText}),0 1px 1px rgba(0,0,0,${1 - node.strokeText})`);
    inner += `<div class="t" id="${id}" data-name="${esc(node.name || '')}" data-max="${node.max || 100}" data-min="${T.TextMin}" data-fixed="${node.fixed || 0}" data-alt="${esc(JSON.stringify(node.alt || [])).replace(/"/g, '&quot;')}" style="${tst.join(';')}"><span>${node.rich ? node.text : esc(node.text)}</span></div>`;
  }
  for (const c of node.children) inner += emit(c, r, depth + 1);
  return `<div class="g" data-name="${esc(node.name || '')}" style="${st.join(';')}">${inner}</div>`;
}

function walk(node, fn, parent) { fn(node, parent); for (const c of node.children) if (c.visible !== false) walk(c, fn, node); }

// ------------------------------------------------------------------------------------------------
// Components (mirrors the Luau code)
// ------------------------------------------------------------------------------------------------
const C = T.Color;
const lighten = (c, a) => c.map((v) => Math.round(v + (255 - v) * a));
const hex = (c) => c.map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase();
function textColorFor(bg) { const lum = (0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2]) / 255; return lum > 0.6 ? C.TextDark : C.Text; }
function Label(p) { // Create.Label
  return N(Object.assign({ size: sc(1, 1), font: 'title', color: C.Text, wrap: true, max: T.TextMax.Normal }, p), p.kids);
}
function Panel(p, kids) { return N(Object.assign({ bg: C.Panel, corner: T.Corner, stroke: [C.Stroke, T.Stroke] }, p), kids); }
function Button(p) { // Button.new
  const color = p.color || C.Accent;
  return N(Object.assign({ bg: color, corner: p.corner ?? T.CornerSmall, stroke: [C.Stroke, T.Stroke], pad: [3, 3, 6, 6],
    text: p.text, font: 'title', color: textColorFor(color), max: p.max || T.TextMax.Normal, size: p.size || sc(1, 1) }, p,
  { color: p.textColor || textColorFor(color) }), p.kids);
}

function currencies(L) {
  const pill = (order, frac, icon, iconColor, value, textColor) => {
    const rowH = null;
    return N({ name: 'Row' + order, bg: C.PanelInset, corner: T.CornerSmall, size: sc(1, frac), order }, [
      N({ name: 'Icon', bg: iconColor, size: sc(1, 1), yy: true, corner: 100, stroke: [C.Stroke, 2] }, [
        Label({ text: icon, color: C.TextDark, size: sc(0.8, 0.8), pos: sc(0.1, 0.1), max: T.TextMax.Big })]),
      N({ name: 'ValueHolder', size: U(1, 0, 1, 0), fitIcon: true }, [
        Label({ name: 'Value', text: value, color: textColor, xa: 'l', strokeText: 0.6, size: U(1, -4, 0.86, 0), pos: sc(0, 0.07), max: T.TextMax.Big })]),
    ]);
  };
  return Panel({ name: 'CurrencyPanel', size: sc(1, 1), bgT: 0.1, pad: [5, 5, 5, 5], list: { dir: 'v', pad: 3 } }, [
    pill(1, CUR.cashFrac, '$', C.Cash, '$1.24M', C.Cash),
    Label({ name: 'Rate', text: '$3.4K/s', font: 'body', color: C.TextDim, xa: 'l', size: sc(1, CUR.rateFrac), order: 2, max: T.TextMax.Small }),
    pill(3, CUR.bonesFrac, 'B', C.Bones, '245', C.Bones),
  ]);
}
// fractions used by HudController.buildCurrencies (parsed below so edits there are reflected)
const HUDC = fs.readFileSync(path.join(ROOT, 'src/client/Controllers/HudController.luau'), 'utf8');
const CUR = {
  cashFrac: Number(HUDC.match(/pill\(panel, 1, ([\d.]+)/)[1]),
  rateFrac: Number(HUDC.match(/Size = UDim2\.fromScale\(1, ([\d.]+)\), LayoutOrder = 2/)[1]),
  bonesFrac: Number(HUDC.match(/pill\(panel, 3, ([\d.]+)/)[1]),
};

function fixIconHolders(root) {
  // HudController: holder.Position = (h + 6, 0), Size = (1, -(h+6), 1, 0) where h = row height
  walk(root, (n) => {
    if (n.fitIcon) { /* handled pre-resolve via rowH below */ }
  });
}

function rail(L) {
  const defs = [['Shop', 'Shop', C.Accent], ['Book', 'Book', C.Info], ['Yard', 'Yard', C.Good], ['Boosts', 'Boost', C.Purple], ['Odds', 'Odds', [240, 130, 70]]];
  // UIGridLayout (HudController.buildRail): CellSize = (RailButtonW, RailButton), FillDirectionMaxCells = RailColumns
  return N({ name: 'RailList', size: sc(1, 1) }, defs.map(([id, text, color], i) =>
    Button({ name: 'Rail' + id, text, color, order: i + 1, max: 22, fixed: Math.min(22, Math.max(12, Math.floor(L.RailButton * 0.36))), size: off(L.RailButtonW, L.RailButton), corner: T.Corner,
      pos: off((i % L.RailColumns) * (L.RailButtonW + L.RailGap), Math.floor(i / L.RailColumns) * (L.RailButton + L.RailGap)),
      kids: id === 'Book' ? [N({ name: 'Dot', badge: true, bg: C.Bad, size: off(12, 12), pos: U(1, -3, 0, 3), anchor: [0.5, 0.5], corner: 6, stroke: [[255, 255, 255], 2] })] : [] })));
}

function boosts(L) {
  const rows = [['Sticky Ball  14m 59s', C.Info], ['Lucky Biscuit  14m 59s', C.Good], ['Golden Whistle x2', [255, 205, 60]], ['Treat Pocket x1', [240, 150, 90]]];
  return N({ name: 'BoostList', size: sc(1, 1), list: { dir: 'v', pad: 4 } }, rows.map(([t, col], i) =>
    N({ name: 'Boost' + i, bg: C.Panel, bgT: 0.1, corner: T.CornerSmall, stroke: [C.Stroke, 2], size: U(1, 0, 0, L.BoostRow), order: i }, [
      N({ name: 'Bar', bg: col, size: U(0, 6, 1, -8), pos: off(4, 4), corner: 3 }),
      Label({ name: 'Text', text: t, font: 'body', xa: 'l', wrap: false, fixed: Math.min(T.TextMax.Small, Math.max(11, Math.floor(L.BoostRow * 0.46))), size: U(1, -18, 1, -6), pos: off(14, 3), max: T.TextMax.Small }),
    ])));
}

function throwPanel(L, needlePos) {
  const TC = fs.readFileSync(path.join(ROOT, 'src/client/Controllers/ThrowController.luau'), 'utf8');
  const meterGood = 0.55, meterPerfect = 0.85; // Game.Meter (approx; parsed below if present)
  const G = fs.readFileSync(path.join(ROOT, 'src/shared/Config/Game.luau'), 'utf8');
  const gm = Number((G.match(/GoodMin\s*=\s*([\d.]+)/) || [0, meterGood])[1]);
  const pm = Number((G.match(/PerfectMin\s*=\s*([\d.]+)/) || [0, meterPerfect])[1]);
  const rowFrac = (name, def) => { const m = TC.match(new RegExp(name + '[^\\n]*?Size = UDim2\\.new\\(([\\d.]+), 0, ([\\d.]+), 0\\)')); return m ? [Number(m[1]), Number(m[2])] : def; };
  const chances = ['95%', '90%', '80%', '65%', '45%', '30%'];
  const left = N({ name: 'Left', size: U(1, -(0), 1, 0), leftOfThrow: true }, [
    Label({ name: 'Summary', text: 'GOOD → Beach (312 studs)', font: 'body', color: C.MeterGood, xa: 'l', wrap: /TextWrapped = true,\s*Size = UDim2\.new\(0\.\d+, 0, 0\.28/.test(TCSRC),
      alt: ['Power 12.4K · Flying Disc · Reach Snowy Peaks', 'Next: buy a Training upgrade in the Shop!', 'Walk to your throw pad (#6) first!', 'Hold THROW, release in the gold zone!'],
      size: TP.summarySize, pos: TP.summaryPos, max: T.TextMax.Normal }),
    N({ name: 'Streak', size: TP.streakSize, pos: TP.streakPos }, [
      Label({ name: 'StreakLabel', text: 'Streak', font: 'body', color: C.TextDim, xa: 'r', wrap: false, size: U(0.5, -4, 1, 0), max: T.TextMax.Small }),
      N({ name: 'Pips', size: U(0.5, 0, 1, 0), pos: sc(0.5, 0), list: { dir: 'h', pad: 4, h: 'r', v: 'c' } }, [0, 1].map((i) =>
        N({ name: 'Pip' + i, bg: i === 0 ? C.Accent : C.PanelInset, size: sc(0.7, 0.7), yy: true, corner: 100, stroke: [C.Stroke, 2], order: i }))),
    ]),
    N({ name: 'Meter', bg: C.MeterTrack, corner: T.CornerSmall, stroke: [C.Stroke, 2], size: TP.meterSize, pos: TP.meterPos }, [
      N({ name: 'Bands', size: sc(1, 1), clip: true, corner: T.CornerSmall }, [
        N({ name: 'Ok', bgCss: `linear-gradient(90deg, ${css(C.MeterOk, 0.7)}, ${css(C.MeterOk, 0.1)})`, bg: C.MeterOk, size: sc(gm, 1) }),
        N({ name: 'Good', bg: C.MeterGood, size: sc(pm - gm, 1), pos: sc(gm, 0) }),
        N({ name: 'Perfect', bg: C.MeterPerfect, size: sc(1 - pm, 1), pos: sc(pm, 0) }),
      ]),
      N({ name: 'Needle', bg: C.Needle, anchor: [0.5, 0.5], size: U(0, 6, 1, 10), pos: U(needlePos, 0, 0.5, 0), corner: 3, stroke: [C.Stroke, 2], z: 3 }),
    ]),
    N({ name: 'CatchChances', size: TP.chipRowSize, pos: TP.chipRowPos, list: { dir: 'h', pad: 3, v: 'c' } }, [
      Label({ name: 'CatchTitle', text: 'Catch', font: 'body', color: C.TextDim, order: 0, size: U(TP.catchTitleW, 0, 1, 0), max: T.TextMax.Small }),
      ...RARITY_ORDER.map((tier, i) => N({ name: 'Chip' + tier, bg: C.PanelInset, corner: 6, stroke: [RARITY[tier], 2], order: i + 1,
        size: U(TP.chipW / 6, -3, 1, 0) }, [
        Label({ text: chances[i], font: 'body', color: lighten(RARITY[tier], 0.3), size: U(1, -4, 1, -2), pos: off(2, 1), max: T.TextMax.Small })])),
    ]),
  ]);
  const btn = Button({ name: 'ThrowButton', text: 'THROW', color: C.MeterPerfect, max: 26, corner: T.Corner, size: sc(1, 1), pos: sc(1, 0), anchor: [1, 0], aspect: 1 });
  return Panel({ name: 'ThrowPanelFrame', size: sc(1, 1), bgT: 0.05, pad: [6, 6, 6, 6] }, [btn, left]);
}
// ThrowController layout fractions (parsed so edits in the Luau are reflected)
const TCSRC = fs.readFileSync(path.join(ROOT, 'src/client/Controllers/ThrowController.luau'), 'utf8');
function grabU(re, def) { const m = TCSRC.match(re); return m ? m.slice(1).map(Number) : def; }
const TP = (() => {
  const s = grabU(/summary = [\s\S]*?Size = UDim2\.new\(([\d.]+), (-?\d+), ([\d.]+), (-?\d+)\)/, [0.72, 0, 0.28, 0]);
  const ss = grabU(/Name = "Streak"[\s\S]*?Size = UDim2\.new\(([\d.]+), (-?\d+), ([\d.]+), (-?\d+)\)/, [0.27, 0, 0.28, 0]);
  const sp = grabU(/Name = "Streak"[\s\S]*?Position = UDim2\.fromScale\(([\d.]+), ([\d.]+)\)/, [0.73, 0]);
  const ms = grabU(/Name = "Meter"[\s\S]*?Size = UDim2\.new\(([\d.]+), (-?\d+), ([\d.]+), (-?\d+)\)/, [1, 0, 0.32, 0]);
  const mp = grabU(/Name = "Meter"[\s\S]*?Position = UDim2\.fromScale\(([\d.]+), ([\d.]+)\)/, [0, 0.32]);
  const cs = grabU(/Name = "CatchChances"[\s\S]*?Size = UDim2\.new\(([\d.]+), (-?\d+), ([\d.]+), (-?\d+)\)/, [1, 0, 0.3, 0]);
  const cp = grabU(/Name = "CatchChances"[\s\S]*?Position = UDim2\.fromScale\(([\d.]+), ([\d.]+)\)/, [0, 0.7]);
  const ct = grabU(/Text = "Catch"[\s\S]*?Size = UDim2\.new\(([\d.]+), 0, 1, 0\)/, [0.13]);
  const cw = grabU(/Size = UDim2\.new\(([\d.]+) \/ #Rarities\.Order/, [0.87]);
  return { summarySize: s, summaryPos: [0, 0, 0, 0], streakSize: ss, streakPos: sc(sp[0], sp[1]), meterSize: ms, meterPos: sc(mp[0], mp[1]),
    chipRowSize: cs, chipRowPos: sc(cp[0], cp[1]), catchTitleW: ct[0], chipW: cw[0] };
})();

function feed(L) {
  const lines = [
    { text: 'Sam caught a <b>LEGENDARY</b> Starlight Husky!', color: RARITY.Legendary },
    { text: '<font color="#FFD25A">[GLOBAL]</font> A MYTHIC Seraph Hound ran off from Kai', color: RARITY.Mythic },
  ];
  return N({ name: 'FeedList', size: sc(1, 1), list: { dir: 'v', pad: H.Feed.Gap ?? 4, h: 'c' } }, lines.map((l, i) =>
    N({ name: 'FeedLine' + i, bg: C.Panel, bgT: 0.15, corner: T.CornerSmall, stroke: [l.color, 2], size: U(1, 0, 0, L.FeedLine), order: i }, [
      Label({ text: l.text.replace(/<font color="#(\w+)">/g, '<span style="color:#$1">').replace(/<\/font>/g, '</span>'), rich: true,
        font: 'body', color: l.color, strokeText: 0.5, wrap: false, size: U(1, -12, 1, -4), pos: off(6, 2), max: T.TextMax.Small }),
    ])));
}

function messages(L) {
  const h = Math.max(H.Toast.MinH, Math.floor(H.Toast.H * L.Scale));
  const toast = (text, color, buttons, order) => {
    const btnW = buttons.length ? Math.floor(h * 2.4) : 0;
    return N({ name: 'Toast' + order, bg: C.Panel, bgT: 0.05, corner: T.CornerSmall, stroke: [color, 2], size: U(1, 0, 0, h), order }, [
      Label({ text, font: 'body', xa: 'l', size: U(1, -(16 + buttons.length * (btnW + 4)), 1, -6), pos: off(8, 3), max: T.TextMax.Small }),
      ...buttons.map((b, i) => Button({ name: 'ToastBtn', text: b[0], color: b[1], max: 16, size: U(0, btnW, 1, -8), pos: U(1, -4 - i * (btnW + 4), 0, 4), anchor: [1, 0] })),
    ]);
  };
  const SB = BANNER;
  const banner = N({ name: 'SpectatorBanner', bg: [34, 30, 48], bgT: 0.08, corner: 12, stroke: [RARITY.Epic, 3], size: U(1, 0, 0, SB.small), order: -1,
    pad: [4, 4, 10, 10] }, [
    Label({ text: `<span style="color:#${hex(RARITY.Epic)}">EPIC</span> Comet Collie [GOLD]  <span style="color:#7CFF8C">CAUGHT</span>`, rich: true,
      font: 'body', xa: 'l', size: sc(1, 1), max: 17 }),
  ]);
  return N({ name: 'MessageList', size: sc(1, 1), list: { dir: 'v', pad: 6, h: 'c' } }, [
    banner,
    toast('Your daily walk is ready!', [240, 130, 70], [['Claim', C.Good]], 1),
    toast('Bought Sticky Ball! Catch +15% for 5m', C.Good, [], 2),
  ]);
}
const PCS = fs.readFileSync(path.join(ROOT, 'src/shared/Cutscene/PlaceholderCutscene.luau'), 'utf8');
const BANNER = (() => {
  const m = PCS.match(/if large then (\d+) else (\d+)\), LayoutOrder = -math/);
  return { large: m ? Number(m[1]) : 58, small: m ? Number(m[2]) : 40 };
})();

function debugBtn() { return Button({ name: 'CutsceneTest', text: 'Test Cutscene', color: C.Purple, max: 16 }); }

// --- modal windows ------------------------------------------------------------------------------
const WSRC = fs.readFileSync(path.join(ROOT, 'src/client/UI/Components/Window.luau'), 'utf8');
const WIN = (() => {
  const bar = WSRC.match(/Size = UDim2\.new\(1, 0, 0, (\d+)\), Parent = frame/);
  const body = WSRC.match(/Name = "Body"[\s\S]*?Size = UDim2\.new\(1, (-?\d+), 1, (-?\d+)\),\s*Position = UDim2\.fromOffset\((\d+), (\d+)\)/);
  const close = WSRC.match(/Size = UDim2\.fromOffset\((\d+), (\d+)\),\s*Position = UDim2\.new\(1, (-?\d+), 0, (\d+)\)/);
  return { bar: bar ? +bar[1] : 44, body: body ? body.slice(1).map(Number) : [-20, -58, 10, 50], close: close ? close.slice(1).map(Number) : [36, 36, -6, 4] };
})();
function windowFrame(title, accent, titleColor, bodyKids, L) {
  // Window.fit(): bar = clamp(floor(h * 0.12), 34, 44); close = bar - 8; body at (10, bar + 6), size (1, -20, 1, -(bar + 14))
  const bar = Math.min(44, Math.max(34, Math.floor(L.Modal.H * 0.12)));
  const closeSz = bar - 8;
  return Panel({ name: 'Window_' + title, size: sc(1, 1) }, [
    N({ name: 'TitleBar', bg: accent, corner: T.Corner, size: U(1, 0, 0, bar) }, [
      N({ name: 'BarFill', bg: accent, size: U(1, 0, 0, 12), pos: U(0, 0, 1, -12) }),
      Label({ name: 'Title', text: title, color: titleColor || C.Text, xa: 'l', strokeText: 0.5, size: U(1, -64, 1, -8), pos: off(14, 4), max: T.TextMax.Title, z: 2 }),
      Button({ name: 'Close', text: 'X', color: C.Bad, max: 22, size: off(closeSz, closeSz), pos: U(1, WIN.close[2], 0, WIN.close[3]), anchor: [1, 0], z: 3 }),
    ]),
    N({ name: 'Body', size: U(1, -20, 1, -(bar + 14)), pos: off(10, bar + 6) }, bodyKids),
  ]);
}
const TABSRC = fs.readFileSync(path.join(ROOT, 'src/client/UI/Components/Tabs.luau'), 'utf8');
function tabs(names, selected, height, extra) {
  const wm = TABSRC.match(/math\.max\((\d+), #n \* (\d+) \+ (\d+)\)/);
  const [mn, per, add] = wm ? wm.slice(1).map(Number) : [72, 10, 24];
  return N(Object.assign({ name: 'Tabs', size: U(1, 0, 0, height), clip: true, list: { dir: 'h', pad: T.Spacing.S } }, extra || {}), names.map((n, i) =>
    Button({ name: 'Tab' + n, text: n, color: n === selected ? C.Accent : C.PanelLight, max: 18, size: U(0, Math.max(mn, n.length * per + add), 1, -4), order: i })));
}
const RLSRC = fs.readFileSync(path.join(ROOT, 'src/client/UI/Components/RowList.luau'), 'utf8');
const RL = (() => {
  const btnW = RLSRC.match(/if p\.ButtonText then (\d+) else 0/);
  const rowH = RLSRC.match(/p\.Height or (\d+)/);
  return { btnW: btnW ? +btnW[1] : 128, rowH: rowH ? +rowH[1] : 56 };
})();
function rowList(items, size, pos) {
  const kids = items.map((it, i) => {
    if (it.text) return Label({ name: 'Text', text: it.text, font: 'body', color: C.TextDim, xa: 'l', ya: 't', size: U(1, 0, 0, it.h || 40), order: i, max: T.TextMax.Small });
    if (it.header) return Label({ name: 'Header', text: it.header, color: C.Accent, xa: 'l', size: U(1, 0, 0, 26), order: i, max: T.TextMax.Normal });
    const h = it.height || RL.rowH;
    const btnW = it.button ? RL.btnW : 0;
    const textW = -(h + 6 + btnW + 12);
    return N({ name: 'Row', bg: C.PanelLight, corner: T.CornerSmall, size: U(1, 0, 0, h), order: i }, [
      N({ name: 'Swatch', bg: it.color, size: off(h - 12, h - 12), pos: off(6, 6), corner: T.CornerSmall, stroke: [C.Stroke, 2] },
        it.swatch ? [Label({ text: it.swatch, color: C.TextDark, size: sc(0.8, 0.8), pos: sc(0.1, 0.1), max: 22 })] : []),
      Label({ name: 'Title', text: it.title, xa: 'l', size: U(1, textW, 0.52, -4), pos: U(0, h + 4, 0, 4), max: T.TextMax.Normal }),
      Label({ name: 'Subtitle', text: it.sub, font: 'body', color: C.TextDim, xa: 'l', size: U(1, textW, 0.42, -4), pos: U(0, h + 4, 0.55, 0), max: T.TextMax.Small }),
      ...(it.button ? [Button({ name: 'Action', text: it.button, color: it.bcolor || C.Accent, max: 18, size: U(0, btnW, 1, -14), pos: U(1, -7, 0, 7), anchor: [1, 0] })] : []),
    ]);
  });
  return N({ name: 'RowList', size: size || sc(1, 1), pos: pos || sc(0, 0), clip: true, pad: [2, 4, 0, 12], list: { dir: 'v', pad: T.Spacing.S } }, kids);
}
const SHOPSRC = fs.readFileSync(path.join(ROOT, 'src/client/Controllers/ShopController.luau'), 'utf8');
function shopWindow(L) {
  const listTop = Number((SHOPSRC.match(/RowList\.new\(w\.Body, UDim2\.new\(1, 0, 1, -(\d+)\)/) || [0, 40])[1]);
  const tabH = Number((SHOPSRC.match(/Tabs\.new\(w\.Body, TAB_NAMES, function\(name\)[\s\S]*?end, (\d+)\)/) || [0, 34])[1]);
  const items = [
    { text: 'Balls are permanent. Better balls fly further and add luck to every throw.', h: 34 },
    { title: 'Tennis Ball', sub: 'Range x1.00 · Luck +0%', color: [205, 230, 70], button: 'Equip', bcolor: C.Info },
    { title: 'Rubber Ball', sub: 'Range x1.25 · Luck +10%', color: [230, 80, 80], button: 'Equipped', bcolor: C.Good },
    { title: 'Flying Disc', sub: 'Range x1.50 · Luck +20%', color: [80, 160, 255], button: '$25K', bcolor: C.Accent },
    { title: 'Glow Ball', sub: 'Range x1.75 · Luck +35%', color: [120, 255, 200], button: '$2.5M', bcolor: C.PanelInset },
    { title: 'Golden Ball', sub: 'Range x2.00 · Luck +50%', color: [255, 205, 60], button: '$250M', bcolor: C.PanelInset },
  ];
  return windowFrame('Shop', C.Accent, C.TextDark, [
    tabs(['Balls', 'Training', 'Boosts', 'Yard', 'Cosmetics', 'Robux'], 'Balls', tabH),
    rowList(items, U(1, 0, 1, -listTop), off(0, listTop)),
  ], L);
}
const BOOKSRC = fs.readFileSync(path.join(ROOT, 'src/client/Controllers/BookController.luau'), 'utf8');
function bookWindow(L) {
  const g = (re, d) => { const m = BOOKSRC.match(re); return m ? Number(m[1]) : d; };
  const zoneTabH = g(/zoneIdFromTab\(name\)[\s\S]*?end, (\d+)\)/, 28);
  const filterY = g(/Size = UDim2\.new\(1, 0, 0, \d+\), Position = UDim2\.fromOffset\(0, (\d+)\),\s*Parent = w\.Body/, 32);
  const filterH = g(/filterRow = Create\.New\("Frame", \{ BackgroundTransparency = 1, Size = UDim2\.new\(1, 0, 0, (\d+)\)/, 26);
  const mY = g(/Name = "Milestones"[\s\S]*?Position = UDim2\.fromOffset\(0, (\d+)\)/, 62);
  const mH = g(/Name = "Milestones", BackgroundTransparency = 1, Size = UDim2\.new\(1, 0, 0, (\d+)\)/, 26);
  const detH = g(/Name = "Detail"[\s\S]*?Size = UDim2\.new\(1, 0, 0, (\d+)\)/, 28);
  const gridTop = g(/Size = UDim2\.new\(1, 0, 1, -\d+\),\s*Position = UDim2\.fromOffset\(0, (\d+)\),\s*CellMinWidth/, 92);
  const gridCut = g(/Size = UDim2\.new\(1, 0, 1, -(\d+)\),\s*Position = UDim2\.fromOffset\(0, \d+\),\s*CellMinWidth/, 124);
  const cellMin = g(/CellMinWidth = (\d+)/, 84);
  const aspect = Number((BOOKSRC.match(/CellAspect = ([\d.]+)/) || [0, 1.05])[1]);
  const maxCols = g(/MaxColumns = (\d+)/, 10);
  const pad = g(/Padding = (\d+),\s*CreateCell/, 6);
  const zones = ['All', 'Backyard', 'Park', 'Beach', 'Farm', 'Forest', 'Snowy Peaks', 'City Rooftops', 'Space Station', 'Mythic Meadow'];
  const names = ['Biscuit', 'Sir Wigglesworth', 'Pebble', 'Doberman', 'Mutt', 'Saltwater Setter', 'Driftwood Doodle', 'Tidepool Terrier',
    'Sandy', 'Captain Barnacle', 'Mochi', 'Coral Corgi', 'Lighthouse Lab', 'Kelpie', 'Seafoam Spaniel', 'Gull Chaser', 'Shelly', 'Pier Pug',
    'Sunny', 'Boardwalk Beagle', 'Wave Rider', 'Scallop', 'Ripple', 'Harbor Hound'];
  const tiers = ['Common', 'Common', 'Common', 'Common', 'Uncommon', 'Rare', 'Common', 'Epic', 'Common', 'Legendary', 'Uncommon', 'Common',
    'Mythic', 'Common', 'Rare', 'Common', 'Common', 'Uncommon', 'Common', 'Common', 'Epic', 'Common', 'Common', 'Rare'];
  const cellNode = (i) => {
    const have = i % 3 !== 2;
    const tier = tiers[i % tiers.length];
    const variant = i === 5 ? 'GOLD' : i === 7 ? 'SHADOW' : i === 10 ? 'RAINBOW' : null;
    const vgrad = { GOLD: 'linear-gradient(90deg,#ffd84a,#c98b10)', SHADOW: 'linear-gradient(90deg,#3a2458,#8a4ad0)', RAINBOW: 'linear-gradient(90deg,#ff5050,#ffd84a,#50e070,#50a0ff,#c060ff)' };
    return N({ name: 'Cell', bg: have ? C.PanelLight : C.PanelInset, corner: T.CornerSmall, stroke: [RARITY[tier], 2] }, [
      N({ name: 'Swatch', bg: have ? [200 - i * 5, 150, 100 + i * 4] : C.Panel, size: sc(0.44, 0.44), pos: sc(0.5, 0.06), anchor: [0.5, 0], xx: true, clip: true, corner: 100, stroke: [C.Stroke, 2] },
        have ? [N({ name: 'Half', bg: [245, 240, 230], size: sc(0.5, 1), pos: sc(0.5, 0) })] : [Label({ text: '?', color: C.TextDim, max: 30 })]),
      Label({ name: 'DogName', text: have ? names[i % names.length] : '???', font: 'body', color: have ? C.Text : C.TextDim, size: U(1, -6, 0.25, 0), pos: U(0, 3, 0.57, 0), max: T.TextMax.Small }),
      Label({ name: 'Tier', text: tier, font: 'body', color: RARITY[tier], size: U(1, -8, 0.14, 0), pos: U(0, 4, 0.83, 0), max: T.TextMax.Tiny }),
      ...(variant ? [N({ name: 'VariantTag', bgCss: vgrad[variant], bg: [255, 255, 255], size: sc(0.86, 0.15), pos: sc(0.5, 0.4), anchor: [0.5, 0], corner: 6, stroke: [C.Stroke, 2] }, [
        Label({ name: 'VariantText', text: variant, font: 'body', strokeText: 0.4, wrap: false, size: U(1, -4, 1, 0), pos: off(2, 0), max: T.TextMax.Tiny })])] : []),
    ]);
  };
  // BookController.relayout(): compact mode when the window body is shorter than 300 px (values mirrored here)
  const barH = Math.min(44, Math.max(34, Math.floor(L.Modal.H * 0.12)));
  const bodyH = L.Modal.H - (barH + 14);
  const compact = bodyH > 0 && bodyH < 300;
  const K = compact
    ? { zoneH: 26, filterY: 30, filterH: 24, vtW: 1, mPos: U(0, 0, 1, -22), mSize: U(0.62, 0, 0, 22), gridPos: off(0, 58), gridSize: U(1, 0, 1, -84),
      detSize: U(1, -12, 0, 30), detPos: U(0, 6, 1, -58), progSize: U(0.37, 0, 0, 22), progPos: U(0.63, 0, 1, -22), cellMin: 84, aspect: 0.9, overlay: true }
    : { zoneH: zoneTabH, filterY, filterH, vtW: 0.62, mPos: off(0, mY), mSize: U(1, 0, 0, mH), gridPos: off(0, gridTop), gridSize: U(1, 0, 1, -gridCut),
      detSize: U(1, 0, 0, detH), detPos: U(0, 0, 1, -detH), progSize: U(0.37, 0, 0, 26), progPos: U(0.63, 0, 0, filterY), cellMin, aspect };
  const gridNode = N({ name: 'VirtualGrid', size: K.gridSize, pos: K.gridPos, clip: true, gridSpec: { cellMin: K.cellMin, aspect: K.aspect, maxCols, pad }, cellNode });
  const milestones = [['25% done', C.PanelInset], ['50% +Luck', C.Good], ['75% Trophy', C.PanelLight], ['100% Title', C.PanelLight]];
  return windowFrame('Kennel Book', C.Info, C.Text, [
    tabs(zones, 'Beach', K.zoneH),
    N({ name: 'FilterRow', size: U(1, 0, 0, K.filterH), pos: off(0, K.filterY) }, [
      tabs(['All forms', 'Base', 'Gold', 'Shadow', 'Rainbow'], 'All forms', K.filterH, { size: U(K.vtW, 0, 1, 0) }),
    ]),
    Label({ name: 'Progress', text: '41 / 179 forms', font: 'body', xa: 'r', size: K.progSize, pos: K.progPos, max: T.TextMax.Small }),
    N({ name: 'Milestones', size: K.mSize, pos: K.mPos, list: { dir: 'h', pad: 6 } }, milestones.map(([t, c], i) =>
      Button({ name: 'Milestone', text: t, color: c, max: 16, size: U(0.25, -6, 1, 0), order: i }))),
    gridNode,
    Label({ name: 'Detail', pad: [2, 2, 6, 6], corner: T.CornerSmall, bg: K.overlay ? C.PanelLight : undefined, bgT: 0.05, z: 5, text: '<b>Captain Barnacle</b> · <span style="color:#FFAA1E">Legendary</span> · Beach · $800/s', rich: true, font: 'body', color: C.TextDim, xa: 'l',
      size: K.detSize, pos: K.detPos, max: T.TextMax.Small }),
  ], L);
}
function expandGrids(root) {
  walk(root, (n) => {
    if (!n.gridSpec) return;
    const { cellMin, aspect, maxCols, pad } = n.gridSpec;
    const width = n.r.w - 10;
    let cols = Math.max(1, Math.floor((width - pad) / (cellMin + pad)));
    cols = Math.min(cols, maxCols);
    const cw = (width - pad * (cols + 1)) / cols;
    const ch = cw * aspect;
    const rows = Math.ceil(n.r.h / (ch + pad)) + 1;
    n.gridInfo = { cols, cw, ch, visibleRows: (n.r.h - pad) / (ch + pad) };
    n.children = [];
    for (let i = 0; i < cols * rows; i++) {
      const c = n.cellNode(i);
      c.size = off(cw, ch);
      c.pos = off(pad + (i % cols) * (cw + pad), pad + Math.floor(i / cols) * (ch + pad));
      n.children.push(c);
    }
    for (const c of n.children) resolve(c, n.content, null);
  });
}

// ------------------------------------------------------------------------------------------------
// Scene assembly
// ------------------------------------------------------------------------------------------------
const TOPBAR = 58;
const DEVICES = [
  { id: '1920x1080', w: 1920, h: 1080, touch: false, inset: { t: TOPBAR, l: 0, r: 0, b: 0 } },
  { id: '1366x768', w: 1366, h: 768, touch: false, inset: { t: TOPBAR, l: 0, r: 0, b: 0 } },
  // iPhone-class landscape: notch insets left/right + home indicator bottom, Roblox top bar on top.
  { id: '844x390', w: 844, h: 390, touch: true, inset: { t: TOPBAR, l: 47, r: 47, b: 21 } },
];
const PHONE_JUMP_RESERVE = 140; // screen-corner box kept free for the Roblox touch jump button

function buildScene(dev, modal) {
  const sw = dev.w - dev.inset.l - dev.inset.r;
  const shgt = dev.h - dev.inset.t - dev.inset.b;
  const L = computeLayout(sw, shgt, dev.touch);
  const safe = { x: dev.inset.l, y: dev.inset.t, w: sw, h: shgt };
  const regionDefs = {
    Currencies: currencies(L), Feed: feed(L), Messages: messages(L), Rail: rail(L), Boosts: boosts(L),
    ThrowPanel: throwPanel(L, 0.66), Debug: debugBtn(),
  };
  const regions = Object.entries(regionDefs).map(([name, content]) => {
    const r = L[name];
    return N({ name: 'Region_' + name, region: name, size: off(r.W, r.H), pos: off(r.X, r.Y) }, [content]);
  });
  const hud = N({ name: 'HUD', size: off(sw, shgt), pos: off(0, 0) }, regions);
  resolve(hud, safe, null);
  // post passes needing resolved sizes: currency value holders (offset by icon width), throw "Left" width
  walk(hud, (n, p) => {
    if (n.fitIcon) { const rh = p.r.h; n.pos = off(rh + 6, 0); n.size = U(1, -(rh + 6), 1, 0); }
    if (n.leftOfThrow) { const btn = p.children.find((c) => c.name === 'ThrowButton'); n.size = U(1, -(btn.r.w + 8), 1, 0); }
  });
  resolve(hud, safe, null);
  let modalRoot = null;
  if (modal) {
    const win = modal === 'shop' ? shopWindow(L) : bookWindow(L);
    modalRoot = N({ name: 'ModalHost', size: off(L.Modal.W, L.Modal.H), pos: off(L.Modal.X, L.Modal.Y) }, [win]);
    resolve(modalRoot, safe, null);
    expandGrids(modalRoot);
  }
  return { L, safe, hud, modalRoot };
}

const inter = (a, b) => a.x < b.x + b.w - 0.01 && b.x < a.x + a.w - 0.01 && a.y < b.y + b.h - 0.01 && b.y < a.y + a.h - 0.01;
function audit(dev, scene) {
  const problems = [];
  const { L, safe, hud, modalRoot } = scene;
  const regions = hud.children.map((c) => ({ name: c.region, r: c.r }));
  // pairwise region overlaps (+ outer stroke of 3 px)
  for (let i = 0; i < regions.length; i++) for (let j = i + 1; j < regions.length; j++) {
    if (inter(regions[i].r, regions[j].r)) problems.push(`overlap: ${regions[i].name} x ${regions[j].name}`);
  }
  const topbar = { x: 0, y: 0, w: dev.w, h: TOPBAR };
  const jump = dev.touch ? { x: dev.w - PHONE_JUMP_RESERVE, y: dev.h - PHONE_JUMP_RESERVE, w: PHONE_JUMP_RESERVE, h: PHONE_JUMP_RESERVE } : null;
  walk(hud, (n, p) => {
    if (!n.r || n.r.w <= 0) return;
    if (n.name === 'HUD' || n.badge) return; // notification badges overhang their button by design (3 px)
    const r = n.r;
    if (inter(r, topbar)) problems.push(`under top bar: ${n.name}`);
    if (jump && inter(r, jump)) problems.push(`under jump button reserve: ${n.name}`);
    if (r.x < -0.5 || r.y < -0.5 || r.x + r.w > dev.w + 0.5 || r.y + r.h > dev.h + 0.5) problems.push(`off-screen: ${n.name}`);
    if (p && p.region && (r.x < p.r.x - 0.5 || r.y < p.r.y - 0.5 || r.x + r.w > p.r.x + p.r.w + 0.5 || r.y + r.h > p.r.y + p.r.h + 0.5))
      problems.push(`escapes region ${p.region}: ${n.name}`);
  });
  // list overflow inside regions (Messages / Boosts / Rail)
  walk(hud, (n) => {
    if (!n.list || !n.r) return;
    const kids = n.children.filter((c) => c.visible !== false && c.r);
    if (!kids.length) return;
    const first = n.list.dir === 'h' ? Math.min(...kids.map((c) => c.r.x)) : Math.min(...kids.map((c) => c.r.y));
    const start = n.list.dir === 'h' ? n.content.x : n.content.y;
    if (first < start - 0.5 && !n.clip) problems.push(`list overflow at start (${(start - first).toFixed(0)} px): ${n.name}`);
    const last = n.list.dir === 'h' ? Math.max(...kids.map((c) => c.r.x + c.r.w)) : Math.max(...kids.map((c) => c.r.y + c.r.h));
    const end = n.list.dir === 'h' ? n.content.x + n.content.w : n.content.y + n.content.h;
    if (last > end + 0.5 && !n.clip && n.name !== 'MessageList') problems.push(`list overflow (${(last - end).toFixed(0)} px): ${n.name}`);
    if (n.name === 'MessageList' && last > end + 0.5) problems.push(`(info) message stack trims ${(last - end).toFixed(0)} px of toasts at runtime`);
  });
  if (modalRoot) {
    walk(modalRoot, (n) => {
      if (!n.r) return;
      if (inter(n.r, topbar)) problems.push(`modal under top bar: ${n.name}`);
    });
    walk(modalRoot, (n) => { if (n.gridInfo) {
      const gi = n.gridInfo;
      if (gi.visibleRows < 1.8) problems.push(`book grid shows only ${gi.visibleRows.toFixed(2)} rows`);
    } });
  }
  return problems;
}

// ------------------------------------------------------------------------------------------------
// Rendering
// ------------------------------------------------------------------------------------------------
function fontFaces() {
  const cache = path.join(os.tmpdir(), 'hud-preview-fonts');
  fs.mkdirSync(cache, { recursive: true });
  const want = [
    ['Fredoka One', 400, 'https://fonts.googleapis.com/css2?family=Fredoka+One'],
    ['Montserrat', 700, 'https://fonts.googleapis.com/css2?family=Montserrat:wght@700'],
    ['Montserrat', 500, 'https://fonts.googleapis.com/css2?family=Montserrat:wght@500'],
  ];
  let out = '';
  for (const [fam, wt, url] of want) {
    const file = path.join(cache, `${fam.replace(/ /g, '')}-${wt}.ttf`);
    try {
      if (!fs.existsSync(file)) {
        const cssText = execFileSync('curl', ['-sS', '-m', '15', url], { encoding: 'utf8' });
        const src = cssText.match(/url\((https:[^)]+\.ttf)\)/);
        if (!src) throw new Error('no ttf');
        execFileSync('curl', ['-sS', '-m', '30', '-o', file, src[1]]);
      }
      const b64 = fs.readFileSync(file).toString('base64');
      out += `@font-face{font-family:'${fam}';font-weight:${wt};src:url(data:font/ttf;base64,${b64}) format('truetype');}`;
    } catch (e) {
      console.warn(`[hud_preview] font ${fam} unavailable (${e.message}); using fallback`);
    }
  }
  return out;
}

function topbarHtml(dev) {
  // Roblox top bar: menu / chat / backpack buttons on the left, 44 px buttons with 12 px margin.
  const btn = (x, label) => `<div class="tb" style="left:${x}px">${label}</div>`;
  return `<div class="topbar" style="height:${TOPBAR}px">${btn(dev.inset.l + 12, '≡')}${btn(dev.inset.l + 64, '💬')}${btn(dev.w - dev.inset.r - 56, '⋯')}</div>`;
}
function jumpHtml(dev) {
  if (!dev.touch) return '';
  const small = Math.min(dev.w, dev.h) <= 500;
  const size = small ? 70 : 120;
  const x = dev.w - (small ? 95 : 170), y = dev.h - (small ? 90 : 140);
  return `<div class="jumpres" style="left:${dev.w - PHONE_JUMP_RESERVE}px;top:${dev.h - PHONE_JUMP_RESERVE}px;width:${PHONE_JUMP_RESERVE}px;height:${PHONE_JUMP_RESERVE}px"></div>
    <div class="jump" style="left:${x}px;top:${y}px;width:${size}px;height:${size}px">⤒</div>
    <div class="thumb" style="left:${dev.inset.l + 30}px;top:${dev.h - 150}px"></div>`;
}

function page(dev, scene, label, faces) {
  const { safe, hud, modalRoot } = scene;
  const root = { x: 0, y: 0 };
  let body = `<div style="position:absolute;inset:0;isolation:isolate">${emit(hud, root)}</div>`;
  if (modalRoot) {
    body += `<div class="backdrop" style="background:rgba(0,0,0,${1 - T.Backdrop})"></div>`;
    body += `<div style="position:absolute;inset:0;isolation:isolate">${emit(modalRoot, root)}</div>`;
  }
  return `<!doctype html><html><head><meta charset="utf-8"><style>${faces}
  *{box-sizing:border-box;margin:0;padding:0}
  html,body{width:${dev.w}px;height:${dev.h}px;overflow:hidden}
  body{position:relative;background:linear-gradient(180deg,#8fd3ff 0%,#bfe8ff 38%,#7cc36a 38.2%,#5aa04c 70%,#c9b38a 70.2%,#b59c70 100%);font-family:'Fredoka One',sans-serif}
  .g{position:absolute}
  .t{position:absolute;display:flex;overflow:visible;line-height:1.0;letter-spacing:0}
  .t>span{display:block}
  .topbar{position:absolute;left:0;top:0;width:100%;}
  .tb{position:absolute;top:7px;width:44px;height:44px;border-radius:22px;background:rgba(18,21,27,.72);color:#fff;font:20px sans-serif;display:flex;align-items:center;justify-content:center}
  .jumpres{position:absolute;border:2px dashed rgba(255,60,60,.8);background:rgba(255,60,60,.08)}
  .jump{position:absolute;border-radius:50%;background:rgba(255,255,255,.35);border:3px solid rgba(255,255,255,.7);color:#fff;font:28px sans-serif;display:flex;align-items:center;justify-content:center}
  .thumb{position:absolute;width:120px;height:120px;border-radius:50%;border:3px solid rgba(255,255,255,.35)}
  .backdrop{position:absolute;inset:0}
  .label{position:absolute;right:6px;top:${TOPBAR + 2}px;font:11px monospace;color:#123;background:rgba(255,255,255,.6);padding:1px 4px;border-radius:3px;z-index:99}
  .t.bad{outline:2px solid #f0f}
  </style></head><body>
  <div style="position:absolute;left:${dev.w * 0.48}px;top:${dev.h * 0.42}px;width:${dev.w * 0.04}px;height:${dev.h * 0.12}px;background:#d9a066;border-radius:8px"></div>
  ${topbarHtml(dev)}${body}${jumpHtml(dev)}
  <div class="label">${dev.id} · ${label}</div>
  <script>
  // TextScaled + UITextSizeConstraint: largest size <= MaxTextSize that fits; below MinTextSize = truncation.
  window.__textReport = [];
  for (const el of document.querySelectorAll('.t')) {
    const span = el.firstElementChild;
    const max = +el.dataset.max, min = +el.dataset.min;
    const W = el.clientWidth, Hh = el.clientHeight;
    const fits = (s) => { el.style.fontSize = s + 'px'; span.style.maxWidth = W + 'px'; return span.scrollWidth <= W + 0.5 && span.offsetHeight <= Hh + 0.5 && span.scrollHeight <= Hh + 0.5; };
    const fixed = +el.dataset.fixed;
    // alternative runtime strings for the same label: each must fit too (checked, then the shown text is restored)
    const shown = span.innerHTML;
    for (const alt of JSON.parse(el.dataset.alt || '[]')) {
      span.textContent = alt;
      let ok = false;
      for (let s2 = Math.min(max, Math.floor(Hh)); s2 >= min; s2--) { if (fits(s2)) { ok = true; break; } }
      if (!ok) window.__textReport.push({ name: el.dataset.name + ' (alt)', text: alt, size: min, truncated: true, box: [W, Hh] });
    }
    span.innerHTML = shown;
    let lo = 1, hi = Math.max(1, Math.floor(Math.min(max, Hh))), best = 0;
    if (fixed) { best = fits(fixed) ? fixed : 0; }
    else while (lo <= hi) { const mid = (lo + hi) >> 1; if (fits(mid)) { best = mid; lo = mid + 1; } else hi = mid - 1; }
    const size = fixed || Math.max(best, min);
    el.style.fontSize = size + 'px';
    const truncated = best < min;
    if (truncated) el.classList.add('bad');
    window.__textReport.push({ name: el.dataset.name, text: span.textContent, size, truncated, box: [W, Hh] });
  }
  </script></body></html>`;
}

async function main() {
  const { chromium } = require('playwright');
  fs.mkdirSync(OUT, { recursive: true });
  const faces = fontFaces();
  const browser = await chromium.launch();
  let failed = false;
  const summary = [];
  for (const dev of DEVICES) {
    for (const [modal, label] of [[null, 'hud'], ['shop', 'shop'], ['book', 'book']]) {
      uid = 0;
      const scene = buildScene(dev, modal);
      const problems = audit(dev, scene);
      const html = page(dev, scene, label, faces);
      const pg = await browser.newPage({ viewport: { width: dev.w, height: dev.h }, deviceScaleFactor: 1 });
      await pg.setContent(html, { waitUntil: 'load' });
      await pg.evaluate(() => document.fonts.ready);
      const text = await pg.evaluate(() => window.__textReport);
      const file = path.join(OUT, `${label}_${dev.id}.png`);
      await pg.screenshot({ path: file });
      await pg.close();
      const truncated = text.filter((t) => t.truncated);
      const tiny = text.filter((t) => !t.truncated && t.size < 10 && t.text.trim());
      for (const t of truncated) problems.push(`text does not fit at MinTextSize: [${t.name}] "${t.text}" box ${t.box.map(Math.round).join('x')}`);
      for (const t of tiny) problems.push(`(warn) small text ${t.size}px: [${t.name}] "${t.text}"`);
      const hard = problems.filter((p) => !p.startsWith('(warn)') && !p.startsWith('(info)'));
      if (hard.length) failed = true;
      summary.push({ file: path.relative(ROOT, file), scale: +scene.L.Scale.toFixed(3), problems });
      if (label === 'hud' && process.argv.includes('--layout')) console.log(dev.id, JSON.stringify(scene.L));
    }
  }
  await browser.close();
  for (const s of summary) {
    console.log(`${s.file}  (UI scale ${s.scale})`);
    if (!s.problems.length) console.log('   OK');
    for (const p of s.problems) console.log('   - ' + p);
  }
  process.exitCode = failed ? 1 : 0;
}

main().catch((e) => { console.error(e); process.exit(2); });
