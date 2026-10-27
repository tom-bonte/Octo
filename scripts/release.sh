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
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Octo.app"
ln -s /Applications "$STAGING/Applications"
DMG="dist/Octo-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Octo $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

echo
echo "Done: $ROOT/$DMG"
echo "Next: on GitHub, draft a new release with tag v$VERSION and attach that file."
