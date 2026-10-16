#!/usr/bin/env bash
# Registers the Canvas.app this script is in: links the `canvas` CLI and
# loads the LaunchAgent that starts the server at login and on first use.
# Run it again after moving or updating the app.
#
#   Canvas.app/Contents/Resources/setup.sh              register
#   Canvas.app/Contents/Resources/setup.sh --stop       stop servers only
#   Canvas.app/Contents/Resources/setup.sh --uninstall  stop and unregister
#
# CANVAS_BIN sets where the CLI is linked (default ~/.local/bin).
set -euo pipefail

app="$(cd "$(dirname "$0")/../.." && pwd)"
bin="${CANVAS_BIN:-$HOME/.local/bin}"
label="dev.kristian.canvas"
agent="$HOME/Library/LaunchAgents/$label.plist"
home="$HOME/Library/Application Support/Canvas"
socket="$home/canvas.sock"
domain="gui/$(id -u)"

# The agent first, so launchd doesn't relaunch what we stop next. Then any
# other server for the default home: whoever holds the lock, or a
# canvas-server started by hand.
stop() {
  launchctl bootout "$domain/$label" 2>/dev/null || true
  local pids
  pids="$( { lsof -t "$home/server.lock" 2>/dev/null || true; pgrep -x canvas-server || true; } | sort -u)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    for _ in $(seq 50); do
      # shellcheck disable=SC2086
      kill -0 $pids 2>/dev/null || break
      sleep 0.1
    done
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
  rm -f "$socket"
}

case "${1:-}" in
  --stop)
    stop
    exit 0
    ;;
  --uninstall)
    stop
    rm -f "$agent"
    [[ "$(readlink "$bin/canvas" 2>/dev/null)" == "$app/Contents/MacOS/canvas" ]] && rm -f "$bin/canvas"
    echo "Unregistered $app. Delete the app and $home to remove everything."
    exit 0
    ;;
  "") ;;
  *)
    echo "usage: setup.sh [--stop | --uninstall]" >&2
    exit 64
    ;;
esac

stop
mkdir -p "$bin"
ln -sfn "$app/Contents/MacOS/canvas" "$bin/canvas"

# Socket activation: launchd listens on the socket and starts the server on
# the first connection, and RunAtLoad starts it at login. No KeepAlive: a
# server that exits stays down until the next connection. ThrottleInterval 1,
# since launchd's default 10 s would stall the first call after a quick exit.
mkdir -p "$(dirname "$agent")" "$home"
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$app/Contents/MacOS/canvas-server</string>
  </array>
  <key>Sockets</key>
  <dict>
    <key>canvas</key>
    <dict>
      <key>SockPathName</key><string>$socket</string>
      <key>SockPathMode</key><integer>384</integer>
    </dict>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>ThrottleInterval</key><integer>1</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF
plutil -lint "$agent" >/dev/null
launchctl bootstrap "$domain" "$agent"

echo "Registered $app"
echo "CLI: $bin/canvas"
case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "Add $bin to your PATH to run canvas." ;;
esac
