#!/usr/bin/env bash
# Acquire the shared native-engine slot before invoking this script.
set -euo pipefail
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/action_memory/data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/action_memory/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/action_memory/config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" artifacts/action_memory_20261003 artifacts/ai_gm_rebuilt /tmp/ai_gm_rebuilt
run() {
  local name="$1"; local script="$2"; shift 2
  local output="artifacts/action_memory_20261003/${name}.log"
  local result=0
  python3 tests/creative_actions/run_owned_guard.py --log "artifacts/action_memory_20261003/${name}_guard.jsonl" --timeout 120 --reserve-mib 1024 -- godot --headless --path . --script "$script" "$@" > "$output" 2>&1 || result=$?
  cat "$output"
  if grep -qE 'SCRIPT ERROR:|ERROR:' "$output"; then result=1; fi
  printf '%s\n' "$result" > "artifacts/action_memory_20261003/${name}.exit"
  return "$result"
}
run focused res://tests/action_memory/test_foundation.gd
run restart res://tests/action_memory/test_foundation.gd -- --reload
run transaction_regression res://tests/experimental/ai_gm_rebuilt/test_integration.gd
