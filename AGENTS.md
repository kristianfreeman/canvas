# Canvas

A system-wide version of Cursor's canvas for macOS. Agents and scripts call
`canvas show plan.md` or `canvas show dash.tsx`, and a floating panel renders
it. With `--wait`, the panel can send a result back (a button click, form
input), so agents can ask the person at the Mac things.

Requirements: macOS 14 or later, the Swift 6 command line tools (Xcode isn't
needed) and Bun for the renderer. The CLI in `docs/protocol.md` is a
contract other tools depend on; change it only with a changelog note.

## Architecture

Canvas is a C CLI and a Swift server that owns the panels, talking over a
Unix socket. Panels render natively: React runs in an in-process
JavaScriptCore context and SwiftUI draws the kit (`docs/native.md`). A
WebKit page renders only TSX that uses raw DOM or CSS.

- **App bundle:** `scripts/bundle.sh [OUT]` builds `Canvas.app` (bundle id
  `dev.kristian.canvas`, `LSUIElement`, version from `VERSION`) and signs it
  with the hardened runtime and `scripts/Canvas.entitlements` (JIT for
  JavaScriptCore), ad hoc unless `CANVAS_SIGN_IDENTITY` names a Developer
  ID. In `Contents/MacOS`, `canvas-server` is the bundle executable and
  `canvas` is the CLI. `Contents/Resources` has `web` (a copy of
  `web/dist`) and `setup.sh`, which links the CLI to `~/.local/bin/canvas`
  and loads the LaunchAgent (`--stop`, `--uninstall`). `scripts/install.sh`
  bundles to `.build/Canvas.app`, stops the old server, copies it to
  `~/Applications` and runs its `setup.sh`. `scripts/release.sh` signs,
  notarizes, staples and zips to `dist/Canvas-VERSION.zip`; it needs
  `CANVAS_SIGN_IDENTITY` and a `notarytool` keychain profile in
  `CANVAS_NOTARY_PROFILE`.
- **CLI:** C17 in `cli/`, built by `cli/build.sh` with clang (`--debug` adds
  ASan and UBSan). The v1 Swift CLI and its role dispatch are gone.
- **Server:** SwiftPM with `swiftLanguageMode(.v5)`. `CanvasCore` is pure
  logic with no AppKit or WebKit (placement, stacking, remembered frames,
  config, channels, request parsing, tracing, the view tree, Markdown blocks,
  key chips, theme tokens and routing), and the unit tests target it.
  `CanvasApp` has the panels, the native runtime and kit, the web pool, the
  listener, channel hub and `canvas.sys.*` sampler. The `canvas-server` executable serves with no
  arguments or with `serve`.
- **Startup:** setup.sh writes the LaunchAgent
  `~/Library/LaunchAgents/dev.kristian.canvas.plist`. launchd owns the
  socket (socket name `canvas`, mode 0600) and starts the server on the first
  connection, plus at login through `RunAtLoad`. `ThrottleInterval` is 1, and
  there's no `KeepAlive`, so a server that exits stays down until the next
  connection. The server takes the socket with `launch_activate_socket`. A
  server started by hand binds the socket itself.
- **Autostart:** when no socket answers, the CLI starts a server
  (`cli/autostart.c`). Inside a bundle it runs `open -g` on the bundle. In a
  dev build it spawns `$CANVAS_SERVER` or a `canvas-server` found next to the
  CLI or in `.build/debug` or `.build/release`, detached. `CANVAS_NO_AUTOSTART=1`
  turns this off.
- **State:** `CANVAS_HOME` (default `~/Library/Application Support/Canvas`)
  has the socket, `server.lock` and `frames.json`. Point it at a temp
  directory to run an isolated server. `CANVAS_CONFIG` overrides
  `~/.config/canvas/config.toml`.
- **Native render path:** `NativeRuntime` keeps one evaluated `JSContext`
  (bundle `web/dist/native.js`) ready on a shared VM, each on its own JS
  thread with a 2 s time limit per call. A render posts view tree ops;
  `NativePanelContent` applies them to a `ViewTree`, which SwiftUI kit views
  in `Sources/CanvasApp/Native/Kit` observe. One native host is parked, and
  SwiftUI is prewarmed offscreen at launch. A native panel is revealed after
  its first measured commit.
- **Fallback:** a render that needs WebKit (`needsWeb`) moves the panel to a
  WebKit host, and `RouteCache` sends that content straight to WebKit next
  time. The web host renders in one `callAsyncJavaScript` round trip and is
  revealed on the page's `painted`. `warm` in config.toml is `linger` (the
  default: no page up front, a closed web panel's page kept
  `linger_seconds`, 120), `always`, `idle` or `never`.
- **Content:** `PanelContent` is the interface `PanelController` uses for
  either renderer; `list` reports each panel's `renderer`.
- **Resting:** a closed native panel waits hidden on the server's
  `RestShelf` (up to 3). A `show` or `toggle` that `PanelRest.sameShow`
  matches reopens it without rendering, in about 1 ms, with the trace note
  `rest`. A panel with channel subscriptions or pending JS timers doesn't
  rest.
- **Panel:** a borderless, non-activating, resizable `NSPanel`, corner radius
  14, 1 px border, with a native background matching the page's `--bg`. A
  native drag strip covers the 40 px header except the rightmost 44 px, where
  the page's × is. A shown FILE is watched and re-rendered on change.
- **Exec tax:** on Macs with endpoint security software, every launch of a
  non-Apple binary, including the CLI, can cost tens of milliseconds. Hot paths build the request
  once with `--emit` and send it with `/usr/bin/nc -U <socket>` (about 2 ms)
  or `canvas-send` from `cli/canvas-send.zsh` in a running zsh.
- **Security:** TSX runs arbitrary JS. The page has CSP `connect-src 'none'`,
  the webview never navigates, and only http, https and mailto links open, in
  the default browser.

## CLI and page contracts

`docs/protocol.md` is the source of truth for the CLI, the wire protocol, the
page API, the kit's channel hooks and the system channels.
`docs/positioning.md` explains placement in depth, with worked frames. Read
them before you change behavior, and update them in the same commit.

In short: the commands are `show`, `toggle`, `update`, `move`, `hide`,
`list`, `pub`, `sub`, `ping` and `help`, and exit codes are 0 success, 1
error, 2 closed or replaced, 3 timeout and 64 usage. The renderer in `web/`
builds with `bun run build` to `web/dist/index.html` with one inline IIFE
script, since browsers block ES modules from `file://`. No network, no CDN,
no bundled fonts. TSX imports only `react` and `canvas`, and the kit's types
in `web/canvas.d.ts` are checked against `web/src/kit`.

## Look

The theme is neutral, built from semantic tokens in `web/src/styles.css`.

- **Surfaces:** dark is `#0a0a0a` with text `#ededed`, light is white with
  text `#171717`, and cards sit slightly lifted. Borders are 8% white in dark
  mode and 8% black in light mode.
- **Accent:** the macOS system accent color, read by the server. `--accent
  COLOR` overrides it per panel, and the page API `canvas.setAccent` sets it
  at run time.
- **Hues:** `--red`, `--orange`, `--yellow`, `--green`, `--teal`, `--blue`,
  `--purple`, `--pink` and `--gray` are Apple's system colors for each
  theme. Kit `color` props take these names, the semantic names (`accent`,
  `success`, `warning`, `danger`, `info`, `muted`) or any CSS color.
- **Code:** Shiki's `github-dark-default` and `github-light-default`.
- **Fonts:** Geist for UI and Berkeley Mono for code and `Kbd`. Both are
  installed system-wide. Never bundle or commit them. The Berkeley Mono
  license forbids it.

Keep it minimal and calm, with generous whitespace and no gradients.

## Testing

`./scripts/test.sh` runs every suite, and the default run opens no windows.

- **Unit tests** (`Tests/CanvasTests`, swift-testing): CanvasCore.
  `PositioningRecipeTests` checks every recipe frame in `docs/positioning.md`.
- **Bridge tests** (`Tests/BridgeTests`): the real renderer in a windowless
  `WKWebView`, driven through the page API.
- **Native tests** (`Tests/NativeTests`): the JS runtime, view tree ops,
  events, channels, the time limit and the fallback to WebKit, with no
  window.
- **Native kit tests** (`Tests/NativeKitTests`): SwiftUI kit layout and
  logic, plus `ImageRenderer` goldens in `Tests/golden/native` for kit
  samples and every example in both themes. `UPDATE_GOLDENS=1` rewrites
  them.
- **CLI tests** (`Tests/CLITests`): the C CLI from `cli/build.sh` against a
  recording server, checking request lines and exit codes.
- **Renderer tests:** `bun test` over `web/src/*.test.ts` and the examples.

`CANVAS_TEST_TIMEOUT` (seconds, default 90) caps each suite. Arguments after
`--` go to `swift test`.

Two more modes:

- `--ui` runs only the on-screen suites in `Tests/BridgeTests/UI`, so it
  needs a go-ahead: reveal on `painted`, golden snapshots in
  `Tests/golden` (rewrite them with `UPDATE_GOLDENS=1`), and the end-to-end
  contract matrix against a dev server started with `CANVAS_TEST=1`, which
  enables the `eval` request. All of it passes. `OnScreen.swift` turns off
  WebKit's window occlusion detection (`_setWindowOcclusionDetectionEnabled:`),
  without which the test window gets no animation frames and `painted` never
  arrives. Goldens compare 3×3 block averages, so text antialiasing that
  shifts between runs doesn't fail them, and `top.tsx` renders without live
  channels.
- `--mutations` runs the default suites, then `Tests/mutations/run.sh`,
  which applies each curated `Tests/mutations/*.patch` to a copy under
  `.build/mutations` and fails if any mutant survives. It takes about 20
  minutes.

Always spell the folder `Tests/`. This Mac's file system ignores case, so
`tests/` works here, but it would break on a case-sensitive checkout.

### Test rules

- A test must fail when the behavior it names breaks. Don't assert on values
  the test itself just set.
- Geometry and parsing get property tests with seeded randomness, and the
  seed goes in the failure message.
- Each new feature gets a mutation patch that its tests catch.

## Status

- **Done (v2):** everything in `docs/protocol.md` and `docs/positioning.md`:
  the C CLI with `--emit` and `canvas-send.zsh`, the server under launchd
  with the warm pool and one-round-trip render, placement, channels and the
  `canvas.sys.*` sampler, and the neutral theme. Examples: `hello.md`,
  `dashboard.tsx`, `approve.tsx`, `keys.tsx` with `keys.json`, `live.tsx` (a
  channel readout) and `top.tsx` (a btop-style system monitor).
- **Done (native):** the in-process JavaScriptCore runtime and SwiftUI kit
  in `docs/native.md`. Every example renders natively. Idle memory is about
  54 MB with no WebKit process.
- **Open:**
  - Idle memory is above the 45 MB target. A panel on the WebKit fallback
    still costs about 75 MB while it's open and for `linger_seconds` after.
  - Each native panel has its own JS context and its own SwiftUI graph, and
    TSX compiles once per context, so every show compiles again. Measured
    windowless with `CANVAS_MEASURE=1`, laid out once in the panel's own
    hosting view: a small kit TSX show takes about 6 ms, `hello.md` about
    20 ms and `keys.tsx` with `keys.json` about 23 ms, mostly SwiftUI
    building and laying out the view graph. The prewarm at launch takes
    about 150 ms. On screen, the installed server took about 65 ms per
    cheat sheet show before the measurer was removed.
  - `LineReaderTests` (seed 74) timed out once under mutation-run load.
  - On screen, a check by eye on 2026-10-15 passed: Markdown, `top.tsx` with
    live `canvas.sys.*` data, a pinned stack, `move`, `pub`/`sub` and
    `hide --all`. Not yet checked by eye: Esc on a pinned panel, remembered
    frames after a drag, `--screen focused`.
  - Mermaid isn't supported.

## Rules

- No secrets, no font files, no build output in git.
- Run `scripts/lint.sh` and `gitleaks git --staged` before each commit.
  Lint has to pass with zero findings. SwiftLint (`.swiftlint.yml`, strict),
  Oxlint (`web/.oxlintrc.json`, plus the cognitive complexity rule in
  `web/tools/oxlint/complexity/`) and clang-tidy (`cli/.clang-tidy`) set
  tight complexity and length limits. Fix findings by decomposing the code.
  Don't loosen the config. A single-line disable needs a reason, and only
  belongs on code whose shape something outside the repo dictates, like a
  WebKit delegate signature.
- Commit in small, working steps.
- Panels popping up interrupt whoever is at the Mac, so the default test run
  is windowless. Ask before anything that opens windows: `canvas show`,
  `scripts/install.sh`, `--ui`, screenshots, dev servers that open panels,
  or `scripts/bench.sh`.
