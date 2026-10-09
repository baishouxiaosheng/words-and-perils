#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
OUT=artifacts/seeded_adventure_20261003
export XDG_DATA_HOME=/tmp/seeded_adventure_native/data XDG_CONFIG_HOME=/tmp/seeded_adventure_native/config XDG_CACHE_HOME=/tmp/seeded_adventure_native/cache FOGBANK_QA_WINDOWED=1 FOGBANK_DELIVERY_EVIDENCE="$PWD/$OUT"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
run() {
  local name="$1"; shift
  echo "RUN $name" | tee -a "$OUT/more_status.txt"
  python3 tests/creative_actions/run_owned_guard.py --log "$OUT/${name}_guard.jsonl" --timeout 180 --reserve-mib 512 -- godot --path . "$@" > "$OUT/$name.log" 2>&1
  local result=$?
  if grep -qE 'SCRIPT ERROR:|ERROR:' "$OUT/$name.log"; then result=1; fi
  echo "$result" > "$OUT/$name.exit"
  tail -8 "$OUT/$name.log"
  echo "EXIT $name $result" | tee -a "$OUT/more_status.txt"
  return "$result"
}
echo RUNNING > "$OUT/more_status.txt"
run scale12 --headless --script tests/seeded_adventure/test_scale.gd -- 12 || exit $?
run scale24 --headless --script tests/seeded_adventure/test_scale.gd -- 24 || exit $?
run native_create --audio-driver Dummy --rendering-method gl_compatibility --script tests/generated_adventure/test_process_restart.gd -- --phase=create || exit $?
run native_resume --audio-driver Dummy --rendering-method gl_compatibility --script tests/generated_adventure/test_process_restart.gd -- --phase=resume || exit $?
echo COMPLETE | tee -a "$OUT/more_status.txt"
