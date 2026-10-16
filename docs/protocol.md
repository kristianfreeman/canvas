# Canvas protocol (v2)

This is the contract between the three parts of Canvas:

- **`canvas`**: the CLI, a small C binary in `cli/`.
- **`canvas-server`**: the Swift app in `Sources/`. It owns the panels, the
  channels and the system sampler.
- **The page**: the renderer in `web/`, loaded into each panel's
  `WKWebView`.

Anything not written here is an implementation detail.

## Rendering

Most panels render natively: React runs in an in-process JavaScriptCore
context and the kit draws with SwiftUI, with no WebKit process. Markdown and
TSX go native first. TSX that uses raw DOM tags, `className` or styles the
native kit can't express falls back to the page, at the first render or
after a later `update`, event or channel push, and the panel switches
renderer in place. The server remembers content that fell back (by path, or
by source for stdin) and sends its next show straight to the page, until the
source changes. `docs/native.md` is the contract for the native renderer;
the page API below is the WebKit one.

## Processes and files

- **App bundle:** `~/Applications/Canvas.app`.
  - `Contents/MacOS/canvas-server` is the server and the bundle executable.
  - `Contents/MacOS/canvas` is the CLI. `~/.local/bin/canvas` links to it.
  - `Contents/Resources/web/` holds the renderer.
- **Home directory:** `CANVAS_HOME`, by default
  `~/Library/Application Support/Canvas`. It holds `canvas.sock` (mode
  0600), `server.lock` and `frames.json`. With `CANVAS_DEBUG=1` the server
  logs to stderr; a dev server autostarted by the CLI sends that to
  `server.log` here. Tests point `CANVAS_HOME` at a temp directory.
- **Config:** `~/.config/canvas/config.toml`, optional. The parser reads flat
  `key = value` lines.
  - `warm = "linger" | "always" | "idle" | "never"`, default `"linger"`.
    It sets when the server keeps a WebKit page for the fallback renderer;
    native panels need none. `"linger"` loads a page when a panel first
    needs one, keeps a closed web panel's page, and drops it
    `linger_seconds` after the last web panel closes. `"always"` keeps one
    page loaded from launch. `"idle"` does too, but drops it `idle_minutes`
    after the last web panel closes. `"never"` loads a page per web panel
    and closes it with the panel. Under memory pressure the server drops
    the parked page whatever the setting.
  - `linger_seconds = 120`, used by `"linger"`.
  - `idle_minutes = 10`, used by `"idle"`.
- **Server start:**
  - **LaunchAgent:** `~/Library/LaunchAgents/dev.kristian.canvas.plist` starts
    the server at login. launchd owns the socket and launches the server
    when it's first used (socket activation, socket name `canvas`).
  - **Started by hand:** `canvas-server serve` binds the socket itself.
  - **No server running:** if connecting fails, the CLI runs `open -g` on the
    bundle that contains it, or spawns `canvas-server serve` in a dev build.
    Then it retries for up to 5 s. `ping`, `list`, `hide`, `sub` and `move`
    never start the server.

## CLI

```
canvas show [FILE | -] [options]           render, return once rendered
canvas toggle [FILE | -] [options]         hide if --id is visible, else show
canvas update --id ID (--data D | --stream)  replace an open canvas's data
canvas move --id ID [placement options]    reposition an open canvas
canvas hide [--id ID | --all]
canvas list                                one JSON object per visible panel
canvas pub CHANNEL [VALUE | -] [--merge] [--keep N] [--every DUR -- CMD ARGS...]
canvas sub CHANNEL... [--history]          NDJSON on stdout until killed
canvas ping                                exit 0 if the server is up
canvas help
```

### Content options (`show` and `toggle`)

| Option | Meaning |
|---|---|
| `FILE` / `-` | A file, watched and re-rendered when it changes. `-` (or a non-TTY stdin with no FILE) reads the source from stdin. |
| `--id ID` | Panel id. Defaults to `default`. Showing an existing id replaces its content in place. |
| `--kind md\|markdown\|tsx\|jsx` | `.tsx`, `.jsx` and `.ts` files are TSX. Stdin is sniffed for `export default`. |
| `--title T` | Defaults to the file name. |
| `--data FILE\|-\|JSON` | Props data. An argument that starts with `{`, `[`, `"`, `-` or a digit, or is `true`, `false` or `null`, is parsed as JSON (a lone `-` means stdin). Anything else is a file path. |
| `--stream` | After rendering, read NDJSON from stdin. Each line replaces `data`, without remounting the component. Exits 0 on EOF and 2 if the panel closes. Needs FILE, since stdin is taken. |
| `--theme auto\|dark\|light` | Defaults to `auto`, which follows the system. |
| `--accent COLOR` | Any CSS color. Defaults to the macOS accent color. |
| `--wait` | Block until the user acts. See the exit codes below. |
| `--buttons "A,B"` | Footer buttons. The first is primary. The result value is the label. |
| `--focus` / `--no-focus` | Defaults to on for `--wait` and `toggle`, off otherwise. |
| `--timeout SECONDS` | With `--wait`, hide the panel and exit 3 when it runs out. |
| `--trace` | Print stage timings to stderr as one JSON line. |

### Placement options (`show`, `toggle` and `move`)

All values are in points.

| Option | Meaning |
|---|---|
| `--position P` | `center` (default), `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, or `mouse`, which places the panel by the cursor and flips it to stay on screen. |
| `--at X,Y` | Absolute position in the screen's visible frame, measured from its top-left corner. A non-negative X sets the left edge and a negative X sets the right edge, so `-24` means 24 pt from the right. Y works the same way for the top and bottom edges. Either value can be a percentage of the visible size, like `50%` or `-10%`. Overrides `--position`. |
| `--screen S` | `mouse` (default), `main` (the screen with the menu bar), `focused` (the screen with the frontmost app's window), `N` (1-based index), or `NAME` (a case-insensitive substring of the display name). |
| `--margin N` | Gap between the panel and the screen edges for presets. Defaults to 24. `top` and `bottom` keep their 64 pt and 24 pt defaults unless `--margin` is given. |
| `--width N\|N%` | Defaults to 720. |
| `--height N\|N%` | A fixed height. Without it, the height follows the content. |
| `--min-height N\|N%`, `--max-height N\|N%` | Bounds on the content-driven height. `--max-height` defaults to 85%. |
| `--resizable` / `--no-resizable` | Whether the user can drag the edges. Defaults to resizable. |
| `--level normal\|floating\|top` | Window level. Defaults to `floating`. `top` sits above full-screen apps and the menu bar. |
| `--spaces all\|current` | Defaults to `all`. |
| `--pin` | Floating level on all Spaces, and Esc doesn't close it. Close it with × or `canvas hide`. |
| `--click-through` | The panel ignores the mouse entirely, for HUD overlays. Use it with `--pin`. |
| `--opacity F` | 0.0 to 1.0. Defaults to 1. |
| `--stack GROUP` | Panels in the same group stack in their corner, 12 pt apart, growing away from the anchor edge. They reflow when one closes. |
| `--forget` | Ignore and clear this id's remembered frame. On an open panel (`show` or `move`), it also places the panel again from its options. |

- **Growth anchor:** when the content height changes, the anchored edge stays
  put.
  - `top`, `top-left` and `top-right` keep their top edge. With `--at`, a
    non-negative Y also keeps the top edge.
  - `bottom`, `bottom-left` and `bottom-right` grow upward. With `--at`, a
    negative Y also grows upward.
  - `center`, `left` and `right` stay vertically centered.
  - `mouse` keeps the edge nearest the cursor.
- **Remembered frames:** when the user drags or resizes a panel, its origin
  and width are saved under its id and the current display arrangement. A
  later `show` or `toggle` for that id that has no `--position` or `--at`
  restores them. The saved width doesn't override an explicit `--width`.
- **Resting panels:** when a native panel closes (Esc, ×, `hide` or a
  `toggle`), it waits hidden, fully drawn, instead of being torn down. A
  later `show` or `toggle` for that id that would draw the same thing shows
  it again without rendering, in about as long as a hide takes. "The same
  thing" means equal source, path, kind, title, data, buttons, accent, theme
  and placement options; `--focus` and `--trace` may differ. Anything else
  renders a new panel. Panels opened with `--wait` or `--stream`, panels
  subscribed to a channel, panels with a `setTimeout` or `setInterval`
  pending and WebKit panels don't rest, so nothing runs while a panel is
  hidden. At most 3 panels rest at once, the longest resting goes first, and
  memory pressure drops them all. A resting panel isn't open: `list`,
  `update` and `move` don't see it.

### Channel commands

- **`canvas pub CHANNEL VALUE`:** publish one JSON value. VALUE follows the
  same JSON-or-file rule as `--data`.
  - `--merge` applies VALUE as an RFC 7386 merge patch to the current value.
  - `--keep N` sets the channel's history capacity. It defaults to 120 for new
    channels, and 0 turns history off.
- **`canvas pub CHANNEL -`:** each line on stdin is one message. One
  connection carries the whole stream, and the command exits 0 on EOF.
- **`canvas pub CHANNEL --every DUR -- CMD ARGS...`:** run CMD every DUR (for
  example `500ms`, `1s` or `2.5m`) in the CLI process, and publish each run's
  stdout parsed as JSON. Runs that fail or produce invalid JSON print a
  warning to stderr and are skipped. Ctrl-C exits 0.
- **`canvas sub CHANNEL...`:** prints one line per message. With one channel
  each line is the bare JSON value, so it pipes straight into `jq` or
  `xargs`. With several channels each line is `{"channel","value"}`.
  - `--history` first prints the buffered history, oldest first, then the
    live messages.
- **Channel names:** dot-separated `[a-z0-9_-]` segments.
  - Names starting with `canvas.` are reserved. `canvas.sys.*` comes from the
    native sampler, and the CLI can't publish to it.
  - A page may publish to any channel that isn't reserved, for example
    `top.select`.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success: rendered, a `--wait` result printed, `hidden`, `ok`, EOF on a stream. |
| 1 | Error: render error (message on stderr), server unreachable, no such panel, bad JSON from the server. |
| 2 | Closed or replaced before a result. Also when the panel of a `--stream` or `update --stream` closes. |
| 3 | `--timeout` elapsed. |
| 64 | Usage error. |

## Wire protocol

- **Transport:** newline-delimited JSON over the Unix socket. The first line
  on a connection is the request, and the server answers with event lines.
- **One-shot commands:** the server sends a final event and closes.
- **Stream commands:** the client keeps sending lines after the request. It
  ends the stream by shutting down its write side (`shutdown(SHUT_WR)`).

### Requests

| `cmd` | Fields | Answer |
|---|---|---|
| `ping` | | `{"event":"pong"}` |
| `show`, `toggle` | See the show request fields below. | `rendered` or `error`, then with `wait` one of `result`, `closed` or `replaced`. A `toggle` that hides answers `hidden`. |
| `update` | `id`, `data` | `{"event":"updated"}`, or `error` when there's no such panel. |
| `update` stream | `id`, `"stream":true`, then lines of `{"data":V}` | `{"event":"updated"}` after EOF, or `closed` if the panel closes first. |
| `move` | `id` plus placement fields | `{"event":"moved","frame":{x,y,width,height}}` or `error` |
| `hide` | `id` or `"all":true` | `{"event":"hidden"}` |
| `list` | | One panel object per line (see below), then close. |
| `pub` | `channel`, `value`, `op`, `keep` | `{"event":"ok"}` or `error` |
| `pub` stream | `channel`, `op`, `keep`, `"stream":true`, then one JSON value per line | `{"event":"ok"}` after EOF |
| `sub` | `channels` (array), `history` (bool) | Optionally `{"event":"history","channel","values":[...]}` per channel, then `{"event":"message","channel","value"}` lines until either side closes. |
| `eval` | `id`, `js` | `{"event":"value","value":V}`. Accepted only when the server started with `CANVAS_TEST=1`; otherwise `error`. Tests use it to drive the page; in a native panel `js` runs as a plain function body in its JavaScript context. |
| `trace` | | `{"event":"trace","stages":[...]}` with the server's most recent stage records (see Tracing). |

`op` is `"set"` (the default) or `"merge"`. Setting `keep` resizes the
history.

**Show request fields.** Only `cmd` and `source` are required. The CLI
leaves out every option the user didn't give, so the server's defaults and
remembered frames apply.

```
cmd, id, kind ("markdown"|"tsx"), source, path, title, data, buttons,
wait, focus, stream, theme, accent, trace,
width (number | "N%"), height (number | "N%"), minHeight, maxHeight (number | "N%"),
position, at: {"x": number | "N%", "y": number | "N%"}, screen (string), margin,
resizable, level, spaces, pin, clickThrough, opacity, stack, forget
```

A negative zero in `at` (flush right or flush bottom) must be sent as `-0.0`
or `"-0"`; JSON parsers read `-0` as 0 and lose the sign.

With `"stream":true` on a show, the connection stays open after `rendered`.
Each following line is `{"data":V}` and replaces the panel's data.

**List entry:**

```
{"id","title","kind","renderer","path","wait","frame":{"x","y","width","height"},
 "screen": "<display name>", "level", "pinned", "clickThrough", "stack"}
```

`renderer` is `"native"` or `"web"`: what draws the panel now. A panel that
fell back to the page reports `"web"`.

`frame` is in AppKit global coordinates: the origin is the bottom-left of the
main screen.

### Events

`rendered`, `error {message}`, `result {value}`, `closed`, `replaced`,
`hidden`, `updated`, `moved {frame}`, `ok`, `pong`, `value {value}`,
`history {channel, values}`, `message {channel, value}`, `trace {stages}`.

When the request had `"trace": true`, the `rendered` and `error` events carry
`"trace"` (see below).

## Tracing

All timestamps are `mach_continuous_time()` converted to nanoseconds. That
clock is shared across processes, so the CLI can subtract its own start time.

`trace` is an object of stage name to timestamp. The server fills:

- `accept`: the connection was accepted.
- `parsed`: the request was decoded.
- `dispatch`: the render call to the page or the native context was issued.
- `jsStart` and `jsEnd`: around the render call. The page reports them and
  the server maps them onto the same clock; the native context's are taken
  on its JavaScript thread.
- `visible`: the window was ordered in at full opacity. A native panel is
  revealed as soon as its first commit is laid out; a web panel waits for
  `painted`.
- `painted`: the first frame after the render was presented (web panels).
- `reply`: the `rendered` event was written.

Each record in the `trace` request's `stages` is
`{"id","cmd","stages","note"?}`. For a `show`, `note` says how the server
handled it (`new` for a pooled host, `fresh` for a new one, `replace`, ...)
and ends with `route=native`, `route=web` (sent straight to the page) or
`route=fallback` (the native render needed the page), for example
`"new route=native"`. A resting panel shown again has the note `rest` and
no render stages.

The CLI adds `cliStart`, `sent` (request written) and `received` (event
read), and prints
`{"total_ms":..., "stages":{"accept":0.41,...}}` to stderr. Each value is in
milliseconds since `cliStart`.

## Page API (Swift calls into the page)

The page is `index.html` with one inline IIFE bundle. The server calls these
functions with `callAsyncJavaScript`, passing arguments natively rather than
as JSON source.

- **`canvas.render(payload) -> {height, error?, jsStart, jsEnd}`:**
  synchronous.
  - It renders with React `flushSync` (or sets Markdown HTML directly), runs
    layout, and returns the natural height of the whole surface (header,
    content and footer) in CSS pixels.
  - `jsStart` and `jsEnd` are `performance.timeOrigin + performance.now()` in
    milliseconds. The server maps them onto its clock.
  - `error` is set when compiling or rendering fails. The page still shows
    the error box and returns its height.
  - The payload is
    `{kind, source, title?, data?, buttons?, wait, theme?, accent?}`.
- **`canvas.setData(data) -> {height}`:** re-renders the current component
  with new `data` props. Component state survives. A Markdown page ignores
  it.
- **`canvas.setAccent(color?)`:** sets `--accent` and the derived
  `--accent-fg`. An empty or invalid color restores the default. `render`
  applies the payload's `accent` the same way, so the server sends it on
  every render and calls `setAccent` when the system accent changes.
- **`canvas.push(batch)`:** delivers channel messages.
  - `batch` is `[{channel, value, history?}]`. `value` is the latest value.
  - `history`, when present, lists the values appended since the last push,
    oldest first, and the latest value is included.
  - On the first push for a subscription, the server sends the full buffered
    history.
- **`canvas.reset()`:** clears the content and state so a pooled page can be
  reused. Returns nothing.
- **`canvas.warm()`:** prewarms React, sucrase and the highlighter during
  idle time. Calling it more than once is harmless.

### Page messages (the page posts to `window.webkit.messageHandlers.canvas`)

| `type` | Fields | Meaning |
|---|---|---|
| `rendered` | | Still posted after every render, for older listeners. The server uses the return value of `render` instead. |
| `error` | `message`, `stack?` | An error after the render, for example in an effect or a later event. |
| `size` | `width`, `height` | The natural height changed after the render, through the ResizeObserver. |
| `painted` | | Posted from the first `requestAnimationFrame` after each `render`. The server reveals a new panel when this arrives, so it never shows an unpainted frame. |
| `result` | `value` | The user submitted a value. |
| `close` | `reason?` | Esc (the first Esc only blurs a focused field), the × button, or `close()`. Esc sends `reason: "escape"`, which a pinned panel ignores. |
| `open` | `url` | A link was clicked. The server opens only http, https and mailto URLs. |
| `subscribe` | `channel`, `every?` (ms, for `canvas.sys.*`) | A hook started listening. The server replies with a `push` holding the history. |
| `unsubscribe` | `channel` | The last hook for that channel unmounted. |
| `publish` | `channel`, `value` | Publish from the page. Reserved names are rejected with a console error. |

## Kit additions (`canvas` module)

- `useChannel<T>(name, opts?: {every?: number}): T | undefined` returns the
  latest value and re-renders when it changes.
- `useSeries<T>(name, size = 120): T[]` returns up to `size` recent values,
  oldest first.
- `publish(name, value)`. `useCanvas()` also returns `publish`.
- The `color` props take semantic names (`accent`, `success`, `warning`,
  `danger`, `info`, `muted`), the hue names `red`, `orange`, `yellow`,
  `green`, `teal`, `blue`, `purple`, `pink` and `gray` (Apple system colors
  for the current theme), or any CSS color.

## System channels (`canvas.sys.*`)

The sampler runs only while at least one subscriber exists, at the smallest
`every` any subscriber asked for. That defaults to 1000 ms, and the floor is
100 ms. Every system channel keeps 300 history entries. Rate channels (cpu,
net, disk and procs) need a baseline reading, so their first value arrives
one interval after the first subscribe.

| Channel | Value |
|---|---|
| `canvas.sys.cpu` | `{total: 0..1, cores: number[]}` (each core 0..1) |
| `canvas.sys.memory` | `{total, used, app, wired, compressed, swapUsed}` (bytes) |
| `canvas.sys.net` | `{rx, tx, rxTotal, txTotal}` (bytes per second, plus totals). Sums interfaces that are up, excluding loopback and VPN tunnels so tunneled traffic isn't counted twice. |
| `canvas.sys.disk` | `{read, write, used, total}` (bytes per second across internal drives, plus the boot volume's capacity) |
| `canvas.sys.procs` | `[{pid, name, cpu, mem}]`: the top 40 by CPU. `cpu` is the share of one core, so it can exceed 1. `mem` is resident bytes. |
| `canvas.sys.battery` | `{percent, charging, source}` or `null` without a battery. `percent` is a whole number 0..100, `source` is `"ac"` or `"battery"`. |
| `canvas.sys.thermal` | `{state: "nominal"\|"fair"\|"serious"\|"critical"}` |
