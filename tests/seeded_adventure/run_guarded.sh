#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=artifacts/seeded_adventure_20261003
export XDG_DATA_HOME=/tmp/seeded_adventure_20261003/data XDG_CONFIG_HOME=/tmp/seeded_adventure_20261003/config XDG_CACHE_HOME=/tmp/seeded_adventure_20261003/cache FOGBANK_QA_WINDOWED=1
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" /tmp/ai_gm_rebuilt
run() {
  local name="$1"; shift
  printf 'RUN %s\n' "$name" | tee -a "$OUT/status.txt"
  python3 tests/creative_actions/run_owned_guard.py --log "$OUT/${name}_guard.jsonl" --timeout 180 --reserve-mib 512 -- godot --path . "$@" > "$OUT/$name.log" 2>&1
  local result=$?
  if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$name.log"; then result=1; fi
  printf '%s\n' "$result" > "$OUT/$name.exit"
  tail -5 "$OUT/$name.log"
  printf 'EXIT %s %s\n' "$name" "$result" | tee -a "$OUT/status.txt"
  return "$result"
}
printf 'RUNNING\n' > "$OUT/status.txt"
run adapter --headless --script tests/seeded_adventure/test_adapter.gd || exit $?
run controller --headless --script tests/seeded_adventure/test_controller.gd || exit $?
run legacy_adapter --headless --script tests/generated_adventure/test_adapter.gd || exit $?
run preview_controller --headless --script tests/seeded_world/test_preview_controller.gd || exit $?
run seed_contract --headless --script tests/test_world_generation_contract.gd || exit $?
run core --headless --script tests/experimental/ai_gm_rebuilt/test_integration.gd || exit $?
printf 'COMPLETE\n' | tee -a "$OUT/status.txt"
