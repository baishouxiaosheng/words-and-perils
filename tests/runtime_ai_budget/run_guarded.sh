#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=$PWD/artifacts/runtime_ai_budget_20261004
export XDG_DATA_HOME=/tmp/public_budget_qa/data XDG_CONFIG_HOME=/tmp/public_budget_qa/config XDG_CACHE_HOME=/tmp/public_budget_qa/cache
mkdir -p "$OUT/creative_core" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
python3 tests/runtime_ai_budget/verify_delta.py > "$OUT/static_delta_report.json" || exit $?
printf 'START\n' > "$OUT/status.txt"
run(){
 local label=$1; local timeout_=$2;shift 2
 printf 'RUN %s\n' "$label" >> "$OUT/status.txt"
 python3 tests/loading_performance/run_owned_guard.py --log "$OUT/${label}_guard.jsonl" --timeout "$timeout_" --reserve-mib 512 -- godot --path . --headless "$@" > "$OUT/$label.log" 2>&1
 local result=$?
 if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$label.log"; then result=1;fi
 printf 'EXIT %s %s\n' "$label" "$result" >> "$OUT/status.txt"
 echo "BUDGET_${label}_EXIT:$result"
 return "$result"
}
run focused 180 --script tests/runtime_ai_budget/test_budget.gd || exit $?
run settlement 180 --script tests/runtime_ai_budget/regression_test_settlement.gd || exit $?
run controller 180 --script tests/runtime_ai_budget/regression_test_controller.gd || exit $?
run integration 180 --script tests/runtime_ai_budget/regression_test_integration.gd || exit $?
run creative_core 180 --script tests/runtime_ai_budget/regression_test_core.gd || exit $?
run memory 180 --script tests/action_memory/test_foundation.gd || exit $?
run memory_restart 180 --script tests/action_memory/test_foundation.gd -- --reload || exit $?
printf 'COMPLETE\n' >> "$OUT/status.txt"
echo ALL_PUBLIC_BUDGET_CASES_COMPLETE
