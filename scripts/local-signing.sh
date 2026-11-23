#!/usr/bin/env bash
# Creates (once) a self-signed "Notchling Local Signing" identity in its own keychain
# and prints the keychain path.
#
# Why: ad-hoc signatures identify the app by its build hash, so every rebuild looks like
# a new app to macOS and it asks again for Calendar, Reminders, Microphone, etc.
# A stable certificate gives a stable identity, so permissions are remembered.
set -euo pipefail

NAME="Notchling Local Signing"
KC="$HOME/Library/Keychains/notchling-signing.keychain-db"
PASS="notchling-local" # protects only this throwaway signing key

if [[ ! -f "$KC" ]]; then
  TMP="$(mktemp -d)"
  cat > "$TMP/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.conf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
  openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS" >/dev/null
  security create-keychain -p "$PASS" "$KC"
  security set-keychain-settings "$KC" # no auto-lock
  security import "$TMP/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
  rm -rf "$TMP"
fi
security unlock-keychain -p "$PASS" "$KC"
echo "$KC"
