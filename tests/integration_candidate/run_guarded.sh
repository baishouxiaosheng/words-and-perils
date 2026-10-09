#!/usr/bin/env bash
# Serial, cache-free copied-project integration gate; run in the cloud terminal.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=artifacts/integration_candidate_20261003
export XDG_DATA_HOME=/tmp/fogbank_combined_candidate/data XDG_CONFIG_HOME=/tmp/fogbank_combined_candidate/config XDG_CACHE_HOME=/tmp/fogbank_combined_candidate/cache FOGBANK_QA_WINDOWED=1
mkdir -p "$OUT" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" /tmp/ai_gm_rebuilt artifacts/ai_gm_rebuilt artifacts/runtime_ai_20261003
START_AT="${1:-}"
if [ -z "$START_AT" ]; then printf 'RUNNING\n' > "$OUT/status.txt"; else printf 'RESUME %s\n' "$START_AT" >> "$OUT/status.txt"; fi
run() {
  local name="$1"; shift
  if [ -n "$START_AT" ]; then
    if [ "$name" != "$START_AT" ]; then return 0; fi
    START_AT=""
  fi
  printf 'RUN %s\n' "$name" | tee -a "$OUT/status.txt"
  python3 tests/creative_actions/run_owned_guard.py --log "$OUT/${name}_guard.jsonl" --timeout 180 --reserve-mib 1024 -- godot --path . "$@" > "$OUT/$name.log" 2>&1
  local result=$?
  if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$name.log"; then result=1; fi
  printf '%s\n' "$result" > "$OUT/$name.exit"
  tail -5 "$OUT/$name.log"
  printf 'EXIT %s %s\n' "$name" "$result" | tee -a "$OUT/status.txt"
  if [ "$result" -ne 0 ]; then return "$result"; fi
}
run clean_import --headless --editor --import --quit || exit $?
run memory --headless --script tests/action_memory/test_foundation.gd || exit $?
run memory_restart --headless --script tests/action_memory/test_foundation.gd -- --reload || exit $?
run core --headless --script tests/experimental/ai_gm_rebuilt/test_integration.gd || exit $?
run seed --headless --script tests/test_world_generation_contract.gd || exit $?
run seed_controller --headless --script tests/seeded_world/test_preview_controller.gd || exit $?
run tabletop_input --headless --script tests/tabletop_interaction/test_input.gd || exit $?
run tabletop_transport --headless --script tests/tabletop_interaction/test_transport.gd || exit $?
run basic_actions --headless --script tests/core_gameplay/test_basic_actions.gd || exit $?
run composite_actions --headless --script tests/core_gameplay/test_composite_actions.gd || exit $?
run release_adapter --headless --script tests/core_gameplay/test_release_adapter.gd || exit $?
run persistent_effects --headless --script tests/persistent_world_effects/test_effects.gd || exit $?
run generated_adapter --headless --script tests/generated_adventure/test_adapter.gd || exit $?
run generated_geometry --headless --script tests/generated_adventure/test_geometry.gd || exit $?
run runtime_mock --headless --script tests/runtime_ai/test_controller.gd || exit $?
run native_flow --audio-driver Dummy --rendering-method gl_compatibility --script tests/integration_candidate/test_native_flow.gd || exit $?
run native_restart --audio-driver Dummy --rendering-method gl_compatibility --script tests/integration_candidate/test_native_flow.gd -- --restart || exit $?
printf 'COMPLETE\n' | tee -a "$OUT/status.txt"
