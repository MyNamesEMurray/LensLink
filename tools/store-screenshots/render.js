#!/usr/bin/env node
// Composes App Store screenshots: a headline, a subline and the raw
// device capture in a bezel, at the exact pixel sizes App Store Connect
// accepts. Raw captures go in raw/<name>-iphone.png and
// raw/<name>-ipad.png (the names are in shots.json); output lands in
// out/. Needs Node and Playwright (npx playwright install chromium once).
//
//   node render.js [--raw DIR] [--out DIR] [--only name,name] [--lang de,ja|all]
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
const captionsDir = path.join(here, 'captions');
const available = fs.readdirSync(captionsDir).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5));
const langArg = opt('--lang', '');
const langs = !langArg ? [null] : langArg === 'all' ? ['en', ...available] : langArg.split(',');

// App Store Connect sizes, portrait. `raw` names which capture feeds
// each: the 6.5-inch set is rendered from the same iPhone captures as
// the 6.9-inch one (App Store Connect asks for one or the other).
const DEVICES = {
  'iphone-6.9': { raw: 'iphone', w: 1320, h: 2868, pad: 120, h1: 104, p: 50, devw: 1120, radius: 140, bezel: 22 },
  'iphone-6.5': { raw: 'iphone', w: 1284, h: 2778, pad: 116, h1: 101, p: 49, devw: 1090, radius: 136, bezel: 22 },
  'ipad-13':    { raw: 'ipad',   w: 2064, h: 2752, pad: 140, h1: 120, p: 56, devw: 1700, radius: 100, bezel: 24 },
};

// Where the battery pill sits in a capture, as fractions of its width
// and height, per capture kind: iPhone's status bar flanks the Dynamic
// Island, the iPad's is a thin strip along the top edge.
const BATTERY = {
  iphone: { sampleX: 0.835, y: 0.034, coverX: 0.84, coverW: 0.10, coverY: 0.022, coverH: 0.025, bx: 0.848, bw: 0.066, bh: 0.0145 },
  ipad:   { sampleX: 0.985, y: 0.0135, coverX: 0.926, coverW: 0.052, coverY: 0.005, coverH: 0.017, bx: 0.934, bw: 0.028, bh: 0.0095 },
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
  const captions = {};
  for (const lang of langs) {
    if (!lang || lang === 'en') continue;
    const file = path.join(captionsDir, `${lang}.json`);
    if (!fs.existsSync(file)) throw new Error(`no captions/${lang}.json (have: en, ${available.join(', ')})`);
    captions[lang] = JSON.parse(fs.readFileSync(file, 'utf8'));
    for (const shot of shots) {
      const c = captions[lang][shot.name];
      if (!c || !c.headline || !c.sub) throw new Error(`captions/${lang}.json is missing "${shot.name}"`);
    }
  }

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
  let made = 0;
  const missing = new Set();

  for (const lang of langs) {
    const langOut = lang ? path.join(outDir, lang) : outDir;
    fs.mkdirSync(langOut, { recursive: true });
    for (const shot of shots) {
      if (only && !only.includes(shot.name)) continue;
      const text = captions[lang] ? captions[lang][shot.name] : shot;
      for (const [device, d] of Object.entries(DEVICES)) {
        const raw = path.join(rawDir, `${shot.name}-${d.raw}.png`);
        if (!fs.existsSync(raw)) { missing.add(path.relative(process.cwd(), raw)); continue; }
        const img = 'data:image/png;base64,' + fs.readFileSync(raw).toString('base64');
        const html = template
          .replace(/{{W}}/g, d.w).replace(/{{H}}/g, d.h).replace(/{{PAD}}/g, d.pad)
          .replace(/{{H1}}/g, d.h1).replace(/{{P}}/g, d.p).replace(/{{DEVW}}/g, d.devw)
          .replace(/{{RADIUS}}/g, d.radius).replace(/{{BEZEL}}/g, d.bezel)
          .replace('{{LANG}}', lang || 'en')
          .replace('{{HEADLINE}}', esc(text.headline)).replace('{{SUB}}', esc(text.sub))
          .replace('{{IMG}}', img)
          .replace('{{FULLBATTERY}}', shot.statusBar ? 'true' : 'false')
          .replace('{{BATTERY}}', JSON.stringify(BATTERY[d.raw]));
        const page = await browser.newPage({ viewport: { width: d.w, height: d.h }, deviceScaleFactor: 1 });
        await page.setContent(html, { waitUntil: 'load' });
        await page.waitForFunction(() => document.getElementById('shot').dataset.fullBattery !== 'true');
        const out = path.join(langOut, `${shot.name}-${device}.png`);
        await page.screenshot({ path: out, clip: { x: 0, y: 0, width: d.w, height: d.h } });
        await page.close();
        console.log('wrote', path.relative(process.cwd(), out));
        made++;
      }
    }
  }
  await browser.close();
  if (missing.size) console.log('no raw capture for:\n  ' + [...missing].join('\n  '));
  console.log(`${made} screenshot(s) written to ${path.relative(process.cwd(), outDir) || '.'}`);
})().catch((e) => { console.error(e); process.exit(1); });
