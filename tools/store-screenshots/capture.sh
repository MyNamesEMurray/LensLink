#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Captures the App Store screenshots in the iOS Simulator (macOS, Xcode).

  capture.sh --app PATH/LensLink.app [--scene PICTURE] [--raw DIR]
             [--family iphone|ipad|all] [--appearance dark|light]
             [--lang en,de,...|all]

--app         a Debug simulator build of the app (Release has no screenshot mode)
--scene       a portrait photo standing in for the camera on the Live shots;
              without it live-glance and live-tray are skipped
--raw         where the captures go (default: raw/ next to this script)
--family      which simulators to use (default: all)
--appearance  the system appearance (default: dark)
--lang        the app languages to capture in (default: en; all is every
              store language)

The captures land in <raw>/<lang>/ as <shot>-iphone.png and
<shot>-ipad.png, where render.js looks for each language's captures.
The obs shot needs a real Mac behind the phone and is never captured
here.
EOF
}

here="$(cd "$(dirname "$0")" && pwd)"
app=""
scene=""
raw="$here/raw"
family="all"
appearance="dark"
langs="en"
bundle_id="com.exaltedpixels.LensLinkCamera"

while [ $# -gt 0 ]; do
  case "$1" in
    --app) app="$2"; shift 2 ;;
    --scene) scene="$2"; shift 2 ;;
    --raw) raw="$2"; shift 2 ;;
    --family) family="$2"; shift 2 ;;
    --appearance) appearance="$2"; shift 2 ;;
    --lang) langs="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$app" ] || [ ! -d "$app" ]; then
  echo "error: --app must point at LensLink.app" >&2
  exit 2
fi
if [ -n "$scene" ]; then
  if [ ! -f "$scene" ]; then
    echo "error: no scene picture at $scene" >&2
    exit 2
  fi
  scene="$(cd "$(dirname "$scene")" && pwd)/$(basename "$scene")"
fi
if [ "$langs" = "all" ]; then
  langs="en,de,es,fr,ja,pt-BR,zh-Hans"
fi
langs="${langs//,/ }"

locale_for() {
  case "$1" in
    en) echo "en_US" ;;
    de) echo "de_DE" ;;
    es) echo "es_MX" ;;
    fr) echo "fr_FR" ;;
    ja) echo "ja_JP" ;;
    pt-BR) echo "pt_BR" ;;
    zh-Hans) echo "zh_CN" ;;
    *) echo "error: no locale for language $1" >&2; exit 2 ;;
  esac
}
for lang in $langs; do
  locale_for "$lang" >/dev/null
done
mkdir -p "$raw"

created=()
cleanup() {
  local udid
  for udid in "${created[@]+"${created[@]}"}"; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("platform") == "iOS" and r.get("isAvailable")]
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"] if runtimes else "")
')"
if [ -z "$runtime" ]; then
  echo "error: no iOS simulator runtime installed" >&2
  exit 1
fi
echo "runtime: $runtime"

device_type() {
  xcrun simctl list devicetypes -j | python3 -c '
import json, re, sys
pattern = re.compile(sys.argv[1])
types = [t for t in json.load(sys.stdin)["devicetypes"] if pattern.search(t["name"])]
types.sort(key=lambda t: [int(n) for n in re.findall(r"[0-9]+", t["name"])])
print(types[-1]["identifier"] if types else "")
' "$1"
}

shots_for() {
  local shots="home format options"
  if [ -n "$scene" ]; then
    shots="home live-glance live-tray format options"
  fi
  echo "$shots"
}

capture_family() {
  local name="$1" pattern="$2"
  local type
  type="$(device_type "$pattern")"
  if [ -z "$type" ]; then
    echo "error: no simulator device type matches $pattern" >&2
    exit 1
  fi
  echo "$name: $type"

  local udid
  udid="$(xcrun simctl create "LensLink screenshots ($name)" "$type" "$runtime")"
  created+=("$udid")

  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl status_bar "$udid" override \
    --time "$(python3 -c 'import datetime; print(datetime.datetime(2007, 1, 9, 9, 41).astimezone().isoformat())')" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100
  xcrun simctl install "$udid" "$app"

  local lang shot language
  for lang in $langs; do
    mkdir -p "$raw/$lang"
    language="$lang"
    if [ "$lang" = "es" ]; then
      language="es-MX"
    fi
    for shot in $(shots_for); do
      xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
      SIMCTL_CHILD_LENSLINK_SCREENSHOT_SCENE="$scene" \
        xcrun simctl launch "$udid" "$bundle_id" -LensLinkScreenshots "$shot" \
          -AppleLanguages "($language)" -AppleLocale "$(locale_for "$lang")" >/dev/null
      sleep 6
      xcrun simctl io "$udid" screenshot --type=png "$raw/$lang/$shot-$name.png" >/dev/null 2>&1
      echo "  $raw/$lang/$shot-$name.png"
    done
  done
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

case "$family" in
  iphone|all) capture_family iphone '^iPhone [0-9]+ Pro Max$' ;;
esac
case "$family" in
  ipad|all) capture_family ipad '^iPad Pro 13-inch' ;;
esac

if [ -z "$scene" ]; then
  echo "note: no --scene, so live-glance and live-tray were skipped"
fi
