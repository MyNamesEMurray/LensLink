#!/usr/bin/env python3
"""LensLink encoder quality suite (VMAF, PSNR, SSIM).

Asks the phone to capture a short burst of raw camera frames and, from
the very same frames, encode one file per encoder configuration (HEVC at
several bitrates, H.264, ProRes flavors). The plugin receives the files,
then this script scores every encode against the raw reference with
FFmpeg's libvmaf filter, the method streaming services use: identical
input, compressed vs original, frame by frame.

Usage:
    python3 tools/quality-suite.py
    python3 tools/quality-suite.py --captures 1080p60,1080p60-422
    python3 tools/quality-suite.py --analyze "<capture folder>"

Needs the dev app build (quality_capture command), a plugin with
/api/quality, OBS open with the phone streaming over USB, and an FFmpeg
built with libvmaf on PATH (on Windows, the "full" build from
gyan.dev). Standard library only.
"""

import argparse
import importlib.util
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))

_spec = importlib.util.spec_from_file_location(
    "bench_suite", os.path.join(HERE, "bench-suite.py"))
bench = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bench)

CAPTURES = {
    "1080p60": {"resolution": "1080p", "fps": 60, "capture422": False},
    "1080p60-422": {"resolution": "1080p", "fps": 60, "capture422": True},
    "4k30": {"resolution": "4K", "fps": 30, "capture422": False},
    "4k30-422": {"resolution": "4K", "fps": 30, "capture422": True},
}

CONFIGS_1080P = [
    {"name": "hevc-bal"},
    {"name": "hevc-max", "maximum": True, "tableScale": 6},
    {"name": "hevc-100", "maximum": True, "bitrateMbps": 100},
    {"name": "h264-bal", "codec": "h264"},
    {"name": "prores-proxy", "codec": "prores", "prores": "proxy"},
    {"name": "prores-lt", "codec": "prores"},
    {"name": "prores-422", "codec": "prores", "prores": "standard"},
]

CONFIGS_4K = [
    {"name": "hevc-bal"},
    {"name": "hevc-max-qmode", "maximum": True, "tableScale": 6,
     "qualityPriority": True},
    {"name": "hevc-max-fix", "maximum": True, "tableScale": 6,
     "qualityPriority": False},
    {"name": "hevc-150", "maximum": True, "bitrateMbps": 150,
     "qualityPriority": False},
    {"name": "prores-proxy", "codec": "prores", "prores": "proxy"},
    {"name": "prores-lt", "codec": "prores"},
]

PANEL_BODY_LIMIT = 512

COMPARE_FORMAT = {"nv12": "yuv420p", "p010le": "yuv420p10le",
                  "p210le": "yuv422p10le"}

log = bench.log


def check_ffmpeg(ffmpeg):
    try:
        out = subprocess.run([ffmpeg, "-hide_banner", "-filters"],
                             capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        raise SystemExit(f"Can't run '{ffmpeg}'. Install FFmpeg (on Windows "
                         "the 'full' build from gyan.dev) and put it on PATH, "
                         "or pass --ffmpeg.")
    if " libvmaf " not in out.stdout:
        raise SystemExit(f"'{ffmpeg}' was built without libvmaf. On Windows "
                         "use the 'full' build from gyan.dev.")


def set_capture_format(panel, spec, settle):
    src = bench.ensure_streaming(panel)
    state = panel.get_json(f"/api/state?src={src}")
    dev = state.get("dev")
    if dev is None or "capture422" not in dev:
        raise RuntimeError("this app build has no quality capture; "
                           "sideload the latest dev build")
    panel.control(src, {"cmd": "dev", "fix4k30": False, "bitrateMbps": 0,
                        "prores": "", "capture422": spec["capture422"]})
    panel.control(src, {"cmd": "set_quality", "quality": "balanced"})
    panel.control(src, {"cmd": "set_format", "resolution": spec["resolution"],
                        "fps": spec["fps"], "codec": "hevc"})

    def ready():
        s = panel.get_json(f"/api/state?src={src}")
        d = s.get("dev") or {}
        return (s.get("resolution") == spec["resolution"]
                and int(s.get("fps", 0)) == spec["fps"]
                and bool(d.get("capture422")) == spec["capture422"]
                and d.get("pix"))

    bench.wait_for("the phone to switch format", ready, 30)
    src = bench.ensure_streaming(panel)
    time.sleep(settle)
    pix = (panel.get_json(f"/api/state?src={src}").get("dev") or {}).get("pix")
    if spec["capture422"] and pix != "x422":
        log(f"    note: the camera delivered '{pix}', not 10-bit 4:2:2 "
            "(this format has no 4:2:2 mode on this phone)")
    return src


def run_capture(panel, src, capture_id, spec, frames, timeout):
    status, payload = panel.request("POST", "/api/quality",
                                    {"id": capture_id})
    if status == 404:
        raise SystemExit("This plugin build has no /api/quality. Install the "
                         "latest plugin build from the branch.")
    if status != 200:
        raise RuntimeError(f"/api/quality: HTTP {status} {payload}")
    configs = CONFIGS_4K if spec["resolution"] == "4K" else CONFIGS_1080P
    command = {"cmd": "quality_capture", "id": capture_id,
               "frames": frames, "configs": configs}
    size = len(json.dumps(command, separators=(",", ":")).encode())
    if size > PANEL_BODY_LIMIT:
        raise RuntimeError(f"the capture request is {size} bytes, over the "
                           f"web panel's {PANEL_BODY_LIMIT}-byte limit; "
                           "trim the config list")
    panel.control(src, command)

    paused = False
    start = time.monotonic()
    last_line = ""
    try:
        while True:
            if time.monotonic() - start > timeout:
                raise TimeoutError("the capture didn't arrive in time")
            q = panel.get_json("/api/quality")
            if q.get("error"):
                raise RuntimeError(f"plugin: {q['error']}")
            if q.get("done"):
                print("\r" + " " * len(last_line) + "\r", end="")
                return q["dir"]
            phone = ""
            try:
                state = panel.get_json(f"/api/state?src={src}")
                phone = (state.get("dev") or {}).get("qc", "")
            except (OSError, RuntimeError, ValueError):
                pass
            if phone.startswith("error"):
                raise RuntimeError(f"phone: {phone}")
            receiving = q.get("files", 0) > 0 or q.get("bytes", 0) > 0
            if receiving and not paused:
                panel.control(src, {"cmd": "pause_stream"})
                paused = True
            if receiving:
                total = max(q.get("total", 0), 1)
                line = (f"    receiving {q.get('file') or '...'} "
                        f"{q.get('bytes', 0) * 100 // total}% "
                        f"({q.get('files', 0)} files done)")
            else:
                line = f"    phone: {phone or 'starting'}"
            print("\r" + line.ljust(len(last_line)), end="", flush=True)
            last_line = line
            time.sleep(1.0)
    finally:
        if paused:
            try:
                panel.control(src, {"cmd": "resume_stream"})
            except (OSError, RuntimeError):
                pass


def percentile(values, pct):
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1,
                       int(round(pct / 100 * (len(ordered) - 1)))))
    return ordered[index]


def score_config(ffmpeg, capture_dir, manifest, config, out_dir):
    w, h, fps = manifest["width"], manifest["height"], manifest["fps"]
    pixfmt = manifest["pixfmt"]
    fmt = COMPARE_FORMAT[pixfmt]
    log_name = f"vmaf-{config['name']}.json"
    model = (":model='version=vmaf_4k_v0.6.1'"
             if w * h > 1920 * 1080 else "")
    graph = (f"[0:v]settb=1/{fps},setpts=N,format={fmt}[dis];"
             f"[1:v]settb=1/{fps},setpts=N,format={fmt}[ref];"
             f"[dis][ref]libvmaf=log_fmt=json:log_path={log_name}"
             f":n_threads={os.cpu_count() or 4}:shortest=1"
             f":feature='name=psnr|name=float_ssim'{model}")
    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
           "-i", os.path.join(capture_dir, config["file"]),
           "-f", "rawvideo", "-pix_fmt", pixfmt, "-s", f"{w}x{h}",
           "-r", str(fps),
           "-i", os.path.join(capture_dir, manifest["reference"]),
           "-lavfi", graph, "-f", "null", "-"]
    result = subprocess.run(cmd, cwd=out_dir, capture_output=True,
                            text=True)
    log_path = os.path.join(out_dir, log_name)
    if result.returncode != 0 or not os.path.exists(log_path):
        return {"error": (result.stderr.strip().splitlines() or
                          ["ffmpeg failed"])[-1]}
    with open(log_path, encoding="utf-8") as f:
        data = json.load(f)
    pooled = data.get("pooled_metrics", {})
    per_frame = [fr["metrics"].get("vmaf") for fr in data.get("frames", [])
                 if "vmaf" in fr.get("metrics", {})]

    def mean(key):
        entry = pooled.get(key)
        return entry.get("mean") if entry else None

    seconds = config.get("frames", 0) / fps if fps else 0
    mbps = (config.get("bytes", 0) * 8 / seconds / 1e6) if seconds else None
    return {
        "vmaf": mean("vmaf"),
        "vmaf_min": min(per_frame) if per_frame else None,
        "vmaf_p1": percentile(per_frame, 1) if per_frame else None,
        "psnr_y": mean("psnr_y"),
        "psnr_cb": mean("psnr_cb"),
        "psnr_cr": mean("psnr_cr"),
        "ssim": mean("float_ssim"),
        "mbps": mbps,
        "scored_frames": len(per_frame),
    }


def score_capture(ffmpeg, capture_dir, out_dir):
    with open(os.path.join(capture_dir, "manifest.json"),
              encoding="utf-8") as f:
        manifest = json.load(f)
    os.makedirs(out_dir, exist_ok=True)
    shutil.copyfile(os.path.join(capture_dir, "manifest.json"),
                    os.path.join(out_dir, "manifest.json"))
    if manifest.get("pixfmt") not in COMPARE_FORMAT:
        raise RuntimeError(f"unknown reference format "
                           f"{manifest.get('pixfmt')!r}")
    rows = []
    for config in manifest["configs"]:
        row = {"name": config["name"], "codec": config["codec"],
               "frames": config.get("frames", 0)}
        if config.get("error"):
            row["error"] = config["error"]
        elif not os.path.exists(os.path.join(capture_dir, config["file"])):
            row["error"] = "file missing"
        else:
            log(f"    scoring {config['name']}")
            row.update(score_config(ffmpeg, capture_dir, manifest, config,
                                    out_dir))
        if (not row.get("error") and row["frames"] != manifest["frames"]):
            row["note"] = (f"{row['frames']} of {manifest['frames']} frames; "
                           "frames after a gap are misaligned")
        rows.append(row)
    return manifest, rows


def fmt(value, digits=2):
    return "n/a" if value is None else f"{value:.{digits}f}"


def capture_table(title, manifest, rows):
    lines = [
        f"## {title}",
        "",
        f"{manifest['width']}x{manifest['height']} at {manifest['fps']} fps, "
        f"{manifest['frames']} frames, reference {manifest['pixfmt']}"
        f"{' (10-bit 4:2:2)' if manifest['pixfmt'] == 'p210le' else ''}"
        f"{', ' + str(manifest['skipped']) + ' frames skipped' if manifest.get('skipped') else ''}.",
        "",
        "| Config | Mbps | VMAF | VMAF 1% low | VMAF worst | PSNR Y | "
        "PSNR Cb | PSNR Cr | SSIM | Notes |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]
    for r in rows:
        if r.get("error"):
            lines.append(f"| {r['name']} | | | | | | | | | "
                         f"failed: {r['error']} |")
            continue
        lines.append(
            f"| {r['name']} | {fmt(r.get('mbps'), 1)} | {fmt(r.get('vmaf'))} | "
            f"{fmt(r.get('vmaf_p1'))} | {fmt(r.get('vmaf_min'))} | "
            f"{fmt(r.get('psnr_y'))} | {fmt(r.get('psnr_cb'))} | "
            f"{fmt(r.get('psnr_cr'))} | {fmt(r.get('ssim'), 4)} | "
            f"{r.get('note', '')} |")
    lines.append("")
    return lines


def write_summary(out_dir, sections):
    lines = [
        "# LensLink encoder quality",
        "",
        f"Generated {datetime.now():%Y-%m-%d %H:%M}. Every encode is of the "
        "same camera frames, scored against the raw frames the camera "
        "delivered (FFmpeg libvmaf; the 4K model above 1080p).",
        "",
        "VMAF: 0-100, about 93+ is indistinguishable for most viewers and "
        "about 6 points is a just-noticeable difference. 1% low and worst "
        "show the bad moments an average hides. PSNR Cb/Cr is colour detail "
        "(what keying depends on); VMAF itself ignores colour. Against a "
        "4:2:0 reference, 4:2:2 encodes can't score higher on colour than "
        "the source had.",
        "",
    ]
    for title, manifest, rows in sections:
        lines += capture_table(title, manifest, rows)
    path = os.path.join(out_dir, "quality-summary.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path


def main():
    parser = argparse.ArgumentParser(
        description="Score LensLink encoder configurations with VMAF/PSNR/"
                    "SSIM against raw camera frames.")
    parser.add_argument("--port", type=int, default=9980)
    parser.add_argument("--captures", default=",".join(CAPTURES),
                        help="comma-separated: " + ", ".join(CAPTURES))
    parser.add_argument("--frames", type=int, default=60,
                        help="frames per 1080p capture (4K uses half; "
                             "default 60)")
    parser.add_argument("--settle", type=int, default=5)
    parser.add_argument("--timeout", type=int, default=900,
                        help="seconds to wait for one capture to arrive")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--out", default=None)
    parser.add_argument("--analyze", default=None,
                        help="score an existing capture folder instead")
    parser.add_argument("--no-pattern", action="store_true")
    args = parser.parse_args()

    check_ffmpeg(args.ffmpeg)
    started = datetime.now()
    out_root = os.path.abspath(
        args.out or f"lenslink-quality-{started:%Y%m%d-%H%M%S}")
    os.makedirs(out_root, exist_ok=True)

    if args.analyze:
        manifest, rows = score_capture(
            args.ffmpeg, os.path.abspath(args.analyze),
            os.path.join(out_root, os.path.basename(
                os.path.normpath(args.analyze))))
        path = write_summary(out_root, [(os.path.basename(
            os.path.normpath(args.analyze)), manifest, rows)])
        print(open(path, encoding="utf-8").read())
        return

    wanted = [c.strip().lower() for c in args.captures.split(",")
              if c.strip()]
    unknown = [c for c in wanted if c not in CAPTURES]
    if unknown:
        raise SystemExit(f"unknown captures: {', '.join(unknown)}")

    panel = bench.Panel(args.port)
    if not panel.reachable():
        raise SystemExit(f"No LensLink web panel on localhost:{args.port}.")

    print("LensLink encoder quality suite")
    print(f"Results: {out_root}")
    if not args.no_pattern:
        page = bench.pattern_page(out_root)
        import webbrowser
        webbrowser.open("file:///" + page.replace(os.sep, "/").lstrip("/"))
        print("A motion pattern opened in your browser; make it full screen "
              "and point the phone at it. For a fair colour test, a real "
              "scene with fine texture and saturated edges works too.")
    print("Keep the phone on USB, plugged in, with the LensLink app open.")
    input("Press Enter to start... ")

    sections = []
    failures = []
    for name in wanted:
        spec = CAPTURES[name]
        frames = args.frames if spec["resolution"] != "4K" else max(
            1, args.frames // 2)
        capture_id = f"{name}-{started:%H%M%S}"
        try:
            log(f"Capture {name}: setting {spec['resolution']} "
                f"{spec['fps']} fps"
                f"{', 10-bit 4:2:2' if spec['capture422'] else ''}")
            src = set_capture_format(panel, spec, args.settle)
            log(f"Capture {name}: recording {frames} frames and encoding "
                "them in every configuration")
            capture_dir = run_capture(panel, src, capture_id, spec, frames,
                                      args.timeout)
            log(f"Capture {name}: received, scoring")
            manifest, rows = score_capture(
                args.ffmpeg, capture_dir, os.path.join(out_root, name))
            sections.append((name, manifest, rows))
            write_summary(out_root, sections)
        except (RuntimeError, TimeoutError, OSError) as err:
            print()
            log(f"Capture {name} failed: {err}")
            failures.append((name, str(err)))

    try:
        src = panel.camera_id()
        panel.control(src, {"cmd": "dev", "capture422": False})
        panel.control(src, {"cmd": "resume_stream"})
    except (OSError, RuntimeError, ValueError):
        pass

    path = write_summary(out_root, sections)
    if failures:
        with open(path, "a", encoding="utf-8") as f:
            f.write("## Captures that didn't complete\n\n")
            for name, why in failures:
                f.write(f"- {name}: {why}\n")
    print()
    print(open(path, encoding="utf-8").read())
    print(f"Everything is in {out_root}. The raw captures stay in the "
          "plugin's config folder (quality/...); delete them when done, "
          "they are large.")


if __name__ == "__main__":
    main()
