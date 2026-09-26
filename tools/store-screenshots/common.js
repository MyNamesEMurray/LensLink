const fs = require('fs');
const path = require('path');

// App Store Connect sizes, portrait. `raw` names which capture feeds
// each: the 6.5-inch set is rendered from the same iPhone captures as
// the 6.9-inch one (App Store Connect asks for one or the other).
const DEVICES = {
  'iphone-6.9': { raw: 'iphone', w: 1320, h: 2868, pad: 120, h1: 104, p: 50, devw: 1120, radius: 140, bezel: 22 },
  'iphone-6.5': { raw: 'iphone', w: 1284, h: 2778, pad: 116, h1: 101, p: 49, devw: 1090, radius: 136, bezel: 22 },
  'ipad-13':    { raw: 'ipad',   w: 2064, h: 2752, pad: 140, h1: 120, p: 56, devw: 1700, radius: 100, bezel: 24 },
};

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require('/opt/node22/lib/node_modules/playwright'));
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');

const captionsDir = path.join(__dirname, 'captions');
const AVAILABLE = fs.readdirSync(captionsDir).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5));

function loadCaptions(langs, shots) {
  const captions = {};
  for (const lang of langs) {
    if (!lang || lang === 'en') continue;
    const file = path.join(captionsDir, `${lang}.json`);
    if (!fs.existsSync(file)) throw new Error(`no captions/${lang}.json (have: en, ${AVAILABLE.join(', ')})`);
    captions[lang] = JSON.parse(fs.readFileSync(file, 'utf8'));
    for (const shot of shots) {
      const c = captions[lang][shot.name];
      if (!c || !c.headline || !c.sub) throw new Error(`captions/${lang}.json is missing "${shot.name}"`);
    }
  }
  return captions;
}

async function launchBrowser() {
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
  return browser;
}

module.exports = { DEVICES, AVAILABLE, esc, launchBrowser, loadCaptions };
