#!/usr/bin/env bash
# verify-mac.sh — local Mac verification for OpenTokenUsage: web, Worker bundle and native iOS.
#
# Usage: scripts/verify-mac.sh [all|web|ios|shots] ...      (default: all)
#   web    tsc, vite build, Worker bundle (wrangler --dry-run), Playwright, Python script tests
#   ios    xcodegen, then xcodebuild test on a dedicated simulator (xcresult kept)
#   shots  light/dark portrait and dark landscape screenshots of every display, unsigned layout
#
# Every gate runs even when an earlier one fails. Exit 1 if any gate FAILED, 2 if none failed but
# one was BLOCKED (a prerequisite is missing), 0 if all passed.
#
# Never touches the person's own simulators: tests and screenshots use a dedicated device
# (default "OTU Verify", an iPhone Duo when Xcode has one), created on first use.
# Nothing is downloaded: npx runs with --no-install, and missing Playwright browsers are reported.
#
# Env:
#   OTU_VERIFY_HOME  cache root (default ~/Library/Caches/otu-verify): DerivedData and run output
#   OTU_SIM_NAME     dedicated simulator name (default "OTU Verify")
#   OTU_SHOT_WAIT    seconds to wait after launch before a screenshot (default 12)
#   OTU_KEEP_SIM=1   leave the dedicated simulator booted afterwards

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${OTU_VERIFY_HOME:-$HOME/Library/Caches/otu-verify}"
RUN="$CACHE/runs/$(date +%Y%m%d-%H%M%S)"
DD="$CACHE/DerivedData"
SIM_NAME="${OTU_SIM_NAME:-OTU Verify}"
SHOT_WAIT="${OTU_SHOT_WAIT:-12}"
BUNDLE="com.chihfu.opentokenusage"
APP="$DD/Build/Products/Debug-iphonesimulator/OpenTokenUsage.app"
SHOTS="$RUN/shots"
mkdir -p "$RUN/logs"
cd "$ROOT" || exit 1

RESULTS=()
FAILED=0
BLOCKED=0
UDID=""
SIM_LABEL=""
SIM_TRIED=0
PROJECT_STATE=""   # "", ok or fail
BOOTED_BY_US=0

record() { # gate status seconds note
  RESULTS+=("$(printf '%-25s %-8s %5ss  %s' "$1" "$2" "$3" "$4")")
  case "$2" in FAIL) FAILED=1 ;; BLOCKED) BLOCKED=1 ;; esac
}

# run_gate NAME NOTE_ON_PASS -- command...   (output goes to $RUN/logs/NAME.log)
run_gate() {
  local name="$1" note="$2"; shift 3
  local log="$RUN/logs/$name.log" start=$SECONDS
  echo "==> $name"
  if "$@" >"$log" 2>&1; then
    record "$name" PASS $((SECONDS - start)) "$note"
    return 0
  fi
  record "$name" FAIL $((SECONDS - start)) "log: $log"
  tail -n 40 "$log" | sed 's/^/    /'
  return 1
}

# ---------------------------------------------------------------- web

web_gates() {
  if [ ! -d node_modules ]; then
    record web BLOCKED 0 "node_modules missing: run npm ci"
    return
  fi
  run_gate tsc "npx tsc --noEmit" -- npx --no-install tsc --noEmit -p .
  run_gate vite-build "dist/ built" -- npx --no-install vite build
  run_gate worker-bundle "wrangler deploy --dry-run (no upload)" -- \
    npx --no-install wrangler deploy --dry-run --outdir "$RUN/worker-bundle"

  if node -e "process.exit(require('fs').existsSync(require('@playwright/test').chromium.executablePath())?0:1)" 2>/dev/null; then
    run_gate playwright "tests/*.spec.ts" -- npx --no-install playwright test
  else
    record playwright BLOCKED 0 "Chromium missing; one-time download (ask first): npx playwright install chromium"
  fi

  local t
  for t in scripts/test_*.py; do
    [ -e "$t" ] || continue
    run_gate "py:$(basename "$t" .py | sed 's/^test_//')" "$t" -- python3 "$t"
  done
}

# ---------------------------------------------------------------- project and simulator

ensure_project() { # xcodegen once per invocation
  [ "$PROJECT_STATE" = ok ] && return 0
  [ "$PROJECT_STATE" = fail ] && return 1
  if ! command -v xcodegen >/dev/null; then
    record xcodegen BLOCKED 0 "brew install xcodegen"
    PROJECT_STATE=fail
    return 1
  fi
  if run_gate xcodegen "ios-native/project.yml -> .xcodeproj" -- sh -c 'cd ios-native && xcodegen generate --quiet'; then
    PROJECT_STATE=ok
    return 0
  fi
  PROJECT_STATE=fail
  return 1
}

pick_sim() {
  local out
  out=$(xcrun simctl list -j devices devicetypes runtimes | SIM_NAME="$SIM_NAME" python3 -I -c '
import json, os, sys
d = json.load(sys.stdin)
name = os.environ["SIM_NAME"]
for devs in d["devices"].values():
    for x in devs:
        if x["name"] == name and x.get("isAvailable", True):
            print("existing", x["udid"]); sys.exit(0)
types = [t["identifier"] for t in d["devicetypes"]]
want = next((t for t in types if t.endswith(".iPhone-Duo")), None) \
    or next((t for t in types if ".iPhone-" in t), None)
def ver(r):
    return tuple(int(p) for p in r["version"].split(".") if p.isdigit())
best = None
for r in d["runtimes"]:
    if not r.get("isAvailable") or r.get("platform", "iOS") != "iOS":
        continue
    if want in [t["identifier"] for t in r.get("supportedDeviceTypes", [])]:
        if best is None or ver(r) > ver(best):
            best = r
if not want or not best:
    print("no simulator device type/runtime found", file=sys.stderr); sys.exit(1)
print("create", want, best["identifier"])
') || return 1
  set -- $out
  if [ "$1" = create ]; then
    echo "Creating simulator \"$SIM_NAME\" ($2, $3)"
    UDID=$(xcrun simctl create "$SIM_NAME" "$2" "$3") || return 1
    SIM_LABEL="$SIM_NAME (${2##*.}, created)"
  else
    UDID="$2"
    SIM_LABEL="$SIM_NAME"
  fi
  if ! xcrun simctl list devices | grep "$UDID" | grep -q Booted; then
    xcrun simctl boot "$UDID" || return 1
    BOOTED_BY_US=1
  fi
  xcrun simctl bootstatus "$UDID" -b
}

ensure_sim() { # pick or create the dedicated simulator once per invocation
  [ -n "$UDID" ] && return 0
  [ "$SIM_TRIED" = 1 ] && return 1
  SIM_TRIED=1
  local start=$SECONDS
  if pick_sim >"$RUN/logs/simulator.log" 2>&1; then
    record simulator PASS $((SECONDS - start)) "$SIM_LABEL $UDID"
    return 0
  fi
  UDID=""
  record simulator FAIL $((SECONDS - start)) "log: $RUN/logs/simulator.log"
  return 1
}

sim_is_duo() {
  xcrun simctl list -j devices | UDID="$UDID" python3 -I -c '
import json, os, sys
d = json.load(sys.stdin)
for devs in d["devices"].values():
    for x in devs:
        if x["udid"] == os.environ["UDID"]:
            sys.exit(0 if x.get("deviceTypeIdentifier", "").endswith(".iPhone-Duo") else 1)
sys.exit(1)'
}

xcb() { # xcodebuild ACTION [extra args]
  local action="$1"; shift
  xcodebuild "$action" -project ios-native/OpenTokenUsage.xcodeproj -scheme OpenTokenUsage \
    -destination "id=$UDID" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO "$@"
}

# ---------------------------------------------------------------- ios

ios_gates() {
  ensure_project || return
  ensure_sim || return
  run_gate xcode-test "xcresult: $RUN/test.xcresult" -- xcb test -resultBundlePath "$RUN/test.xcresult"
  grep -E 'Executed [0-9]+ tests?|Test run with [0-9]+ tests|\*\* TEST (SUCCEEDED|FAILED) \*\*' \
    "$RUN/logs/xcode-test.log" 2>/dev/null | tail -n 3 | sed 's/^/    /'
}

# ---------------------------------------------------------------- screenshots

is_unlit() { # PNG -> exit 0 when every pixel is black (a display that isn't lit)
  local tiny
  tiny="$(mktemp -d "${TMPDIR:-/tmp}/otu-px.XXXXXX")/px.bmp" || return 1
  sips -Z 32 -s format bmp "$1" --out "$tiny" >/dev/null 2>&1 || return 1
  python3 -I -c '
import struct, sys
d = open(sys.argv[1], "rb").read()
off = struct.unpack_from("<I", d, 10)[0]
step = max(1, struct.unpack_from("<H", d, 28)[0] // 8)
px = d[off:]
sys.exit(0 if max(max(px[i::step], default=0) for i in range(min(step, 3))) <= 8 else 1)
' "$tiny"
}

keep_if_lit() { # move an all-black frame to unlit/ so it is never mistaken for evidence
  if is_unlit "$1"; then
    mkdir -p "$SHOTS/unlit" && mv "$1" "$SHOTS/unlit/"
  fi
}

capture() { # name: one PNG per display (iPhone Duo reports several)
  local name="$1" err displays d
  if err=$(xcrun simctl io "$UDID" screenshot "$SHOTS/$name.png" 2>&1); then
    keep_if_lit "$SHOTS/$name.png"
    return 0
  fi
  displays=$(echo "$err" | grep -oE -- '--display=[0-9]+' | cut -d= -f2 | sort -u)
  [ -n "$displays" ] || { echo "$err"; return 1; }
  for d in $displays; do
    xcrun simctl io "$UDID" screenshot --display="$d" "$SHOTS/$name-display$d.png" || return 1
    keep_if_lit "$SHOTS/$name-display$d.png"
  done
}

shoot() { # app name appearance
  xcrun simctl ui "$UDID" appearance "$3" || return 1
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
  xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null
  xcrun simctl install "$UDID" "$1" || return 1
  # Unsigned layout: four 未設定 rows, no sample figures.
  xcrun simctl launch "$UDID" "$BUNDLE" || return 1
  sleep "$SHOT_WAIT"
  capture "$2"
}

landscape_copy() { # prints the path of an ad-hoc signed copy limited to LandscapeLeft
  local dst
  dst="$(mktemp -d "${TMPDIR:-/tmp}/otu-land.XXXXXX")/OpenTokenUsage.app" || return 1
  cp -R "$APP" "$dst" || return 1
  /usr/libexec/PlistBuddy -c "Delete :UISupportedInterfaceOrientations" "$dst/Info.plist" >/dev/null 2>&1
  /usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations array" "$dst/Info.plist" >&2 || return 1
  /usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationLandscapeLeft" "$dst/Info.plist" >&2 || return 1
  codesign --force --deep -s - "$dst" >&2 || return 1
  echo "$dst"
}

shots_all() {
  local land
  mkdir -p "$SHOTS" || return 1
  xcb build || return 1
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
  shoot "$APP" portrait-dark dark || return 1
  shoot "$APP" portrait-light light || return 1
  land=$(landscape_copy) || return 1
  shoot "$land" landscape-dark dark || return 1
  ls -R "$SHOTS"
  # Fail when nothing rendered: every frame black means the app never drew.
  ls "$SHOTS"/*.png >/dev/null 2>&1
}

shot_gates() {
  ensure_project || return
  ensure_sim || return
  run_gate screenshots "$SHOTS (all-black displays moved to unlit/)" -- shots_all
}

# ---------------------------------------------------------------- main

[ $# -eq 0 ] && set -- all
for arg in "$@"; do
  case "$arg" in
    all) web_gates; ios_gates; shot_gates ;;
    web) web_gates ;;
    ios) ios_gates ;;
    shots) shot_gates ;;
    *) echo "unknown target: $arg (use all, web, ios or shots)"; exit 64 ;;
  esac
done

echo
echo "verify-mac summary  ($RUN)"
[ ${#RESULTS[@]} -gt 0 ] && printf '%s\n' "${RESULTS[@]}"
if [ -n "$UDID" ]; then
  if printf '%s\n' "${RESULTS[@]}" | grep -q '^xcode-test *PASS'; then
    if sim_is_duo; then
      echo "Gate: G2/G3 reached (build + XCTest on an iPhone Duo simulator). G4 posture matrix and G5 device not covered."
    else
      echo "Gate: build + XCTest passed on a non-Duo simulator; below G2."
    fi
  else
    echo "Gate: below G2 (no passing XCTest run in this invocation)."
  fi
  if [ "$BOOTED_BY_US" = 1 ] && [ "${OTU_KEEP_SIM:-0}" != 1 ]; then
    xcrun simctl shutdown "$UDID" 2>/dev/null
  fi
fi
[ "$FAILED" = 1 ] && exit 1
[ "$BLOCKED" = 1 ] && exit 2
exit 0
