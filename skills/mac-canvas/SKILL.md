---
name: mac-canvas
description: Shows Markdown or TSX in a floating macOS panel with the `canvas` CLI, keeps it updated with live data, and can wait for the user to click a button or fill in a form. Use when output is easier to read laid out than in chat (plans, summaries, tables, dashboards, diffs, progress), when the user may be in another app, or when you need a quick decision (approve, pick one, fill in a value). Not Cursor's in-editor Canvas (.canvas.tsx files); inside Cursor, prefer that for durable artifacts.
---

# mac-canvas

`canvas` opens a floating panel over whatever the user is doing and renders Markdown or a TSX component in it. Run `canvas ping` first. Exit 0 means the server is up. Anything else, including a missing command, means answer in chat. `canvas help` lists every flag.

Every command exits with one of these codes:
- 0: ok
- 1: error, with the message on stderr (a TSX compile or render error, an unknown `--id`)
- 2: the panel was closed or replaced without a result
- 3: `--timeout` ran out
- 64: bad arguments

## Show something

```bash
canvas show plan.md
canvas show --id deploy --title "Deploy summary" - <<'EOF'
# Deploy summary
| Service | Status |
|---------|--------|
| api     | ok     |
EOF
canvas show dash.tsx --id dash --data results.json
```

- The command returns once the panel has rendered, with exit 0, or exit 1 and the error on stderr. Fix a TSX error and show again.
- A shown file is watched, so editing it re-renders the panel.
- `--data` takes inline JSON, a file, or `-` for stdin. TSX gets it as `props.data`.
- `--id NAME` names the panel, and showing an existing id replaces its content. The default id is `default`. Give each panel you own its own id so you don't replace someone else's.
- Panels don't take keyboard focus unless you pass `--focus` or `--wait`. Don't pass `--focus` while the user is likely typing elsewhere.

## Ask and wait

`--wait` blocks until the user acts and prints the result as JSON on stdout. With `--buttons`, the result is the label of the button they clicked, and the first button is primary.

```bash
choice=$(canvas show --id merge --wait --timeout 300 --buttons "Ship it,Hold" - <<'EOF'
## Ready to merge #482?
3 files, tests pass. Migration adds an index on `orders.created_at`.
EOF
)
```

Here `$choice` is `"Ship it"` (with the quotes, since it's JSON). Exit 2 means the user closed the panel, and exit 3 means nobody answered in 300 seconds, so the panel was hidden. Always pass `--timeout` when the run is unattended.

For anything richer, write TSX. What the page submits is printed the same way:

- Inside a `Form`, a `Button` with no `onClick` submits the form's named fields as one object, plus that button's `name` and `value`. Cmd+Enter presses the primary button.
- Outside a form, a `Button` with a `value` and no `onClick` submits that value.
- `submit(value)` and `close()` from `useCanvas()` cover anything else. `close()` exits 2.

```tsx
import { Form, Input, Button, Row, useCanvas } from 'canvas'

export default function Ask() {
  const { close } = useCanvas()
  return (
    <Form>
      <Input name="branch" label="Branch name" />
      <Row>
        <Button variant="primary" name="action" value="create">Create</Button>
        <Button variant="ghost" onClick={close}>Cancel</Button>
      </Row>
    </Form>
  )
}
```

Submitting that prints `{"branch":"…","action":"create"}`.

## Keep it updated

For progress or results that change, show the page once and then send new data. The page re-renders without remounting, so it keeps its scroll position and state.

```bash
canvas show progress.tsx --id build --data '{"done":0,"total":12}'
canvas update --id build --data '{"done":5,"total":12}'
canvas hide --id build
```

Channels suit a stream of values, or a value several pages read. A channel is named with dot-separated lowercase segments. `canvas pub` sends one JSON value, and the page reads it with `useChannel` (the latest value) or `useSeries` (recent values, oldest first). `--merge` applies the value as a JSON merge patch to the current one.

```bash
canvas pub build.status '{"step":"tests","ok":true}'
canvas pub build.status --merge '{"ok":false}'
canvas pub build.load --every 2s -- sh -c 'sysctl -n vm.loadavg | cut -d" " -f2'
```

Names starting with `canvas.` are reserved. `canvas.sys.cpu`, `canvas.sys.memory`, `canvas.sys.net`, `canvas.sys.disk`, `canvas.sys.procs`, `canvas.sys.battery` and `canvas.sys.thermal` carry live system stats, so a page can chart them without a publisher. Their value shapes are in `docs/protocol.md`.

## Place it

The panel is centered at 720 points wide by default, and its height follows the content. These flags work on `show`, `toggle` and `move`:

- `--position`: `center`, `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left`, `bottom-right` or `mouse`
- `--width` and `--height`: points or a percentage of the screen, such as `--width 40%`
- `--stack GROUP`: panels in the same group stack in their corner, like notifications
- `--pin`: floats on every Space, and Esc doesn't close it

```bash
canvas show - --id note-1 --stack notes --position top-right --width 360 <<'EOF'
**Build finished** in 4m 12s
EOF
canvas move --id note-1 --position bottom-right
```

## Manage panels

- `canvas list` prints one JSON object per visible panel.
- `canvas toggle FILE --id NAME` hides the panel if it's visible and shows it otherwise.
- `canvas hide --id NAME` closes one panel, and `canvas hide --all` closes every panel. Close panels you opened once they're stale.

## TSX

A `.tsx` file default-exports a component that gets `{ data }` as props. It can import from `react` and `canvas` only.

- **Hooks:** `useCanvas()` returns `submit`, `close`, `publish`, `data` and `wait` (true when the caller is blocking on `--wait`). `useChannel`, `useSeries` and `publish` are also exports.
- **Layout:** `Stack`, `Row`, `Grid`, `Divider`, `Spacer`
- **Text:** `Heading`, `Text`, `Code`, `CodeBlock`, `Markdown`, `Kbd`, `KeyChips`
- **Data:** `Card`, `Table`, `Stat`, `Badge`, `Progress`, `BarChart`, `Sparkline`
- **Input:** `Button`, `Input`, `TextArea`, `Select`, `Checkbox`, `Form`

```tsx
import { Card, Progress, Stack, Stat, Text, useChannel } from 'canvas'

type Build = { done: number; total: number }

export default function BuildProgress({ data }: { data: Build }) {
  const status = useChannel<{ step: string; ok: boolean }>('build.status')
  return (
    <Card title="Build">
      <Stack gap={10}>
        <Stat label="Steps" value={`${data.done} of ${data.total}`} />
        <Progress value={data.done} max={data.total} />
        <Text muted>{status ? `${status.step}: ${status.ok ? 'passing' : 'failing'}` : 'Waiting for status'}</Text>
      </Stack>
    </Card>
  )
}
```

Props and their types are in `web/canvas.d.ts` in the Canvas checkout. This skill's folder is `skills/mac-canvas` in that checkout, so resolve its real path to find the checkout.

Kit `color` props take a semantic name (`accent`, `success`, `warning`, `danger`, `info`, `muted`), an Apple system hue (`red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink`, `gray`) or any CSS color. In your own styles, use the theme's CSS variables, such as `var(--accent)`, `var(--fg-muted)`, `var(--border)` and `var(--green)`, so the page works in both light and dark mode.

Pages have no network: no fetch, no remote images or fonts. Local `file://` images work.

## When not to use it

- For one-line answers, or anything the user will read in the chat anyway.
- For several panels at once, unless they're a `--stack` group. Reuse one `--id` and update it.
- As a prompt with no `--timeout` during an unattended run. Treat exit 3 as no answer.
