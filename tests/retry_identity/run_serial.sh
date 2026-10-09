#!/usr/bin/env bash
# Coordinate the shared Godot/render slot with the integration owner before running.
set -euo pipefail
cd "$(dirname "$0")/../.."
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/fogbank_retry_identity/data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/fogbank_retry_identity/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/fogbank_retry_identity/config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" artifacts/retry_identity_20261003
for script in reproduce_original_engine test_retry_identity reload_process test_adapter_retry; do
  godot --headless --path . --script "res://tests/retry_identity/$script.gd" > "artifacts/retry_identity_20261003/$script.log" 2>&1
  tail -2 "artifacts/retry_identity_20261003/$script.log"
done
