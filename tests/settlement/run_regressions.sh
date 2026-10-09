#!/usr/bin/env bash
set -uo pipefail
cd .
OUT=artifacts/settlement_20261003
printf 'START\n' > "$OUT/regression_status.txt"
for test in tests/persistent_world_effects/test_effects.gd tests/core_gameplay/test_release_adapter.gd tests/core_gameplay/test_basic_actions.gd tests/core_gameplay/test_composite_actions.gd tests/experimental/ai_gm_rebuilt/test_integration.gd tests/traversal_scene/test_framework.gd tests/traversal_scene/test_scalar_scene_proof.gd tests/traversal_scene/test_source_flight_route.gd;do
 name=$(basename "$test" .gd)
 printf 'RUN %s\n' "$name" >> "$OUT/regression_status.txt"
 env HOME=/tmp/fogbank_settlement/home XDG_DATA_HOME=/tmp/fogbank_settlement/data XDG_CONFIG_HOME=/tmp/fogbank_settlement/config XDG_CACHE_HOME=/tmp/fogbank_settlement/cache GODOT_SILENCE_ROOT_WARNING=1 timeout -k 10 180 godot --headless --path . --script "res://$test" > "$OUT/regression_$name.log" 2>&1
 status=$?;printf 'EXIT %s %d\n' "$name" "$status" >> "$OUT/regression_status.txt";tail -6 "$OUT/regression_$name.log"
 [ "$status" -eq 0 ] || exit "$status"
done
printf 'COMPLETE\n' >> "$OUT/regression_status.txt"
