#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=artifacts/generated_inventory_20261004
export XDG_DATA_HOME=/tmp/generated_inventory_native_20261004/data XDG_CONFIG_HOME=/tmp/generated_inventory_native_20261004/config XDG_CACHE_HOME=/tmp/generated_inventory_native_20261004/cache FOGBANK_QA_WINDOWED=1 FOGBANK_DELIVERY_EVIDENCE="$PWD/$OUT"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
echo RUNNING > "$OUT/native_status.txt"
for phase in create resume; do
 python3 tests/creative_actions/run_owned_guard.py --log "$OUT/native_${phase}_guard.jsonl" --timeout 240 --reserve-mib 512 -- godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tests/generated_inventory/test_native_restart.gd -- --phase="$phase" > "$OUT/native_$phase.log" 2>&1
 result=$?
 if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/native_$phase.log"; then result=1; fi
 echo "$result" > "$OUT/native_$phase.exit"; tail -8 "$OUT/native_$phase.log"
 echo "EXIT $phase $result" | tee -a "$OUT/native_status.txt"
 if [ "$result" != 0 ]; then exit "$result"; fi
done
echo COMPLETE | tee -a "$OUT/native_status.txt"
