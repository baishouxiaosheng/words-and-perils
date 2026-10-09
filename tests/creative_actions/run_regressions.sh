#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=artifacts/creative_actions_20261003/regressions
mkdir -p "$OUT" tests/creative_actions/regression_wrappers /tmp/creative_regression/{home,data,config,cache}
printf 'START\n' > "$OUT/status.txt"
for test in tests/persistent_world_effects/test_effects.gd tests/core_gameplay/test_release_adapter.gd tests/core_gameplay/test_basic_actions.gd tests/core_gameplay/test_composite_actions.gd tests/experimental/ai_gm_rebuilt/test_integration.gd tests/traversal_scene/test_framework.gd tests/traversal_scene/test_scalar_scene_proof.gd tests/traversal_scene/test_source_flight_route.gd tests/runtime_ai/test_controller.gd; do
 name=$(basename "$test" .gd)
 # Keep earlier evidence untouched. Only redirect test-owned report output paths;
 # all production code, rules, assertions and historical fixture imports are exact.
 wrapper="tests/creative_actions/regression_wrappers/$name.gd"
 python - "$test" "$wrapper" "$OUT/$name.json" <<'PY'
import sys,pathlib,hashlib,json
src,dst,out=sys.argv[1:];text=pathlib.Path(src).read_text()
for old in ['res://tests/persistent_world_effects/report.json','res://artifacts/ai_gm_rebuilt/test_report.json','res://artifacts/runtime_ai_20261003/controller_results.json']:
 text=text.replace(old,'res://'+out)
pathlib.Path(dst).write_text(text)
print(json.dumps({'original':src,'sha256':hashlib.sha256(pathlib.Path(src).read_bytes()).hexdigest(),'output_redirect_only':dst}))
PY
 printf 'RUN %s\n' "$name" >> "$OUT/status.txt"
 set +e
 env HOME=/tmp/creative_regression/home XDG_DATA_HOME=/tmp/creative_regression/data XDG_CONFIG_HOME=/tmp/creative_regression/config XDG_CACHE_HOME=/tmp/creative_regression/cache GODOT_SILENCE_ROOT_WARNING=1 timeout -k 5 180 bash -c 'ulimit -v 8388608; exec godot --headless --path . --script "res://'$wrapper'"' > "$OUT/$name.log" 2>&1
 status=$?; set -e
 printf 'EXIT %s %d\n' "$name" "$status" >> "$OUT/status.txt"
 tail -6 "$OUT/$name.log"
 [ "$status" -eq 0 ] || exit "$status"
done
printf 'COMPLETE\n' >> "$OUT/status.txt"
