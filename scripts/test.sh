#!/bin/zsh
# Runs the gesture and settings tests. Run from anywhere: scripts/test.sh
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
swift run --scratch-path "$HOME/Library/Caches/Octo/build" OctoChecks
