#!/bin/zsh
# The one command after any change: tests, builds, and installs Octo into /Applications,
# replacing and restarting the running copy. Run from anywhere: scripts/install.sh
set -euo pipefail
ROOT="${0:A:h:h}"

echo "Testing…"
if ! output="$("$ROOT/scripts/test.sh" 2>&1)"; then
  echo "$output" | tail -40
  echo "Tests failed, so nothing was installed." >&2
  exit 1
fi
echo "$output" | grep -E "Test run" || true

echo "Building…"
"$ROOT/scripts/build.sh" | tail -1

pkill -x Octo 2>/dev/null || true
sleep 1
rm -rf /Applications/Octo.app
ditto "$ROOT/build/Octo.app" /Applications/Octo.app
open /Applications/Octo.app
echo "Installed and restarted /Applications/Octo.app"
