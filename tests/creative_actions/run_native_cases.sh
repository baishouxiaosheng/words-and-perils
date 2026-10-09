#!/usr/bin/env bash
# Each child exits before the next heavy renderer starts. Stop at every failure.
set -u
cd "$(dirname "$0")/../.."
for case_name in full resume partial failure; do
  bash tests/creative_actions/run_native.sh "$case_name" || exit $?
done
