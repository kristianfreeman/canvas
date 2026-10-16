#!/usr/bin/env bash
# Builds a Developer ID signed, notarized and stapled Canvas.app and zips it
# into dist/Canvas-VERSION.zip for download.
#
#   CANVAS_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   CANVAS_NOTARY_PROFILE=canvas scripts/release.sh
#
# The profile is stored once with
#   xcrun notarytool store-credentials canvas --apple-id ID --team-id TEAMID
# and its secret stays in the login keychain.
set -euo pipefail

: "${CANVAS_SIGN_IDENTITY:?set CANVAS_SIGN_IDENTITY to a Developer ID Application identity}"
: "${CANVAS_NOTARY_PROFILE:?set CANVAS_NOTARY_PROFILE to a notarytool keychain profile}"

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
dist="$root/dist"
app="$dist/Canvas.app"
zip="$dist/Canvas-$version.zip"

rm -rf "$dist"
mkdir -p "$dist"
"$root/scripts/bundle.sh" "$app" >/dev/null

ditto -c -k --keepParent "$app" "$dist/notarize.zip"
xcrun notarytool submit "$dist/notarize.zip" --keychain-profile "$CANVAS_NOTARY_PROFILE" --wait
rm "$dist/notarize.zip"
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"

ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip"
