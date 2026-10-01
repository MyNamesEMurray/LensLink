#!/usr/bin/env python3
"""Show or change the LensLink app's experimental dev toggles.

Usage:
    python3 tools/lenslink-dev.py                 # show current values
    python3 tools/lenslink-dev.py fix4k30=on bitrate=100 prores=lt
    python3 tools/lenslink-dev.py reset           # back to defaults

Toggles:
    fix4k30=on|off      Maximum quality skips the slow quality-first
                        encoder mode above 1080p (cuts 4K30 latency)
    bitrate=<Mbps>|0    Pin Maximum quality's bitrate over USB (0 = the
                        app's normal adaptive range, max 400)
    prores=proxy|lt|standard|hq|off
                        Encode ProRes 422 instead of H.264/HEVC (SDR only)

Talks to the plugin's web control panel on localhost (OBS must be open
with a connected LensLink Camera source). Changes apply live and last
until the app restarts. Standard library only.
"""

import http.client
import json
import sys
import time

PORT = 9980
FLAVORS = ("proxy", "lt", "standard", "hq")


def request(method, path, body=None):
    conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=5)
    try:
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Host": f"localhost:{PORT}"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        conn.request(method, path, body=data, headers=headers)
        resp = conn.getresponse()
        return resp.status, resp.read().decode("utf-8", "replace")
    finally:
        conn.close()


def camera_id():
    status, payload = request("GET", "/api/sources")
    if status != 200:
        raise SystemExit(f"web panel error: HTTP {status}")
    cams = [s for s in json.loads(payload)["sources"] if not s["screen"]]
    if not cams:
        raise SystemExit("no LensLink Camera source in OBS")
    live = [s for s in cams if s["connected"]]
    return (live or cams)[0]["id"]


def show(src):
    status, payload = request("GET", f"/api/state?src={src}")
    if status != 200:
        raise SystemExit(f"web panel error: HTTP {status}")
    state = json.loads(payload)
    dev = state.get("dev")
    if dev is None:
        raise SystemExit("this app build has no dev toggles (or the phone "
                         "isn't connected yet)")
    print(f"format:      {state.get('resolution')} {state.get('fps')} fps, "
          f"{state.get('codec')}, quality {state.get('quality')}")
    print(f"fix4k30:     {'on' if dev.get('fix4k30') else 'off'}")
    mbps = dev.get("bitrateMbps", 0)
    print(f"bitrate:     {f'{mbps} Mbps (Maximum, USB)' if mbps else 'normal'}")
    print(f"prores:      {dev.get('prores') or 'off'}"
          f"{'' if dev.get('proresOK') else ' (not supported on this phone)'}")
    print(f"on the wire: {dev.get('wire') or '?'}")
    if dev.get("encErr"):
        print(f"encoder errors: {dev['encErr']} (last status "
              f"{dev.get('encStatus')})")


def parse(args):
    cmd = {"cmd": "dev"}
    for arg in args:
        if arg == "reset":
            cmd.update(fix4k30=False, bitrateMbps=0, prores="")
            continue
        key, _, value = arg.partition("=")
        key, value = key.lower(), value.lower()
        if key == "fix4k30" and value in ("on", "off"):
            cmd["fix4k30"] = value == "on"
        elif key == "bitrate" and value.isdigit():
            cmd["bitrateMbps"] = int(value)
        elif key == "prores" and (value in FLAVORS or value == "off"):
            cmd["prores"] = "" if value == "off" else value
        else:
            raise SystemExit(f"don't understand '{arg}'\n\n{__doc__}")
    return cmd


def main():
    args = sys.argv[1:]
    if args and args[0] in ("-h", "--help"):
        print(__doc__)
        return
    src = camera_id()
    if args:
        status, payload = request("POST", f"/api/control?src={src}",
                                  parse(args))
        if status not in (200, 204):
            raise SystemExit(f"control failed: HTTP {status} {payload}")
        time.sleep(1.5)
    show(src)


if __name__ == "__main__":
    main()
