#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=artifacts/generated_inventory_20261004
export XDG_DATA_HOME=/tmp/generated_inventory_20261004/data XDG_CONFIG_HOME=/tmp/generated_inventory_20261004/config XDG_CACHE_HOME=/tmp/generated_inventory_20261004/cache FOGBANK_QA_WINDOWED=1
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" /tmp/ai_gm_rebuilt
run() {
 local name="$1"; shift
 echo "RUN $name" | tee -a "$OUT/status.txt"
 python3 tests/creative_actions/run_owned_guard.py --log "$OUT/${name}_guard.jsonl" --timeout 240 --reserve-mib 512 -- godot --path . "$@" > "$OUT/$name.log" 2>&1
 local result=$?
 if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$name.log"; then result=1; fi
 echo "$result" > "$OUT/$name.exit"; tail -8 "$OUT/$name.log"
 echo "EXIT $name $result" | tee -a "$OUT/status.txt"
 return "$result"
}
echo RUNNING > "$OUT/status.txt"
run adapter --headless --script tests/generated_inventory/test_adapter.gd || exit $?
run controller --headless --script tests/generated_inventory/test_controller.gd || exit $?
run legacy_generated --headless --script tests/generated_adventure/test_adapter.gd || exit $?
run seeded --headless --script tests/seeded_adventure/test_adapter.gd || exit $?
run seeded_controller --headless --script tests/seeded_adventure/test_controller.gd || exit $?
run core --headless --script tests/experimental/ai_gm_rebuilt/test_integration.gd || exit $?
echo COMPLETE | tee -a "$OUT/status.txt"
