#!/bin/bash
# Creates a self-signed code signing identity in the login keychain.
#
# Why: macOS ties Screen Recording and Accessibility grants to the signature of
# the app that asked for them. An ad-hoc signature changes on every build, so
# every rebuild loses both grants. Signing with one stable certificate keeps
# them. The certificate is local, self-signed and only good for signing code on
# this machine.
set -euo pipefail

NAME="EVE-APM Mac Dev"

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
	echo "identity \"$NAME\" already exists"
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout "$work/key.pem" -out "$work/cert.pem" \
	-subj "/CN=$NAME" \
	-addext "basicConstraints=critical,CA:false" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# The keychain reads only the older PKCS#12 algorithms, and refuses a bundle
# with an empty password, so both are spelled out here.
openssl pkcs12 -export -name "$NAME" \
	-inkey "$work/key.pem" -in "$work/cert.pem" \
	-out "$work/identity.p12" -passout pass:eveapm \
	-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

# -A lets codesign use the key without a keychain prompt on every build.
security import "$work/identity.p12" \
	-k "$HOME/Library/Keychains/login.keychain-db" -P eveapm -A

echo "created identity \"$NAME\""
echo "build with: make"
