#!/usr/bin/env bash
# Native component-only evidence. The full coast is deliberately not loaded.
set -u
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=/tmp/fogbank-aa-components/data XDG_CACHE_HOME=/tmp/fogbank-aa-components/cache XDG_CONFIG_HOME=/tmp/fogbank-aa-components/config
out=artifacts/render_quality_20261003/components
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$out"
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then echo 'Actual native display required' >&2; exit 2; fi
python3 tests/creative_actions/run_owned_guard.py --log "$out/resources.jsonl" --timeout 45 --reserve-mib 512 -- godot --path . --audio-driver Dummy --rendering-method gl_compatibility --max-fps 20 --script tests/render_quality/capture_components.gd > "$out/native.log" 2>&1
code=$?
if grep -Eq 'SCRIPT ERROR|SHADER ERROR|Parse Error|Compile Error' "$out/native.log"; then code=1; fi
printf '%s\n' "$code" > "$out/native.exit"
echo "AA COMPONENTS EXIT $code"
exit "$code"
