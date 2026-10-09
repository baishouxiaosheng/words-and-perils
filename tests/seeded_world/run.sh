#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME=/tmp/godot_seeded_world/data XDG_CONFIG_HOME=/tmp/godot_seeded_world/config XDG_CACHE_HOME=/tmp/godot_seeded_world/cache
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
python3 tests/creative_actions/run_owned_guard.py --log tests/seeded_world/contract_guard.jsonl --timeout 180 --reserve-mib 512 -- godot --headless --path . --script tests/test_world_generation_contract.gd > tests/seeded_world/contract.log 2>&1
result=$?
if grep -qE 'SCRIPT ERROR:|ERROR:' tests/seeded_world/contract.log; then result=1; fi
printf '%s\n' "$result" > tests/seeded_world/contract.exit
cat tests/seeded_world/contract.log
exit "$result"
