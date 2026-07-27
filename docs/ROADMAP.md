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
| P2 | Digital pan/tilt + crop | Control & workflow | Medium |
| P2 | Voice isolation for the phone mic | Video & audio quality | Small |
| P2 | Document the control API | Control & workflow | Small |
| P3 | Manual bitrate cap | Video & audio quality | Small |
| P3 | Zero-copy encoder output | Performance | Medium |
| P3 | iPad: keep streaming in Split View | Control & workflow | Small |
| P3 | Two lenses at once (multicam) | Video & audio quality | Large |

- **P1 — next up.** Protects or finishes what already ships, plus the
  one tiny-effort/large-payoff outlier. Pick from here first.
- **P2 — on deck.** Clearly worth building; start once P1 is moving.
- **P3 — needs a trigger.** A dependency landing, a measurement, or
  real user demand should promote these before anyone starts.

Recently shipped and pruned from this file (see the release notes):
tally light with customizable colours (v1.8.0), 10-bit HDR (HLG) with
the zero-copy GPU path and Apple Log (v1.9.0), virtual green screen
with depth assist and subject-distance cutoff (v1.10.0). Pairing &
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
could send `start_stream`). A one-time pairing (PIN shown in the app,
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
`AVCaptureMultiCamSession` (iOS 13+) can run the front and a rear
camera simultaneously — one phone feeding a face cam *and* a scene cam
as two LensLink sources (a second connection with its own HELLO; the
plugin's per-source device pinning already gives each stream a home).
No competitor does this. It's P3 for a reason: multicam formats are
heavily restricted (no 4K, limited fps), the thermal budget for two
encodes is severe (prototype heat before UI), and the app's
capture/encode/listener plumbing is currently single-stream. *Trigger:
real user demand, and a thermal prototype that survives 30 minutes.*

### Manual bitrate cap — P3, small
Adaptive bitrate already reacts to congestion, but there's no user
ceiling. A cap (Options row, plus a live command so the web panel can
set it) keeps shared/metered networks and multi-phone rigs predictable.
STATE advertises the cap so remote UIs stay in lock-step. *Trigger:
users actually hitting the situations it solves; the adaptive path
covers most of them today.*

## Control & workflow

### Digital pan/tilt + crop — reframe without touching the rig — P2, medium
Zoom today is the camera's own, always center-locked. An adjustable
crop applied on the phone *before* encoding (Camera Hub's signature
control) lets the operator reframe a mounted phone from the web panel —
and because the full encode bitrate then covers only the cropped
region, it reads sharper than cropping in OBS. New CONTROL command with
a normalized crop rect, STATE carries it back, web panel and Live
screen get a drag-to-frame control. *The biggest quality-of-life gap
for the mounted-phone use case this app is built around.*

### iPad: keep streaming in Split View — P3, small
The app streams only while foregrounded (iOS suspends background
camera capture), which on iPad is a real limitation — a streamer might
want notes or chat beside the camera app. On supporting iPads,
`AVCaptureSession.isMultitaskingCameraAccessEnabled` (iOS 16+) lets
capture continue in Split View / Stage Manager. Gate on
`isMultitaskingCameraAccessSupported`, keep the listener alive, and
soften the "foregrounded only" wording where it applies. iPhone
still suspends — this is iPad-only relief. *Trigger: iPad users
asking; pairs naturally with the tally light for multi-window rigs.*

### Document the control API — Stream Deck without a plugin — P2, small
The web panel's endpoints (`/api/state`, `POST /api/control`) are
stable and already scriptable; what's missing is a docs page listing
the commands with curl examples and a Stream Deck "Website"-action /
Bitfocus Companion recipe. That unlocks hardware-button control without
shipping or maintaining a native Stream Deck plugin — revisit a real
plugin only if demand shows up. *Docs-only; a good first-contribution
item.*

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
- **Micro-optimizations** (poll cadences, timesync/ping rates, web-panel
  polling, recv-buffer tuning): all measured or bounded at ≪1% — not
  worth the review risk.

## How to use this document

Pick the top unclaimed P1, open a GitHub issue referencing the section,
and prune the entry here when it ships. Priorities are judgment, not
physics: if reality disagrees with one (a profile, a pile of user
requests, a platform shift), re-rank it — this file is a map, not a
promise.
