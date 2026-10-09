#!/bin/sh
set -eu
cd "$(dirname "$0")"
python3 tools/restore_large_assets.py
godot --headless --path "$PWD" --editor --quit
exec godot --path "$PWD" "$@"
