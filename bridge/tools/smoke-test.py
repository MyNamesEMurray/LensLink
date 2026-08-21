#!/usr/bin/env python3
"""End-to-end check for the bridge, with no iPhone involved.

Starts fake-phone.py, points the bridge at it, and asserts that real
pixels came out the far end: the bridge must connect, negotiate, decode,
convert to NV12, hand frames to the virtual-camera backend, and serve
the control panel.

    python3 smoke-test.py --bridge ../build/lenslink-bridge

Exits non-zero with a reason on any failure. Standard library only, and
cross-platform, because CI runs it on both Linux and Windows.
"""

import argparse
import json
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
FRAMES = 30


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def read_ppm(path):
    data = path.read_bytes()
    magic, dims, _maxval, pixels = data.split(b"\n", 3)
    if magic != b"P6":
        raise ValueError(f"not a binary PPM: {magic!r}")
    width, height = (int(v) for v in dims.split())
    return width, height, pixels


def check_snapshot(path, expect_w, expect_h):
    width, height, pixels = read_ppm(path)
    if (width, height) != (expect_w, expect_h):
        raise ValueError(
            f"snapshot is {width}x{height}, expected {expect_w}x{expect_h}"
        )
    expected_bytes = width * height * 3
    if len(pixels) < expected_bytes:
        raise ValueError(
            f"snapshot is truncated: {len(pixels)} of {expected_bytes} bytes"
        )
    # The fixture is a diagonal ramp. A frame that decoded to a flat
    # colour means the pipeline moved bytes but not *picture* — the
    # failure this assertion exists to catch.
    if len(set(pixels[:expected_bytes:997])) < 8:
        raise ValueError("snapshot is a flat colour, not decoded video")
    print(f"  snapshot: {width}x{height}, varied pixel content")


def wait_for_panel(port, timeout_s=10):
    deadline = time.monotonic() + timeout_s
    last_error = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/api/sources", timeout=1
            ) as response:
                return json.loads(response.read())
        except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
            last_error = exc
            time.sleep(0.2)
    raise TimeoutError(f"control panel never answered on {port}: {last_error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bridge", required=True, type=Path, help="path to lenslink-bridge"
    )
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()

    if not args.bridge.exists():
        sys.exit(f"bridge executable not found: {args.bridge}")

    phone_port = free_port()
    panel_port = free_port()
    workdir = Path(tempfile.mkdtemp(prefix="lenslink-smoke-"))
    snapshot = workdir / "frame.ppm"
    config = workdir / "bridge.ini"
    config.write_text("")

    print(f"fake phone on {phone_port}, control panel on {panel_port}")

    phone = subprocess.Popen(
        [
            sys.executable,
            str(HERE / "fake-phone.py"),
            "--once",
            "--port",
            str(phone_port),
            "--frames",
            "600",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    bridge = None
    failure = None
    try:
        time.sleep(1)
        bridge = subprocess.Popen(
            [
                str(args.bridge),
                "--host",
                f"127.0.0.1:{phone_port}",
                "--config",
                str(config),
                "--web-port",
                str(panel_port),
                "--snapshot",
                str(snapshot),
                "--frames",
                str(FRAMES),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        sources = wait_for_panel(panel_port)
        print(f"  control panel: {json.dumps(sources)}")
        if not sources.get("sources"):
            raise ValueError("control panel lists no sources")

        bridge.wait(timeout=args.timeout)
        if bridge.returncode != 0:
            raise ValueError(f"bridge exited with {bridge.returncode}")

        if not snapshot.exists():
            raise ValueError("no snapshot was written — nothing decoded")
        check_snapshot(snapshot, 320, 240)

    except Exception as exc:  # noqa: BLE001 - reported below with logs
        failure = exc
    finally:
        for proc, label in ((bridge, "bridge"), (phone, "phone")):
            if not proc:
                continue
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
            output = proc.stdout.read() if proc.stdout else ""
            if failure:
                print(f"\n--- {label} output ---\n{output}")

    if failure:
        sys.exit(f"\nsmoke test FAILED: {failure}")

    print("\nsmoke test passed")


if __name__ == "__main__":
    main()
