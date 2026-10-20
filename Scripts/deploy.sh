#!/bin/zsh
# Build, install, and relaunch Altitude on the phone from the command line.
#
# The app is terminated before the install. Installing a new build over a
# running background location session can orphan that session, which leaves
# the location indicator stuck in the status bar until the phone restarts.
# A clean kill ends the session the same way a user force-quit does.
#
# Usage: Scripts/deploy.sh [device-id]
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-${ALTITUDE_DEVICE:-0E4AA04B-BBEB-53B0-9B82-5B6F4CD4B56A}}"
BUNDLE_ID="com.gregcorey.altitude"
SCRATCH="$(mktemp -d)"

echo "Building…"
xcodebuild -project Altitude.xcodeproj -scheme Altitude \
  -destination "id=$DEVICE" -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP="$(xcodebuild -project Altitude.xcodeproj -scheme Altitude -destination "id=$DEVICE" \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ {print $3}')/Altitude.app"

echo "Stopping the running app, if any…"
xcrun devicectl device info processes --device "$DEVICE" --json-output "$SCRATCH/procs.json" >/dev/null 2>&1 || true
PID="$(python3 -I - "$SCRATCH/procs.json" <<'PY'
import json, sys
try:
    procs = json.load(open(sys.argv[1]))["result"]["runningProcesses"]
except Exception:
    sys.exit(0)
for p in procs:
    if p.get("executable", "").endswith("/Altitude.app/Altitude"):
        print(p["processIdentifier"]); break
PY
)"
if [[ -n "$PID" ]]; then
  xcrun devicectl device process signal --device "$DEVICE" --pid "$PID" --signal SIGTERM >/dev/null 2>&1 || true
  sleep 1
fi

echo "Installing…"
xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -E "App installed|error" || true

echo "Launching…"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" 2>&1 | grep -E "Launched|error" || true
rm -rf "$SCRATCH"
