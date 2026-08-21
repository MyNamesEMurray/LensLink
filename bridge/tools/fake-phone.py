#!/usr/bin/env python3
"""Stand in for an iPhone running LensLink, so the bridge can be tested
without one.

Speaks the phone side of docs/PROTOCOL.md over TCP: HELLO, VIDEO_CONFIG,
VIDEO access units from a checked-in H.264 fixture, TIMESYNC_RESP, and a
STATE snapshot. Prints every CONTROL command the bridge sends, which is
how the remote-start and control-panel paths get verified.

    python3 fake-phone.py                 # stream immediately
    python3 fake-phone.py --standby       # wait for start_stream first
    python3 fake-phone.py --port 19979    # a port that needs no phone

Standard library only, matching tools/bench-report.py.
"""

import argparse
import json
import socket
import struct
import sys
import time
from pathlib import Path

MAGIC = b"OBSC"
VERSION = 1
HEADER_SIZE = 20

PKT_HELLO = 1
PKT_VIDEO_CONFIG = 2
PKT_VIDEO = 3
PKT_PING = 4
PKT_TIMESYNC_REQ = 5
PKT_TIMESYNC_RESP = 6
PKT_CONTROL = 7
PKT_STATE = 8

FLAG_KEYFRAME = 0x0001

DEFAULT_FIXTURE = Path(__file__).parent / "testdata" / "pattern.h264"


def now_ns():
    return time.monotonic_ns()


def build_packet(pkt_type, payload=b"", flags=0, pts_ns=None):
    if pts_ns is None:
        pts_ns = now_ns()
    header = MAGIC + struct.pack(
        ">BBHQI", VERSION, pkt_type, flags, pts_ns, len(payload)
    )
    return header + payload


def split_access_units(data):
    """Annex B bytes -> a list of (au_bytes, is_keyframe).

    A new access unit starts at each VCL NAL (types 1 and 5); parameter
    sets and SEI that precede one ride along with it, which is what makes
    each keyframe self-contained on the wire.
    """
    starts = []
    i = 0
    while True:
        idx3 = data.find(b"\x00\x00\x01", i)
        if idx3 < 0:
            break
        # A 4-byte start code is a 3-byte one with an extra leading zero.
        start = idx3 - 1 if idx3 > 0 and data[idx3 - 1] == 0 else idx3
        payload_at = idx3 + 3
        starts.append((start, payload_at))
        i = payload_at

    units = []
    for n, (start, payload_at) in enumerate(starts):
        end = starts[n + 1][0] if n + 1 < len(starts) else len(data)
        nal_type = data[payload_at] & 0x1F
        units.append((data[start:end], nal_type))

    access_units = []
    pending = b""
    for nal_bytes, nal_type in units:
        pending += nal_bytes
        if nal_type in (1, 5):
            access_units.append((pending, nal_type == 5))
            pending = b""
    if pending:
        access_units.append((pending, False))
    return access_units


class FakePhone:
    def __init__(self, conn, args, access_units):
        self.conn = conn
        self.args = args
        self.access_units = access_units
        self.buffer = b""
        self.streaming = not args.standby
        self.sent_config = False

    def send(self, packet):
        self.conn.sendall(packet)

    def hello(self):
        payload = json.dumps(
            {
                "name": self.args.name,
                "kind": "screen" if self.args.screen else "camera",
                "standby": self.args.standby,
            }
        ).encode()
        self.send(build_packet(PKT_HELLO, payload))
        print(f"-> HELLO ({'standby' if self.args.standby else 'streaming'})")

    def video_config(self):
        payload = json.dumps(
            {
                "codec": "h264",
                "width": self.args.width,
                "height": self.args.height,
                "fps": self.args.fps,
                "kind": "screen" if self.args.screen else "camera",
            }
        ).encode()
        self.send(build_packet(PKT_VIDEO_CONFIG, payload))
        self.sent_config = True
        print("-> VIDEO_CONFIG")

    def state(self):
        payload = json.dumps(
            {
                "zoom": 1.0,
                "maxZoom": 10,
                "exposureBias": 0.0,
                "focusMode": "auto",
                "flashlight": False,
                "hasFlashlight": True,
                "camera": "back",
                "resolution": f"{self.args.height}p",
                "fps": self.args.fps,
                "codec": "h264",
            }
        ).encode()
        self.send(build_packet(PKT_STATE, payload))
        print("-> STATE")

    def drain_incoming(self):
        """Reads whatever is pending and answers it. Non-blocking."""
        self.conn.setblocking(False)
        try:
            while True:
                chunk = self.conn.recv(65536)
                if not chunk:
                    raise ConnectionError("bridge closed the connection")
                self.buffer += chunk
        except BlockingIOError:
            pass
        finally:
            self.conn.setblocking(True)

        while len(self.buffer) >= HEADER_SIZE:
            if self.buffer[:4] != MAGIC:
                raise ValueError("bad magic from the bridge")
            _, pkt_type, _, pts_ns, size = struct.unpack(
                ">BBHQI", self.buffer[4:HEADER_SIZE]
            )
            if len(self.buffer) < HEADER_SIZE + size:
                return
            payload = self.buffer[HEADER_SIZE : HEADER_SIZE + size]
            self.buffer = self.buffer[HEADER_SIZE + size :]
            self.handle(pkt_type, pts_ns, payload)

    def handle(self, pkt_type, pts_ns, payload):
        if pkt_type == PKT_TIMESYNC_REQ:
            # pts = our clock; payload echoes the bridge's t1.
            self.send(
                build_packet(
                    PKT_TIMESYNC_RESP, struct.pack(">Q", pts_ns), pts_ns=now_ns()
                )
            )
        elif pkt_type == PKT_CONTROL:
            text = payload.decode("utf-8", "replace")
            print(f"<- CONTROL {text}")
            try:
                cmd = json.loads(text).get("cmd")
            except json.JSONDecodeError:
                return
            if cmd == "start_stream" and not self.streaming:
                print("   (starting the stream)")
                self.streaming = True
            elif cmd == "stop_stream":
                print("   (stopping the stream)")
                self.streaming = False
                self.sent_config = False
        elif pkt_type == PKT_PING:
            pass

    def run(self):
        self.hello()
        self.state()

        frame_interval = 1.0 / self.args.fps
        index = 0
        sent = 0
        next_frame = time.monotonic()

        while True:
            self.drain_incoming()

            if not self.streaming:
                time.sleep(0.05)
                continue

            if not self.sent_config:
                self.video_config()

            sleep_for = next_frame - time.monotonic()
            if sleep_for > 0:
                time.sleep(sleep_for)
            next_frame += frame_interval

            au, keyframe = self.access_units[index % len(self.access_units)]
            index += 1
            self.send(
                build_packet(
                    PKT_VIDEO, au, FLAG_KEYFRAME if keyframe else 0
                )
            )
            sent += 1
            if sent % self.args.fps == 0:
                print(f"-> {sent} frames")
            if self.args.frames and sent >= self.args.frames:
                print(f"-> sent {sent} frames, done")
                return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9979)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--name", default="Fake iPhone")
    parser.add_argument("--fixture", type=Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--height", type=int, default=240)
    parser.add_argument(
        "--standby",
        action="store_true",
        help="announce standby and wait for a start_stream command",
    )
    parser.add_argument(
        "--screen", action="store_true", help='announce kind "screen"'
    )
    parser.add_argument(
        "--frames", type=int, default=0, help="stop after n frames (0 = forever)"
    )
    parser.add_argument(
        "--once", action="store_true", help="exit after one connection"
    )
    args = parser.parse_args()

    if not args.fixture.exists():
        sys.exit(f"fixture not found: {args.fixture} (see make-fixture.c)")

    access_units = split_access_units(args.fixture.read_bytes())
    keyframes = sum(1 for _, key in access_units if key)
    print(
        f"{args.fixture.name}: {len(access_units)} access units, "
        f"{keyframes} keyframes"
    )

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((args.bind, args.port))
    listener.listen(1)
    print(f"listening on {args.bind}:{args.port}")

    while True:
        conn, addr = listener.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(f"bridge connected from {addr[0]}:{addr[1]}")
        try:
            FakePhone(conn, args, access_units).run()
        except (ConnectionError, OSError, ValueError) as exc:
            print(f"connection ended: {exc}")
        finally:
            conn.close()
        if args.once:
            return


if __name__ == "__main__":
    main()
