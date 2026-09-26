# App Store screenshots

Turns raw device captures into the captioned, framed screenshots the
store listing uses, at the exact sizes App Store Connect accepts:
**1320 × 2868** (6.9-inch iPhone), **1284 × 2778** (6.5-inch iPhone,
from the same captures) and **2064 × 2752** (13-inch iPad).

1. Take the captures on device (Volume up + Side button). The list of
   shots, their headlines and the order they appear in is `shots.json`;
   `docs/APP_STORE.md` says what each one should show.
2. Drop them in `raw/` as `<name>-iphone.png` and `<name>-ipad.png`,
   e.g. `raw/home-iphone.png`. Any iPhone or iPad capture works; it is
   scaled to fit the bezel.
3. Render:

   ```bash
   cd tools/store-screenshots
   npm install playwright   # once; no browser download needed
   node render.js
   ```

   It drives the Edge or Chrome already on the machine. Only if neither
   is installed does it need `npx playwright install chromium`.

   Output lands in `out/` as `<name>-iphone-6.9.png`,
   `<name>-iphone-6.5.png` and `<name>-ipad-13.png`, ready to upload.
   Upload whichever iPhone size the App Store Connect slot asks for.
   `--only home,live-glance` renders a subset; `--raw` and `--out`
   point elsewhere.

## Other languages

The same captures, with the headline and subline translated:

```bash
node render.js --lang all      # English plus every language below
node render.js --lang de,ja    # just these
```

Each language lands in its own folder, `out/<lang>/`, with the same file
names; upload a folder to the matching localization in App Store
Connect (`es` serves both Spanish (Mexico) and Spanish (Spain)). The
translations are `captions/<lang>.json`: one entry per shot in
`shots.json`, and the render stops if one is missing, so a new shot
needs its caption in every file. They follow the glossary in
`docs/LOCALIZATION.md`. Without `--lang`, English renders into `out/`
as before.

Shots marked `"statusBar": true` in `shots.json` get their battery pill
repainted as a full white battery, so a capture taken on a low phone
doesn't ship with a red one; the time and signal icons stay as taken.

`raw/` and `out/` are ignored by git: captures are large and personal to
the device they came from, and the output is regenerated in seconds.
Edit `template.html` for the frame and typography, `shots.json` for
copy; the sizes live at the top of `render.js`.
