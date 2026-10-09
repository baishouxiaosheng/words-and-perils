#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=$PWD/artifacts/runtime_ai_capacity_20261004
export XDG_DATA_HOME=/tmp/capacity_qa/data XDG_CONFIG_HOME=/tmp/capacity_qa/config XDG_CACHE_HOME=/tmp/capacity_qa/cache FOGBANK_QA_WINDOWED=1
export FOGBANK_CITY_JOURNEY_OUT="$OUT/native"
mkdir -p "$FOGBANK_CITY_JOURNEY_OUT"
printf 'START\n' > "$OUT/native_status.txt"
run(){
 local label=$1;shift
 printf 'RUN %s\n' "$label" >> "$OUT/native_status.txt"
 python3 tests/loading_performance/run_owned_guard.py --log "$OUT/${label}_guard.jsonl" --timeout 300 --reserve-mib 512 -- godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/runtime_ai_capacity/test_native_journey.gd "$@" > "$OUT/$label.log" 2>&1
 local result=$?
 if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$label.log";then result=1;fi
 printf 'EXIT %s %s\n' "$label" "$result" >> "$OUT/native_status.txt"
 echo "CAPACITY_${label}_EXIT:$result"
 return "$result"
}
run native || exit $?
run native_resume -- --resume || exit $?
printf 'COMPLETE\n' >> "$OUT/native_status.txt"
