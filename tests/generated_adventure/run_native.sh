#!/usr/bin/env bash
set -uo pipefail
cd .
export XDG_DATA_HOME=/tmp/godot_generated_adventure_native/data XDG_CONFIG_HOME=/tmp/godot_generated_adventure_native/config XDG_CACHE_HOME=/tmp/godot_generated_adventure_native/cache FOGBANK_QA_WINDOWED=1
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
python3 tests/creative_actions/run_owned_guard.py --log tests/generated_adventure/native_guard.jsonl --timeout 180 --reserve-mib 512 -- godot --audio-driver Dummy --path . --script tests/generated_adventure/capture_native.gd > tests/generated_adventure/native.log 2>&1
result=$?
if grep -qE 'SCRIPT ERROR:|ERROR:' tests/generated_adventure/native.log; then result=1; fi
printf 'GENERATED NATIVE EXIT %s\n' "$result"
printf '%s\n' "$result" > tests/generated_adventure/native.exit
exit "$result"
