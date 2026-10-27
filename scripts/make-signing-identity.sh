#!/bin/zsh
# Creates Octo's signing certificate (once per Mac). Run from anywhere: scripts/make-signing-identity.sh
#
# Why: macOS remembers permissions (Accessibility, Screen Recording) per signature. Signing every
# build with the same certificate means people keep those permissions when they update Octo.
# The certificate is self-signed (free). A paid Apple Developer ID can replace it later; then
# macOS also stops warning about an unidentified developer.
#
# Everything lives in ~/.octo-signing, outside the repository (never commit it).
# Back up that folder: if it's lost, a new certificate works too, but everyone who updates
# has to turn Octo's permissions on again once.
set -euo pipefail

DIR="$HOME/.octo-signing"
KEYCHAIN="$DIR/octo-signing.keychain-db"
NAME="Octo Self-Signed"

if [[ -f "$KEYCHAIN" ]]; then
  echo "Already set up: $KEYCHAIN"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
cd "$DIR"

# Random passwords for the keychain and the backup file (not your Mac password).
/usr/bin/openssl rand -hex 24 > keychain-password
/usr/bin/openssl rand -hex 24 > backup-password
chmod 600 keychain-password backup-password

cat > cert.conf <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
O = Octo
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# A 20-year certificate: it only has to stay the same, not expire.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -config cert.conf -keyout key.pem -out cert.pem 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" \
  -out octo-signing.p12 -passout "pass:$(cat backup-password)"
rm key.pem cert.conf
chmod 600 octo-signing.p12

# A keychain of its own, so your login keychain stays untouched and signing never asks for a password.
security create-keychain -p "$(cat keychain-password)" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN" # no auto-lock
security unlock-keychain -p "$(cat keychain-password)" "$KEYCHAIN"
security import octo-signing.p12 -k "$KEYCHAIN" -P "$(cat backup-password)" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat keychain-password)" "$KEYCHAIN" >/dev/null

echo "Created \"$NAME\" in $DIR"
echo "Back up that folder (octo-signing.p12 + backup-password) somewhere private."
