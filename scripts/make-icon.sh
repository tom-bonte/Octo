#!/bin/zsh
# Rebuilds Resources/AppIcon.icns (the Octo octopus) from scripts/make-icon.swift.
set -euo pipefail
ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"
swift "$ROOT/scripts/make-icon.swift" "$WORK/icon-1024.png"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
cp "$WORK/icon-1024.png" "$ROOT/Resources/AppIcon.png"
rm -rf "$WORK"
echo "Wrote Resources/AppIcon.icns"
