#!/usr/bin/env bash
# Run from the native cloud desktop terminal. Never invent DISPLAY or resize
# the desktop. One native renderer at a time, separate process per resolution.
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=/tmp/fogbank-screen-qa/data
export XDG_CACHE_HOME=/tmp/fogbank-screen-qa/cache
export XDG_CONFIG_HOME=/tmp/fogbank-screen-qa/config
export FOGBANK_QA_WINDOWED=1
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" artifacts/screen_adaptation_20261003
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "BLOCKED: no native display in this shell. Use the desktop terminal." >&2
  exit 2
fi
status=0
for size in "${@:-1280x720 1920x1080 2560x1440 3440x1440 1920x1200}"; do
  for resolution in $size; do
    echo "BEGIN $resolution $(date -u +%FT%TZ)"
    timeout --signal=TERM --kill-after=5s 180s godot --path . --rendering-method gl_compatibility --audio-driver Dummy --max-fps 20 --script tests/screen_adaptation/capture_matrix.gd -- --size="$resolution" > "artifacts/screen_adaptation_20261003/run_${resolution}.log" 2>&1
    code=$?
    echo "EXIT $resolution $code $(date -u +%FT%TZ)"
    [ "$code" -eq 0 ] || status=1
    if grep -q "SCRIPT ERROR" "artifacts/screen_adaptation_20261003/run_${resolution}.log"; then exit 1; fi
    # An aborted fixture is a blocker, not a reason to start more heavy work.
    [ "$code" -eq 124 ] || [ "$code" -eq 137 ] && break 2
  done
done
if [ "$#" -eq 0 ]; then
  bash tests/screen_adaptation/run_transitions.sh || status=1
fi
exit "$status"
