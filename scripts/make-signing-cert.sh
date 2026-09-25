#!/bin/sh
# Creates a local, self-signed "MyNotch Local Signing" code-signing certificate in your login
# keychain. Signing every build with the same certificate lets macOS remember the privacy
# permissions you grant MyNotch (Downloads, Calendar, Camera) across rebuilds.
# The certificate can only sign code, and only /usr/bin/codesign may use its private key.
set -e

NAME="MyNotch Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists. Nothing to do."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > cert.cnf <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" -passout "pass:$PASS" -out cert.p12 2>/dev/null
security import cert.p12 -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo
echo "Created \"$NAME\". (Temporary files, including the private key file, have been deleted;"
echo "the key now lives only in your login keychain.)"
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
