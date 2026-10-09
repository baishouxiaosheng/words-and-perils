#!/usr/bin/env bash
cd "$(dirname "$0")/../.."
python tests/creative_actions/inspect_native_memory.py > artifacts/creative_actions_20261003/native/native_host_inventory.log
printf 'NATIVE READ-ONLY MEMORY INVENTORY COMPLETE\n'
