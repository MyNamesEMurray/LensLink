#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { DEVICES, AVAILABLE, esc, launchBrowser, loadCaptions } = require('./common');

const args = process.argv.slice(2);
const opt = (flag, dflt) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : dflt;
};
const here = __dirname;
const inDir = path.resolve(opt('--in', path.join(here, 'english')));
const outDir = path.resolve(opt('--out', path.join(here, 'out')));
const langArg = opt('--lang', 'all');
const langs = langArg === 'all' ? AVAILABLE : langArg.split(',');

const BLANK = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==';

function pngSize(buf) {
  if (buf.toString('ascii', 1, 4) !== 'PNG') return null;
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

function pageHtml(template, d, lang, text, devTop, original) {
  const left = (d.w - d.devw) / 2;
  const overlay = `
  <style>
    .device { position: absolute; top: ${devTop}px; left: ${left}px; margin: 0; height: ${d.h - devTop}px; }
    #orig { position: absolute; left: 0; top: 0; width: ${d.w}px; height: ${d.h}px; clip-path: inset(${devTop - 2}px 0 0 0); }
  </style>
  <img id="orig" src="${original}" alt="">
</body>`;
  return template
    .replace(/{{W}}/g, d.w).replace(/{{H}}/g, d.h).replace(/{{PAD}}/g, d.pad)
    .replace(/{{H1}}/g, d.h1).replace(/{{P}}/g, d.p).replace(/{{DEVW}}/g, d.devw)
    .replace(/{{RADIUS}}/g, d.radius).replace(/{{BEZEL}}/g, d.bezel)
    .replace('{{LANG}}', lang)
    .replace('{{HEADLINE}}', esc(text.headline)).replace('{{SUB}}', esc(text.sub))
    .replace('{{IMG}}', BLANK)
    .replace('{{FULLBATTERY}}', 'false')
    .replace('{{BATTERY}}', '{}')
    .replace('</body>', overlay);
}

async function findFrameTop(page, original, d) {
  return page.evaluate(async ({ src, d }) => {
    const img = new Image();
    img.src = src;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = d.w; c.height = d.h;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    const x0 = Math.round((d.w - d.devw) / 2 + d.radius + 4);
    const x1 = Math.round((d.w + d.devw) / 2 - d.radius - 4);
    const rows = g.getImageData(x0, 0, x1 - x0, Math.round(d.h * 0.6)).data;
    const n = x1 - x0;
    for (let y = d.pad; y < d.h * 0.6; y++) {
      let hits = 0;
      for (let x = 0; x < n; x++) {
        const i = (y * n + x) * 4;
        if (Math.abs(rows[i] - 42) <= 8 && Math.abs(rows[i + 1] - 42) <= 8 && Math.abs(rows[i + 2] - 44) <= 8) hits++;
      }
      if (hits >= n * 0.95) return y + 2;
    }
    return null;
  }, { src: original, d });
}

async function render(browser, html, d, devTop, gap) {
  const page = await browser.newPage({ viewport: { width: d.w, height: d.h }, deviceScaleFactor: 1 });
  await page.setContent(html, { waitUntil: 'load' });
  await page.evaluate(({ limit }) => {
    const h1 = document.querySelector('h1');
    const p = document.querySelector('p');
    const h1Size = parseFloat(getComputedStyle(h1).fontSize);
    const pSize = parseFloat(getComputedStyle(p).fontSize);
    for (let scale = 1; scale >= 0.6 && p.getBoundingClientRect().bottom > limit; scale -= 0.02) {
      h1.style.fontSize = `${h1Size * scale}px`;
      p.style.fontSize = `${pSize * scale}px`;
    }
  }, { limit: devTop - gap });
  await page.evaluate(() => document.getElementById('orig').decode());
  const buf = await page.screenshot({ clip: { x: 0, y: 0, width: d.w, height: d.h } });
  await page.close();
  return buf;
}

async function captionDiff(page, a, b, d, bottom) {
  return page.evaluate(async ({ a, b, d, bottom }) => {
    const load = async (src) => {
      const img = new Image();
      img.src = src;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = d.w; c.height = bottom;
      c.getContext('2d').drawImage(img, 0, 0);
      return c.getContext('2d').getImageData(0, 0, d.w, bottom).data;
    };
    const [x, y] = await Promise.all([load(a), load(b)]);
    let sum = 0;
    for (let i = 0; i < x.length; i += 4) sum += Math.abs(x[i] - y[i]) + Math.abs(x[i + 1] - y[i + 1]) + Math.abs(x[i + 2] - y[i + 2]);
    return sum / (x.length / 4);
  }, { a, b, d, bottom });
}

(async () => {
  const shots = JSON.parse(fs.readFileSync(path.join(here, 'shots.json'), 'utf8'));
  const template = fs.readFileSync(path.join(here, 'template.html'), 'utf8');
  const captions = loadCaptions(langs, shots);
  if (!fs.existsSync(inDir)) throw new Error(`no ${path.relative(process.cwd(), inDir)}/ folder: put the English screenshots there`);
  const files = fs.readdirSync(inDir).filter((f) => /\.png$/i.test(f)).sort();
  if (!files.length) throw new Error(`no .png files in ${path.relative(process.cwd(), inDir)}/`);

  const browser = await launchBrowser();
  const tool = await browser.newPage();
  const byName = [...shots].sort((a, b) => b.name.length - a.name.length);
  let made = 0;
  const seen = new Map();

  for (const file of files) {
    const buf = fs.readFileSync(path.join(inDir, file));
    const size = pngSize(buf);
    const entry = size && Object.entries(DEVICES).find(([, d]) => d.w === size.w && d.h === size.h);
    if (!entry) {
      console.log(`skip ${file}: ${size ? `${size.w}x${size.h}` : 'not a PNG'} is not a store screenshot size`);
      continue;
    }
    const [device, d] = entry;
    const original = 'data:image/png;base64,' + buf.toString('base64');
    const devTop = await findFrameTop(tool, original, d);
    if (!devTop) {
      console.log(`skip ${file}: no device frame found`);
      continue;
    }

    let shot = byName.find((s) => file.toLowerCase().includes(s.name));
    if (!shot) {
      let best = Infinity;
      for (const s of shots) {
        const png = await render(browser, pageHtml(template, d, 'en', s, devTop, original), d, devTop, 0);
        const diff = await captionDiff(tool, original, 'data:image/png;base64,' + png.toString('base64'), d, devTop - 2);
        if (diff < best) { best = diff; shot = s; }
      }
    }
    const key = `${shot.name}-${device}`;
    if (seen.has(key)) {
      console.log(`skip ${file}: ${key} again (already from ${seen.get(key)})`);
      continue;
    }
    seen.set(key, file);
    console.log(`${file}: ${key}`);

    for (const lang of langs) {
      const html = pageHtml(template, d, lang, captions[lang][shot.name], devTop, original);
      const png = await render(browser, html, d, devTop, d.pad * 0.5);
      const dir = path.join(outDir, lang);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `${key}.png`), png);
      made++;
    }
  }
  await browser.close();
  console.log(`${made} screenshot(s) written to ${path.relative(process.cwd(), outDir) || '.'}`);
})().catch((e) => { console.error(e.message || e); process.exit(1); });
