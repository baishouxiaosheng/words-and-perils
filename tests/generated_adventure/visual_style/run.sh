#!/usr/bin/env bash
set -uo pipefail
cd .
export XDG_DATA_HOME=/tmp/godot_generated_matte/data XDG_CONFIG_HOME=/tmp/godot_generated_matte/config XDG_CACHE_HOME=/tmp/godot_generated_matte/cache FOGBANK_QA_WINDOWED=1
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
name=${1:-native}
extra=()
if [[ "$name" == parse ]]; then extra=(--headless --check-only); fi
python3 tests/creative_actions/run_owned_guard.py --log "tests/generated_adventure/visual_style/${name}_guard.jsonl" --timeout 180 --reserve-mib 512 -- godot "${extra[@]}" --audio-driver Dummy --path . --script tests/generated_adventure/visual_style/capture.gd > "tests/generated_adventure/visual_style/${name}.log" 2>&1
result=$?
if grep -qE 'SCRIPT ERROR:|ERROR:' "tests/generated_adventure/visual_style/${name}.log"; then result=1; fi
printf 'GENERATED MATTE %s EXIT %s\n' "$name" "$result"
printf '%s\n' "$result" > "tests/generated_adventure/visual_style/${name}.exit"
exit "$result"
