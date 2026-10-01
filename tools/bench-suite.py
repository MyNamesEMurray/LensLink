#!/usr/bin/env python3
"""LensLink benchmark suite.

Runs the codec/latency test matrix against a live LensLink Camera source
through the plugin's web control panel, records one labelled benchmark
CSV per run, and writes comparison reports plus a summary into one
results folder. Standard library only.

Usage:
    python3 tools/bench-suite.py
    python3 tools/bench-suite.py --runs A,B,C --duration 30

Needs a plugin build with /api/bench (the per-stage benchmark branch),
OBS open with one LensLink Camera source, and the phone connected over
USB with the app open. Steps the panel can't drive (USB vs Wi-Fi,
hardware decoding, the GPU pipeline) are prompted for and then checked
against the plugin's diagnostics before recording.
"""

import argparse
import csv
import http.client
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
import webbrowser
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))

BASE = {"transport": "USB", "hw": True, "gpu": False,
        "resolution": "1080p", "fps": 60, "codec": "hevc",
        "quality": "balanced"}

RUNS = [
    ("A", "usb-hevc-1080p60-balanced", {}),
    ("B", "usb-h264-1080p60-balanced", {"codec": "h264"}),
    ("C", "usb-hevc-1080p60-maximum", {"quality": "maximum"}),
    ("D", "usb-hevc-4k30-maximum",
     {"resolution": "4K", "fps": 30, "quality": "maximum"}),
    ("H", "usb-hevc-4k30-balanced", {"resolution": "4K", "fps": 30}),
    ("E", "wifi-hevc-1080p60-balanced", {"transport": "Wi-Fi"}),
    ("E2", "wifi-hevc-4k30-maximum",
     {"transport": "Wi-Fi", "resolution": "4K", "fps": 30,
      "quality": "maximum"}),
    ("F", "usb-hevc-1080p60-softwaredecode", {"hw": False}),
    ("G", "usb-hevc-1080p60-gpupipeline", {"gpu": True}),
]

COMPARISONS = [("A", "B"), ("A", "C"), ("A", "D"), ("A", "E"),
               ("D", "E2"), ("A", "F"), ("A", "G"), ("D", "H")]

SUMMARY_COLUMNS = [
    ("latency_ms", "Capture->decode (ms)"),
    ("arrival_ms", "Capture->arrival (ms)"),
    ("phone_capture_ms", "Phone capture->encoder (ms)"),
    ("phone_encode_ms", "Phone encode (ms)"),
    ("phone_send_ms", "Phone encoder->sent (ms)"),
    ("phone_total_ms", "Phone capture->sent (ms)"),
    ("decode_ms", "Decode (ms)"),
    ("max_decode_ms", "Decode worst (ms)"),
    ("avg_cost_ms", "Video path (ms)"),
    ("rtt_ms", "Link RTT (ms)"),
    ("fps", "FPS"),
    ("obs_cpu_pct", "OBS CPU (%)"),
]


class Panel:
    def __init__(self, port):
        self.port = port

    def request(self, method, path, body=None, timeout=5):
        conn = http.client.HTTPConnection("127.0.0.1", self.port,
                                          timeout=timeout)
        try:
            data = json.dumps(body).encode() if body is not None else None
            headers = {"Host": f"localhost:{self.port}"}
            if data is not None:
                headers["Content-Type"] = "application/json"
            conn.request(method, path, body=data, headers=headers)
            resp = conn.getresponse()
            payload = resp.read().decode("utf-8", "replace")
            return resp.status, payload
        finally:
            conn.close()

    def get_json(self, path):
        status, payload = self.request("GET", path)
        if status != 200:
            raise RuntimeError(f"GET {path}: HTTP {status} {payload}")
        return json.loads(payload)

    def reachable(self):
        try:
            self.request("GET", "/api/sources", timeout=2)
            return True
        except OSError:
            return False

    def camera_id(self):
        sources = self.get_json("/api/sources")["sources"]
        cams = [s for s in sources if not s.get("screen")]
        if not cams:
            raise RuntimeError("no LensLink Camera source in OBS")
        live = [s for s in cams if s.get("connected")]
        return (live or cams)[0]["id"]

    def control(self, src, cmd):
        status, payload = self.request("POST", f"/api/control?src={src}",
                                       cmd)
        if status not in (200, 204):
            raise RuntimeError(f"control {cmd}: HTTP {status} {payload}")

    def bench(self, on, label=""):
        status, payload = self.request("POST", "/api/bench",
                                       {"on": on, "label": label})
        if status == 404:
            raise SystemExit(
                "This plugin build has no /api/bench. Install the build "
                "from the claude/bench-stage-timings branch.")
        if status not in (200, 204):
            raise RuntimeError(f"bench: HTTP {status} {payload}")

    def diagnostics(self):
        status, payload = self.request("GET", "/api/diagnostics")
        return payload if status == 200 else ""


def parse_diagnostics(text):
    info = {"gpu": None, "transport": None, "decoder": None}
    in_camera = False
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("GPU decode pipeline:"):
            info["gpu"] = line.split(":", 1)[1].strip().startswith("on")
        elif raw.startswith("[Camera]"):
            in_camera = info["transport"] is None
        elif raw.startswith("["):
            in_camera = False
        elif in_camera and line.startswith("transport:"):
            info["transport"] = line.split(":", 1)[1].strip()
        elif in_camera and line.startswith("decoder:"):
            info["decoder"] = line.split(":", 1)[1].strip()
    return info


def log(msg):
    print(f"[{datetime.now():%H:%M:%S}] {msg}", flush=True)


def wait_for(what, check, timeout, interval=1.0):
    deadline = time.monotonic() + timeout
    last_err = None
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except (OSError, RuntimeError, ValueError, KeyError) as err:
            last_err = err
        time.sleep(interval)
    detail = f" ({last_err})" if last_err else ""
    raise TimeoutError(f"timed out waiting for {what}{detail}")


def manual_steps(prev, cfg):
    steps = []
    if prev is None or prev["transport"] != cfg["transport"]:
        if cfg["transport"] == "USB":
            steps.append("In the LensLink Camera source properties, set "
                         "Connection to 'USB cable'.")
        else:
            steps.append("In the LensLink Camera source properties, set "
                         "Connection to Wi-Fi and enter the phone's IP "
                         "(shown in the app). Unplug the cable if you "
                         "like; it isn't used either way.")
    if prev is None or prev["hw"] != cfg["hw"]:
        steps.append("In the source properties, turn 'Hardware decoding "
                     f"(GPU)' {'ON' if cfg['hw'] else 'OFF'}.")
    if prev is None or prev["gpu"] != cfg["gpu"]:
        steps.append("In Tools -> LensLink Settings, turn 'GPU decode "
                     f"pipeline (beta)' {'ON' if cfg['gpu'] else 'OFF'}, "
                     "then restart OBS.")
    return steps


def verify_manual(panel, cfg):
    info = parse_diagnostics(panel.diagnostics())
    problems = []
    if info["transport"] and info["transport"] != cfg["transport"]:
        problems.append(f"transport is {info['transport']}, expected "
                        f"{cfg['transport']}")
    if info["gpu"] is not None and info["gpu"] != cfg["gpu"]:
        problems.append("GPU decode pipeline is "
                        f"{'on' if info['gpu'] else 'off'}, expected "
                        f"{'on' if cfg['gpu'] else 'off'}")
    decoder = (info["decoder"] or "").lower()
    if decoder and not cfg["hw"] and not decoder.startswith("software"):
        problems.append(f"decoder is {info['decoder']}, expected software")
    if decoder and cfg["hw"] and decoder.startswith("software"):
        problems.append("decoder is software although hardware decoding "
                        "is expected (the GPU may have fallen back)")
    return info, problems


def state_matches(state, cfg):
    return (state.get("resolution") == cfg["resolution"]
            and int(state.get("fps", 0)) == cfg["fps"]
            and state.get("codec") == cfg["codec"]
            and state.get("quality") == cfg["quality"])


def apply_format(panel, src, cfg):
    state = panel.get_json(f"/api/state?src={src}")
    if state.get("hdr") or state.get("color"):
        raise RuntimeError("the app is in an HLG/Log colour mode; switch "
                           "it to SDR so H.264 runs are possible")
    for key, options in (("resolution", "resolutions"),
                         ("fps", "frameRates"), ("codec", "codecs")):
        allowed = state.get(options)
        if allowed and cfg[key] not in allowed:
            raise RuntimeError(f"the phone doesn't offer {key}="
                               f"{cfg[key]} on this lens (offers "
                               f"{allowed})")
    if state.get("quality") != cfg["quality"]:
        panel.control(src, {"cmd": "set_quality",
                            "quality": cfg["quality"]})
    panel.control(src, {"cmd": "set_format",
                        "resolution": cfg["resolution"],
                        "fps": cfg["fps"], "codec": cfg["codec"]})
    wait_for("the phone to switch format",
             lambda: state_matches(
                 panel.get_json(f"/api/state?src={src}"), cfg), 30)


def ensure_streaming(panel):
    def live():
        src = panel.camera_id()
        sources = panel.get_json("/api/sources")["sources"]
        me = next(s for s in sources if s["id"] == src)
        if me.get("connected") and me.get("standby"):
            panel.control(src, {"cmd": "start_stream"})
            return None
        if me.get("connected"):
            state = panel.get_json(f"/api/state?src={src}")
            if state.get("paused"):
                panel.control(src, {"cmd": "resume_stream"})
                return None
            return src
        return None
    return wait_for("the phone to connect and stream", live, 180, 2.0)


def load_rows(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def column_mean(rows, key):
    vals = []
    for r in rows:
        try:
            vals.append(float(r[key]))
        except (KeyError, TypeError, ValueError):
            pass
    return statistics.fmean(vals) if vals else None


def pattern_page(out_dir):
    path = os.path.join(out_dir, "motion-pattern.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write("""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>LensLink motion pattern</title>
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
canvas{display:block;width:100vw;height:100vh}
#t{position:fixed;left:16px;top:16px;font:bold 48px monospace;
color:#fff;background:#000a;padding:4px 12px}</style></head>
<body><canvas id="c"></canvas><div id="t"></div><script>
const c=document.getElementById('c'),x=c.getContext('2d'),
t=document.getElementById('t');let seed=1;
function rnd(){seed=(seed*16807)%2147483647;return seed/2147483647}
function size(){c.width=innerWidth;c.height=innerHeight}
addEventListener('resize',size);size();
function frame(ms){const w=c.width,h=c.height,s=ms/1000;
x.fillStyle='hsl('+(s*40%360)+',60%,25%)';x.fillRect(0,0,w,h);
for(let i=0;i<14;i++){const a=s*(0.4+i*0.13)+i;
x.fillStyle='hsl('+((i*27+s*60)%360)+',80%,55%)';
x.beginPath();x.arc(w/2+Math.cos(a)*w*0.38,h/2+Math.sin(a*1.3)*h*0.38,
40+30*Math.sin(s+i),0,7);x.fill()}
seed=Math.floor(s*30)+1;for(let i=0;i<1600;i++){
const v=Math.floor(rnd()*255);x.fillStyle='rgb('+v+','+v+','+v+')';
x.fillRect(rnd()*w,rnd()*h,6,6)}
t.textContent=new Date().toISOString().slice(11,23);
requestAnimationFrame(frame)}requestAnimationFrame(frame);
</script></body></html>
""")
    return path


def run_one(panel, run_id, label, cfg, args, out_dir, prev_cfg):
    steps = manual_steps(prev_cfg, cfg)
    if steps:
        print()
        log(f"Run {run_id} needs you to change OBS settings:")
        for i, step in enumerate(steps, 1):
            print(f"    {i}. {step}")
        input("    Press Enter when done... ")
        wait_for("the LensLink web panel", panel.reachable, 300, 2.0)

    log(f"Run {run_id} ({label}): waiting for the phone")
    src = ensure_streaming(panel)
    _, problems = verify_manual(panel, cfg)
    while problems:
        print("    Settings don't match this run yet:")
        for p in problems:
            print(f"      - {p}")
        choice = input("    Fix it and press Enter to re-check, or type "
                       "'go' to record anyway: ").strip().lower()
        if choice == "go":
            break
        wait_for("the LensLink web panel", panel.reachable, 300, 2.0)
        src = ensure_streaming(panel)
        _, problems = verify_manual(panel, cfg)

    log(f"Run {run_id}: setting {cfg['resolution']} {cfg['fps']} fps "
        f"{cfg['codec']} {cfg['quality']}")
    apply_format(panel, src, cfg)
    src = ensure_streaming(panel)

    log(f"Run {run_id}: settling for {args.settle} s")
    time.sleep(args.settle)
    info, _ = verify_manual(panel, cfg)

    tag = f"{run_id}-{label}"
    panel.bench(True, tag)
    log(f"Run {run_id}: recording for {args.duration} s")
    start = time.monotonic()
    try:
        while True:
            left = args.duration - (time.monotonic() - start)
            if left <= 0:
                break
            print(f"\r    {int(left):3d} s left ", end="", flush=True)
            time.sleep(min(1.0, left))
    finally:
        print("\r" + " " * 20 + "\r", end="")
        panel.bench(False)

    status = panel.get_json("/api/bench")
    src_file = status.get("file", "")
    if not src_file or tag not in os.path.basename(src_file):
        raise RuntimeError("the plugin didn't write a sample file for "
                           "this run (was video flowing?)")
    dest = os.path.join(out_dir, f"bench-{tag}.csv")
    shutil.copyfile(src_file, dest)
    with open(os.path.join(out_dir, f"diagnostics-{run_id}.txt"), "w",
              encoding="utf-8") as f:
        f.write(panel.diagnostics())

    rows = load_rows(dest)
    if len(rows) < max(5, args.duration // 2):
        log(f"Run {run_id}: only {len(rows)} samples recorded; the "
            "stream may have stalled")
    log(f"Run {run_id}: done, {len(rows)} samples, decoder "
        f"{info.get('decoder') or '?'}")
    return dest


def compare(out_dir, files, before, after):
    if before not in files or after not in files:
        return None
    sub = os.path.join(out_dir, f"compare-{before}-vs-{after}")
    os.makedirs(sub, exist_ok=True)
    subprocess.run([sys.executable,
                    os.path.join(HERE, "bench-report.py"),
                    files[before], files[after]],
                   cwd=sub, check=True, stdout=subprocess.DEVNULL,
                   env=dict(os.environ, PYTHONUTF8="1"))
    return sub


def write_summary(out_dir, files, meta, failures):
    lines = ["# LensLink benchmark suite", "",
             f"Recorded {meta['started']}, {meta['duration']} s per run "
             f"after {meta['settle']} s settling.", ""]
    header = "| Run | Config | Transport | Decoder | " + " | ".join(
        label for _, label in SUMMARY_COLUMNS) + " |"
    lines += [header, "|" + "---|" * (len(SUMMARY_COLUMNS) + 4)]
    for run_id, label, _ in RUNS:
        if run_id not in files:
            continue
        rows = load_rows(files[run_id])
        cells = []
        for key, _ in SUMMARY_COLUMNS:
            v = column_mean(rows, key)
            cells.append("n/a" if v is None else f"{v:.2f}")
        diag_path = os.path.join(out_dir, f"diagnostics-{run_id}.txt")
        info = {}
        if os.path.exists(diag_path):
            with open(diag_path, encoding="utf-8") as f:
                info = parse_diagnostics(f.read())
        lines.append(f"| {run_id} | {label} | "
                     f"{info.get('transport') or '?'} | "
                     f"{info.get('decoder') or '?'} | "
                     + " | ".join(cells) + " |")
    if failures:
        lines += ["", "## Runs that didn't complete", ""]
        lines += [f"- {run_id}: {why}" for run_id, why in failures]
    lines += ["", "Comparisons (bench-report.py) are in the compare-* "
              "folders; diagnostics-*.txt has the decoder and transport "
              "each run actually used."]
    path = os.path.join(out_dir, "summary.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path


def main():
    parser = argparse.ArgumentParser(
        description="Run the LensLink codec/latency benchmark matrix.")
    parser.add_argument("--port", type=int, default=9980,
                        help="web control panel port (default 9980)")
    parser.add_argument("--duration", type=int, default=60,
                        help="seconds recorded per run (default 60)")
    parser.add_argument("--settle", type=int, default=15,
                        help="seconds to wait after a change (default 15)")
    parser.add_argument("--cooldown", type=int, default=0,
                        help="seconds to pause between runs (default 0)")
    parser.add_argument("--runs", default=",".join(r[0] for r in RUNS),
                        help="comma-separated run ids (default: all)")
    parser.add_argument("--out", default=None,
                        help="results folder (default: "
                             "lenslink-bench-<date>)")
    parser.add_argument("--no-pattern", action="store_true",
                        help="don't open the motion pattern page")
    args = parser.parse_args()

    wanted = [r.strip().upper() for r in args.runs.split(",") if r.strip()]
    unknown = [r for r in wanted if r not in {x[0] for x in RUNS}]
    if unknown:
        raise SystemExit(f"unknown run ids: {', '.join(unknown)}")
    plan = [r for r in RUNS if r[0] in wanted]

    panel = Panel(args.port)
    if not panel.reachable():
        raise SystemExit(f"No LensLink web panel on localhost:{args.port}. "
                         "Is OBS open with the panel enabled?")
    status, _ = panel.request("GET", "/api/bench")
    if status == 404:
        raise SystemExit("This plugin build has no /api/bench. Install the "
                         "build from the claude/bench-stage-timings "
                         "branch.")

    started = datetime.now()
    out_dir = os.path.abspath(
        args.out or f"lenslink-bench-{started:%Y%m%d-%H%M%S}")
    os.makedirs(out_dir, exist_ok=True)

    print("LensLink benchmark suite")
    print(f"Results: {out_dir}")
    print(f"Runs: {', '.join(r[0] for r in plan)}; about "
          f"{len(plan) * (args.duration + args.settle + 20) // 60 + 1} "
          "minutes plus any manual steps.")
    if not args.no_pattern:
        page = pattern_page(out_dir)
        webbrowser.open("file:///" + page.replace(os.sep, "/").lstrip("/"))
        print("A motion pattern opened in your browser. Make it full "
              "screen (F11) and point the phone at it, filling the frame.")
    print("Keep the phone plugged in, on a stand, with the LensLink app "
          "open and on screen.")
    input("Press Enter to start... ")

    files, failures = {}, []
    prev = None
    try:
        for i, (run_id, label, overrides) in enumerate(plan):
            cfg = dict(BASE, **overrides)
            try:
                files[run_id] = run_one(panel, run_id, label, cfg, args,
                                        out_dir, prev)
            except (RuntimeError, TimeoutError, OSError) as err:
                log(f"Run {run_id} skipped: {err}")
                failures.append((run_id, str(err)))
                try:
                    panel.bench(False)
                except OSError:
                    pass
            prev = cfg
            if args.cooldown and i + 1 < len(plan):
                log(f"Cooling down for {args.cooldown} s")
                time.sleep(args.cooldown)
    except KeyboardInterrupt:
        print()
        log("Interrupted; writing what was recorded so far")
        try:
            panel.bench(False)
        except OSError:
            pass

    if prev and prev["gpu"]:
        print("\nRemember to turn 'GPU decode pipeline (beta)' back off in "
              "Tools -> LensLink Settings if you don't normally use it.")

    for before, after in COMPARISONS:
        try:
            compare(out_dir, files, before, after)
        except subprocess.CalledProcessError as err:
            failures.append((f"{before} vs {after}", f"report failed: "
                             f"{err}"))

    summary = write_summary(out_dir, files, {
        "started": f"{started:%Y-%m-%d %H:%M}",
        "duration": args.duration, "settle": args.settle}, failures)
    print()
    with open(summary, encoding="utf-8") as f:
        print(f.read())
    print(f"Everything is in {out_dir}. Zip that folder and send it over.")


if __name__ == "__main__":
    main()
