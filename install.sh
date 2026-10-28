#!/bin/zsh
# Installs Octo, or updates it, from the latest release on GitHub. Paste this into Terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/tom-bonte/Octo/main/install.sh | zsh
#
# It downloads the disk image, checks that the app inside is signed with Octo's own certificate,
# copies it into Applications (replacing an older Octo) and opens it. Files downloaded with curl
# aren't marked as coming from the internet, so macOS doesn't ask you to allow Octo in
# Privacy & Security. Your settings and permissions stay as they are.
#
# Everything is inside main(), so nothing runs unless the whole script has downloaded.

main() {
  set -euo pipefail
  local repo="tom-bonte/Octo"
  # Octo's signing certificate (scripts/make-signing-identity.sh); a build signed with any other
  # certificate isn't installed.
  local certificate="72c673e326bc5bc98109f9a235a9f18e1e242ae0"
  local destination="/Applications/Octo.app"

  fail() { print -u2 "\n$1"; exit 1; }

  [[ "$(uname)" == Darwin ]] || fail "Octo is a Mac app."
  (( ${$(sw_vers -productVersion)%%.*} >= 14 )) || fail "Octo needs macOS 14 Sonoma or later."
  [[ -w /Applications ]] || fail "Your account can't add apps to Applications. Ask an administrator, or use the download on GitHub."

  # The latest release's page address ends in its tag, like …/releases/tag/v1.1.1.
  local url version
  if [[ -n "${OCTO_DMG_URL:-}" ]]; then
    url="$OCTO_DMG_URL" # for testing a build before it's released
  else
    local latest
    latest="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")" ||
      fail "Couldn't reach GitHub. Check your internet connection and try again."
    version="${latest##*/v}"
    [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "Couldn't find Octo's latest release."
    url="https://github.com/$repo/releases/download/v$version/Octo-$version.dmg"
  fi

  local work
  work="$(mktemp -d)"
  trap "hdiutil detach -quiet -force '$work/disk' 2>/dev/null; rm -rf '$work'" EXIT

  print "Downloading Octo${version:+ $version}…"
  curl -fL --progress-bar -o "$work/Octo.dmg" "$url" </dev/null || fail "The download didn't work. Try again in a moment."

  mkdir "$work/disk"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$work/disk" "$work/Octo.dmg" </dev/null ||
    fail "Couldn't open the downloaded disk image."
  local app="$work/disk/Octo.app" requirement=""
  codesign --verify --strict "$app" 2>/dev/null && requirement="$(codesign --display --requirements - "$app" 2>&1)"
  [[ "$requirement" == *"$certificate"* ]] || fail "The download isn't signed with Octo's certificate, so it wasn't installed."

  if pgrep -x Octo >/dev/null; then
    print "Closing the Octo that's running…"
    pkill -x Octo || true
    local tries=0
    while pgrep -x Octo >/dev/null && (( tries++ < 20 )); do sleep 0.25; done
  fi

  print "Installing into Applications…"
  rm -rf "$destination"
  ditto "$app" "$destination"
  open "$destination"
  print "\nDone. Octo is in your menu bar (the octopus). Run the same line again any time to update."
}

main "$@"
