// Renders build/ui-preview/*.svg to PNG with headless Chromium (Playwright), for visual review.
//   node tools/uicheck/screenshot.js [svgDir] [outDir] [filter]
//   e.g. node tools/uicheck/screenshot.js build/ui-preview docs/qa/reveal reveal-
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const dir = path.resolve(process.argv[2] || 'build/ui-preview');
  const out = path.resolve(process.argv[3] || dir);
  const filter = process.argv[4] || '';
  fs.mkdirSync(out, { recursive: true });
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.svg') && f.includes(filter));
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const f of files) {
    const svg = fs.readFileSync(path.join(dir, f), 'utf8');
    const m = svg.match(/width="(\d+)" height="(\d+)"/);
    const w = parseInt(m[1]), h = parseInt(m[2]);
    await page.setViewportSize({ width: w, height: h });
    await page.setContent(`<html><body style="margin:0;background:#222">${svg}</body></html>`);
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(out, f.replace('.svg', '.png')), clip: { x: 0, y: 0, width: w, height: h } });
  }
  await browser.close();
  console.log(`rendered ${files.length} previews -> ${out}`);
})();
