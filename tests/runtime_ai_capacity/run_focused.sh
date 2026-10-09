#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=$PWD/artifacts/runtime_ai_capacity_20261004
export XDG_DATA_HOME=/tmp/capacity_qa/data XDG_CONFIG_HOME=/tmp/capacity_qa/config XDG_CACHE_HOME=/tmp/capacity_qa/cache
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
python3 tests/loading_performance/run_owned_guard.py --log "$OUT/policy_guard.jsonl" --timeout 240 --reserve-mib 512 -- godot --path . --headless --script tests/runtime_ai_capacity/test_policy.gd > "$OUT/policy.log" 2>&1
result=$?
if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/policy.log"; then result=1; fi
echo "$result" > "$OUT/policy_exit.txt"
echo CAPACITY_POLICY_EXIT:$result
