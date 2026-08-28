# LensLink Bridge

Use an iPhone running LensLink as a webcam **without OBS**. Design,
scope and the list of what this mode deliberately drops:
[`docs/DRIVERLESS.md`](../docs/DRIVERLESS.md).

> **Stages 1-2.** The bridge connects and decodes, and the DirectShow
> camera puts the phone in Zoom, Discord and other DirectShow apps.
> Teams and the Windows Camera app use Media Foundation and need the
> next backend.

## Get a build

Every push to a `dev/**` branch produces executables: **Actions → Bridge
→ the run for your commit → Artifacts**, `lenslink-bridge-windows-x64`.
No OBS, no FFmpeg DLLs.

```
lenslink-bridge.exe      run this, pointed at your phone
install-camera.bat       registers the camera with Windows (admin, once)
uninstall-camera.bat     removes it -- run BEFORE deleting the folder
x64\, x86\               the filter itself, one per architecture
```

Right-click `install-camera.bat` → Run as administrator, then start
`lenslink-bridge.exe` and pick **LensLink Camera** in Zoom. Apps that
were already running need a restart before they see a new camera.

## Build it yourself

Linux (also the quickest place to check a change compiles):

```bash
sudo apt install cmake pkg-config libavcodec-dev libavutil-dev
cmake -S bridge -B bridge/build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-Wall -Wextra -Werror"
cmake --build bridge/build
```

CI builds with `-Wall -Wextra -Werror`, so use those locally to match.
New `.c` files go in the lists in `bridge/CMakeLists.txt` — no globbing,
same rule as the plugin.

Windows needs a static FFmpeg; the CI job in
`.github/workflows/bridge.yml` shows the exact CMake invocation.

## Run it

```bash
lenslink-bridge --host 192.168.1.42     # the IP the LensLink app shows
lenslink-bridge --usb                   # over the cable (needs iTunes)
lenslink-bridge --discover              # find phones on the LAN
lenslink-bridge --list-usb              # find phones on USB
lenslink-bridge --help
```

The control panel is the plugin's, unchanged: <http://127.0.0.1:9980>.

## Config

`%APPDATA%\LensLink\bridge.ini` on Windows,
`~/.config/lenslink/bridge.ini` elsewhere. `--save` writes a populated
file to start from, `--config` points somewhere else.

```ini
web_control = true
web_control_port = 9980
log_file =

[device]
name = LensLink Camera
mode = lan            ; lan | usb
host = 192.168.1.42   ; "host:port" is accepted, for testing
usb_udid =            ; pin to one phone; empty takes the first free one
kind = camera         ; camera | screen
auto_start = true     ; start the phone's camera when the app is idle
hardware_decode = true
```

Command-line flags override the first `[device]`; a multi-phone setup
belongs in the file.

## Testing without an iPhone

`tools/fake-phone.py` plays the phone side of `docs/PROTOCOL.md` — HELLO,
VIDEO_CONFIG, real H.264 from a checked-in fixture, TIMESYNC, STATE — and
prints every CONTROL command it receives. That last part is how the
control panel and remote start get verified.

```bash
python3 bridge/tools/fake-phone.py &            # port 9979
bridge/build/lenslink-bridge --host 127.0.0.1 --snapshot /tmp/frame.ppm

python3 bridge/tools/fake-phone.py --standby    # test remote start
```

The whole thing in one command, which is also what CI runs:

```bash
python3 bridge/tools/smoke-test.py --bridge bridge/build/lenslink-bridge
```

It asserts the bridge connected, the panel answered, and the decoded
frame contains actual picture rather than a flat colour — the failure
that looks like success when a pipeline moves bytes but not video.

The fixture is committed; `tools/make-fixture.c` regenerates it and
documents how.

## Layout

| Path | What |
|------|------|
| `src/main.c` | arguments, wiring, the frame pump, status heartbeat |
| `src/bridge-core.c` | dial loop, packet handling, the control-panel upcalls |
| `src/nv12.c` | decoded frame → NV12 (no swscale; the static FFmpeg has none) |
| `src/frame-queue.c` | decode → sink hand-off, newest-wins |
| `src/vcam.h` | virtual-camera backend interface |
| `src/vcam-shm.c` | Windows backend: negotiate, scale, publish to shared memory |
| `src/vcam-null.c` | everywhere else: count frames, write snapshots |
| `src/frame-shm.c` | the cross-process mapping, shared with the DLL |
| `src/nv12-scale.c` | letterbox scaling to the camera's negotiated size |
| `vcam-dshow/` | `lenslink-vcam.dll` — the DirectShow filter itself |
| `src/bridge-config.c` | the INI file |
| `src/compat/`, `src/obs-shim.c` | the libobs slice the reused plugin sources need |
| `tools/` | fake phone, smoke test, fixture generator |
