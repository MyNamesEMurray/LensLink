#!/usr/bin/env node
// Composes App Store screenshots: a headline, a subline and the raw
// device capture in a bezel, at the exact pixel sizes App Store Connect
// accepts. Raw captures go in raw/<name>-iphone.png and
// raw/<name>-ipad.png (the names are in shots.json); output lands in
// out/. Needs Node and Playwright (npx playwright install chromium once).
//
//   node render.js [--raw DIR] [--out DIR] [--only name,name]
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (flag, dflt) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : dflt;
};
const here = __dirname;
const rawDir = path.resolve(opt('--raw', path.join(here, 'raw')));
const outDir = path.resolve(opt('--out', path.join(here, 'out')));
const only = opt('--only', '') ? opt('--only', '').split(',') : null;

// App Store Connect sizes: 6.9-inch iPhone and 13-inch iPad, portrait.
const DEVICES = {
  iphone: { w: 1320, h: 2868, pad: 120, h1: 104, p: 50, devw: 1120, radius: 140, bezel: 22 },
  ipad:   { w: 2064, h: 2752, pad: 140, h1: 120, p: 56, devw: 1700, radius: 100, bezel: 24 },
};

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require('/opt/node22/lib/node_modules/playwright'));
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

(async () => {
  const shots = JSON.parse(fs.readFileSync(path.join(here, 'shots.json'), 'utf8'));
  const template = fs.readFileSync(path.join(here, 'template.html'), 'utf8');
  fs.mkdirSync(outDir, { recursive: true });

  // No browser download needed: an installed Edge or Chrome is driven
  // directly, and Playwright's own Chromium is the last resort.
  const attempts = [];
  if (process.env.CHROMIUM_PATH) attempts.push({ executablePath: process.env.CHROMIUM_PATH });
  attempts.push({ channel: 'msedge' }, { channel: 'chrome' }, {});
  let browser, lastErr;
  for (const a of attempts) {
    try { browser = await chromium.launch({ headless: true, ...a }); break; }
    catch (e) { lastErr = e; }
  }
  if (!browser) throw lastErr;
  let made = 0, missing = [];

  for (const shot of shots) {
    if (only && !only.includes(shot.name)) continue;
    for (const [device, d] of Object.entries(DEVICES)) {
      const raw = path.join(rawDir, `${shot.name}-${device}.png`);
      if (!fs.existsSync(raw)) { missing.push(path.relative(process.cwd(), raw)); continue; }
      const img = 'data:image/png;base64,' + fs.readFileSync(raw).toString('base64');
      const html = template
        .replace(/{{W}}/g, d.w).replace(/{{H}}/g, d.h).replace(/{{PAD}}/g, d.pad)
        .replace(/{{H1}}/g, d.h1).replace(/{{P}}/g, d.p).replace(/{{DEVW}}/g, d.devw)
        .replace(/{{RADIUS}}/g, d.radius).replace(/{{BEZEL}}/g, d.bezel)
        .replace('{{HEADLINE}}', esc(shot.headline)).replace('{{SUB}}', esc(shot.sub))
        .replace('{{IMG}}', img)
        .replace('{{FULLBATTERY}}', shot.statusBar ? 'true' : 'false');
      const page = await browser.newPage({ viewport: { width: d.w, height: d.h }, deviceScaleFactor: 1 });
      await page.setContent(html, { waitUntil: 'load' });
      await page.waitForFunction(() => document.getElementById('shot').dataset.fullBattery !== 'true');
      const out = path.join(outDir, `${shot.name}-${device}.png`);
      await page.screenshot({ path: out, clip: { x: 0, y: 0, width: d.w, height: d.h } });
      await page.close();
      console.log('wrote', path.relative(process.cwd(), out));
      made++;
    }
  }
  await browser.close();
  if (missing.length) console.log('no raw capture for:\n  ' + missing.join('\n  '));
  console.log(`${made} screenshot(s) written to ${path.relative(process.cwd(), outDir) || '.'}`);
})().catch((e) => { console.error(e); process.exit(1); });
