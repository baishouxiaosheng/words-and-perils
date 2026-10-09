# Explicit V3 village + inventory profile

- Profile: `generated_v3_village_inventory/v1`; world prefix: `generated_v3_village_inventory_v1_`
- Save: `generated_v3_village_inventory_save/v1` at `user://generated_v3_village_inventory_v1.json`; independent request: `user://generated_v3_village_inventory_request_v1.json`
- The existing inventory source is admitted first. Its exact terrain source, emitted mesh, item catalog and original spawn are preserved. Its terrain `base_runtime_hash` remains unchanged; `inventory_runtime_hash` records the existing inventory admission identity.
- `Planner.build` uses that original spawn. A saved `placement_manifest` must pass exact deterministic `Planner.validate` before constructing navigation overlay; self-rehashing cannot grant authority. The final runtime hash binds the new profile digest, original terrain and inventory identities, placement identity, effective navigation hash and immutable static catalog.
- The accepted inventory state validator and complete receipt replay are reused on the detached combined authority. The accepted item resolvers implement all drop/pickup semantics. Existing move, cell-observe and rest engines consume only the verified overlay. Admission explicitly proves that the overlay origin-reachable set equals the original spawn component; the published component is reconstructed from that effective graph. There is no new item engine.
- Settlement, building and road references select immutable source-bound public facts. Static selection itself changes no turn, entropy or history. Existing cell observation may carry a static frozen focus. Buildings cannot be picked up; there are no conversations, gates, interiors, NPC behavior or road movement bonuses.
- Combined model projection is dispatched before the inventory projection. Malformed combined markers remain fail-closed. Public scene `navigation_id` identifies the unchanged base terrain layer; `generated_source.effective_navigation_id` identifies the obstruction overlay that actually controls movement and pickup reach. Public cells stay bounded; static descriptors are explicit whitelists. Raw source, whole placement manifest, complete navigation and RNG/history are not projected.
- Legacy exploration/inventory save schemas and destinations are rejected atomically. Restart is an explicit fresh combined journey and never overwrites an existing save.

Verification entrypoints: `tests/generated_v3_village/test_adapter.gd` and `test_process_restart.gd`. The latter supports independent `write/read` processes for `idle`, `canceled`, `pending`, `ready`, `locked`, `staged`, `committed`. Engine execution is reserved for the coordinating parent; this implementation lane performs no native/engine launch.

## Final frozen fresh-process gate

Run only after all final production modules are frozen and the coordinating parent owns the serialized native slot. Do not change production files between writer and reader. Seven states each use two separate Godot processes (14 launches total). Every reader checks the complete canonical save digest before resuming; locked/staged readers also prove cancel rejection and exactly one whole-stack commit.

From the candidate `game` directory, the parent may use:

```bash
set -euo pipefail
export XDG_DATA_HOME=/tmp/v3_village_final_restart/data
export XDG_CONFIG_HOME=/tmp/v3_village_final_restart/config
export XDG_CACHE_HOME=/tmp/v3_village_final_restart/cache
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" artifacts/generated_v3_village
for phase in idle canceled pending ready locked staged committed; do
  for mode in write read; do
    label="restart_${phase}_${mode}"
    python3 tests/creative_actions/run_owned_guard.py \
      --log "artifacts/generated_v3_village/${label}_guard.jsonl" \
      --timeout 180 --reserve-mib 512 -- \
      godot --headless --path . \
      --script tests/generated_v3_village/test_process_restart.gd \
      -- "$mode" "$phase" \
      >"artifacts/generated_v3_village/${label}.log" 2>&1
    if grep -qE 'SCRIPT ERROR:|ERROR:|FAIL' "artifacts/generated_v3_village/${label}.log"; then
      cat "artifacts/generated_v3_village/${label}.log"
      exit 1
    fi
    grep -F "V3 VILLAGE PROCESS $mode $phase PASS" "artifacts/generated_v3_village/${label}.log"
  done
done
```

This is a prepared invocation recipe, not an execution record. The implementation lane never launches it. The original owned-process guard, 512 MiB reserve, physical cgroup checks and single-child ownership remain unchanged.
