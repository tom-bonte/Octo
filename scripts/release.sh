#!/bin/zsh
# Makes a release: tests, a universal build (Apple Silicon + Intel), and dist/Octo-<version>.dmg.
# Run from anywhere:
#   scripts/release.sh          release the version in Resources/Info.plist
#   scripts/release.sh 1.0.1    set the version to 1.0.1 (and bump the build number) first
# Uploading the .dmg to GitHub is a separate, manual step.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
PLIST=Resources/Info.plist
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

if [[ -n "${1:-}" ]]; then
  [[ "$1" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Version must look like 1.2.3" >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $1" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(( $(plist CFBundleVersion) + 1 ))" "$PLIST"
fi
VERSION="$(plist CFBundleShortVersionString)"
echo "Releasing Octo $VERSION (build $(plist CFBundleVersion))"

# Public links must be filled in, or the Support and GitHub buttons would be missing.
problems=()
[[ -n "$(plist OctoSupportURL)" ]] || problems+=("OctoSupportURL (your Ko-fi page) is empty in $PLIST")
[[ -n "$(plist OctoWebsiteURL)" ]] || problems+=("OctoWebsiteURL (your GitHub page) is empty in $PLIST")
grep -q "YOUR-" README.md && problems+=("README.md still has YOUR-… placeholders")
for image in $(grep -oE 'docs/[A-Za-z0-9_-]+\.png' README.md | sort -u); do
  [[ -f "$image" ]] || problems+=("README.md shows $image, which doesn't exist")
done
[[ -f "$HOME/.octo-signing/octo-signing.keychain-db" ]] || problems+=("no signing certificate: run scripts/make-signing-identity.sh")
if (( ${#problems} )); then
  printf 'Not ready to release:\n' >&2
  printf '  - %s\n' "${problems[@]}" >&2
  exit 1
fi

echo "Testing…"
scripts/test.sh 2>&1 | grep -E "Test run" || { echo "Tests failed" >&2; exit 1; }

echo "Building for Apple Silicon and Intel…"
scripts/build.sh --universal | tail -1
APP="$ROOT/build/Octo.app"
codesign --verify --strict "$APP"
lipo "$APP/Contents/MacOS/Octo" -verify_arch arm64 x86_64

echo "Making the disk image…"
mkdir -p dist
WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
STAGING="$WORK/staging"
mkdir -p "$STAGING/.background"
ditto "$APP" "$STAGING/Octo.app"
ln -s /Applications "$STAGING/Applications"
swift scripts/make-dmg-background.swift "$STAGING/.background" >/dev/null 2>&1

# A writable image first, so Finder can save the window's layout (icon positions, size,
# background picture with the install steps) into it. Then it's compressed for download.
VOLUME="Octo $VERSION"
[[ -d "/Volumes/$VOLUME" ]] && { echo "Eject the disk named \"$VOLUME\" first" >&2; exit 1; }
SIZE_MB=$(( $(du -sm "$STAGING" | cut -f1) + 20 ))
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "/Volumes/$VOLUME" "$WORK/rw.dmg"
MOUNT="/Volumes/$VOLUME"
# The window is 660×440 points, the size of the background picture; icon positions are their
# centres. Finder saves a window's layout lazily and sometimes not at all, so the window is
# reopened and resized to make it save, and the release waits until the layout file really holds
# the background picture, trying again if needed.
lay_out_window() {
  osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  tell disk "$VOLUME"
    open
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set the bounds to {200, 120, 860, 560}
    end tell
    set viewOptions to the icon view options of container window
    tell viewOptions
      set arrangement to not arranged
      set icon size to 100
      set text size to 13
    end tell
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Octo.app" of container window to {170, 135}
    set position of item "Applications" of container window to {490, 135}
    close
    open
    delay 1
    tell container window
      set statusbar visible to false
      set the bounds to {200, 120, 850, 550}
    end tell
  end tell
  delay 1
  tell disk "$VOLUME"
    tell container window
      set statusbar visible to false
      set the bounds to {200, 120, 860, 560}
    end tell
    update without registering applications
  end tell
end tell
APPLESCRIPT
}
layout_saved() { LC_ALL=C grep -a -q backgroundImageAlias "$MOUNT/.DS_Store" 2>/dev/null }
for attempt in 1 2 3; do
  lay_out_window
  for second in {1..20}; do
    layout_saved && break 2
    sleep 1
  done
done
layout_saved || { echo "Finder didn't save the install window's layout. Run the release again." >&2; exit 1; }
osascript -e "tell application \"Finder\" to close container window of disk \"$VOLUME\"" >/dev/null
sleep 1
sync
hdiutil detach -quiet "$MOUNT"
MOUNT=""
DMG="dist/Octo-$VERSION.dmg"
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo
echo "Done: $ROOT/$DMG"
echo "Next: on GitHub, draft a new release with tag v$VERSION and attach that file."
