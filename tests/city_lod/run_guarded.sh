#!/usr/bin/env bash
# Execute from the native host where the real /sys/fs/cgroup is visible.
# No engine concurrency; owned PID guard preserves the 512MiB reserve.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT="${FOGBANK_CITY_REVIEW_OUT:-$PWD/artifacts/city_lod_20261004/reproduction}"
mkdir -p "$OUT"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/fogbank_city_lod/data}" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/fogbank_city_lod/config}" XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/fogbank_city_lod/cache}" FOGBANK_QA_WINDOWED=1
export FOGBANK_CITY_JOURNEY_OUT="$OUT/journey"
mkdir -p "$FOGBANK_CITY_JOURNEY_OUT"
all_ok=1
run(){
 local label=$1;local limit=$2;shift 2
 mkdir -p "$OUT/$label"
 export FOGBANK_CITY_OUT="$OUT/$label" FOGBANK_CITY_RULES_OUT="$OUT/$label"
 python3 tests/loading_performance/run_owned_guard.py --log "$OUT/$label/guard.jsonl" --timeout "$limit" --reserve-mib 512 -- godot --path . "$@" > "$OUT/$label/log.txt" 2>&1
 local result=$?
 if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$label/log.txt";then result=1;fi
 echo "$result" > "$OUT/$label/exit.txt"
 echo "$label exit=$result"
 if [ "$result" -ne 0 ];then all_ok=0;fi
 # Never keep launching after a memory-guard or supervisor failure.
 if [ "$result" -ne 0 ] && [ "$result" -ne 1 ];then exit "$result";fi
}
python3 tests/city_lod/test_asset_contract.py > "$OUT/asset_contract.json" || exit $?
run profile 180 --audio-driver Dummy --rendering-method gl_compatibility --script tests/city_lod/profile.gd
run lod 180 --audio-driver Dummy --rendering-method gl_compatibility --script tests/city_lod/test_lod.gd
run rules 180 --headless --script tests/city_lod/test_rules.gd
run journey 300 --audio-driver Dummy --rendering-method gl_compatibility --script tests/city_lod/test_native_journey.gd
run resume 300 --audio-driver Dummy --rendering-method gl_compatibility --script tests/city_lod/test_native_journey.gd -- --resume
if [ "$all_ok" -eq 1 ];then exit 0;else exit 1;fi
