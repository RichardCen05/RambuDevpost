#!/usr/bin/env bash
# Records the parent and caregiver simulators at the same time for the demo video.
# Usage: tools/record_demo.sh <output-folder> [parent-udid] [caregiver-udid]
# Press Ctrl+C to stop; both .mov files are finalized on exit.
set -euo pipefail

OUT="${1:?output folder}"
PARENT="${2:-88B6F31A-7067-4334-9C60-5E754F8468C3}"     # iPhone 17 Pro
CAREGIVER="${3:-6B1481AC-EB0D-4828-90B2-9E29BAC226A1}"  # iPhone 17 Pro Max
mkdir -p "$OUT"
STAMP="$(date +%H%M%S)"

for udid in "$PARENT" "$CAREGIVER"; do
  xcrun simctl status_bar "$udid" override --time "09:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
done

xcrun simctl io "$PARENT" recordVideo --codec h264 --force "$OUT/parent-$STAMP.mov" &
P1=$!
xcrun simctl io "$CAREGIVER" recordVideo --codec h264 --force "$OUT/caregiver-$STAMP.mov" &
P2=$!
echo "recording parent-$STAMP.mov and caregiver-$STAMP.mov in $OUT (Ctrl+C to stop)"
trap 'kill -INT $P1 $P2 2>/dev/null; wait $P1 $P2 2>/dev/null; echo saved' INT TERM
wait
