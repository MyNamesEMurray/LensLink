# App Store screenshots

Turns raw device captures into the captioned, framed screenshots the
store listing uses, at the exact sizes App Store Connect accepts:
**1320 × 2868** (6.9-inch iPhone) and **2064 × 2752** (13-inch iPad).

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

   Output lands in `out/`, one file per shot and device, ready to upload.
   `--only home,live-glance` renders a subset; `--raw` and `--out`
   point elsewhere.

Shots marked `"statusBar": true` in `shots.json` get their battery pill
repainted as a full white battery, so a capture taken on a low phone
doesn't ship with a red one; the time and signal icons stay as taken.

`raw/` and `out/` are ignored by git: captures are large and personal to
the device they came from, and the output is regenerated in seconds.
Edit `template.html` for the frame and typography, `shots.json` for
copy; the sizes live at the top of `render.js`.
