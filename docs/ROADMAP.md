# LensLink — Roadmap

Candidate work, curated and ranked. Nothing here is committed to a
release; items graduate to a GitHub issue when they're picked up. Two
house rules carry over from [`PERFORMANCE.md`](PERFORMANCE.md):
performance changes quote a before/after measurement, and behavior
users rely on (the invariants listed there) doesn't regress in the name
of speed. Provenance: the performance items trace to the 2026-07
efficiency audit; most feature items came out of a 2026-07 survey of
comparable products (Camo, DroidCam, Elgato Camera Hub/EpocCam,
Continuity Camera, iVCam/Iriun, NDI HX Camera/Larix).

## Priorities at a glance

| Priority | Item | Category | Effort |
|----------|------|----------|--------|
| P1 | Thermal & low-power adaptation | Reliability & security | Medium |
| P1 | Optional pairing & encryption | Reliability & security | Medium |
| P1 | Graduate the GPU decode pipeline | Performance | Small |
| P2 | Voice isolation for the phone mic | Video & audio quality | Small |
| P3 | Manual bitrate cap | Video & audio quality | Small |
| P3 | Zero-copy encoder output | Performance | Medium |
| P3 | Two lenses at once (multicam) | Video & audio quality | Large |

- **P1 — next up.** Protects or finishes what already ships, plus the
  one tiny-effort/large-payoff outlier. Pick from here first.
- **P2 — on deck.** Clearly worth building; start once P1 is moving.
- **P3 — needs a trigger.** A dependency landing, a measurement, or
  real user demand should promote these before anyone starts.

Recently shipped and pruned from this file (see the release notes):
tally light with customizable colours (v1.8.0), 10-bit HDR (HLG) with
the zero-copy GPU path and Apple Log (v1.9.0), virtual green screen
with depth assist and subject-distance cutoff (v1.10.0), iPad
multitasking capture — streaming continues in Split View, Slide Over
and Stage Manager on iPads that support it, and a native Stream Deck
plugin (`streamdeck/`, 2026-10, on request) on top of the documented
control API, and digital reframe — zoom and pan from the web panel or
OBS, applied on the phone before encoding, locked to 16:9, with an opt-in
high-quality mode that captures one size up so zoom keeps real detail
(2026-11). Pairing &
encryption was explicitly deprioritized by the maintainer in 2026-07 —
revisit when remote start gets promoted or users stream on shared
networks.

## Reliability & security

### Thermal & low-power adaptation on the phone — P1, medium (partially shipped)
For a mounted phone streaming for hours, the practical limit is heat
soak: iOS throttles, capture stutters, and at worst the phone shuts
down mid-stream. **Shipped (PR #63):** the capture device's
`systemPressureState` is observed per Apple's guidance — `.serious`
halves the bitrate, `.critical` quarters it and halves the frame rate,
both restored on recovery, logged to the unified log. **Remaining:**
surface the adaptation in the app status and the OBS source status
(today it's silent), consider `ProcessInfo.thermalState` for
earlier/coarser signals, resolution step-down as the last rung, and
optionally respect Low Power Mode. *The biggest real-world win for
long streams.*

### Optional pairing & encryption — close the trusted-LAN caveat — P1, medium
The README honestly says the stream is unencrypted and intended for
trusted networks, and remote start raises the stakes (any LAN peer
could send `start_stream` while the app is armed). A one-time pairing (PIN shown in the app,
entered in OBS) yielding a stored token, carried in the plugin's first
packet and required for CONTROL — plus optional TLS via `NWProtocolTLS`
with a pinned self-signed cert — would make the app safe on shared
networks (dorms, offices, event venues). Designed as opt-in ("Require
pairing" toggle) to keep the zero-config home path frictionless. *The
right thing to ship before promoting remote start heavily.*

## Performance

### Graduate the GPU decode pipeline from beta — P1, small
Shipped as the opt-in **GPU decode pipeline (beta)** in Tools →
LensLink Settings (per-platform interop: D3D11 keyed-mutex shared
textures on Windows, IOSurface/BGRA on macOS, VAAPI dmabuf→EGL on
Linux; automatic per-source fallback whenever interop fails). The
before/after measurement the house rule asks for is done — see the
12-configuration table in `PERFORMANCE.md` (89–99% per-frame cost
reduction). What remains is field validation beyond that one
Windows/NVIDIA machine: macOS IOSurface, Linux VAAPI on Mesa and
`nvidia-vaapi-driver`, AMD/Intel GPUs, and the multi-GPU fallback.
When the matrix looks healthy, drop the beta label (and consider
defaulting it on). *Small effort, mostly soak time; finishes a flagship
feature that's already built.*

### Zero-copy encoder output on the phone — P3, medium
The one remaining per-frame copy in the app is the AVCC→Annex B rewrite
into an owned buffer (`VideoEncoder.annexBData`). In-place prefix
rewriting plus retaining the sample buffer until TCP send completion
would eliminate it — but that pins VideoToolbox's buffer pool for up to
12 in-flight frames and can starve the encoder under congestion, which
is why the copy is deliberate today. *Trigger: an Instruments pass
showing the copy actually mattering. Size the encoder pool explicitly
if you do it.*

## Video & audio quality

### Voice isolation for the phone mic — P2, small
The mic features send the raw microphone feed; iOS's built-in
voice-processing pipeline (echo cancellation + noise suppression, the
FaceTime mic sound) is nearly free to enable. An Options toggle in the
Microphone group, applied to the send-phone-mic path. *Makes the
"phone as wireless mic" feature genuinely usable in untreated rooms.*

### Two lenses at once (multicam) — P3, large
`AVCaptureMultiCamSession` (iOS 13+) runs two cameras at once (front plus
a rear lens, or two rear lenses on newer phones): one phone feeding a face
cam *and* a scene cam as two LensLink sources. No competitor does this.
Design sketch: a second listener (next port, own Bonjour record) so the
plugin's existing per-source dial and device pinning give each stream a
home, a `stream` field in HELLO, and per-stream STATE/CONTROL so every
existing control already addresses the right camera. The work is in the
app: `Streamer` owns one camera, one encoder and one client, so this
means N capture-encode-send pipelines. Hard limits, all Apple's: only
formats flagged `isMultiCamSupported` (no 4K, usually 30 fps and below
the single-camera maximum), a combined `hardwareCost` and
`systemPressureCost` under 1.0 or the session refuses to start, one
microphone, no depth assist (green screen is segmentation-only), no
Cinematic stabilization, and 10-bit colour often unavailable. Heat is the
real risk: prototype two encodes for 30 minutes before any UI. *Trigger:
real user demand and a thermal prototype that survives 30 minutes.*

### Manual bitrate cap — P3, small
Adaptive bitrate already reacts to congestion, but there's no user
ceiling. A cap (Options row, plus a live command so the web panel can
set it) keeps shared/metered networks and multi-phone rigs predictable.
STATE advertises the cap so remote UIs stay in lock-step. *Trigger:
users actually hitting the situations it solves; the adaptive path
covers most of them today.*

## Not planned — revisit when the world changes

- **Stream rotation ("Match phone orientation").** Built and working
  (PR #33's original scope, preserved in that branch's history): the
  capture pipeline rotates buffers, the encoder rebuilds with swapped
  dimensions on aspect flips, and OBS follows the bitstream — real
  portrait video for portrait rigs. Shelved by choice, not difficulty:
  it adds a setup-UI toggle few people would use, and a nudged mounted
  phone resizing its OBS source is a support trap. The shipped behavior
  is UI-follows-rotation with a steady sensor-native landscape stream.
  Revisit if users actually ask for portrait streaming.
- **AV1.** Gated on Apple shipping AV1 *hardware encode* (current Apple
  silicon has decode only, and software AV1 encode on a phone is a
  battery fire). When that changes, the plumbing is cheap: a `VideoCodec`
  case + capability probe in the app, an `AV_CODEC_ID_AV1` mapping in the
  plugin — the decoder path is already codec-agnostic with GPU/software
  fallback. Until then HEVC is the right codec for a LAN/USB link.
- **ProRes over USB.** Built and measured on an iPhone 15 Pro (branch
  `claude/bench-stage-timings`, numbers in docs/PERFORMANCE.md): it
  encodes in real time, but ProRes LT 1080p60 lands about 4 ms behind
  HEVC Maximum for under 3 VMAF points (below what viewers notice), HQ
  and 4K don't fit the ~300 Mbps USB path, decode is CPU-only on
  Windows, and 10-bit 4:2:2 capture showed no keying advantage. Revisit
  if Apple's USB path gets much faster or a keying workflow shows a
  visible difference.
- **A higher HEVC bitrate ceiling over USB.** Pinning Maximum at
  100 Mbps (1080p60) bought +1.4 VMAF for about 6 ms more latency, all
  of it transfer time. Maximum's current ceiling is the sweet spot.
- **Low-latency GPU codecs (PyroWave and similar).** The PC side is
  under 2 ms of a 36 ms 1080p60 pipeline, and the camera stage alone is
  28 ms, so a faster decoder has nothing to win; they also need Vulkan,
  which iOS doesn't have, and would encode on the phone's GPU instead
  of its media engine.
- **USB 3 cables.** No measurable difference from USB 2: the limit is
  the usbmuxd path (about 37 MB/s), not the cable. Not worth advising.
- **Micro-optimizations** (poll cadences, timesync/ping rates, web-panel
  polling, recv-buffer tuning): all measured or bounded at ≪1% — not
  worth the review risk.

## How to use this document

Pick the top unclaimed P1, open a GitHub issue referencing the section,
and prune the entry here when it ships. Priorities are judgment, not
physics: if reality disagrees with one (a profile, a pile of user
requests, a platform shift), re-rank it — this file is a map, not a
promise.
