#!/usr/bin/env bash
# Builds Canvas.app at OUT (default .build/Canvas.app) and signs it with the
# hardened runtime.
#
#   scripts/bundle.sh [OUT]
#
# CANVAS_SIGN_IDENTITY names a "Developer ID Application: ..." identity for
# a build other Macs will open. Unset, it signs ad hoc, which only this Mac
# trusts.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/.build/Canvas.app}"
identity="${CANVAS_SIGN_IDENTITY:--}"
label="dev.kristian.canvas"

(cd "$root/web" && bun run build)
cd "$root"
swift build -c release --product canvas-server
server="$(swift build -c release --show-bin-path)/canvas-server"
cli="$("$root/cli/build.sh")"

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
cp "$server" "$out/Contents/MacOS/canvas-server"
cp "$cli" "$out/Contents/MacOS/canvas"
cp -R "$root/web/dist" "$out/Contents/Resources/web"
cp "$root/scripts/setup.sh" "$out/Contents/Resources/setup.sh"

version="$(tr -d '[:space:]' < "$root/VERSION")"
build="$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)"
cat > "$out/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Canvas</string>
  <key>CFBundleDisplayName</key><string>Canvas</string>
  <key>CFBundleExecutable</key><string>canvas-server</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad hoc signatures can't carry a secure timestamp; notarization needs one.
sign=(codesign --force --options runtime --entitlements "$root/scripts/Canvas.entitlements" -s "$identity")
if [[ "$identity" != "-" ]]; then sign+=(--timestamp); fi
"${sign[@]}" "$out/Contents/MacOS/canvas"
"${sign[@]}" "$out"
codesign --verify --strict "$out"
echo "$out"
