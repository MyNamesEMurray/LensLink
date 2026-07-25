# Development

Contributor and maintainer notes. End-user documentation is in the
[README](../README.md).

## Components

| Component | Path | What it does |
|-----------|------|--------------|
| **OBS plugin** (`LensLink Camera` source) | [`obs-plugin/`](../obs-plugin/) | Connects to the phone (LAN IP or USB via usbmuxd), decodes the incoming H.264/HEVC stream with FFmpeg (GPU when available), and renders it as a normal OBS video source. |
| **iOS app** (`LensLink`) | [`ios-app/`](../ios-app/) | Captures the camera with AVFoundation, hardware-encodes with VideoToolbox, and serves the stream to the plugin over TCP (port 9979 on the device). |

```
┌────────────── iPhone ───────────────┐         ┌─────────── Computer ────────────┐
│ AVCaptureSession → VideoToolbox     │   TCP   │ plugin dials the phone (LAN IP  │
│ H.264/HEVC → Annex B → NWListener   │ ◀────── │ or USB via usbmuxd) → decode →  │
│ (port 9979 on the device)           │ ──────▶ │ obs_source_output_video()       │
└─────────────────────────────────────┘  video  └─────────────────────────────────┘
```

## Repository layout

```
obs-plugin/            C plugin for OBS Studio (CMake)
  src/protocol.h       wire-protocol constants + header parsing
  src/ios-camera-source.c   the OBS source: dial loop, latency, lip sync
  src/h264-decoder.c   libavcodec H.264/HEVC → obs_source_frame (GPU-capable)
  src/usbmux.c         usbmuxd client (USB transport)
  src/web-control.c    browser control panel (http://localhost:9980)
  src/lipsync.c        audio cross-correlation for lip-sync calibration
ios-app/               SwiftUI companion app (XcodeGen project)
  Sources/VideoEncoder.swift    VideoToolbox encode + AVCC→Annex B
  Sources/StreamClient.swift    Network.framework listener + framing
  Sources/AudioReference.swift  mic capture for lip-sync reference
  Sources/StreamingView.swift   full-screen streaming UI + camera controls
installer/windows/     Inno Setup script for the Windows plugin installer
docs/PROTOCOL.md       wire protocol specification
docs/UI_DESIGN.md      app + web-panel design system
```

## Building

- Plugin: [`obs-plugin/BUILDING.md`](../obs-plugin/BUILDING.md)
- App: [`ios-app/BUILDING.md`](../ios-app/BUILDING.md)

## Protocol

A small length-prefixed packet protocol over one TCP connection (video is
H.264/HEVC Annex B access units; timestamps in nanoseconds). Full spec in
[`docs/PROTOCOL.md`](PROTOCOL.md).

## Continuous integration

Pull requests run [`.github/workflows/build.yml`](../.github/workflows/build.yml):

- **OBS plugin** — built on Ubuntu and Windows against libobs + FFmpeg with
  `-Wall -Wextra -Werror`.
- **iOS app** — the Xcode project is generated with XcodeGen and compiled
  for the iOS Simulator on a macOS runner (validates the Swift; installable
  device builds must be signed).

PRs merge automatically once the required Build checks pass (branch
protection on `main`).

## Releases

Every merge to `main` that touches `obs-plugin/`, `ios-app/`, or
`installer/` automatically tags a version and publishes a GitHub Release
with ready-to-install builds (Windows plugin zip, Linux plugin tarball,
unsigned IPA), via
[`.github/workflows/auto-release.yml`](../.github/workflows/auto-release.yml).
The TestFlight upload piggybacks on that release, but only when the merge
touched `ios-app/`.

The bump is a **git trailer** on its own line in any commit of the merged
PR (case-insensitive):

| Trailer line          | Bump   | Example                 |
|-----------------------|--------|-------------------------|
| *(none)*              | patch  | v0.3.0 → v0.3.1         |
| `Release-Bump: minor` | minor  | v0.3.0 → v0.4.0         |
| `Release-Bump: major` | major  | v0.3.0 → v1.0.0         |
| `Release-Skip: true`  | none   | no release              |
| `Release-Beta: true`  | *(as above)*, pre-release | v0.3.0 → v0.3.1-beta.1 |

### Beta releases

`Release-Beta: true` ships everything a normal release does — same builds,
same assets, **same TestFlight upload** (TestFlight is the beta channel
either way) — but publishes the GitHub release flagged **Pre-release**. A
pre-release never becomes "Latest", so the README's version badge and
anyone downloading the latest release stay on the last stable build until
you cut one.

The tag gains a `-beta.N` suffix inside the version it is a beta *of*, and
`N` counts up as you iterate:

```
v1.8.1                    <- last stable
v1.8.2-beta.1             merge with Release-Beta: true
v1.8.2-beta.2             merge again with Release-Beta: true
v1.8.2                    merge without it — the beta becomes the release
```

Combine it with a bump trailer to beta a bigger version:
`Release-Bump: minor` + `Release-Beta: true` → `v1.9.0-beta.1`.

A `-beta.` tag publishes as a pre-release however it was created, so a
hand-pushed `v1.8.0-beta.1` doesn't become a stable release just because
it arrived without the flag set. (A hand-pushed tag still won't upload to
TestFlight — releases published with `GITHUB_TOKEN` don't trigger other
workflows, which is why the auto-release path *calls* TestFlight directly.
Dispatch `testflight.yml` with the tag if you need that.)

Two details worth knowing. The next version is computed from **stable tags
only** — git's version sort puts `v1.9.0-beta.2` *above* `v1.9.0`, and the
patch field would read `0-beta.2`, which the shell can't add 1 to, so an
unfiltered list would fail the next stable release outright. And the
TestFlight "What to Test" notes are looked up **by tag**, because the
`/releases/latest` endpoint is defined as the newest non-pre-release and
would otherwise hand testers the previous stable release's changelog with
nothing to indicate it had.

Because it must be a standalone line, mentioning the keywords in prose
can't trigger a bump.

**The last directive wins.** Every commit of the merged PR is scanned, in
order, and the newest release directive is the one that counts — a later
commit revises an earlier one, in either direction. Asking to release
clears an earlier skip; asking to skip after that suppresses it again.
This matters on branches that start with a docs-only commit: a
release-suppressing trailer written for that commit alone used to outrank
every later, deliberate request, and the only sign was one line in the
Auto Release log (it silently swallowed v1.8.0-beta.1 once).

Manual releases also work — push any `v*` tag:

```bash
git tag v0.4.0 && git push origin v0.4.0
```

The **Linux** release job builds its own minimal static FFmpeg
(H.264/HEVC decode + VAAPI, cached between runs) and links it into
`lenslink.so`, because a tarball linked against the runner's shared
FFmpeg only loads on distros shipping that same FFmpeg major
(issue #65 — `libavcodec.so.60` missing on Arch). The job verifies the
binary has no `libavcodec`/`libavutil` `NEEDED` entries before
packaging. Local/source builds are unaffected — they link the system
FFmpeg via pkg-config, which always matches the machine they run on.

### Release notes

Every release page follows a fixed template: a compact **Install** table
(templated in `release.yml`'s publish job — direct asset links, with
manual/sideload/USB detail collapsed underneath), then GitHub's generated
**What's Changed** changelog, shaped by
[`.github/release.yml`](../.github/release.yml). Label a PR `enhancement`
or `bug` to sort it into the New/Fixes section; unlabeled PRs land under
"Other changes", and Dependabot bumps are excluded. Two invariants:
the install table stays *above* the changelog (the API prepends the
body), and the "What's Changed" heading must survive verbatim —
`testflight_whats_to_test.py` splits the body on it to fill TestFlight's
"What to Test".
