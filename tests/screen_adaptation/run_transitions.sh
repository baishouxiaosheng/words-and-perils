#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=/tmp/fogbank-screen-qa/data
export XDG_CACHE_HOME=/tmp/fogbank-screen-qa/cache
export XDG_CONFIG_HOME=/tmp/fogbank-screen-qa/config
export FOGBANK_QA_WINDOWED=1
mkdir -p artifacts/screen_adaptation_20261003/transitions
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "BLOCKED: a native desktop terminal is required" >&2
  exit 2
fi
timeout --signal=TERM --kill-after=5s 180s godot --path . --rendering-method gl_compatibility --audio-driver Dummy --max-fps 20 --script tests/screen_adaptation/test_window_transitions.gd > artifacts/screen_adaptation_20261003/transitions/run.log 2>&1
code=$?
echo "TRANSITIONS EXIT $code $(date -u +%FT%TZ)"
exit "$code"
