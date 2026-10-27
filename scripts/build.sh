#!/bin/zsh
# Builds build/Octo.app. Run from anywhere: scripts/build.sh
#   --universal   also include Intel Macs (used for releases; takes about twice as long)
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

UNIVERSAL=false
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=true

# Compiler files live outside the project (and any synced folder): they are large and can always be rebuilt.
CACHE="$HOME/Library/Caches/Octo/build"

[[ -f Resources/AppIcon.icns ]] || scripts/make-icon.sh

build() { # build <triple>: prints the path of the built executable
  swift build -c release --product Octo --scratch-path "$CACHE" --triple "$1" >&2
  echo "$(swift build -c release --product Octo --scratch-path "$CACHE" --triple "$1" --show-bin-path)/Octo"
}

APP="$ROOT/build/Octo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if $UNIVERSAL; then
  lipo -create -output "$APP/Contents/MacOS/Octo" \
    "$(build arm64-apple-macosx14.0)" "$(build x86_64-apple-macosx14.0)"
else
  cp "$(build arm64-apple-macosx14.0)" "$APP/Contents/MacOS/Octo"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with Octo's own certificate (see scripts/make-signing-identity.sh), so macOS keeps the
# Accessibility and Screen Recording permissions when Octo is updated. Without it, fall back to
# an ad-hoc signature: it works, but permissions must be turned on again after each update.
SIGNING="$HOME/.octo-signing"
KEYCHAIN="$SIGNING/octo-signing.keychain-db"
if [[ -f "$KEYCHAIN" ]]; then
  # codesign only finds certificates in the keychain search list, so add Octo's keychain for
  # the moment of signing and put the list back exactly as it was afterwards.
  ORIGINAL=("${(@f)$(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')}")
  trap 'security list-keychains -d user -s "${ORIGINAL[@]}"' EXIT
  security list-keychains -d user -s "${ORIGINAL[@]}" "$KEYCHAIN"
  security unlock-keychain -p "$(cat "$SIGNING/keychain-password")" "$KEYCHAIN"
  codesign --force --timestamp=none --sign "Octo Self-Signed" "$APP"
else
  echo "warning: no signing certificate (run scripts/make-signing-identity.sh); signing ad-hoc" >&2
  codesign --force --sign - "$APP"
fi

echo "Built $APP"
