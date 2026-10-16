#!/usr/bin/env bash
# Builds Canvas from this checkout, installs it to ~/Applications/Canvas.app
# and registers it (scripts/setup.sh): the CLI at ~/.local/bin/canvas and a
# LaunchAgent that starts the server at login and on first use.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$HOME/Applications/Canvas.app"
staged="$root/.build/Canvas.app"

# Build everything before touching the running install.
"$root/scripts/bundle.sh" "$staged" >/dev/null
"$staged/Contents/Resources/setup.sh" --stop

rm -rf "$app"
mkdir -p "$(dirname "$app")"
ditto "$staged" "$app"
"$app/Contents/Resources/setup.sh"
echo "Installed $app"
