#!/usr/bin/env bash
cd "$(dirname "$0")/../.." || exit 1
export XDG_DATA_HOME=/tmp/godot_seeded_world/data XDG_CONFIG_HOME=/tmp/godot_seeded_world/config XDG_CACHE_HOME=/tmp/godot_seeded_world/cache
python3 tests/creative_actions/run_owned_guard.py --log tests/seeded_world/controller_guard.jsonl --timeout 60 --reserve-mib 512 -- godot --headless --path . --script tests/seeded_world/test_preview_controller.gd > tests/seeded_world/controller.log 2>&1
result=$?
if grep -qE 'SCRIPT ERROR:|ERROR:' tests/seeded_world/controller.log; then result=1; fi
printf '%s\n' "$result" > tests/seeded_world/controller.exit
cat tests/seeded_world/controller.log
exit "$result"
