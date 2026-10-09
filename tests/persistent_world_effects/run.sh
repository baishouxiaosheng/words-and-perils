#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export HOME=/tmp/typed_effects_test_home
export XDG_DATA_HOME=/tmp/typed_effects_test_data
export XDG_CONFIG_HOME=/tmp/typed_effects_test_config
export XDG_CACHE_HOME=/tmp/typed_effects_test_cache
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
log=tests/persistent_world_effects/test_effects.log
if ! godot --headless --path . --script res://tests/persistent_world_effects/test_effects.gd > "$log" 2>&1; then
  cat "$log"
  exit 1
fi
cat "$log"
if grep -Eq 'SCRIPT ERROR|^ERROR:|^FAIL:' "$log"; then exit 1; fi
grep -q 'PERSISTENT WORLD EFFECTS' "$log"
