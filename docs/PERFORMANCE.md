# LensLink — Performance Notes

Where the cycles and joules actually go, what has been optimized, and how
to measure before optimizing further. The guiding rule: **the codec
hardware and the network are the floor** — the app/plugin code around them
should add as close to zero as possible.

## Where the cost is (by design)

| Stage | Where | Cost | Avoidable? |
|-------|-------|------|------------|
| Camera capture | iPhone ISP/sensor | fixed | No — it's the product |
| H.264/HEVC encode | iPhone media engine (VideoToolbox) | fixed | No (hardware block) |
| Send to socket | iPhone CPU (memcpy + syscall) | ~1 copy/frame | Minimized (see below) |
| Receive + parse | OBS-box CPU | ~0 copies | Already zero-copy into the decoder |
| H.264/HEVC decode | OBS-box GPU (D3D11VA/VideoToolbox/VAAPI) | fixed | Software fallback only when GPU fails |
| GPU→CPU frame download | OBS-box (`av_hwframe_transfer_data`) | 1 copy/frame | No — `obs_source_output_video` needs system memory |
| OBS async frame ingest | OBS-box (`obs_source_output_video`) | 1 copy/frame | No — OBS API copies internally |

## What the code already does (don't regress these)

**iOS app**
- Capture delivers **NV12 video-range** buffers (`420YpCbCr8BiPlanarVideoRange`)
  straight into VideoToolbox — no BGRA, no format conversion, and
  `alwaysDiscardsLateVideoFrames` sheds load instead of queueing it.
- Encoder is tuned for live use: real-time mode, no frame reordering,
  `PrioritizeEncodingSpeedOverQuality`, `MaxFrameDelayCount = 1`.
- One copy per frame out of the encoder (AVCC→Annex B into an owned `Data`,
  sized up-front with `reserveCapacity`). This copy is deliberate:
  wrapping VideoToolbox's block buffer zero-copy would pin encoder-pool
  buffers until TCP send completion — up to 12 in flight — and starve the
  encoder under congestion.
- **Header + payload are sent as two batched writes** (`NWConnection.batch`),
  so the frame payload is *not* memcpy'd a second time just to gain a
  20-byte header prefix (`StreamClient.sendVideoOnQueue`).
- Backpressure drops frames rather than queueing them (bounded memory,
  bounded latency), and adaptive bitrate reacts to send-delay/drops.
- **Dimmed = GPU idle:** the dim overlay disables the preview layer's
  connection, so no preview frames are rendered under the near-black
  cover (`CameraPreviewView.previewEnabled`). The outgoing stream is
  unaffected. On top of the existing OLED-black + brightness drop, this
  is the biggest saver for the "phone mounted behind the monitor" case.
- **The paused still samples at 1 Hz, not per frame.** `PausedStill.note`
  compares a timestamp per frame and, about once a second, reads a 64×36
  luma thumbnail — a few thousand reads whatever the resolution, never
  touching chroma. The still itself is drawn once when the pause starts
  and re-encoded (not redrawn) once a second, which a static frame
  compresses to tens of bytes. Nothing is retained from the capture pool
  between frames, so no buffer is pinned.
- Idle standby listener costs nothing measurable: no timers, no camera —
  just an accepting socket and 1 Hz timesync replies while OBS is
  connected.
- The health overlay's `@Published` sample is only written while the
  overlay is on screen (off by default). A 1 Hz publish on the main actor
  invalidates the whole Live view once a second, which is exactly the
  wakeup "dimmed = GPU idle" is trying to avoid; the counters advance
  regardless, so switching it on still reads correctly a second later.

**OBS plugin**
- The receive buffer is parsed **in place**; video packets go to
  libavcodec via pointer (`pkt->data = recv_buffer + offset`) — zero
  copies from socket to decoder. Compaction is one `memmove` of the
  unparsed tail per recv cycle (amortized, not per packet), and the
  buffer shrinks after keyframe spikes so memory isn't pinned.
- Decode is single-threaded with `LOW_DELAY` on purpose: frame threading
  adds a frame of latency per thread and buys nothing for a live stream
  that arrives one access unit at a time.
- One dial-loop thread per source, poll-driven at 200 ms when idle;
  timesync (1 Hz), control forwarding, and diagnostics all piggyback on
  that loop — no extra threads or timers.
- The web panel is a 1 Hz poll of two tiny JSON endpoints on loopback.
- Lip-sync cross-correlation runs **on the dial-loop thread**, so its cost
  is a hole in the video receive path, not spare CPU. Two things keep it
  small (`lipsync.c`): the mic window's energy comes from a prefix sum
  (successive lags overlap almost completely — recomputing it per lag was
  a second pass over the whole window), and the dot product uses four
  independent accumulators, because one `double` accumulator serializes
  the loop on FP-add latency regardless of how little else it does.
  Together: 1.51 ms → 0.90 ms per estimate, bit-identical results.
- It also runs **far less often**. What it measures — the mic's latency —
  is a property of the audio gear, while the number that actually moves
  is the video latency timesync already tracks for free. So the mic
  figure is latched once confident and the offset is re-derived from
  latency alone; the correlation returns only every 90 s to confirm the
  latched figure still holds (`lipsync-cal.h`). Over a quiet ten-minute
  stretch that is 6 correlations instead of 120 — and, more importantly,
  120 offset updates instead of none, since tracking no longer waits on
  someone talking.
- Once locked, the plugin also tells the phone to **stop the reference
  entirely** (`{"cmd":"reference","on":false}`): a live mic capture and
  ~256 kbit/s that teach the correlation nothing more, gone — including
  iOS's persistent mic indicator. It's requested back briefly around
  each periodic verification, and while measuring/relocking.
- Effect parameter handles are resolved **once**, with the effect, not per
  render (`yuv_effect()`). `video_render` runs per source per rendered
  frame on the graphics thread — the thread the whole compositor waits
  on — and `gs_effect_get_param_by_name` is a by-name lookup.

## How to measure (before optimizing further)

- **iPhone:** Instruments → *Energy Log* + *Time Profiler* while streaming
  1080p60 and 4K30, once undimmed and once dimmed. The app's own CPU
  should be single-digit percent; the energy split should be dominated by
  camera + display (undimmed) and camera only (dimmed).
- **OBS box:** OBS Studio → Tools → *Stats* (render/encode lag) plus the
  plugin's own log line (`capture->decode latency: avg …`) and, for CPU,
  a profiler over `obs64`/`obs` filtered to the `ios-camera-server`
  thread. That thread should be nearly all `recv`/`memmove`/decoder time.
- The wire protocol's TIMESYNC gives an end-to-end capture→decode latency
  figure continuously — watch it in the source's Status field; ~60 ms
  over USB at 1080p is the expected baseline.

### Pipeline benchmark (built-in, for the GPU-pipeline comparison)

Tools → LensLink Settings → **"Log pipeline benchmark numbers every
5 s"**. Every ~5 s of live streaming, one tagged line lands in the OBS
log:

```
[lenslink][bench] pipeline=standard | 1920x1080 ~60 fps |
  video-path cost/frame: avg 2.84 ms, max 4.10 ms |
  pixel copies: 186.4 MB/s | OBS process CPU: 9.8%
```

- **video-path cost/frame** — CPU time the plugin spends moving each
  decoded frame toward the compositor: GPU download + OBS's frame copy
  on the standard pipeline; texture map/draw prep on the GPU pipeline.
  This is the work the two pipelines do differently, isolated.
- **pixel copies** — decoded video crossing system memory (0 on a
  healthy GPU-pipeline run; nonzero there means the fallback engaged).
- **OBS process CPU** — sampled the same way OBS's own Stats dock does.

While the toggle is on, the plugin also writes one CSV row **per second
of live video** to `bench-<pipeline>-<epoch>.csv` in its config
directory (the OBS log prints the exact path when the file opens).

The before/after recipe:

1. Keep your normal settings, enable the benchmark toggle, and stream
   the scene for ~10 s or more. That's the **before** file.
2. Flip the GPU pipeline setting, restart OBS, and stream the same
   phone/scene/resolution for the same length. That's the **after**
   file.
3. Run `python3 tools/bench-report.py` in a terminal/command prompt.
   With no arguments it lists the benchmark files it finds in the
   plugin's config directory and asks you to pick the before and after
   runs (or pass the two CSV paths directly).
4. It prints and writes `lenslink-bench-report.md` (the comparison
   table — mean/median/p95 per metric with % change) and
   `lenslink-bench-report.html` (the same plus per-second charts),
   ready to paste into the repo.

Sanity check built into the report: "pixels crossing system memory"
must read **0.00** on the GPU-pipeline run — a nonzero value there
means the automatic CPU fallback engaged and the comparison isn't
measuring what you think. Those report numbers are what a performance
claim in this repo should cite.

Any future performance PR should quote at least one of these numbers
before/after.

## Measured results: standard vs GPU pipeline

Field measurements from the benchmark above — 12 configurations
(720p/1080p/4K × 30/60 fps × H.264/HEVC), ~25 s of live video each, same
PC (Ryzen 7 7800X3D, NVIDIA, D3D11) and same iPhone over Wi-Fi. Pixel
copies read **0.00 MB/s on every GPU-pipeline run**: the zero-copy path
engaged in all 12 configurations.

| Config | Cost/frame, mean (ms) | Pixel copies (MB/s) | OBS CPU (%) |
|---|---|---|---|
| 720p 30 H.264 | 1.14 → 0.09 (−92%) | 82 → 0 | 1.7 → 1.4 |
| 720p 30 HEVC | 0.81 → 0.09 (−89%) | 83 → 0 | 2.3 → 1.5 |
| 720p 60 H.264 | 1.09 → 0.10 (−91%) | 166 → 0 | 2.1 → 1.4 |
| 720p 60 HEVC | 0.81 → 0.09 (−89%) | 163 → 0 | 2.2 → 1.4 |
| 1080p 30 H.264 | 2.13 → 0.11 (−95%) | 187 → 0 | 1.7 → 1.6 |
| 1080p 30 HEVC | 1.48 → 0.10 (−93%) | 183 → 0 | 2.3 → 1.4 |
| 1080p 60 H.264 | 2.11 → 0.10 (−95%) | 370 → 0 | 2.3 → 1.6 |
| 1080p 60 HEVC | 1.42 → 0.09 (−93%) | 373 → 0 | 2.6 → 1.4 |
| 4K 30 H.264 | 7.71 → 0.10 (−99%) | 734 → 0 | 3.3 → 1.5 |
| 4K 30 HEVC | 4.96 → 0.14 (−97%) | 721 → 0 | 2.9 → 1.5 |
| 4K 60 H.264 | 7.54 → 0.10 (−99%) | 1221 → 0 | 4.1 → 1.8 |
| 4K 60 HEVC | 4.75 → 0.10 (−98%) | 1439 → 0 | 4.1 → 1.6 |

Reading: per-frame video-path cost drops 89–99% (the copy work simply
disappears), and the win scales with resolution — at 4K60 HEVC the
standard pipeline was pushing ~1.4 GB/s of decoded video through system
memory that the GPU pipeline eliminates outright, roughly halving OBS
process CPU. Capture→decode latency and decoded fps are measured before
the pipelines diverge and showed no systematic difference — those are
set by the network and the phone's encoder, not by the render path.

The table above is 8-bit. 10-bit streams (HLG / Apple Log) gained the
same zero-copy path (D3D11 shared P010, VAAPI R16/GR1616 dmabuf) a
release later; the sanity check applies unchanged — pixel copies must
read 0.00 with the GPU pipeline on, and at 10 bits the eliminated
copy traffic is 2× the 8-bit figures. A before/after bench pair for a
10-bit config still needs to be captured and pasted here (macOS is
excluded: VideoToolbox converts 10-bit to 8-bit BGRA itself, so HDR
there renders via the RGBA path).

## Measured results: where the latency goes, and what other codecs buy

An instrumented build (branch `claude/bench-stage-timings`) timed every
frame from both ends: the app timestamped capture, encoder in, encoder
out and the hand-off to the network; the plugin timed arrival, decode
and the copy into OBS, all on the TIMESYNC-corrected clock. The same
build switched experiments on and off at runtime and scored quality the
way streaming services do: the phone encoded the same raw camera frames
once per configuration and FFmpeg's VMAF compared each against the raw
frames. iPhone 15 Pro over USB (Windows, D3D11VA decode), 60 s per
latency run.

**Where 36 ms of 1080p60 latency goes** (HEVC, Balanced):

| Stage | ms |
|---|---|
| Capture → encoder input (sensor, ISP, delivery; stabilization already off) | 28.0 |
| Encode (VideoToolbox HEVC) | 7.6 |
| Encoder output → network stack | 0.3 |
| USB transfer | ~0.15 |
| Decode (D3D11VA) | 0.14 |
| Into OBS (download + frame copy; ~0.1 on the GPU pipeline) | 1.5 |

The camera stage dominates; the codec is a fifth of the total and the
PC side is under 2 ms. No decoder change on the PC can buy more than
that.

**Encoder quality mode costs 47 ms at 4K and buys nothing.** 4K30 has
exactly 1080p120's pixel rate, so `qualityPriorityAffordable` used to
let Maximum's quality-first encoder mode through. Frame rate held, but
each frame took 69 ms to encode instead of 22:

| 4K30 Maximum | Capture → arrival | Encode | VMAF (same frames) |
|---|---|---|---|
| Quality mode (before) | 106.6 ms | 69.4 ms | 98.51 |
| Speed mode (now) | 59.7 ms | 22.5 ms | 98.59 |

Repeated with 10-bit 4:2:2 capture: VMAF 97.28 vs 97.37. Maximum now
keeps speed mode above 1080p; at 1080p and below quality mode costs
about 3.5 ms and stays.

**The USB link carries about 300 Mbps, whatever the cable.** USB 2 and
USB 3 (SuperSpeed confirmed) cables gave identical results in every
run; the limit is the usbmuxd / Apple Mobile Device Service path, which
sustained about 37 MB/s. Within that, bigger frames simply take longer
to cross: pinning HEVC Maximum at 100 Mbps (1080p60) added 4.2 ms of
transfer and about 6 ms end to end; 150 Mbps at 4K30 added 9.3 ms.

**Encoder quality** (1080p60, VMAF against the raw frames; about 6
points is the smallest difference most viewers notice):

| Config | Mbps | VMAF | Worst frame |
|---|---|---|---|
| HEVC Balanced | 4.8 | 90.8 | 82.7 |
| HEVC Maximum (USB ceiling) | 28 | 97.2 | 93.4 |
| HEVC pinned at 100 Mbps | 100 | 98.7 | 96.7 |
| ProRes 422 Proxy | 65 | 98.0 | 96.0 |
| ProRes 422 LT | 174 | 99.8 | 98.5 |

Maximum is the sweet spot: Balanced shows visible bad moments in
motion, Maximum doesn't, and the steps above it are under 3 VMAF points
for 3.5× to 6× the data. (During these captures the camera delivered
fewer frames while seven encoders ran, which makes HEVC's job harder
than live and favours ProRes; the ranking held anyway.)

**ProRes works but doesn't pay.** The 15 Pro encodes ProRes in real
time and faster than HEVC (5.5 ms vs 7.6 at 1080p60), but its frames
are about 7× bigger: ProRes LT 1080p60 (~205 Mbps) streamed at 60 fps
for 44 ms capture → arrival, about 4 ms behind HEVC Maximum, with
software decode at about 1.2 ms and 4% OBS CPU. ProRes HQ at 1080p60
and LT at 4K30 exceed the USB path (39 and 22 fps). Its colour scores
showed no keying advantage over HEVC, even from 10-bit 4:2:2 capture.

## Apple capture guidance: what we follow, what we deliberately don't

The iOS capture/encode path was audited against Apple's AVFoundation and
VideoToolbox guidance for real-time capture. Followed: `RealTime` +
`AllowFrameReordering=false` (no B-frames) + `PrioritizeEncodingSpeed
OverQuality` + `MaxFrameDelayCount=1` on the encoder, average bitrate
with a hard data-rate cap (1.5× over one-second windows), 2-second
keyframes, `alwaysDiscardsLate
VideoFrames`, session interruption/runtime-error observers with restart,
and — per the `systemPressureState` docs — thermal/power mitigation:
at `.serious` the bitrate is halved, at `.critical` it's quartered and
the frame rate halves (60→30, 30→15), restored when pressure abates.

**Quality → Maximum** (Format sheet) relaxes three of those on purpose,
and only there: speed-over-quality off (1080p and below only; above it
quality mode costs ~47 ms per frame for no measurable gain, see the
measured results above), the peak cap at 2×, keyframes
every 4 s (the plugin requests one on join). It also turns the adaptive
loop from "back off from a fixed target" into a probe: start at 2× the
table, +15% per 3 clean seconds up to 6× (USB) or 4× (Wi-Fi) the table,
hold while sends queue 60–200 ms, cut a quarter on a drop or >200 ms,
and stay under the level that broke for a minute. Same one-second
cadence and the same counters the health readout uses — no new sampling
and no new thread. Balanced keeps the original behaviour exactly.

Deliberate divergences (don't "fix" these without reading this):

- **Frame durations are locked** (min = max = 1/fps). Apple's default
  lets auto-exposure sag the frame rate in low light, like the Camera
  app's Auto FPS. A sagging cadence hurts the encoder's rate control,
  OBS timing, and the lip-sync/latency math; we hold cadence and let the
  image get noisier instead. Two sanctioned exceptions: the thermal
  throttle above, and the opt-in **Allow system video effects** toggle
  (Options), which leaves the max duration at the format default —
  the Control Center effects appear to require that downward
  flexibility, and the toggle exists to prove or disprove exactly that.
  The thermal path keeps max unlocked too while the toggle is on.
- **Video stabilization is off by default** (the AVCaptureVideoDataOutput
  default). Every stabilization mode adds frames of latency; this is a
  latency-first product, so it exists only as the opt-in Options →
  Stabilization (Standard or Cinematic), never switched on by the app.
- **The wire defaults to 8-bit 4:2:0 video-range** (`420v`). The
  opt-in colour modes switch the camera path to 10-bit end-to-end —
  HLG captures `x420`, Apple Log captures `x422` (its formats are the
  10-bit-422 class; VideoToolbox does the 4:2:0 downsample inside the
  Main10 encode) — but 10-bit only ever enters the pipeline through
  that setting. SDR capture, the screen mirror, and the H.264 path
  stay 8-bit; keep the 8-bit paths free of 10-bit branches (the
  decoder maps formats per-frame, so SDR costs nothing extra).
- **Rotation is sensor-native** (`.landscapeRight`, an effective 0°).
  The AVCaptureConnection docs warn per-frame rotation costs; we never
  rotate the stream, only the on-phone preview.
- **Green screen OFF is free, ON pays exactly once.** With the toggle
  off, the capture→encode path is the pre-feature code verbatim — no
  compositor branch on the hot path, no depth output attached. On, the
  budget is: Vision person segmentation per frame (`.fast` above
  30 fps, `.balanced` at 30 — the dominant cost), one Metal compute
  pass writing green into a pool buffer (that pass *is* the single
  copy; the camera's own buffer is never written in place — it races
  the encoder's async read), and depth at ~15 Hz when assist is
  active. Depth delivery deactivates Center Stage and the system video
  effects by iOS policy, and overload sheds frames via the existing
  drop-don't-queue capture behaviour. On-device bench + thermal-soak
  numbers for green-screen-ON are still to be captured and pasted
  here; the OFF run must show the zero-cost claim holds.
