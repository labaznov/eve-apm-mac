#!/bin/bash
# Creates the self-signed code signing identity this project signs with, in the
# login keychain.
#
# Why: macOS ties Screen Recording and Accessibility grants to a code
# requirement, and for an ad-hoc signature that requirement names the hash of the
# binary — which changes on every build, so every rebuild and every update loses
# both grants. Signed with a certificate, the requirement names the certificate
# instead and holds across builds:
#
#   ad-hoc:      cdhash H"767079dd…" or cdhash H"a7b88c81…"      (new each build)
#   certificate: identifier "…" and certificate leaf = H"2f2d…"  (stable)
#
# The same identity signs local builds and published releases, so a downloaded
# update is the same app to macOS and keeps the permissions already given. The
# certificate is local and self-signed: it makes the signature stable, not
# trusted, so a downloaded build still needs Gatekeeper's permission once.
#
# The name is kept as it was so the grants already given still match.
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

# -A puts every application on the key's access list. The keychain still asks
# once for authorisation, which "Always Allow" settles for good.
security import "$work/identity.p12" \
	-k "$HOME/Library/Keychains/login.keychain-db" -P eveapm -A

echo "created identity \"$NAME\""
echo
echo "The first build asks for the login keychain password, because codesign"
echo "has to reach the new private key. Answer it with \"Always Allow\" and it"
echo "will not ask again."
echo
echo "build with: make        release with: ./scripts/release.sh <version>"
