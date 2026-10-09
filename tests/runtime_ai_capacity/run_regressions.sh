#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=$PWD/artifacts/runtime_ai_capacity_20261004
export XDG_DATA_HOME=/tmp/capacity_qa/data XDG_CONFIG_HOME=/tmp/capacity_qa/config XDG_CACHE_HOME=/tmp/capacity_qa/cache FOGBANK_QA_WINDOWED=1
export FOGBANK_CITY_JOURNEY_OUT="$OUT/native"
mkdir -p "$OUT/regressions/creative_core" "$FOGBANK_CITY_JOURNEY_OUT"
python3 tests/runtime_ai_capacity/verify_static.py > "$OUT/static_report.json" || exit $?
printf 'START\n' > "$OUT/regression_status.txt"
run(){
 local label=$1;local timeout_=$2;shift 2
 printf 'RUN %s\n' "$label" >> "$OUT/regression_status.txt"
 python3 tests/loading_performance/run_owned_guard.py --log "$OUT/${label}_guard.jsonl" --timeout "$timeout_" --reserve-mib 512 -- godot --path . "$@" > "$OUT/$label.log" 2>&1
 local result=$?
 if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$label.log";then result=1;fi
 printf 'EXIT %s %s\n' "$label" "$result" >> "$OUT/regression_status.txt"
 echo "CAPACITY_${label}_EXIT:$result"
 return "$result"
}
run policy 240 --headless --script tests/runtime_ai_capacity/test_policy.gd || exit $?
run legacy 180 --headless --script tests/runtime_ai_capacity/regressions/test_legacy_budget.gd || exit $?
run controller 180 --headless --script tests/runtime_ai_capacity/regressions/regression_test_controller.gd || exit $?
run integration 180 --headless --script tests/runtime_ai_capacity/regressions/regression_test_integration.gd || exit $?
run creative_core 180 --headless --script tests/runtime_ai_capacity/regressions/regression_test_core.gd || exit $?
run settlement 180 --headless --script tests/runtime_ai_capacity/regressions/regression_test_settlement.gd || exit $?
run memory 180 --headless --script tests/action_memory/test_foundation.gd || exit $?
run memory_restart 180 --headless --script tests/action_memory/test_foundation.gd -- --reload || exit $?
run native 300 --audio-driver Dummy --rendering-method gl_compatibility --script tests/runtime_ai_capacity/test_native_journey.gd || exit $?
run native_resume 300 --audio-driver Dummy --rendering-method gl_compatibility --script tests/runtime_ai_capacity/test_native_journey.gd -- --resume || exit $?
run panel 180 --audio-driver Dummy --rendering-method gl_compatibility --script tests/runtime_ai_capacity/test_panel_native.gd || exit $?
printf 'COMPLETE\n' >> "$OUT/regression_status.txt"
