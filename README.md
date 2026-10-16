# Canvas

**Canvas** is a floating panel for macOS that renders Markdown or TSX from the command line. Agents and scripts run `canvas show plan.md` or `canvas show dash.tsx` and get a laid-out page beside whatever app has focus, without opening a browser or an editor. With `--wait`, the panel sends a button click or form input back as JSON, so a script can ask a question and act on the answer. Panels can also follow live data: a script publishes to a channel, and every panel subscribed to it re-renders.

This README covers installing, the commands you'll use most, the TSX component kit and troubleshooting. Every flag, the wire protocol and the page API are in `docs/protocol.md`. Placement (corners, screens, stacks, remembered frames) is in `docs/positioning.md`.

## Install

```sh
./scripts/install.sh
```

The script builds the web renderer, the Swift server and the C CLI, then assembles `~/Applications/Canvas.app` (signed ad hoc) and runs the app's `Contents/Resources/setup.sh`, which links the CLI at `~/.local/bin/canvas` and loads a LaunchAgent, `~/Library/LaunchAgents/dev.kristian.canvas.plist`. launchd listens on the socket and starts the server at login and on the first connection, so the first `canvas` call finds a running server with a native page ready. Rerun the script to upgrade. It stops the running server first. To remove Canvas, run `~/Applications/Canvas.app/Contents/Resources/setup.sh --uninstall`, then delete the app.

## Show a page

`canvas show` returns once the page has rendered. A TSX file that fails to compile or render exits 1 with the message on stderr, so an agent learns right away whether its component works.

```sh
canvas show examples/hello.md
canvas show examples/dashboard.tsx --theme light
echo '# Hi' | canvas show -                     # stdin, add --kind tsx for TSX
canvas show examples/keys.tsx --data examples/keys.json --width 880
```

A shown file reloads live when it changes. Each panel has an id (`default` unless you pass `--id`), and showing an id that's already open replaces its content in place. `--data` takes inline JSON, a file path or `-` for stdin, and the component receives it as `props.data`.

Change an open panel's data without re-sending the source:

```sh
canvas update --id dash --data '{"uptime": 99.95}'
```

Or keep a pipe open and send one JSON object per line. Each line replaces `data` without remounting the component, so its state survives:

```sh
./metrics.sh | canvas show dash.tsx --id dash --stream
```

## Ask a question

With `--wait`, `show` blocks until the user acts. A result prints as JSON on stdout and exits 0. Closing the panel (Esc or ×) exits 2, and `--timeout SECONDS` exits 3.

```sh
canvas show plan.md --wait --buttons "Approve,Reject"   # prints "Approve"
canvas show examples/approve.tsx --wait                 # prints {"decision":"approve","comment":""}
```

The first `--buttons` label is the primary button. Cmd+Enter presses it. `--wait` focuses the panel so the keyboard works at once. A plain `show` leaves focus where it was.

## Toggle, move and hide

`toggle` takes the same options as `show`. It hides the panel when that id is visible and shows it otherwise, which suits a hotkey:

```sh
canvas toggle examples/keys.tsx --id keys --data examples/keys.json --width 880
canvas hide --id keys
canvas hide --all
canvas list                                    # one JSON object per visible panel
```

## Placement

Panels open centered on the display under the mouse at 720 pt wide, and their height follows the content. The placement options change that. All values are in points, and most also take a percentage of the screen.

```sh
canvas show note.md --position top-right --width 360
canvas show examples/approve.tsx --position mouse --width 420 --wait
canvas show examples/dashboard.tsx --screen 2 --position right --margin 0 --width 50% --height 100%
canvas show status.md --at -24,-24              # bottom-right corner, 24 pt in
```

A HUD that stays up on every Space and lets clicks pass through:

```sh
canvas show cpu.tsx --id cpu --screen main --position top-right --width 320 --pin --click-through --opacity 0.85
canvas move --id cpu --position bottom-right
```

A pinned panel ignores Esc and passes it to the page. Close it with its × or `canvas hide --id cpu`. Panels in the same `--stack` group line up in their corner, 12 pt apart, like notifications:

```sh
echo '**Build finished**' | canvas show - --id note-1 --stack notes --position top-right --width 360
echo '**Tests passed**' | canvas show - --id note-2 --stack notes --position top-right --width 360
```

When you drag or resize a panel, Canvas remembers its frame under its id. A later `show` without `--position` or `--at` puts it back there. `--forget` clears it.

## Live data with channels

A channel is a named stream of JSON values that the server keeps, with a short history. Scripts publish with `canvas pub`, pages listen with the `useChannel` and `useSeries` hooks, and anything can read with `canvas sub`.

```sh
canvas show examples/live.tsx --data '{"channel":"demo.load","label":"Load"}'
canvas pub demo.load 42
while true; do canvas pub demo.load $((RANDOM % 100)); sleep 0.5; done
canvas pub demo.load --every 1s -- sh -c 'echo $((RANDOM % 100))'
canvas sub demo.load.mark                       # what the page's Mark button publishes
```

`--merge` applies the value as a JSON merge patch to the current one, and `--keep N` sets how many values the channel keeps (120 by default).

Channels under `canvas.sys.*` come from a native sampler: CPU per core, memory, network, disk, the top processes, battery and thermal state. It runs only while a page or a `canvas sub` is listening, at the fastest rate any page asked for (1 s by default). `examples/top.tsx` is a btop-style monitor built on them. Clicking a process publishes it on `top.select`:

```sh
canvas show examples/top.tsx --id top --width 820
canvas sub top.select
```

## Write a TSX page

A `.tsx` file default-exports a component that gets `{data}` as props. It can import from `react` and `canvas` only.

```tsx
import { Card, Stat, Button, useChannel } from 'canvas'

export default function Uptime({ data }) {
  const cpu = useChannel<{ total: number }>('canvas.sys.cpu')
  return (
    <Card title="API">
      <Stat label="Uptime" value={`${data.uptime}%`} />
      <Stat label="CPU" value={`${Math.round((cpu?.total ?? 0) * 100)}%`} />
      <Button value="ack">Acknowledge</Button>
    </Card>
  )
}
```

The `canvas` module has:

- **Hooks:** `useCanvas()` (`submit`, `close`, `publish`, `data`, `wait`), `useChannel`, `useSeries` and `publish`.
- **Layout:** `Stack`, `Row`, `Grid`, `Divider`, `Spacer`.
- **Text:** `Heading`, `Text`, `Code`, `CodeBlock`, `Markdown`, `Kbd`.
- **Data:** `Card`, `Table`, `Stat`, `Badge`, `Progress`, `BarChart`, `Sparkline`.
- **Input:** `Button`, `Input`, `TextArea`, `Select`, `Checkbox`, `Form`. `Form` submits its named fields as one object.

`color` props take a semantic name (`accent`, `success`, `warning`, `danger`, `info`, `muted`), an Apple system hue (`red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink`, `gray`) or any CSS color. The accent is the macOS accent color unless you pass `--accent COLOR`. Types are in `web/canvas.d.ts`.

### Native and WebKit rendering

A page built only from the kit renders natively: React runs in a JavaScriptCore context inside the server, and SwiftUI draws the kit. No WebKit process starts. A page that uses DOM tags such as `<div>`, `className` or CSS falls back to a WebKit page, which takes longer to open and uses about 75 MB more memory while it's open. `canvas list` shows each panel's `renderer` (`native` or `web`). `docs/native.md` lists what renders natively.

## Call it from a hotkey

On a Mac with endpoint security software, every launch of a non-Apple binary, the `canvas` CLI included, can cost tens of milliseconds. For a hotkey, build the request once with `--emit` and send the saved line with Apple's `nc`, which takes about 2 ms:

```sh
mkdir -p ~/.config/canvas
canvas toggle examples/keys.tsx --id keys --data examples/keys.json --emit > ~/.config/canvas/keys.json
/usr/bin/nc -U "$HOME/Library/Application Support/Canvas/canvas.sock" < ~/.config/canvas/keys.json
```

`nc` prints the server's event lines, and its exit status doesn't reflect them. From a zsh that's already running, `canvas-send` in `cli/canvas-send.zsh` sends the same file with zsh's socket builtins and returns the CLI's exit codes:

```sh
source /path/to/canvas/cli/canvas-send.zsh
canvas-send ~/.config/canvas/keys.json
```

Note: the saved request carries the source and data as they were when you ran `--emit`. Run it again after changing either. `--emit` works on every command except `sub`, `pub -` and `pub --every`, and can't carry `--stream` or `--timeout`.

## Troubleshooting

Check that the server answers, and what launchd thinks of the agent:

```sh
canvas ping && echo up
launchctl print gui/$(id -u)/dev.kristian.canvas
```

`canvas show FILE --trace` prints one JSON line on stderr with the total time and each stage, from the server accepting the connection through render and paint to the reply, in milliseconds.

The server started by launchd doesn't write a log. To see its debug output, stop the agent and run the server in a terminal:

```sh
launchctl bootout gui/$(id -u)/dev.kristian.canvas
CANVAS_DEBUG=1 ~/Applications/Canvas.app/Contents/MacOS/canvas-server serve
```

Press Ctrl-C when you're done, then load the agent again:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.kristian.canvas.plist
```

**Error:** `canvas: the canvas server is not running (CANVAS_NO_AUTOSTART=1)`

**Cause:** `CANVAS_NO_AUTOSTART=1` is set, and nothing listens on the socket.

**Solution:** unset the variable, or load the agent with `launchctl bootstrap`.

## Develop

```sh
cd web && bun install && bun run build && bun run typecheck
bun run dev                                     # renderer harness at http://localhost:5178
swift build && cli/build.sh                     # .build/debug/canvas-server, .build/cli/canvas
CANVAS_HOME=$(mktemp -d) .build/cli/canvas show examples/hello.md
./scripts/test.sh                               # unit, bridge, CLI and bun tests, no windows
./scripts/test.sh --ui                          # on-screen tests: panels will appear
./scripts/lint.sh                               # SwiftLint, Oxlint, clang-tidy, typecheck
```

`CANVAS_HOME` points the CLI and server at a separate socket and state directory, so a dev build doesn't talk to the installed server. With no server on that socket, the dev CLI starts `.build/debug/canvas-server` itself. Set `CANVAS_SERVER` to use a different server binary. A dev server finds `web/dist` by walking up from its binary, and `CANVAS_WEB_DIR` overrides that. `~/.config/canvas/config.toml` sets the WebKit page policy (`warm = "linger" | "always" | "idle" | "never"`, default `"linger"`, which starts no page up front and keeps a closed web panel's page for `linger_seconds = 120`; `idle_minutes = 10` for `"idle"`), and `CANVAS_CONFIG` points at a different file.

`scripts/lint.sh` needs SwiftLint (`brew install swiftlint`) and installs Homebrew's llvm for clang-tidy if it's missing. Without Xcode it points SwiftLint at the Command Line Tools' sourcekitd through `TOOLCHAIN_DIR`.
