#!/bin/bash
# Publishes a release: stamps the version, builds the universal app, tags the
# commit and uploads the archive.
#
# A published version is never rewritten. Every build that reaches anyone gets
# a number of its own, so a report of "it happens on 0.2.1" always means one
# exact binary.
#
#   ./scripts/release.sh 0.2.0 [notes-file]
#
set -euo pipefail

version=${1:-}
notes=${2:-}

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: $0 <major.minor.patch> [notes-file]" >&2
	exit 2
fi

if git rev-parse "v$version" >/dev/null 2>&1; then
	echo "v$version already exists; pick the next number" >&2
	exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
	echo "commit or stash your changes first" >&2
	exit 1
fi

plist=Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$plist"

swift test
make release

git add "$plist"
git commit -m "build: release $version"
git tag -a "v$version" -m "EVE-APM Mac $version"
git push
git push origin "v$version"

archive="build/EVE-APM-Mac-$version-universal.zip"
if [[ -n $notes ]]; then
	gh release create "v$version" "$archive#EVE-APM Mac $version (universal)" \
		--title "EVE-APM Mac $version" --notes-file "$notes"
else
	gh release create "v$version" "$archive#EVE-APM Mac $version (universal)" \
		--title "EVE-APM Mac $version" --generate-notes
fi

echo
echo "published v$version"
shasum -a 256 "$archive"
