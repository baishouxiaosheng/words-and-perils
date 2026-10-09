#!/usr/bin/env bash
# Launch only after the native-render queue grants admission and verifies headroom.
# One actual world load; no user-computer/GPU claim and no invented DISPLAY.
set -u
cd "$(dirname "$0")/../.."
size=${1:-1280x720}
case "$size" in 1280x720|1920x1080) ;; *) echo 'Use an admitted native test resolution' >&2; exit 2;; esac
out="artifacts/render_quality_20261003/native_$size"
mkdir -p "$out" /tmp/fogbank-aa-qa/{data,config,cache}
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo 'BLOCKED: run from the actual cloud-desktop terminal.' >&2; exit 2
fi
limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unknown)
if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -gt 8589934592 ]; then
  echo "BLOCKED: unknown physical memory ceiling $limit" >&2; exit 2
fi
export XDG_DATA_HOME=/tmp/fogbank-aa-qa/data
export XDG_CONFIG_HOME=/tmp/fogbank-aa-qa/config
export XDG_CACHE_HOME=/tmp/fogbank-aa-qa/cache
export FOGBANK_QA_WINDOWED=1
export FOGBANK_LOAD_PROFILE=1
printf 'running\n' > "$out/native_run.exit"
cat /sys/fs/cgroup/memory.events > "$out/memory_before.txt"
python3 tests/creative_actions/run_owned_guard.py --log "$out/resources.jsonl" --timeout 180 --reserve-mib 512 -- godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script tests/render_quality/capture_comparison.gd -- --size="$size" --out="res://$out" > "$out/native_run.log" 2>&1
code=$?
cat /sys/fs/cgroup/memory.events > "$out/memory_after.txt"
if grep -Eq 'SCRIPT ERROR|SHADER ERROR|Parse Error|Compile Error' "$out/native_run.log"; then code=1; fi
printf '%s\n' "$code" > "$out/native_run.exit"
echo "AA NATIVE $size EXIT $code $(date -u +%FT%TZ)"
exit "$code"
