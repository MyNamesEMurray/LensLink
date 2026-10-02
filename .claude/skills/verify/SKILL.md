---
name: verify
description: How to verify LensLink changes from this Linux container — per-surface recipes and gotchas.
---

# Verifying LensLink changes (Linux container)

## iOS app (Swift)
No Xcode here. `ios-app/syntax-check.sh` parse-checks every source
(installs a Linux toolchain to `~/.cache/lenslink-swift` on first run).
Syntax only — type/API errors surface in the macOS CI job on PRs.
Real behavior needs a device; say so rather than claiming a PASS.

## OBS plugin (C)
Build with `-Wall -Wextra -Werror` as in CLAUDE.md; Windows and macOS
only build in CI on PRs. Unit tests: configure a second build dir with
`-DLENSLINK_BUILD_TESTS=ON`, then `ctest --test-dir <dir>
--output-on-failure`; add `-fsanitize=address,undefined` to
`CMAKE_C_FLAGS` (with `-DENABLE_FRONTEND_UI=OFF`) to match CI.

Wire behaviour without a phone: `python3 tools/fake-phone.py` listens on
127.0.0.1:9979 (`--standby`, `--unarmed`, `--screen`, `--port`,
`--frames N --once`). In OBS, set a source to Wi-Fi with Phone 127.0.0.1.
Without OBS, a few lines of Python that dial it and read the 20-byte
headers capture the exact HELLO/VIDEO_CONFIG bytes for a parser test.
Locale/string changes can only be cross-checked against the app/plugin
sources, not observed in OBS.

## GitHub Actions scripts (.github/scripts/*.py — App Store Connect)
Drive the real script via its real invocation (`python3 <script>` with
the workflow's env) against a local mock of the two APIs:

- venv required: system python3's `cryptography` is broken
  (`_cffi_backend` missing). `python3 -m venv x && pip install PyJWT
  cryptography`.
- Put a `sitecustomize.py` on `PYTHONPATH` that wraps
  `urllib.request.urlopen` and rewrites
  `https://api.appstoreconnect.apple.com` / `https://api.github.com`
  to `http://127.0.0.1:<port>/asc|/gh`. The script stays unmodified.
- The mock should *verify* the ES256 JWT (decode with the test key's
  public half, check aud/kid) — that catches auth-shape regressions.
- Generate a throwaway key: `openssl ecparam -genkey -name prime256v1`.
- Poll loops sleep 60 s; stub `time.sleep` from the shim (env flag)
  to exercise timeout paths in seconds.
- Feed fixtures with a REAL release body from
  `mcp__github__get_latest_release`, not hand-written markdown.

A worked example (mock server + shim + scenario runner) was built in a
prior session; the shape is small enough to rebuild from this note.

## Live-dispatch warning
Never verify `testflight.yml` by dispatching it — a run archives and
uploads a real build to TestFlight (consumes a build number). Same for
anything that creates releases or tags.
