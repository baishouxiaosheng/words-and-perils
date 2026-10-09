#!/usr/bin/env bash
# Explicit root queue and fresh cgroup headroom admission required before use.
set -u
cd "$(dirname "$0")/../.."
resolution=${1:-1280x720}
case "$resolution" in 1280x720|2560x1440) ;; *) echo 'Use one admitted720p or1440p process' >&2; exit 2;; esac
export XDG_DATA_HOME=/tmp/fogbank-ui-review/data XDG_CACHE_HOME=/tmp/fogbank-ui-review/cache XDG_CONFIG_HOME=/tmp/fogbank-ui-review/config FOGBANK_QA_WINDOWED=1
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" artifacts/ui_readability_20261003/game
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then echo 'Native display required' >&2; exit 2; fi
python3 tests/creative_actions/run_owned_guard.py --log "artifacts/ui_readability_20261003/game/resources_${resolution}.jsonl" --timeout 90 --reserve-mib 512 -- godot --path . --audio-driver Dummy --rendering-method gl_compatibility --max-fps 20 --script tests/ui_readability/capture_game_ui.gd -- --size="$resolution" > "artifacts/ui_readability_20261003/game/run_${resolution}.log" 2>&1
code=$?
printf '%s\n' "$code" > "artifacts/ui_readability_20261003/game/run_${resolution}.exit"
echo "ACTUAL HUD $resolution EXIT $code"
exit "$code"
