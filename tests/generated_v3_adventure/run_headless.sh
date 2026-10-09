#!/usr/bin/env bash
# Invoke only after the parent grants the shared serialized Godot engine slot.
set -euo pipefail
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/godot_v3_adventure/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/godot_v3_adventure/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/godot_v3_adventure/cache}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" artifacts/generated_v3_adventure
mode="${1:-adapter}"
run() {
  local label="$1"; shift
  python3 tests/creative_actions/run_owned_guard.py --log "artifacts/generated_v3_adventure/${label}_guard.jsonl" --timeout 180 --reserve-mib 512 -- godot --headless --path . "$@" >"artifacts/generated_v3_adventure/${label}.log" 2>&1
  if grep -qE 'SCRIPT ERROR:|ERROR:' "artifacts/generated_v3_adventure/${label}.log"; then cat "artifacts/generated_v3_adventure/${label}.log"; return 1; fi
  tail -4 "artifacts/generated_v3_adventure/${label}.log"
}
if [[ "$mode" == restart ]]; then
  for phase in idle canceled pending ready locked staged committed; do
    run "restart_${phase}_write" --script tests/generated_v3_adventure/test_process_restart.gd -- write "$phase"
    run "restart_${phase}_read" --script tests/generated_v3_adventure/test_process_restart.gd -- read "$phase"
  done
elif [[ "$mode" == audit ]]; then
  run admission_audit --script tests/generated_v3_adventure/test_admission_audit.gd
elif [[ "$mode" == parse ]]; then
  run parse --script tests/generated_v3_adventure/test_adapter.gd --check-only
else
  run adapter --script tests/generated_v3_adventure/test_adapter.gd
fi
