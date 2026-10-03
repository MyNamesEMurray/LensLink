# LensLink — Wire Protocol (version 1)

The iOS app **listens** on TCP port **9979** on the device; the OBS plugin
**dials** it — over the LAN (the phone's IP, shown in the app) or through
usbmuxd (USB cable). Once connected, the app immediately sends HELLO and
the packet stream begins.

All multi-byte integers are **big-endian** (network byte order).

## Packet framing

Every packet starts with a fixed 20-byte header, immediately followed by
`payload_size` bytes of payload:

| Offset | Size | Field          | Notes                                    |
|--------|------|----------------|------------------------------------------|
| 0      | 4    | magic          | ASCII `OBSC` (0x4F 0x42 0x53 0x43)       |
| 4      | 1    | version        | `1`                                      |
| 5      | 1    | type           | see packet types below                   |
| 6      | 2    | flags          | bit 0 (`0x0001`) = keyframe (video only) |
| 8      | 8    | pts            | presentation timestamp, **nanoseconds**  |
| 16     | 4    | payload_size   | max 16 MiB (`16 * 1024 * 1024`)          |

A receiver that sees a bad magic, an unknown version, or an oversized
`payload_size` must drop the connection.

## Packet types

### 1 — HELLO
Sent once by the client right after the TCP connection is established.
Payload: UTF-8 JSON, e.g.

```json
{ "name": "Emma's iPhone", "app": "LensLink", "protocol": 1, "kind": "camera" }
```

`kind` is `"camera"` (the app) or `"screen"` (the screen-mirror broadcast
extension); it lets the plugin label the source and, for `screen`, expect
system audio (packet type 10) instead of camera controls. Absent = camera.

An optional `"standby": true` means the app is reachable but the camera
isn't running yet (the app is open and idle). No video follows until the
plugin sends a `start_stream` control command (type 7). The app re-sends
HELLO (without `standby`) when the stream starts; the plugin also treats
VIDEO_CONFIG as leaving standby, so either signal suffices. Absent = a
live stream follows as usual.

Alongside `standby`, `"armed"` says whether the user has armed remote
start on the phone. `"armed": false` means the app will refuse
`start_stream`: the plugin shows that the phone is connected but not
armed, offers no Start button, and does not auto-start. The app re-sends
HELLO whenever arming changes, so `"armed": true` arriving on the same
connection is the cue to auto-start. Absent = armed: apps from before
arming existed honoured `start_stream` whenever they were in standby.

```json
{ "name": "Emma's iPhone", "app": "LensLink", "protocol": 1,
  "kind": "camera", "standby": true, "armed": false }
```

A plugin older than `armed` ignores it, so to such a plugin an unarmed
app looks like ordinary standby: it may auto-send `start_stream`, which
the app refuses by re-sending its HELLO (the plugin then shows plain
standby instead of "starting"). Once the user arms, that plugin's
auto-start has already been spent, so the camera starts from its
**Start camera on the phone** button or from the phone.

### 2 — VIDEO_CONFIG
Sent after HELLO and again whenever the capture format changes.
Payload: UTF-8 JSON, e.g.

```json
{ "codec": "h264", "width": 1280, "height": 720, "fps": 30, "kind": "camera" }
```

`codec` is `"h264"` or `"hevc"` and selects the plugin's decoder; a codec
change mid-stream resets the decoder (the next keyframe re-initializes it).
`kind` mirrors the HELLO field. Dimensions/fps are informational; the
authoritative values come from the bitstream parameter sets.

An optional `"color"` field names the stream's colour mode: `"hlg"`
(10-bit HEVC, BT.2020 primaries, HLG transfer) or `"log"` (10-bit
HEVC, **Apple Log 1**: BT.2020 primaries and matrix, Apple's log curve
— the VUI carries transfer *unspecified*, because H.273 has no code
point for Apple Log; the receiver shows the flat log image untouched
for LUT grading). `"log2"` (Apple Log 2, which uses Apple-Gamut
primaries, not BT.2020) is reserved and must not be sent as `"log"`.
Absent = 8-bit SDR BT.709, which every stream was before the field
existed. For `"hlg"` the field is **informational** — the decoder
takes the authoritative colour description from the bitstream's VUI;
for `"log"` it is the *only* label (an elementary stream cannot carry
Apple Log identity), though a receiver that ignores it still renders
the flat image correctly since the VUI's matrix/primaries are real and
transfer-unspecified decodes as-is. 10-bit streams are HEVC-only (the
iPhone encoder has no 10-bit H.264) and camera-only (screen broadcast
stays 8-bit).

### 3 — VIDEO
Payload: one H.264 or HEVC **access unit in Annex B format** (start-code
delimited NAL units), per the codec announced in VIDEO_CONFIG. Keyframe
packets must set the keyframe flag and must be self-contained: parameter
sets (SPS/PPS for H.264, VPS/SPS/PPS for HEVC) are prepended before the
IDR/IRAP slice so a decoder can join mid-stream.

`pts` is the capture presentation timestamp in nanoseconds. It only needs to
be monotonic; OBS re-bases async timestamps itself.

### 4 — PING
Optional keep-alive, empty payload, sent by the app every ~2 s.
The plugin ignores it.

### 5 — TIMESYNC_REQ (plugin → app)
Empty payload; `pts` = the plugin's monotonic clock (t1, nanoseconds).
Sent about once a second while connected.

### 6 — TIMESYNC_RESP (app → plugin)
Sent immediately upon receiving a TIMESYNC_REQ. `pts` = the device's
host clock (t2) — the **same clock domain as video frame timestamps** —
and the payload is the echoed 8-byte big-endian t1.

The plugin computes, NTP-style, with t3 = its clock at receipt:
`rtt = t3 - t1`, `offset = t2 - (t1 + t3)/2` (phone clock minus plugin
clock, error ≤ rtt/2). Per-frame capture→decode latency is then
`now - (frame_pts - offset)`, logged and shown in the source status.

### 7 — CONTROL (plugin → app)
Camera remote control. Payload: UTF-8 JSON, one command per packet:

```json
{ "cmd": "zoom", "value": 2.0 }
{ "cmd": "exposure_bias", "value": -0.5 }
{ "cmd": "focus", "mode": "auto" }
{ "cmd": "focus", "mode": "locked", "lensPosition": 0.42 }
{ "cmd": "focus", "faces": true }
{ "cmd": "flashlight", "on": true }
{ "cmd": "natural_blur", "on": true }
{ "cmd": "flip" }
{ "cmd": "selectLens", "label": "Ultra Wide (0.5×)" }
{ "cmd": "white_balance", "mode": "locked", "temperature": 5600 }
{ "cmd": "white_balance", "mode": "auto" }
{ "cmd": "white_balance", "mode": "calibrate" }
{ "cmd": "white_balance", "mode": "calibrate", "x": 0.31, "y": 0.62 }
{ "cmd": "lock", "target": "whiteBalance", "on": true }
{ "cmd": "stabilization", "mode": "cinematic" }
{ "cmd": "exposure", "mode": "manual", "iso": 400, "shutterSeconds": 0.004 }
{ "cmd": "exposure", "mode": "auto" }
{ "cmd": "start_stream" }
{ "cmd": "stop_stream" }
{ "cmd": "pause_stream" }
{ "cmd": "resume_stream" }
{ "cmd": "set_format", "resolution": "1080p", "fps": 60, "codec": "hevc" }
{ "cmd": "set_quality", "quality": "maximum" }
{ "cmd": "mic", "id": "builtin:2" }
{ "cmd": "tally", "program": true, "preview": false, "sync": "locked" }
{ "cmd": "green_screen", "on": true, "maxDistance": 2.5 }
{ "cmd": "identify", "host": "Studio-Mac", "obs": "32.0.1", "transport": "usb" }
```

`white_balance` with `"mode": "calibrate"` locks white balance so the
centre of the picture (white paper or a gray card held there) comes out
neutral; the app measures that patch in live frames over a few rounds.
The app's own eyedropper does the same at a tapped point, and so does
the command when it carries `x` and `y`: a point in the streamed
picture, normalized 0–1 from the top-left, as OBS shows it (the web
panel's eyedropper picks it on a still from `GET /api/still`). Apps
older than the point fields ignore them and use the centre. The result arrives in STATE as `"locked"` with the measured
`whiteBalanceTemperature` and `whiteBalanceTint`. An app older than this
command treats it as `"auto"`.

`lock` is the app's tray Lock button: `on: true` freezes what auto is
doing right now for `target` — `"focus"`, `"whiteBalance"`,
`"exposure"` (ISO and shutter together) or `"all"` — so the picture
doesn't jump the way a `locked`/`manual` command carrying stale values
would; `on: false` hands it back to auto. Apps that predate it ignore
it; remote UIs tell them apart by the absence of `lensFactors` in STATE
and fall back to the explicit-value commands.

`stabilization` sets the video stabilization mode: `"off"`,
`"standard"` or `"cinematic"` (the app's Options setting; the camera
runs it off while depth assist does). STATE reports it as
`stabilization`.

`set_format` switches the capture format mid-stream; any subset of its
fields may be present. The app validates the combination against the
active lens (the STATE snapshot advertises the valid choices in
`resolutions` / `frameRates` / `codecs`, plus the current `resolution` /
`fps` / `codec`) and ignores unsupported requests. A format change flows
through the normal live-reconfigure path: new VIDEO_CONFIG, fresh
keyframe, decoder reset on a codec change.

Screen-mirror connections honour only `set_format`'s `fps`, 60 or 30. The
plugin's LensLink Screen source sends `{ "cmd": "set_format", "fps": 30 }`
on every new connection and whenever its **Frame rate** property changes
(the same on-change + re-announce contract as `tally`). The phone keeps
capturing at the display's rate and skips frames down to the requested
rate before encoding, scaling the bitrate with it, and announces the new
rate in the next VIDEO_CONFIG. An older app ignores it and sends 60.

`set_quality` picks the bitrate strategy: `"balanced"` (the app's table,
safe on ordinary Wi-Fi, the adaptive loop only backs off from it) or
`"maximum"` (starts higher and probes upward while the link is clean, to
a transport-set ceiling, with the encoder's quality-first settings). The
STATE snapshot reports it as `quality`. A live stream rebuilds its
encoder on the change, like a format change.

`selectLens` switches to the lens whose `label` matches one of the STATE
snapshot's `lenses` (English labels such as `"Main (Wide)"`, never
translated). The app ignores an unknown label, and a lens that can't
capture the current `resolution` / `fps`. `flip` is the shortcut that
moves to a lens on the other side that supports the current format.

`mic` selects which microphone feeds the phone-mic capture, hot-switchable
mid-stream. Ids come from the STATE snapshot's `mics` list: `"auto"`
(system routing), `"builtin:<dataSourceID>"` (a physical phone mic —
Bottom/Front/Back), or `"port:<uid>"` (an external input). The app
validates the id against the live list and ignores stale ones (e.g. a
Bluetooth mic that just disconnected).

`tally` drives the app's on-air light and its lip-sync readout. `program`
is true while the source is part of what OBS is actually sending out;
`preview` is true when it's visible somewhere else (preview, a projector)
but not on air — the two are mutually exclusive, and both false means
neither. `sync` reports auto lip-sync calibration as one of `"off"`,
`"measuring"`, `"locked"` or `"relocking"` (see docs/UI_DESIGN.md for the
words and colours each maps to).

Unlike the camera commands, `tally` is sent **on change** rather than on
request, and re-announced on every new connection — a device is never
assumed to remember what it was last told. The app clears the light
whenever the connection drops, so a stale "live" can't outlive the OBS
that set it. Screen-mirror connections receive it too and ignore it: the
broadcast extension has no UI.

`natural_blur` turns the 180° shutter rule for auto exposure on or off:
while on, auto exposure never runs the shutter slower than half the frame
interval (1/60 at 30 fps) and raises ISO instead. The STATE snapshot
reports it as `naturalBlur`; an app that predates it ignores the command
and omits the field.

`focus` takes any subset of its fields: `mode` (`"auto"` / `"locked"`)
with an optional `lensPosition`, and `faces` — whether the camera should
keep focus and exposure on the faces it sees while on auto (the STATE
snapshot reports it as `faceFocus`, and `supportsFaceFocus` says whether
this camera can). Absent fields are left as they are.

`identify` is the plugin introducing itself, sent once per connection
right after HELLO: `host` is the computer's host name (any domain tail
stripped), `obs` the OBS Studio version, `transport` `"usb"` or `"lan"`
for how the plugin dialed. The app uses it to name the computer on its
Home screen; it forgets the values when the connection drops. Fields may be empty strings where the plugin couldn't
learn them, and an older app ignores the command.

`reference` gates the lip-sync reference (packet type 9):

```json
{ "cmd": "reference", "on": false }
```

The reference costs the phone a live mic capture and ~256 kbit/s for as
long as it runs, but once the plugin's calibration has locked the mic
latency it has nothing left to learn — so the plugin sends `on: false`
after locking, and `on: true` while measuring/relocking and briefly
around each periodic re-verification. Same on-change + re-announce
contract as `tally`. The app only ever honours it *within* the user's own
settings: `on: true` never starts a capture whose **Auto lip-sync
reference** toggle is off, and `on: false` never touches a mic capture
serving as source audio (type 10). An older app ignores the command and
streams continuously, which the plugin handles fine; a plugin that never
sends it gets today's always-on behaviour.

`green_screen` toggles the virtual green screen and its depth cutoff;
either field may appear alone. `on` arms/disarms the segmentation +
green composite (the compositing happens **on the phone, before
encoding** — the wire carries ordinary video whose background happens
to be chroma green, so receivers need no new decode behaviour).
`maxDistance` (metres; `0` = no cutoff, `-1` = Auto, which keeps the
cutoff about 0.6 m behind the person the depth map finds,
otherwise 0.5–5.0) drives the depth-assisted subject cutoff and is meaningful only while depth
assist is active — the app clamps and ignores as needed. Green screen
is SDR-only: arming it forces the Standard colour pipeline, and the
STATE fields below keep every surface honest about what's running.
Camera connections only; screen mirror ignores it.

Unknown commands are ignored, so new ones can be added compatibly. The
plugin's embedded web panel (http://localhost:9980) generates these.

`pause_stream` / `resume_stream` **hold** a running stream instead of
ending it: the app keeps the connection, the camera and the encoder, and
stops sending the camera's frames. In their place it draws a **held
picture** — the last frame blurred to a 64×36 thumbnail and back, in
grey, with a pause glyph — and sends that as ordinary VIDEO, forced to a
keyframe, about once a second for as long as the pause lasts. Repeating
it is what covers a source shown again mid-pause or a plugin that
reconnects; a static frame costs tens of bytes. Drawing it here rather
than in the plugin is deliberate: as video it reaches every decode
pipeline, where a plugin-side drawing could only ever work for the
standard one (the GPU pipeline keeps frames in textures). Audio is unaffected — a phone acting as the
wireless mic keeps carrying the show. Resuming asks the encoder for a
keyframe, so the plugin has something self-contained to restart decoding
on. Unlike remote start these need no arming: they can only hold a
stream the user already started, never turn a camera on.

`start_stream` / `stop_stream` are the **remote start** commands: they
start/stop the camera itself (not just the connection). `start_stream`
is honoured only while remote start is **armed** in the app (see HELLO);
`stop_stream` is honoured always (apps before 1.17.1 also required
arming), since it can only turn the camera off. Arming: the user
taps **Arm Remote Start** (or turns on **Arm remote start on open**), and
it stays armed until they disarm it, stop a stream on the phone, or leave
the app. A `stop_stream` keeps it armed. A `start_stream` the app refuses
makes it re-send its HELLO. The plugin sends `start_stream` when the user
clicks **Start camera on the phone** (source properties or web panel), or
automatically on receiving an armed standby HELLO when its **auto-start**
option is enabled — but only if the app was previously unreachable (just
opened or foregrounded) or reported itself unarmed, so stopping the
stream on the phone doesn't bounce straight back into streaming (a stop
on the phone also disarms). With
**Disconnect when this source isn't shown anywhere** plus auto-start, the
plugin sends `stop_stream` before dropping the connection on hide and
`start_stream` again on show.

### 8 — STATE (app → plugin)
Camera-state snapshot, sent (debounced ~200 ms) whenever a control value
changes and once on connect. Payload: UTF-8 JSON, e.g.

```json
{ "zoom": 2.5, "maxZoom": 10, "exposureBias": -0.5,
  "focusMode": "locked", "lensPosition": 0.4,
  "faceFocus": true, "supportsFaceFocus": true,
  "quality": "balanced",
  "flashlight": true, "hasFlashlight": true, "camera": "back" }
```

The plugin caches the latest snapshot and serves it at `/api/state` so
remote UIs mirror the app (and vice versa) regardless of where a change
was made.

The snapshot also carries white-balance and manual-exposure state
(`whiteBalanceMode`/`whiteBalanceTemperature`/`whiteBalanceTint`, the
tint being 0 unless set by a calibration, `exposureMode`/`iso`/
`shutterSeconds` with their ranges `minISO`/`maxISO` and
`minShutterSeconds`/`maxShutterSeconds` (the longest shutter is capped
at one frame interval, so it follows `fps`), plus
`supportsWhiteBalanceLock` and `supportsManualExposure` so UIs hide what
the camera lacks), the lens (`lens`, the current label, and `lenses`,
every label the phone has, for `selectLens` pickers, with
`lensFactors`, each lens's magnification relative to Main in the same
order, so remote UIs can label lens buttons `.5 · 1× · 3` as the app
does, and `cropZoom`, Main's full-detail sensor crop zoom when the
format has one and the camera can zoom), `stabilization`, and the capture
format (`resolution`/`fps`/`codec` with `resolutions`/`frameRates`/
`codecs` capability lists for `set_format` pickers).

While a 10-bit colour pipeline is active the snapshot says so —
`"hdr": true` for HLG, `"color": "log"` for Apple Log — and the
`codecs` list shrinks to `["hevc"]`, which is how remote UIs refuse
H.264 through the ordinary `set_format` validation. Both fields are
absent on SDR streams, whose snapshots are unchanged from before
colour modes existed.

Pause rides the snapshot too, so surfaces can say *why* a picture is
held rather than only show it: `"paused": true` while video is held, with
`"pauseReason"` saying who held it — `"user"` for an operator pause (the
app's Pause button, the web panel, or the source properties) or
`"camera"` when iOS interrupted capture (another app opening the camera
beside LensLink on an iPad, say). The reason is what lets a surface choose between offering a Resume button
and explaining that the phone is waiting on iOS.

Green screen state rides the snapshot the same way:
`"supportsGreenScreen": true` advertises the feature (remote UIs gate
their row on it; the app sends it only when green screen was on at
stream start or has been turned on since, so a user who never uses it
doesn't see the row), `"greenScreen": true` appears while it is armed,
`"greenScreenDepth": true` while depth assist is actually running
(TrueDepth front / LiDAR rear Main lens, and a depth-capable format
matched — absent means segmentation-only; remote UIs key the distance
control off truthiness), and `"greenScreenMaxDistance"` carries the
cutoff in metres when one is set, or `-1` while it is on Auto (absent
means no cutoff). Older apps treat a `-1` command as no cutoff, and
older panels show a `-1` snapshot as "All". Boolean snapshot fields are emitted
only when true: a receiver's STATE cache has finite room (older
plugins truncate silently past 1 KiB), so snapshot growth is real
cost — weigh every new field against it. The plugin also reacts to `"greenScreen": true` on a
camera source by auto-adding a pre-configured chroma-key filter —
once, by name, respecting a user's later deletion of it.

While the phone mic streams as the source's audio (packet type 10), the
snapshot additionally carries `micEnabled: true`, the selected `mic` id,
and the selectable `mics` list (`[{ "id", "name" }, …]`) for the `mic`
command's pickers. Absent otherwise, so remote UIs key their mic row off
`micEnabled`.

### 9 — AUDIO (app → plugin)
Reference audio for lip-sync auto-calibration. Payload: raw **16 kHz mono
signed-16-bit little-endian PCM**; `pts` = capture time of the first
sample, in the same clock domain as video frames. Sent in ~100 ms chunks
only while the app's "Auto lip-sync reference" option is on.

This audio is **never played out**. The plugin converts each chunk's pts
to its own clock (via the TIMESYNC offset), builds an amplitude envelope,
and cross-correlates it against the OBS microphone the user selected. The
correlation peak is the mic's true latency `L_mic`; the applied sync
offset is then `L_v − L_mic` (video latency minus mic latency), measured
directly with no manual entry. Low-confidence windows (silence) hold the
last value.

### 10 — SCREEN_AUDIO (app → plugin)
**Playable audio**, output as the source's audio in OBS via
`obs_source_output_audio` — unlike type 9, this is not a lip-sync
reference. Payload: raw **48 kHz stereo signed-16-bit little-endian
interleaved PCM**; `pts` = capture time of the first sample, in the same
clock domain as the video frames, so OBS keeps A/V aligned.

Two senders use it:

- the **broadcast extension** (`kind: "screen"`): the mirrored screen's
  system audio. Microphone audio is intentionally omitted there (a
  streamer mics themselves in OBS; the phone mic would double it).
- the **camera app** (`kind: "camera"`), only while its **Send phone mic
  to OBS** option is on: the phone microphone as the camera source's
  audio — the phone as a wireless mic. Mutually exclusive with the
  type-9 lip-sync reference (one mic, one role).

### 11 — DIAG (app/extension → plugin)
Optional diagnostics. Payload: a short UTF-8 text line summarising the
sender's internal counters (screen samples in, frames encoded/sent, bytes,
connection state). The plugin echoes it into the OBS log (prefixed
`[lenslink][phone]`) when the source's **Verbose diagnostics** option is on,
so both ends of the pipeline appear together — the broadcast extension has
no console of its own. Purely informational; a receiver may ignore it.

### 12 — REQUEST (app → plugin)
CONTROL's mirror image: one UTF-8 JSON command per packet, directed at
the plugin itself rather than the camera. Commands:

```json
{ "cmd": "recalibrate" }
```

`recalibrate` asks the plugin to discard its locked lip-sync mic latency
and measure afresh (the app's sync pill tap; the web panel does the same
thing via `POST /api/recalibrate`, no packet involved). Unknown commands
are ignored, so new ones stay compatible; a plugin older than this type
logs an unknown-type warning and carries on.

## Discovery (Bonjour)

Whenever the app's listener is up (streaming, standby, or a screen
broadcast), it is advertised over Bonjour as **`_lenslink._tcp`** with the
device's name as the service instance. The plugin performs a one-shot
mDNS-SD browse (RFC 6762 §5.1: PTR query from an ephemeral port with the
unicast-response bit, answers arrive unicast) when the source's
properties open, and offers discovered phones by name in the Phone
field. Only the PTR answer's instance label and the responder's source
address are used — the wire port is fixed — so no SRV/A parsing or
multicast group membership is required. Typing an IP directly still
works exactly as before.

## USB transport

The packet protocol is identical over USB. The plugin reaches the app's
listener through the usbmuxd protocol (Apple Mobile Device Service on
`localhost:27015` on Windows; the `/var/run/usbmuxd` socket on
macOS/Linux): `ListDevices` → first attached device → `Connect` with the
port in network byte order. After a successful `Connect` result the mux
socket is a raw byte pipe and the normal packet stream begins with the
app's HELLO.
