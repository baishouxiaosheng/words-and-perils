#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export HOME=/tmp/committed_feedback_composite_home XDG_DATA_HOME=/tmp/committed_feedback_composite_data XDG_CONFIG_HOME=/tmp/committed_feedback_composite_config XDG_CACHE_HOME=/tmp/committed_feedback_composite_cache
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
log=tests/committed_action_feedback/test_composite_preflight.log
timeout --signal=TERM --kill-after=3s 95s godot --headless --path . --script res://tests/committed_action_feedback/test_main_composite_capture.gd > "$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|COMBAT_CAPTURE_FAIL|^FAIL:' "$log"; then exit 1; fi
grep -q 'ACTUAL MAIN COMBAT CAPTURE PASSED' "$log"
