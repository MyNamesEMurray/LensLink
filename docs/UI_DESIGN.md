# LensLink — UI Design System

This document defines the visual and interaction language shared by the two
user-facing surfaces of the project:

1. **The iOS app (LensLink)** — runs on the phone; two screens: **Setup**
   (before streaming) and **Live** (full-screen while streaming).
2. **The plugin's web control panel** — served on the PC at
   `http://localhost:9980`; a remote control surface for the operator at
   the computer.

They serve different vantage points (phone vs. PC) but must feel like one
product: same palette, same control metaphors, same status vocabulary.
This document is the single source of truth; the app's `DesignSystem.swift`
and the plugin's `web-control.c` page both implement the tokens below, and
any change here should be reflected in both.

---

## 1. Principles

- **The video is the interface.** On the Live screen and the web panel the
  camera image is the hero; controls float over it in translucent glass and
  never obscure the frame more than necessary.
- **One glance = status.** A single coloured dot + one word communicates
  connection state identically everywhere.
- **Same control, same shape.** Zoom, exposure, focus, flashlight, lens
  and flip mean the same thing and sit in the same order on the phone and
  in the browser. The phone folds them into one dial because a thumb on
  a viewfinder has less room than a mouse on a page; the web panel keeps
  a row per control.
- **Two layers on the phone.** The Live screen shows only what a stream
  needs at a glance; everything adjustable is one tap away in a tray.
  The Camera app has more controls than LensLink and feels simpler
  because almost none of them are visible at once.
- **Calm by default.** Muted surfaces, one accent colour, restrained
  motion. Nothing pulses or animates unless it reflects real state change.
- **Reversible & non-destructive.** Only Stop is destructive (red); every
  other control is a safe, adjustable value.

---

## 2. Colour

All colours are given as hex so the native app and the web page render
identically. The status palette intentionally mirrors iOS system semantic
colours so it also looks native on the phone.

### Accent
| Token            | Hex       | Use |
|------------------|-----------|-----|
| `accent`         | `#3D7BFF` | Primary actions, active toggles, slider fills, selection |
| `accentPressed`  | `#2E63E6` | Pressed/active state of accent controls |

### Status (dot + label)
| State        | Token         | Hex       | Label            |
|--------------|---------------|-----------|------------------|
| Idle         | `idleGrey`    | `#8E8E93` | "Not connected"  |
| Standby      | `connectAmber`| `#FF9F0A` | "OBS connected — ready" |
| Connecting   | `connectAmber`| `#FF9F0A` | "Waiting for OBS…" |
| Live         | `liveGreen`   | `#30D158` | "Live"           |
| Paused       | `connectAmber`| `#FF9F0A` | "Paused"         |
| Error        | `errorRed`    | `#FF453A` | *(the message)*  |

Paused is a **held** stream, not a broken one: connected, camera
running, no camera video going out — what OBS shows instead is the
phone's own held picture (the last frame blurred to grey with a pause
glyph), so a pause never looks like a stall. It takes the same amber as Standby and
Connecting — connected but not live — and is always the single word
"Paused". An operator pause (the Live screen's pause chip, the web
panel, the source properties) says exactly that; a pause iOS forced by
taking the camera keeps its explanatory message instead, because there
the sentence is the actionable part. Either way the plugin learns of it
through STATE and says so rather than sitting on a frozen picture.

Standby is the remote-start state: the app is idle but OBS is connected
and can start the camera. It shares the amber of Connecting — both mean
"linked, not yet live". On the web panel the standby state replaces the
(dead) camera controls with a single accent **Start camera** button;
while live, the panel ends in a red **Stop camera** button (Stop stays
the one destructive control, mirroring the app's red Stop chip).

While remote start is armed the phone holds its idle timer (auto-lock
would suspend the listener and kill remote start), so the Setup screen
reuses the Live screen's near-black tap-to-wake dim overlay — on a
60-second fuse instead of 10, with the icon in `connectAmber` rather
than `liveGreen` (armed, not live). The standby dim runs only when the
idle view is **Dim screen** (§6.2 — a clean feed means nothing on a
settings form), and it never fires while the user is interacting: any
touch resets the fuse, and it can't trigger while a sheet is open (the
overlay would sit behind the sheet with its tap-to-wake unreachable).

The status **word and colour are defined once** (`Streamer.Status.displayName`
/ `.tint` in the app) and reused by every view. The web panel colours its
pill from the `tone` the plugin reports with every status in
`/api/status` (`idle` grey, `wait` and `ready` amber, `live` green,
`error` red), never from the status text, which is translated. A stream
paused on the phone reports `ready`, and the moment between the TCP
connect and the phone's HELLO reports `wait`, so the pill never flashes
green before settling on standby.

### Tally (screen border)

A border around the whole Live screen, driven by a **user-ordered
priority list** of statuses (Options → Tally light): the highest status
in the list that is currently true and has a colour lights the border.
"Off" removes a status from consideration — lower ones show through.

| Status (default order) | Default colour | Meaning |
|---|---|---|
| On air | Red `tallyLive` `#FF3B30`, 6 pt | in OBS's live output |
| In preview | Amber `connectAmber` `#FF9F0A`, 4 pt | visible but not live |
| Connection lost | Off | streaming, link to OBS dropped |
| Calibrating lip-sync | Off | measuring / re-measuring |
| Lip-sync locked | Off | calibration locked on |
| Low battery | Off | Low Power Mode, or ≤ 20%, while unplugged |

Assignable colours: Red `#FF3B30`, Amber `#FF9F0A`, Green `#30D158`,
Blue `#3D7BFF`, Purple `tallyPurple` `#BF5AF2`, White, or Off. The
defaults reproduce the pre-customization behaviour exactly. On air keeps
the heaviest stroke (6 pt vs 4 pt) whatever its colour, so live stays
the most emphatic state.

Any lit status can also **pulse** instead of holding steady — off by
default on every status, so the calm-by-default principle holds until
somebody asks for motion (the button beside its colour): a 0.9 s ease
between full and 30% opacity — never to zero, so a glance during the
dark half still finds a border. Motion is
for a status you are meant to notice without watching for it, low battery
being the case it was added for. `accessibilityReduceMotion` turns every
pulse into a steady border of the same colour: less motion, never less
warning.

The tally's core answer — *am I on air?* — must never be ambiguous, so
it is **its own indicator**, not a mode of the status dot. It's a border
rather than a dot because it has to read at arm's length from a phone
mounted behind a monitor, and it draws **above the dim overlay**: the
screen dims after ten seconds exactly when the operator is furthest
away. By default an unlit tally is as meaningful as a lit one — "not on
air" draws nothing rather than a grey border that could be mistaken for
a dark red one.

`tallyLive` is deliberately separate from `errorRed` despite both being
red today: on air is not an error, and the two must stay independently
adjustable. Preview reuses `connectAmber` — it means the same thing the
amber statuses do, "linked, not yet live".

The border's corners are **rounded** (continuous curve, ~58 pt) on
devices whose display corners are rounded — a sharp-cornered stroke gets
physically clipped by the panel and visibly breaks at all four corners.
Squared displays (SE, iPads) keep square corners; erring on the large
side is fine, curving early looks intentional where getting clipped
looks broken.

### Lip-sync calibration (dot + label)

| State      | Token          | Hex       | Label            |
|------------|----------------|-----------|------------------|
| Off        | —              | —         | *(nothing shown)* |
| Measuring  | `accent`       | `#3D7BFF` | "Measuring sync" |
| Locked     | `liveGreen`    | `#30D158` | "Sync locked"    |
| Relocking  | `connectAmber` | `#FF9F0A` | "Recalibrating"  |

Shown on the Live screen on **its own row under the status bar** (the
top bar's three buttons left too little width — "Sync lo…" is worse than
nothing), and in the web panel's header as a second pill. Blue reads as
*working on it*, green as *done*, amber as *attention, transitional* —
the same reading those colours carry elsewhere in the product. Nothing
is drawn when auto-calibrate isn't running, so setups that don't use it
never see a readout they'd have to learn to ignore — and the web panel
also hides it while no phone is connected, because the plugin's lock
survives disconnects by design and "Lip-sync locked" beside "Trying to
reach the phone" reads as stale.

**Recalibrate** lives with the readout, shown only in the locked state
(the one state where it does anything): on the phone, the pill itself is
tappable and gains a small `arrow.clockwise`; on the web panel it's a
small button inside the pill. Both flip optimistically to the amber
"Recalibrating" wording — the next state push corrects them if the
request was lost.

The plugin owns these states (`lipsync-cal.h`) and pushes them to the app
in the `tally` command's `sync` field; the web panel reads the same value
from `/api/status`. Recalibration requests flow back as a REQUEST packet
(app) or `POST /api/recalibrate` (panel).

### Surfaces (dark / over-video)
| Token          | Value                                   | Use |
|----------------|-----------------------------------------|-----|
| `pageBg`       | `#0E0F13`                               | Web page background; app preview backdrop is pure black |
| `glassPanel`   | black @ 55% + blur (`.regularMaterial`) | Floating control panels |
| `glassChip`    | white @ 12%                             | Circular control buttons (idle) |
| `glassChipOn`  | `accent` @ 90%                          | Active/toggled control buttons |
| `cameraYellow` | `#FFD60A`                               | App only: the selected lens button, the dial's readout and thumb, the auto badge — the Camera app's own colour for "the setting you're touching" |
| `hairline`     | white @ 8%                              | Panel borders on the web |

### Text on glass
| Token            | Value          |
|------------------|----------------|
| `textPrimary`    | `#FFFFFF`      |
| `textSecondary`  | white @ 60%    |

### Setup screen (light/dark system)
The Setup screen uses the **native grouped-form** styling (system
background, `.insetGrouped` lists) so it feels like a standard iOS settings
screen and adapts to light/dark automatically. Only the accent colour and
the status dot/label carry the brand palette into it.

---

## 3. Typography

Native system font (SF on Apple, `system-ui` on web).

| Role            | Size / weight            | Notes |
|-----------------|--------------------------|-------|
| Screen title    | 20 semibold              | "LensLink", panel headings |
| Body            | 15–17 regular            | Descriptions, list rows |
| Label / caption | 13 regular               | Secondary text, field labels |
| Numeric readout | 13–15 **monospaced digits** | Zoom `2.0×`, exposure `+0.3`, latency `57 ms` — monospaced so values don't jitter while dragging |

### Microcopy (explanations, captions, the Documentation screen)

Explanatory text is a cost the reader pays on every visit. The rules:

- **Setting screens are pure controls — no section footers.** Every
  explanation lives in the **Documentation** screen (main screen tail →
  Documentation, `DocumentationView.swift`), grouped by feature.
  Adding or changing a control means updating its Documentation entry
  in the same change — the screen is the manual, and a control it
  doesn't cover doesn't exist as far as the reader knows. Two
  sanctioned exceptions: the version line under the tail (bug reports
  need a build to cite) and failure text that must be seen in place
  (a broken broadcast extension warns on the main screen).
- **An entry earns its place by adding a consequence or constraint the
  control's label can't carry** — a precondition ("while the app is open
  and idle"), a cost ("the phone stays awake"), a boundary ("iOS mutes
  DRM audio"). An entry that restates the label gets deleted, not
  shortened.
- Sentence case; no exclamation marks; no "please". Em-dash asides over
  nested parentheses. Numbers as numerals ("10 seconds"). Bold the
  control's name at the start of its entry so the list scans.
- **American English** in user-facing copy ("color"), matching the
  platform's own language. (These docs may write "colour"; the UI must
  not.)
- Name OBS-side things exactly as OBS shows them: a "LensLink Camera"
  source, the Phone IP field, an "Apply LUT" filter.
- Overlay/status lines follow the pattern *state — action*: "Streaming —
  tap to wake", "Not visible by name in OBS — tap to allow…".
- Diagnostics (probe results, extension checks) are exempt from the
  length rules — a failed check should say exactly what to do next — but
  follow the `✓ / ✗ + state — action` pattern.

---

## 4. Spacing, radius, sizing

- **Spacing scale:** 4, 8, 12, 16, 20, 24. Use these steps only.
- **Radius:** panel `16`, chip/segment `12`, pill/status `full`.
- **Control button:** 44×44 pt/px circular hit target (glass chip),
  22 pt icon.
- **Panel padding:** 16 (14 acceptable on very small screens).
- **Slider row:** leading icon · slider · trailing icon · readout (fixed
  40–48 pt width, right-aligned, monospaced).

---

## 5. Iconography & control metaphors

SF Symbols on iOS; the web mirrors the same glyph meaning (unicode/inline
SVG) and identical layout. Every control appears in the same order on both
surfaces.

| Control     | Icon(s)                                   | Pattern |
|-------------|-------------------------------------------|---------|
| Zoom        | web: `minus.magnifyingglass` / `plus.magnifyingglass`; app: the **Zoom** chip and the lens buttons | Slider 1×…max, readout `N.N×`. On the phone, pinch is the primary control and the lens buttons (`.5` · `1×` · `2`, the Camera app's row) switch physical lenses |
| Exposure    | web: `sun.min` / `sun.max`; app: the **Exposure** chip, or a one-finger vertical drag on the picture | Slider −range…+range, readout `±N.N EV`. Drag on the phone: six stops per screen height, readout in `cameraYellow` while the finger is down, inert in manual exposure |
| Focus       | web: segmented **AF / Lock**; app: the **Focus** chip | When Lock: a lens-position slider (0=near, 1=far). On the phone the chip wears an **A** badge on auto; dragging the dial locks, tapping the active chip again unlocks. Auto is **faces first** (Options → Focus on faces, default on; `faceFocus` in STATE): the camera tracks faces for focus and exposure, the Camera app's behaviour |
| Exposure mode | web: segmented **AE / Manual**; app: the **Shutter** chip | When Manual: the bias slider is replaced by ISO (`dial.min`/`dial.max`) and Shutter (`tortoise`/`hare`, log-scale, readout `1/125`) rows. On the phone, dragging Shutter takes exposure manual and the Exposure chip becomes **ISO**; tapping either active chip returns to auto. Hidden if unsupported |
| White balance | web: segmented **AWB / Lock**; app: the **WB** chip | When Lock: a colour-temperature slider (2500–8000 K, readout `5600 K`). Hidden if unsupported |
| Flashlight  | `bolt.fill` (toggle; hidden if unavailable)  | Chip, `glassChipOn` when on. **Always labelled "Flashlight," never "Torch."** (Voice Control also accepts "Torch" as a spoken alias, §8; it is never shown.) In the app, in the tray's bottom row |
| Lens        | web: `camera.aperture` menu; app: the lens buttons | Menu of the device's real lenses; check on the active one. The app's buttons show each lens's magnification relative to Main (front lenses: relative to the regular front camera), the active one in `cameraYellow` carrying the live zoom (`2.4×`); tapping the active one resets its zoom |
| Flip        | `arrow.triangle.2.circlepath.camera`      | Quick front/back. In the app, in the tray's bottom row |
| Stop        | `stop.fill`                                | Red chip; the only destructive control |
| Pause       | `pause.fill` / `play.fill`                 | Amber `glassChipOn` while paused; between the status pill and Stop |
| Idle (app)  | `moon.fill` (Dim screen) / `eye.slash` (Clean feed) | App-only, an item in the status pill's menu; engages the chosen idle view now instead of waiting out the 10 s fuse. Absent in Standard |
| Pulse (app) | `waveform.path`                            | App-only, in Options → Tally light: one glyph, `accent` when that status pulses and secondary when steady — the active-chip language, not a swapped icon |
| Stats (app) | `gauge`, checked while on                  | App-only, a toggle in the status pill's menu (the menu's own checkmark, so VoiceOver hears the state); shows a health pill (`60 fps · 11.9 Mb/s · 0 dropped`, monospaced) under the status bar |
| Green screen | `person.fill.viewfinder`                  | **Always "Green screen"** (never "chroma key", "background removal", or "matte" in UI copy). Armed from the Setup screen; while live **with depth assist**, a subject-distance control (0.5–5.0 m, readout `2.5 m` monospaced) appears: the **Subject** chip in the app's tray, a slider row on the web panel. Dragging always sets a real cutoff — full-left = tightest (0.5 m); **"All" (no cutoff)** is tapping the active Subject chip in the app and tapping the readout on the web, and while "All" the thumb parks at the far (5.0) end |

### The app icon (three appearances)

The mark is a camera lens (ring + aperture dot) with a smaller link ring
on its lower-right edge. It ships in Apple's three home-screen
appearances (iOS 18+), all generated by `assets/make-icon.py` from one
set of geometry — never hand-edited, and never re-drawn per variant:

| Appearance | Background | Ink |
|------------|-----------|-----|
| Default (light) | our own `#FFFFFF → #ECF0F7` vertical gradient, **opaque** (iOS forbids alpha here) | `accent` lens ring and aperture dot; the link ring in the deep `#2E5FD6`, because the pale `#8FB4FF` washes out on white |
| Dark | **transparent** — iOS draws its own dark backdrop | same hues at 86% brightness; a saturated blue glares on an all-dark home screen |
| Tinted | **transparent** — iOS draws the user's tint | **greys only.** iOS discards hue and maps luminance through the tint, so the palette becomes a brightness ranking: link ring `#FFF`, lens ring `#CCC`, aperture dot `#C2` → `#73` |

Three rules carry across all three. The link ring always stands out from
the lens ring: brighter on the dark and tinted variants (the tinted one
preserves that hierarchy instead of colour), deeper on the light default,
where contrast against white does the same job. The light and dark icons
look clearly different, so switching the home screen between light and
dark visibly changes the icon. And the keyline gap that separates the two
rings stays — on the transparent variants it reveals iOS's backdrop
rather than ours, which is the same read.

Adding an appearance means adding a palette in `make-icon.py` **and** an
entry in `AppIcon.appiconset/Contents.json`; a PNG without the matching
`appearances` key is dead weight the asset compiler ignores.

---

## 6. Screen specifications

### 6.1 App — Setup screen
An inset grouped form in the Settings app's own anatomy — every row a
coloured icon tile (`SettingsRowLabel`, 29 pt, radius 7, white SF
Symbol) and a title — top to bottom:

1. **Title** — "LensLink" as a plain large title (no navigation bar;
   nothing is ever pushed, so nothing needs a back button).
2. **The computer** — one card: a computer glyph in `status.tint`
   (`laptopcomputer` over USB, `desktopcomputer` otherwise), the
   computer's **host name** once the plugin has introduced itself (the
   `identify` command; "OBS Studio" until then), and under it the status
   dot + `status.displayName`, with the OBS version and transport
   appended while connected ("OBS connected — ready · OBS 32.0 · USB").
   On the right: in Standby, an accent **Start** capsule; otherwise the
   phone's Wi-Fi IP (monospaced, tap-to-copy), because the address is how
   OBS finds this phone. Below, the Local Network warning when Bonjour
   was denied, and the "How to connect" disclosure with the two setup
   steps — collapsible, and it stays collapsed once read.
3. **Camera** — **Camera** (the lens picker), **Format** — one row whose
   value reads `4K · 60 fps · HEVC` (`· HDR` or `· Log` appended when the
   colour isn't Standard) and opens the Format sheet — and the **Green
   screen** toggle. A contextual "Open Settings" button appears only if
   a permission was denied.

   **The Format sheet**: Resolution and Frame rate pickers (each filtered
   to what the selected lens supports), then **Quality** (**Balanced** or
   **Maximum**, the latter with a small accent **Beta** tag and no
   caption; the Format row's value gains `· Max`), then **Codec** and
   **Color** as check-row lists rather than pickers, because the two constrain each
   other (HDR and Apple Log are HEVC only; green screen is Standard
   only) and a picker that hides H.264 reads as a bug. Every choice stays
   visible; the captions stay short — HDR and Apple Log read "HEVC only",
   nothing else carries one — and the model does the switching when a
   choice needs it (picking H.264 returns Color to Standard, picking a
   10-bit colour switches the codec to HEVC and turns green screen off).
4. **Start** — two stacked full-width buttons: **Start Camera** in the
   accent, **Mirror Screen** in the system's secondary fill (the system
   broadcast picker is stretched invisibly over the button face — iOS
   won't start a broadcast any other way). A broken broadcast extension
   warns above them. On iOS 27 and later the app mirrors in-process:
   Mirror Screen is a plain button that opens the system screen-sharing
   picker and reads **Stop Mirroring** while mirroring, the extension
   warning is hidden, a mirroring failure shows in the same red caption,
   and the connection card shows the mirror's status ("Live" once OBS is
   connected, "Waiting for OBS…" before).
5. **Microphone** — see below.
6. **Tail** — **Options** and **Documentation** rows that present their
   sheets, **Report a problem**, the GitHub link, and the version line in
   the footer.

Long explanations don't belong on this screen: the only footer is the
version line, so the form stays close to one screenful.

**Microphone module** (between Camera and Screen mirror): **Send phone
mic to OBS**, then — only while that is on — a **Microphone** picker of
the phone's inputs, then **Auto lip-sync reference** (mutually exclusive
with the mic toggle; turning one on turns the other off). The picker
lives here and not on the Live screen because which mic is a set-once
decision made before Start; the web panel keeps its own mic row for
switching mid-stream.

**Options sheet.** The behaviour toggles live in a sheet (`OptionsView`)
so the main screen stays short, in the same icon-tile rows as Setup.
First group, the things that matter during a stream: **Remote start from
OBS**, **Idle view** (Standard / Clean feed / Dim screen), **Focus on
faces** (default on), and the pushed screen **Tally light** (row value: the statuses that light it,
"On air, In preview"), and **Remember camera settings** (default on; see
§6.2.1). Second group, the experiments and the diagnostics: **High frame rate**
(adds 120 / 240 fps to the Format sheet where the camera has them; off
by default), **Allow system video effects**, **Camera diagnostics**. Pure
controls, no footers: every explanation lives in the Documentation screen (§3), which
is also why the pushed screens carry none.

### 6.2 App — Live screen
Full-screen black; camera preview `resizeAspect`; two layers over it.

**The glance layer** — the whole screen for most of a stream:

- **Top bar:** status pill (dot + word + a small `chevron.down`, left) ·
  Pause · Stop (red). Glass chips. The pill is a **menu**: **Stats** (a
  checkmark toggle) and, when an idle view is set, **Clean feed now** /
  **Dim screen now** — both are about the screen rather than the shot and
  earn no button of their own. With Stats on, a health pill (fps · Mb/s ·
  dropped) sits under the bar, leading-aligned.
- **Notice row:** one row under the status bar for whatever needs saying
  — today the lip-sync readout. Nothing is drawn when there is nothing
  to say; never two pills stacked.
- **Lens buttons** (bottom centre, as in the Camera app): one round
  button per lens on the selected side, labelled with its magnification
  relative to Main (`.5`, `2`, `3`); front lenses are measured against
  the regular front camera instead (an iPad Pro's front ultra wide reads
  about `.7`). The active one is larger, in `cameraYellow`, carrying the
  live zoom (`1×`, `2.4×`). Tapping another switches the physical lens;
  tapping the active one returns it to its own zoom (`1×` of that lens).
  Hidden when the selected side has only one camera.
- **Chevron** (`chevron.up` in a glass capsule) under the lens buttons
  opens the tray.
- **Gestures:** pinch = zoom within the lens; **tap** = focus/expose at
  the point, marked by the Camera app's square — a 72 pt `cameraYellow`
  rounded rectangle that lands with a 150 ms scale-in and fades a second
  later. The point holds until the camera's own subject-area monitoring
  says the scene changed, then auto (faces, or centre-weighted) takes
  over again — never a timer of ours, and never for the rest of the
  stream. **Long press** (0.5 s) = **AE/AF Lock** at the point: one scan,
  then focus is held at the lens position it found and exposure at the
  ISO and shutter it chose, as the same locked / manual states the chips
  show ("AE/AF Lock" tag under the square, 1.8 s); releasing is tapping
  Focus or ISO. A **one-finger vertical drag** = exposure bias (the Camera app's sun
  slider: six stops per screen height, a `cameraYellow` readout centred
  while the finger is down, inert in manual exposure). With those, the
  tray stays closed unless the operator means it.

**The adjust tray** (`glassPanel`, radius 16, replaces the lens buttons
and chevron; 200 ms):

- **Chip row:** Zoom · Exposure · Shutter · WB · Focus (· Subject while
  green screen runs with depth assist). Shutter needs manual exposure and
  WB needs a lockable white balance; unsupported chips aren't drawn. The
  active chip is white with black text. A chip on auto wears a small
  `cameraYellow` **A** badge at its top-right corner (Zoom has none — it
  has no auto).
- **One dial:** a `cameraYellow` monospaced readout (`+0.7 EV`, `ISO 200`,
  `1/125`, `5600 K`, `0.45`, `2.5 m` / `All`) over a native slider, driving
  whatever the active chip names. Ranges and scales are the web panel's
  (shutter log-scale, subject 0.5–5.0 m).
- **Auto ↔ manual rule:** a drag on the dial takes that parameter out of
  auto on the first touch (Shutter → manual exposure, WB → lock, Focus →
  lock). Tapping the *active* chip again hands it back to auto. Exposure on
  auto is the bias dial — an auto-exposure control, so dragging it leaves
  auto alone — and once Shutter has taken exposure manual the same chip
  reads **ISO** and drives ISO, so chip and readout never disagree.
- **Bottom row:** a caption naming the mode (`Auto · drag to set by hand`,
  `Manual · tap WB for auto`, `Pinch the picture to zoom`) · Flashlight ·
  Flip · `chevron.down` to close.

Set-once choices are not on this screen at all: the microphone picker is
on Setup (Microphone module), lens defaults come from Setup's Lens
picker, idle appearance from Options.
- **Idle view:** what the screen becomes 10 s after the last touch, the
  user's choice in Options → Idle view. Any tap brings the controls back
  and restarts the fuse.
  - **Standard** — nothing happens; the controls stay up all stream.
  - **Clean feed** — the preview alone: status pill, notice row, lens
    buttons and tray fade out over 0.2 s. Two things deliberately stay,
    because neither is a control: the tally border, and the health pill
    when Stats is on — Stats *is* the "clean, but keep the numbers"
    switch, so no second setting exists for it. A transparent tap catcher covers
    the screen, so the waking tap is only a wake (never also a focus pull)
    and the letterbox bars wake it too.
  - **Dim screen** — near-black overlay with a small "Streaming — tap to
    wake" hint, brightness at 5%, and preview rendering stopped. Under the
    hint sits a **battery readout** (level glyph + monospaced percentage,
    a bolt while charging), set deliberately large — around 44 pt, the
    biggest thing on the dimmed screen, because the phone it answers for
    is on a stand across the room. It answers "do I need to plug this in?"
    without waking the screen — the one question a dimmed phone on a
    stand cannot otherwise answer. A bright grey normally (plain
    `idleGrey` disappears at 5% brightness under the overlay),
    `connectAmber` in Low Power Mode, `errorRed` at 20% or below, and
    grey again whenever charging: Low Power Mode can be switched on at 80%, and one colour
    for both would be a warning you learn to ignore. Nothing renders
    where iOS reports no level (Simulator). This is the only idle view
    that also applies to the Setup screen, which dims a minute into
    remote-start standby.

### 6.2.1 Remembered camera settings

No saved looks to name. Each camera's **exposure, white balance, zoom
and focus** are stored per lens as they change while streaming (on the
debounced STATE send, and once more at stop) and put back when that
lens next starts — at stream start, or a live lens switch — after the
usual reset. The Camera app remembers the same way. Rules:

- Everything is stored, every time: there is no "which groups" choice,
  because there is no screen to make it on. The tray shows what came
  back (locked chips, the ISO readout), and tapping a chip releases it.
- Values are clamped again on apply by the same didSets the Live screen
  uses, so a lens position or ISO saved on one format never exceeds the
  next one's limits.
- **Options → Remember camera settings** (default on) is the whole UI.
  Off forgets what is stored and every camera starts on auto.
- Phone-local; the same properties the Live screen and `CONTROL` move,
  so the `STATE` snapshot follows for free — no protocol change.

### 6.3 Web control panel
Dark page (`pageBg`), single centered column (max ~440 px):

1. **Header:** "LensLink" title + status pill (dot + text) mapped from the
   plugin's status/latency line to the shared palette.
2. **Source tabs** (segmented control, accent = selected) directly under
   the header — only when more than one camera source is live. Every API
   request carries the selected source's `?src=` id; one page controls
   every phone.
3. **Controls** in the *same order as the app's chip row*: Zoom row,
   Exposure row, Focus (AF/Lock + lens slider), then a chip row of
   Flashlight · Lens · Flip. One row per control rather than the phone's
   single dial: a page at a desk has the room, and a mouse is not a
   thumb.
4. All controls send `CONTROL` packets; the panel polls `/api/state` and
   mirrors app-side changes (pausing while the operator is interacting), so
   the two stay in lock-step.

The page sets `color-scheme: dark`, so native browser chrome — most
visibly the popup list of a `<select>` — renders dark instead of a light
list with inherited white (invisible) text.

The web panel deliberately shows the **plugin's** connection/latency status
(the PC's vantage point), not the phone app's status — but styled with the
identical pill, palette and control language.

### 6.4 OBS status bar & dock

A third surface lives inside OBS itself (Qt, `frontend-ui.cpp`): a
one-line health readout in the main window's status bar
(`LensLink: <device> 60 fps · 11.9 Mb/s · 43 ms`, live sources joined by
`  |  `, hidden when nothing is
connected; "ready (camera idle)" during standby) and a dockable
**LensLink** panel listing every source with its device, status, and
rates. These render with OBS's native theme rather than our palette —
inside OBS's chrome, OBS's design language wins; our vocabulary (the
status wording, `fps · Mb/s · ms` ordering, monospace-style numerals)
is what carries over.

### 6.5 Plugin settings dialog (Tools → LensLink Settings)

Plugin-wide switches live here, not in source properties: anything with
one value for the whole plugin (web panel + its port, diagnostics, the
stream dump, the GPU pipeline beta). Native Qt widgets, OBS's theme,
no custom chrome. Rules of the room: a setting that needs an OBS
restart says so right under its checkbox in muted text; per-source
properties never duplicate a global (the property sheet points at the
Tools menu instead).

---

## 7. Motion

- Toggles / dim / selection: 200 ms ease.
- Sliders: track the finger live (no animation lag).
- Status colour changes: cross-fade 200 ms.
- Nothing loops or pulses; motion always encodes a real state change.
- Reduce Motion takes out movement and keeps fades (§8).

---

## 8. Accessibility

The app declares Apple's Accessibility Nutrition Labels
(`docs/APP_STORE.md` lists which, and the device checks behind each).
That makes these design-system rules rather than extras: a control that
breaks one breaks a claim on the store page.

### Names and state

- **Every icon-only control has a spoken name**, in the words the UI
  already uses: "Flashlight", "Flip camera", "Stop camera", "Adjust
  camera", "Close". `ControlButton` takes the name as a required
  argument, so a glass chip can't be built without one.
- **An on/off control also speaks its state**, as the value "On" or
  "Off": the Flashlight, a tally row's pulse switch. One approach
  everywhere. The *selected* trait means something else, "the chosen
  one of several": the active lens button, the active dial chip, the
  checked Format row.
- A button whose label changes with its state (Pause / Resume) speaks
  the label and no value.
- **Voice Control names** (`accessibilityInputLabels`) put the spoken
  name first, then the short words people actually say: "Stop", "Flip",
  "Switch camera", "Adjust", "Wake", "Status", "Mirror". "Torch" and
  "Light" are accepted for the Flashlight: an alias is what the user
  says, not what we show, so "never Torch" (§5) still holds on screen.
  Aliases are localized like any other string.
- **Decorative images are hidden** where a word beside them already
  says it: the computer glyph on the Setup card, row chevrons, the
  dimmed screen's camera glyph. Transient echoes of a gesture (the
  focus square, the drag readout) are hidden too. The dial's readout is
  hidden in favour of the slider, which speaks the chip's name as its
  label and the readout as its value.
- The Mirror Screen button's name sits on the system broadcast picker's
  own button, and our styled face under it is hidden, so VoiceOver
  finds one button, not two. On iOS 27 and later it is our own button,
  named "Mirror Screen" or "Stop Mirroring", with "Mirror" or "Stop" as
  the short Voice Control names.

### Assistive technology suspends idle

The idle view (§6.2) and the standby dim (§2) are fuses that touches
reset, and VoiceOver and Switch Control produce no touches the fuse can
see. While either runs (`AssistiveTech.suspendsIdle`, fed by iOS's
status notifications) neither fuse burns. Turning one on while the
screen is dimmed wakes it; turning it off restarts the fuse from zero
instead of dimming at once. **Dim screen now** / **Clean feed now** in
the status pill's menu still work on request: the wake hint is then a
button, the clean feed's invisible tap catcher carries the same name,
and "Wake" is the Voice Control name for both, because Voice Control
has no running flag to suspend on.

### Announcements and haptics

Changes the operator would otherwise have to look for are spoken, only
while VoiceOver runs, and queued behind whatever VoiceOver is already
saying: going **Live** (also on regaining OBS, and on resume),
**Paused**, an error (its own message), **Connection lost** mid-stream,
**On air**, and **Sync locked**. The words are the existing vocabulary
(`Status.displayName`, the tally statuses, the sync pill), never new
phrasing. `Streamer` derives them from the state change itself,
coalesced per run-loop turn: a status that passes through an
intermediate state (an error that stops the stream) speaks only where
it landed, and nothing fires because a view appeared again.

Haptics are for everyone: a success tap on going Live (not on resume,
which the operator just pressed), a warning when a running stream loses
OBS or fails.

### Differentiate Without Color

Colour never carries meaning alone: every status dot sits beside its
word, the sync dot beside its wording, and an auto chip wears a letter.
With the setting on, the places that were colour-only gain words:

- **The tally border** gets a badge naming the lit status ("On air",
  "In preview", "Low battery"): trailing-aligned under the top bar,
  stroked in the border's colour, and drawn above the dim overlay like
  the border itself.
- The dimmed battery readout adds "Low battery" under the percentage
  whenever it is amber or red.
- The tally list's pulse switch sits on an accent disc when on, instead
  of only changing colour.

### Reduce Transparency and Increase Contrast

Glass over a bright picture can pull white text below a readable ratio.
Both settings resolve in one place, `glassBackground(_:style:)` in
`DesignSystem.swift`; no call site picks its own fill.

| Token | Value | Replaces | When |
|---|---|---|---|
| `glassPanelSolid` | black @ 90% | `glassPanel`, the lens buttons' scrim | Reduce Transparency or Increase Contrast |
| `glassChipSolid` | `#383838`, opaque | `glassChip` | Reduce Transparency or Increase Contrast |
| *(accent)* | `accent` @ 100% | `glassChipOn` | Reduce Transparency or Increase Contrast |
| `textSecondaryIncreased` | white @ 90% | `textSecondary`; the 80 to 85% chip and lens text goes to full white | Increase Contrast |
| `hairlineStrong` | white @ 50%, 1 pt | no edge | Increase Contrast: every glass surface gets an edge |

The Setup screen is a native grouped form and gets both settings from
iOS. The web panel follows the same rules through `prefers-contrast:
more` and `prefers-reduced-transparency: reduce`.

### Larger Text

Native forms (Setup, Options, Format, Tally light, Documentation)
follow Dynamic Type all the way. At accessibility sizes the Setup
card stacks Start or the phone's address under the computer's name
instead of squeezing both into one row. The Live screen is an overlay
on a picture and can't grow without limit: its text uses text styles
clamped at `accessibility2` (twice the default footnote), and the
controls that stay a fixed size (glass buttons, dial chips, lens
buttons, the status, sync and health pills) show the **large content
viewer** on a long press, with the name VoiceOver reads. Text over the
picture uses text styles; `.system(size:)` stays for control glyphs
and the deliberately huge battery readout.

### Reduce Motion

Motion that moves things goes: the tray and the idle view switch
without animated layout, the focus square lands without its scale-in,
and every tally pulse holds steady (§2). Fades and colour changes stay;
they are not the motion the setting is about. The web panel drops its
dot transition under `prefers-reduced-motion`.

### Web panel

Screen-reader basics, in the same vocabulary:

- Icon-only buttons, sliders and selects without a visible label get
  `aria-label` from the tooltip key they carry: `data-t-title` sets
  both. An element with visible text keeps its text as its name, and
  the tooltip becomes its description. ISO and Shutter are labelled by
  their visible row labels.
- Toggles and segmented buttons expose `aria-pressed`, kept in step by
  the same functions that set their `on` class, so the two never
  disagree. Source tabs too.
- Sliders whose raw value means nothing (the shutter's log position,
  subject distance, zoom, colour temperature) carry the readout as
  `aria-valuetext`. The subject readout is a keyboard-reachable button.
- Decorative SVGs are `aria-hidden`.
- The status pill is not itself a live region: its text carries a
  latency figure that changes every few seconds. A visually hidden
  `role=status` region speaks the status only when its tone changes
  (or a different error arrives); the sync wording is a polite live
  region of its own. Text is only ever rewritten when it changed, so a
  poll never re-announces.

---

## 9. Reconciliation checklist (this revision)

- [x] Status **word** unified via `Status.displayName` (was two different
      strings for connecting across Setup vs Live).
- [x] Status **colour** unified via `Status.tint` (Live screen previously
      had no error/idle colour).
- [x] Shared **design tokens** (`DesignSystem.swift`) replace ad-hoc
      opacities, radii and paddings.
- [x] "Torch" → **"Flashlight"** everywhere (icon-only in app, labelled on
      web).
- [x] Web panel restyled to the palette, typography, control metaphors and
      ordering above; **Lens selection** added for parity with the app.
