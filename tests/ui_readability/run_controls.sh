#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=/tmp/fogbank-ui-preview/data XDG_CACHE_HOME=/tmp/fogbank-ui-preview/cache XDG_CONFIG_HOME=/tmp/fogbank-ui-preview/config
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" artifacts/ui_readability_20261003
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then echo "Native display required" >&2; exit 2; fi
python3 tests/creative_actions/run_owned_guard.py --log artifacts/ui_readability_20261003/controls_resources.jsonl --timeout 45 --reserve-mib 512 -- godot --path . --audio-driver Dummy --rendering-method gl_compatibility --max-fps 20 --script tests/ui_readability/capture_controls.gd > artifacts/ui_readability_20261003/controls_native.log 2>&1
code=$?
printf '%s\n' "$code" > artifacts/ui_readability_20261003/controls_native.exit
echo "CONTROLS EXIT $code"
exit "$code"
