// Rough renders of the generated fetch field, for visual QA of the zone dressing (no Studio needed).
// Input: the part dump written by   lune run tools/worldcheck/zones.luau -- --dump=build/field_parts.json
// Output (PNG, headless Chromium via Playwright, drawn on a 2D canvas):
//   docs/qa/field/topdown.png        the whole field from above, in four 800-stud strips
//   docs/qa/field/platform.png       platform camera, ~(0, 55, 40) looking down +Z
//   docs/qa/field/platform_tele.png  same camera, narrow field of view (the far zones)
//   docs/qa/field/ballpov.png        ball POV ~15 studs up at x = 0, one panel per zone
// Parts are drawn as their oriented boxes (balls / round ellipsoids as discs), flat-shaded, coloured by Color,
// painter-sorted, with a distance haze. It is a rough proxy for the in-game look, not a renderer.
// Usage: node tools/worldcheck/zones_view.js [build/field_parts.json] [docs/qa/field]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const input = path.resolve(process.argv[2] || 'build/field_parts.json');
const outDir = path.resolve(process.argv[3] || 'docs/qa/field');
fs.mkdirSync(outDir, { recursive: true });
const data = JSON.parse(fs.readFileSync(input, 'utf8'));

// ---------------------------------------------------------------- drawing code (runs inside the page)
function renderInPage(data, view) {
  const NAMES = { Backyard: 'Backyard', Park: 'Park', Beach: 'Beach', Farm: 'Farm', Forest: 'Forest',
    SnowyPeaks: 'Snowy Peaks', CityRooftops: 'City Rooftops', SpaceStation: 'Space Station', MythicMeadow: 'Mythic Meadow' };
  const SKY = [178, 210, 245];
  const canvas = document.getElementById('c');
  canvas.width = view.w; canvas.height = view.h;
  const g = canvas.getContext('2d');
  const parts = data.parts;
  const sun = norm([-0.35, 0.85, -0.4]);
  function norm(v) { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; }
  function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
  function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
  function add(a, b) { return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; }
  function mul(a, k) { return [a[0] * k, a[1] * k, a[2] * k]; }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function rgb(c, k, fog, fogc) {
    const f = fog || 0, fc = fogc || SKY;
    const r = c.map((v, i) => Math.max(0, Math.min(255, (v * k) * (1 - f) + fc[i] * f)));
    return `rgb(${r[0] | 0},${r[1] | 0},${r[2] | 0})`;
  }
  function light(p, n) {
    let k = 0.62 + 0.42 * Math.max(0, dot(n, sun));
    if (p.m === 'Neon') k = 1.25;
    return k;
  }
  function corners(p) {
    const hx = mul(p.x, p.s[0] / 2), hy = mul(p.y, p.s[1] / 2), hz = mul(p.z, p.s[2] / 2);
    const out = [];
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1])
      out.push(add(add(add(p.c, mul(hx, sx)), mul(hy, sy)), mul(hz, sz)));
    return out; // index = (sx>0)*4 + (sy>0)*2 + (sz>0)
  }
  const FACES = [ // [corner indices], axis, sign
    [[4, 5, 7, 6], 'x', 1], [[0, 2, 3, 1], 'x', -1],
    [[2, 6, 7, 3], 'y', 1], [[0, 1, 5, 4], 'y', -1],
    [[1, 3, 7, 5], 'z', 1], [[0, 4, 6, 2], 'z', -1],
  ];
  function roundish(p) {
    if (p.sh === 'Ball') return true;
    if (p.sh === 'Ellipsoid') { const s = p.s.slice().sort((a, b) => a - b); return s[0] > 0.45 * s[2]; }
    return false;
  }

  g.fillStyle = `rgb(${SKY.join(',')})`;
  g.fillRect(0, 0, view.w, view.h);

  if (view.kind === 'top') {
    // four strips seen from above: +Z to the right, +X up (the platform view has +X on its left)
    const S = view.scale, strip = view.strip, xHalf = 160, pad = 26;
    const stripH = xHalf * 2 * S + pad;
    const order = parts.map((p, i) => i).sort((a, b) => (parts[a].c[1] + parts[a].s[1] / 2 * Math.abs(parts[a].y[1])) - (parts[b].c[1] + parts[b].s[1] / 2 * Math.abs(parts[b].y[1])));
    for (let k = 0; k < 4; k++) {
      const z0 = 60 + k * strip, z1 = z0 + strip, oy = k * stripH + pad;
      g.save();
      g.beginPath(); g.rect(0, oy, strip * S, xHalf * 2 * S); g.clip();
      g.fillStyle = '#3a3f46'; g.fillRect(0, oy, strip * S, xHalf * 2 * S);
      const P = (v) => [(v[2] - z0) * S, oy + (xHalf - v[0]) * S];
      for (const i of order) {
        const p = parts[i];
        const ext = Math.max(p.s[0], p.s[1], p.s[2]);
        if (p.c[2] + ext < z0 || p.c[2] - ext > z1) continue;
        const top = p.c[1];
        const k2 = Math.min(1.3, 0.8 + Math.max(0, top) / 60);
        g.fillStyle = rgb(p.col, p.m === 'Neon' ? 1.2 : k2);
        if (roundish(p)) {
          const [px, py] = P(p.c);
          const r = Math.max(p.s[0], p.s[2]) / 2 * S;
          g.beginPath(); g.arc(px, py, Math.max(0.6, r), 0, Math.PI * 2); g.fill();
          continue;
        }
        const pts = corners(p).map(P);
        // convex hull of the projected corners
        pts.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
        const crossz = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
        const lower = [], upper = [];
        for (const q of pts) { while (lower.length >= 2 && crossz(lower[lower.length - 2], lower[lower.length - 1], q) <= 0) lower.pop(); lower.push(q); }
        for (let j = pts.length - 1; j >= 0; j--) { const q = pts[j]; while (upper.length >= 2 && crossz(upper[upper.length - 2], upper[upper.length - 1], q) <= 0) upper.pop(); upper.push(q); }
        const hull = lower.slice(0, -1).concat(upper.slice(0, -1));
        g.beginPath(); hull.forEach((q, j) => j ? g.lineTo(q[0], q[1]) : g.moveTo(q[0], q[1])); g.closePath(); g.fill();
      }
      // field edge + zone starts
      g.strokeStyle = 'rgba(255,255,255,0.5)'; g.lineWidth = 1;
      g.strokeRect(0, oy + (xHalf - 120) * S, strip * S, 240 * S);
      g.restore();
      g.fillStyle = '#fff'; g.font = '13px sans-serif';
      g.fillText(`z ${z0} .. ${z1}  (distance ${z0 - 60} .. ${z1 - 60})`, 6, oy - 8);
      for (const zn of data.zones) {
        if (zn.z0 >= z0 && zn.z0 < z1) {
          const x = (zn.z0 - z0) * S;
          g.fillStyle = 'rgba(0,0,0,0.55)'; g.fillRect(x + 2, oy + 2, g.measureText(NAMES[zn.id]).width + 8, 18);
          g.fillStyle = '#fff'; g.fillText(NAMES[zn.id], x + 6, oy + 15);
        }
      }
    }
    return;
  }

  // ---------------------------------------------------------------- perspective
  function camera(pos, yaw, pitch, fov, vx, vy, vw, vh, fogDist) {
    const fwd = norm([Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), Math.cos(yaw) * Math.cos(pitch)]);
    const right = norm(cross([0, 1, 0], fwd)); // +X when looking down +Z... flip so screen right = -X? keep world +X on the left
    const up = cross(fwd, right);
    const f = (vh / 2) / Math.tan(fov / 2);
    const near = 0.5;
    const toCam = (v) => { const d = sub(v, pos); return [dot(d, right), dot(d, up), dot(d, fwd)]; };
    const proj = (c) => [vx + vw / 2 - c[0] / c[2] * f, vy + vh / 2 - c[1] / c[2] * f];
    const polys = [];
    for (const p of parts) {
      const cc = toCam(p.c);
      const ext = Math.hypot(p.s[0], p.s[1], p.s[2]) / 2;
      if (cc[2] + ext < near) continue;
      if (cc[2] - ext > 4000) continue;
      const flat = (p.c[1] + Math.abs(p.y[1]) * p.s[1] / 2) <= 0.13 && p.s[1] <= 1.01;
      if (roundish(p)) {
        if (cc[2] < near + 0.1) continue;
        const [sx, sy] = proj(cc);
        const r = (p.s[0] + p.s[1] + p.s[2]) / 6 * f / cc[2];
        const fog = 1 - Math.exp(-Math.max(0, cc[2]) / fogDist);
        polys.push({ d: cc[2], flat: false, ball: [sx, sy, r], color: rgb(p.col, p.m === 'Neon' ? 1.25 : 0.95, fog) });
        continue;
      }
      const cs = corners(p);
      const camCs = cs.map(toCam);
      for (const [idx, axis, sign] of FACES) {
        const n = mul(p[axis], sign);
        const fc = mul(idx.reduce((a, i) => add(a, cs[i]), [0, 0, 0]), 0.25);
        if (dot(n, sub(fc, pos)) >= 0) continue; // back face
        // clip against the near plane
        let poly = idx.map((i) => camCs[i]);
        const out = [];
        for (let j = 0; j < poly.length; j++) {
          const a = poly[j], b = poly[(j + 1) % poly.length];
          const ina = a[2] >= near, inb = b[2] >= near;
          if (ina) out.push(a);
          if (ina !== inb) { const t = (near - a[2]) / (b[2] - a[2]); out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, near]); }
        }
        if (out.length < 3) continue;
        const dcen = out.reduce((s, q) => s + q[2], 0) / out.length;
        const fog = 1 - Math.exp(-Math.max(0, dcen) / fogDist);
        polys.push({ d: flat ? Math.max(...out.map((q) => q[2])) : dcen, flat, pts: out.map(proj), color: rgb(p.col, light(p, n), fog) });
      }
    }
    // ground layer first (far to near), then everything else (far to near)
    polys.sort((a, b) => (a.flat === b.flat ? b.d - a.d : (a.flat ? -1 : 1)));
    g.save();
    g.beginPath(); g.rect(vx, vy, vw, vh); g.clip();
    const grad = g.createLinearGradient(0, vy, 0, vy + vh);
    grad.addColorStop(0, 'rgb(120,170,235)'); grad.addColorStop(1, `rgb(${SKY.join(',')})`);
    g.fillStyle = grad; g.fillRect(vx, vy, vw, vh);
    for (const q of polys) {
      g.fillStyle = q.color;
      g.beginPath();
      if (q.ball) { g.arc(q.ball[0], q.ball[1], Math.max(0.5, q.ball[2]), 0, Math.PI * 2); }
      else { q.pts.forEach((s, j) => j ? g.lineTo(s[0], s[1]) : g.moveTo(s[0], s[1])); g.closePath(); }
      g.fill();
      if (!q.ball && !q.flat) { g.strokeStyle = 'rgba(0,0,0,0.08)'; g.lineWidth = 0.5; g.stroke(); }
    }
    g.restore();
  }
  if (view.kind === 'persp') {
    camera(view.pos, 0, view.pitch, view.fov, 0, 0, view.w, view.h, view.fog);
  } else if (view.kind === 'pov') {
    const cols = 3, pw = view.w / cols, ph = view.h / 3;
    data.zones.forEach((zn, i) => {
      const z = Math.max(zn.z0, 70) - 25 + 0.12 * (zn.z1 - zn.z0);
      const vx = (i % cols) * pw, vy = Math.floor(i / cols) * ph;
      camera([0, 15, z], 0, -0.22, 1.25, vx, vy, pw, ph, view.fog);
      g.fillStyle = 'rgba(0,0,0,0.55)'; g.fillRect(vx + 4, vy + 4, 230, 20);
      g.fillStyle = '#fff'; g.font = '13px sans-serif';
      g.fillText(`${NAMES[zn.id]}  cam (0, 15, ${Math.round(z)})`, vx + 9, vy + 18);
      g.strokeStyle = '#000'; g.lineWidth = 2; g.strokeRect(vx, vy, pw, ph);
    });
  }
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const views = [
    { file: 'topdown.png', kind: 'top', scale: 1.5, strip: 800, w: 1200, h: 4 * (320 * 1.5 + 26) + 4 },
    { file: 'platform.png', kind: 'persp', pos: [0, 55, 40], pitch: -0.2, fov: 1.2, w: 1600, h: 900, fog: 2600 },
    { file: 'platform_tele.png', kind: 'persp', pos: [0, 55, 40], pitch: -0.035, fov: 0.32, w: 1600, h: 900, fog: 5000 },
    { file: 'ballpov.png', kind: 'pov', w: 1920, h: 1080, fog: 700 },
  ];
  for (const v of views) {
    await page.setViewportSize({ width: v.w, height: v.h });
    await page.setContent(`<html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>`);
    await page.evaluate(`(${renderInPage.toString()})(${JSON.stringify(data)}, ${JSON.stringify(v)})`);
    await page.screenshot({ path: path.join(outDir, v.file), clip: { x: 0, y: 0, width: v.w, height: v.h } });
    console.log('wrote ' + path.join(outDir, v.file));
  }
  await browser.close();
})();
