#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export HOME=/tmp/committed_feedback_home XDG_DATA_HOME=/tmp/committed_feedback_data XDG_CONFIG_HOME=/tmp/committed_feedback_config XDG_CACHE_HOME=/tmp/committed_feedback_cache
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
log=tests/committed_action_feedback/test_camera_feedback.log
timeout --signal=TERM --kill-after=3s 30s godot --headless --path . --script res://tests/committed_action_feedback/test_camera_feedback.gd > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL:' "$log"; then exit 1; fi
grep -q 'COMMITTED CAMERA FEEDBACK PASSED' "$log"
