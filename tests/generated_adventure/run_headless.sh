#!/usr/bin/env bash
set -uo pipefail
cd .
export XDG_DATA_HOME=/tmp/godot_generated_adventure/data XDG_CONFIG_HOME=/tmp/godot_generated_adventure/config XDG_CACHE_HOME=/tmp/godot_generated_adventure/cache
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
name=${1:-adapter}
extra=()
script=tests/generated_adventure/test_adapter.gd
if [[ "$name" == scale12 ]]; then script=tests/generated_adventure/test_scale.gd; extra=(-- 12); fi
if [[ "$name" == scale24 ]]; then script=tests/generated_adventure/test_scale.gd; extra=(-- 24); fi
if [[ "$name" == core ]]; then script=tests/generated_adventure/test_core_compat.gd; fi
if [[ "$name" == release ]]; then script=tests/core_gameplay/test_release_adapter.gd; fi
if [[ "$name" == geometry ]]; then script=tests/generated_adventure/test_geometry.gd; fi
if [[ "$name" == ui ]]; then script=tests/generated_adventure/test_ui.gd; fi
if [[ "$name" == uiparse ]]; then script=tests/generated_adventure/test_ui.gd; extra=(--check-only); fi
if [[ "$name" == containment ]]; then script=tests/map_preview/test_release_containment.gd; fi
if [[ "$name" == parse ]]; then extra=(--check-only); fi
python3 tests/creative_actions/run_owned_guard.py --log "tests/generated_adventure/${name}_guard.jsonl" --timeout 180 --reserve-mib 512 -- godot --headless --path . --script "$script" "${extra[@]}" > "tests/generated_adventure/${name}.log" 2>&1
result=$?
if grep -qE "SCRIPT ERROR:|ERROR:" "tests/generated_adventure/${name}.log"; then result=1; fi
printf 'GENERATED %s EXIT %s\n' "$name" "$result"
printf '%s\n' "$result" > "tests/generated_adventure/${name}.exit"
exit "$result"
