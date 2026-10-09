#!/usr/bin/env bash
# One fresh process per case, launched only from the real cloud-desktop terminal.
# The existing verified physical cgroup limit bounds RAM. Do not cap virtual
# address space or change the desktop display configuration.
set -u
cd "$(dirname "$0")/../.."
case_name=${1:-full}
checkpoint_case=${2:-full}
case "$case_name" in full|resume|partial|failure|same_process_load) ;; *) echo 'Unknown native case' >&2; exit 2;; esac
case "$checkpoint_case" in full|same_process_load) ;; *) echo 'Unknown checkpoint case' >&2; exit 2;; esac
export XDG_DATA_HOME=/tmp/fogbank-creative-qa/data
export XDG_CACHE_HOME=/tmp/fogbank-creative-qa/cache
export XDG_CONFIG_HOME=/tmp/fogbank-creative-qa/config
export FOGBANK_QA_WINDOWED=1
export FOGBANK_LOAD_PROFILE=1
base=artifacts/creative_actions_20261003/native
out="$base/$case_name"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$out"
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo 'BLOCKED: use the real cloud-desktop terminal; no display is available here.' >&2
  exit 2
fi
limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo unknown)
if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -gt 8589934592 ]; then
  echo "BLOCKED: physical cgroup RAM ceiling must be verified at <=8GiB; found $limit" >&2
  exit 2
fi
printf 'running\n' > "$out/native_run.exit"
start=$(date +%s)
{
  echo "START $(date -u +%FT%TZ) CASE $case_name"
  echo "LIMITS physical_cgroup_bytes=$limit address_space=unchanged stack=unchanged LP_NUM_THREADS=${LP_NUM_THREADS:-default} external_timeout_s=180 kill_after_s=5"
  grep -E 'MemAvailable|MemFree|AnonPages|Shmem' /proc/meminfo
  cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.events
} > "$out/native_resources.log"
python tests/creative_actions/run_owned_guard.py --log "$out/owned_guard.jsonl" --timeout 180 --reserve-mib 512 -- godot --path . --rendering-method gl_compatibility --audio-driver Dummy --max-fps 20 --script tests/creative_actions/test_native.gd -- --case="$case_name" --checkpoint-dir="$checkpoint_case" --out="res://$base" > "$out/native_run.log" 2>&1
code=$?
{
  echo "END $(date -u +%FT%TZ) EXIT $code ELAPSED_SECONDS $(($(date +%s)-start))"
  grep -E 'MemAvailable|MemFree|AnonPages|Shmem' /proc/meminfo
  cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.events
} >> "$out/native_resources.log"
printf '%s\n' "$code" > "$out/native_run.exit"
echo "CREATIVE NATIVE CASE $case_name EXIT $code $(date -u +%FT%TZ)"
exit "$code"
