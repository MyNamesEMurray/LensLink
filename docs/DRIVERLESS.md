# Driverless mode — the phone as a plain webcam

**Status: in progress.** The bridge (stage 1) is built and testable. The
virtual-camera backends that make the phone appear in Teams and Zoom are
stages 2 and 3 — see [Where this stands](#where-this-stands).

Today LensLink needs OBS. That is a large ask for someone who only wants
their iPhone to be the camera in a Teams call. Driverless mode removes
OBS from that path: a small resident program dials the phone exactly the
way the plugin does, and publishes the decoded video as a system camera
that any app can pick.

## What "driverless" can and cannot mean on Windows

There is no way to make Windows see an iPhone as a webcam with *nothing*
installed on the PC. An iPhone cannot present itself as a USB Video Class
device — iOS has no UVC gadget mode, and the port speaks only Apple's own
protocols. Continuity Camera works because Apple owns both ends; Windows
11's own Connected Camera feature is Android-only and closed to third
parties.

So driverless here means what Camo, EpocCam and Iriun mean by it:

- **no kernel-mode driver**, and nothing signed by Microsoft's hardware
  program;
- **no OBS**, and no per-app plugin;
- one small user-mode install that registers a virtual camera, after
  which the phone is in every app's camera dropdown.

USB keeps one asterisk that no competitor avoids either: the usbmuxd
transport needs Apple Mobile Device Support, which arrives with iTunes.
Wi-Fi is the zero-extra-install path.

## Shape

```
iPhone (app unchanged)  ──TCP 9979──▶  lenslink-bridge
                                          │  dial + decode + NV12
                                          ├─▶ Media Foundation vcam  → Teams, Camera app, Chromium
                                          ├─▶ DirectShow filter      → Zoom, Discord, 32-bit apps
                                          └─▶ control panel :9980    → the plugin's own web UI
```

Two virtual-camera backends rather than one, because the ecosystem is
split. Media Foundation (`MFCreateVirtualCamera`, Windows 11 22000+)
covers new Teams, the Windows Camera app and Chromium's capture path;
a DirectShow filter covers Zoom and anything 32-bit. Windows 10 gets
DirectShow only.

The bridge is resident because it has to be: something must hold the TCP
connection and the decoder, and an MF virtual camera is tied to the
lifetime of the process that creates it. A filter DLL loaded inside
Zoom's process cannot be the thing dialing a phone.

### No new wire protocol

The bridge speaks protocol version 1 unchanged. It is another dialer, not
a new peer — nothing in `docs/PROTOCOL.md` moves for this feature, and an
app build from before driverless mode existed works with it. Keep it that
way.

### Shared code, not copied code

The bridge compiles four of the plugin's own sources **unmodified**:

| File | What it brings |
|------|----------------|
| `usbmux.c` | the USB transport |
| `mdns.c` | Bonjour discovery of `_lenslink._tcp` |
| `h264-decoder.c` | H.264/HEVC decode with the GPU fallback walk |
| `web-control.c` | the entire browser control panel and `/api/*` |

`bridge/src/compat/` is a small shim providing the slice of libobs those
files call — `blog`, the `bmalloc` family, `os_gettime_ns`, and the
video-format declarations that keep a dead branch compiling. It is about
250 lines and it exists so that the two builds cannot drift: the bridge's
transport behaviour is not *like* the plugin's, it is the plugin's.

`web-control.c` deserves a specific note. It talks to a source through
twelve upcalls declared in `web-control.h`; the bridge implements those
against its own connection state, and the browser panel then works with
no changes at all — same HTML, same `/api/state`, same `/api/control`.
That is why `bridge-core.c` names its type `struct ios_camera_source`.

The dial loop itself is a second implementation, in `bridge-core.c`. It
mirrors `ios-camera-source.c` minus everything OBS-shaped. That is a real
duplication and the plan is to collapse it: the next refactor lifts the
shared logic into a `lenslink-core` library both binaries link. It was
not done first because the extraction touches 3,500 lines of shipping
plugin code and the bridge needed to exist before it could be proven
against.

## What driverless mode does not do

A webcam is a narrower contract than an OBS source, and some of what
LensLink does has nowhere to go.

**Gone entirely**

- **All audio.** A virtual camera carries no audio track; Teams and Zoom
  pick a microphone separately. Shipping phone audio would need a virtual
  *audio* device, which on Windows genuinely is a signed kernel driver —
  the exact thing this mode exists to avoid. So the phone-mic source
  (`SCREEN_AUDIO`, type 10) is out, and the lip-sync reference (type 9)
  with it. The bridge drops both packet types.
- **Lip-sync calibration.** Meaningless with no second audio device to
  align against: the meeting app does its own A/V sync across two
  independent devices. `/api/state` reports `sync: "off"` permanently.
- **The OBS chroma-key auto-filter.** Green screen composites *on the
  phone*, so the feed arrives green and there is nothing downstream to
  key it. Still useful paired with Zoom's own "I have a green screen"
  option; useless otherwise.
- **Zero-copy GPU output.** The plugin's GPU pipeline keeps frames on the
  card all the way to the compositor. A virtual camera hands the meeting
  app system memory either way, so the pipeline ends in a readback. GPU
  *decode* still pays off; the zero-copy invariant in
  `docs/PERFORMANCE.md` does not apply to this path, and a performance
  claim about it needs its own before/after numbers.

**Reduced**

- **Tally** loses program versus preview — there is no scene graph. The
  honest signal is "an app has the camera open".
- **Format changes mid-call.** OBS follows whatever the bitstream says.
  DirectShow and Media Foundation must advertise a fixed media-type list
  up front, and most apps pick once at open. Expect `set_format` while a
  meeting app is attached to be ignored or to require reopening the
  camera there.
- **HDR and Apple Log.** 10-bit input is truncated to 8-bit NV12
  (`nv12.c`): a webcam feed has nowhere to put the extra bits.
- **USB** needs iTunes, as above.
- **One consumer per phone.** The app's listener is "newest connection
  wins" (`StreamClient.swift`), so the bridge and the OBS plugin dialing
  the same phone will fight. Run one or the other until the fan-out
  design below lands.

**Unchanged:** everything the phone does — capture, encode, zoom, focus,
exposure, white balance, flashlight, remote start, adaptive bitrate,
Bonjour discovery — plus the whole browser control panel and its HTTP
API.

## Where this stands

| Stage | What | State |
|-------|------|-------|
| 1 | Bridge: dial, decode, NV12, control panel, CI artifacts | **done** |
| 2 | DirectShow backend (Zoom, Discord, 32-bit apps) | next |
| 3 | Media Foundation backend (Teams, Camera app, Chromium) | after 2 |
| 4 | Tray UI, installer, autostart | after 3 |
| 5 | `lenslink-core` extraction; plugin and bridge share one dial loop | follows |

Stage 1 is testable on its own: it proves the phone connects, the stream
decodes, the control panel works and the frames are real pixels. What it
cannot yet do is appear in a camera dropdown — that is stage 2.

Two things worth deciding before stage 4:

- **Fan-out.** Once the bridge is the sole dialer it can feed several
  consumers from one connection and one decode — the virtual camera *and*
  an OBS source at the same time. That is the single feature that makes
  the daemon architecture worth its costs, and it wants designing before
  the installer sets the shape in users' minds.
- **Multiple phones.** The config file and the control panel are already
  multi-device; the virtual-camera backends need to decide whether that
  means a fixed pair of registered cameras or dynamic registration.

## Building and testing

See [`bridge/README.md`](../bridge/README.md) for the commands, the
config file, and how to run the whole pipeline against a simulated phone
with no iPhone in the room.

CI (`.github/workflows/bridge.yml`) builds the bridge on Linux and
Windows and uploads runnable executables. It runs on **pushes to
`dev/**` branches**, not only on pull requests, because this feature can
only really be validated by pointing a real binary at a real phone.
