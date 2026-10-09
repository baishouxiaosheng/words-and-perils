#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../.."
bash tests/ui_readability/run_game_ui.sh 1280x720
bash tests/ui_readability/run_game_ui.sh 2560x1440
