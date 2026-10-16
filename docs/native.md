# Native rendering

Most panels render natively. React runs in an in-process JavaScriptCore
context, and its host elements are the kit components, drawn with SwiftUI.
No WebKit process starts. TSX that uses raw DOM tags, `className`, or styles
outside a small allowed set falls back to the WebKit renderer.

`docs/protocol.md` stays the contract for the CLI, the wire and the page
API. This file is the contract between the JavaScript runtime
(`web/native/`, built to `web/dist/native.js`) and the Swift side
(`Sources/CanvasApp/Native/`, model in `Sources/CanvasCore/ViewTree.swift`).

## Runtime

- **Bundle:** `web/dist/native.js`, one IIFE that defines
  `globalThis.canvasNative`. It holds sucrase, React, `react-reconciler`
  with the host config below, the kit shim, the channel hooks, markdown-it
  (footnotes and task lists, as on the web) and highlight.js core.
- **Contexts:** one `JSVirtualMachine` per server. Each panel gets its own
  `JSContext` with the bundle evaluated, on a dedicated JS thread. The server
  keeps one evaluated context ready, like the old warm page.
- **Globals Swift provides** before evaluating the bundle:
  - `setTimeout(fn, ms)`, `clearTimeout(id)`, `setInterval`, `clearInterval`,
    `queueMicrotask(fn)` (or JSC's own), `performance.now()`.
  - `console.log/warn/error` (to the debug log).
  - `__post(message)`: one function for everything the runtime sends Swift.
    `message` is a plain object with a `type`, listed under Messages.
- **No other host APIs.** No DOM, network, file system or `eval` of strings
  from outside the shown source.
- **Time limit:** each call into the context is limited (default 2 s). A
  script that runs over is terminated, and the panel shows the error.

## Calls (Swift into the context)

All return plain JSON-able values.

- `canvasNative.render(payload) -> {ok: true} | {error, stack?, needsWeb?:
  true}`. `payload` is the same object the web page gets: `{kind, source,
  title?, data?, buttons?, wait, theme?, accent?}`. Markdown renders as
  `<Markdown source={source}/>`. Ops for the commit are posted before it
  returns. A `needsWeb` render posts no ops; if the context is reused, its
  next batch starts by removing the root children Swift still shows.
- `canvasNative.setData(data)`: re-render with new `data`, state kept.
- `canvasNative.invoke(fnId, args)`: call a function prop (an event).
  `args` is an array of JSON values.
- `canvasNative.push(batch)`: channel delivery, same shape as the page's
  `canvas.push`.
- `setData`, `invoke` and `push` return `{error, needsWeb: true}` when the
  new tree needs WebKit; the posted `error` message carries `needsWeb: true`
  too.
- `canvasNative.reset()`: unmount and clear state so the context can be
  reused. It posts no ops: Swift starts a fresh `ViewTree`.
- `canvasNative.warm()`: renders a sample off-tree so the first real render
  is fast. It does nothing while content is shown.
- **Time limit:** a call stopped by the limit returns `timedOut`. The
  context is left mid-render, so Swift retires it. All contexts share one
  VM, so a runaway script stalls every panel's JS for up to the limit.

## Messages (`__post`)

- `{type: "ops", ops: [Op]}`: one React commit. Swift applies the whole
  batch, then lays out.
- `{type: "result", value}`, `{type: "close"}`, `{type: "close", reason:
  "escape"}`: as the page messages in `docs/protocol.md`.
- `{type: "subscribe", channel, every?}`, `{type: "unsubscribe", channel}`,
  `{type: "publish", channel, value}`: as the page messages.
- `{type: "error", message, stack?}`: an error after the first render.
- `{type: "open", url}`: a link was clicked (Markdown links).

## Ops

Node ids are positive integers chosen by the runtime. The root container is
id `0`.

```
{"op":"create","id":7,"type":"Card","props":{...}}
{"op":"text","id":8,"text":"Hello"}
{"op":"append","parent":7,"child":8}
{"op":"insert","parent":7,"child":9,"before":8}
{"op":"remove","parent":7,"child":8}
{"op":"props","id":7,"props":{...}}
{"op":"setText","id":8,"text":"Hello again"}
```

- `props` always carries the full prop set for the node, never a patch.
- A node is created once and can move between parents (`remove` then
  `append` or `insert`). A removed node that isn't re-added by the end of
  the batch is gone.
- `children` is never a prop: children arrive as ops. Text children become
  `text` nodes.
- **Functions:** a function prop is sent as `{"$fn": N}`. The id is stable
  for that node and prop as long as the prop stays a function, and the
  runtime always calls the latest function for it.
- **Values:** props are JSON values only. `undefined` props are omitted.

## Host element types

Each kit export is a React component in the shim. It renders one host
element of the same name. ReactNode props become `slot` children:

```
<Card title={<b>CPU</b>}>{body}</Card>
=> Card
     slot name="title"   (children: the title nodes)
     ...body nodes
```

A `slot` host element has one prop, `name`. Everything else under a host
element is its body.

| Type | Props | Slots |
|---|---|---|
| `Stack` | `gap`, `align`, `style?` | |
| `Row` | `gap`, `align`, `justify`, `wrap`, `style?` | |
| `Grid` | `columns` (number, or a string of track sizes like `"1fr 2fr"` or `"max-content 1fr"`), `gap`, `style?` | |
| `Divider` | `style?` | |
| `Spacer` | `size?` | |
| `Heading` | `level` | |
| `Text` | `size`, `muted`, `weight`, `color`, `mono` | |
| `Code` | | |
| `CodeBlock` | `lang`, `lines` (see Highlighting) | |
| `Markdown` | `blocks` (see Markdown) | |
| `Kbd` | `tone?` (`"accent"`) | |
| `KeyChips` | `keys` (string or string array; Swift splits it, see Key chips) | |
| `Card` | `padding` | `title`, `subtitle`, `actions` |
| `Table` | `columns: [{key, align?, width?}]` | `head` with one `TableCell` per column; body is `TableRow` nodes |
| `TableRow` | `key`, `selected?` (true on the `Table.selected` row), `onClick?` (with `onRowClick`) | |
| `TableCell` | `align?`; in `head` also `sort?` (`ascending` or `descending` on the sorted column) and `onClick?` (with `onSort`) | |
| `Stat` | `delta?` (display text without sign or arrow), `tone` (`up`, `down`, `flat`; always sent), `good` (bool, delta coloring after `invertDelta`; false when flat), `color?` | `label`, `value`, `hint` |
| `Badge` | `color`, `dot` | |
| `Progress` | `value` (0..1, already divided by `max`), `color`, `showValue` (bool: render the percent) | `label` |
| `BarChart` | `data: [{value, color?}]`, `max`, `height`, `color` | one `slot` per bar named `label0`, `label1`, ..., and `value0`... when `format` is given |
| `Sparkline` | `data`, `width` (points, or `"100%"` to fill the container), `height`, `color`, `fill` | |
| `Button` | `variant`, `disabled`, `onClick?` (`$fn`), `submit` (bool: a Form submit button), `name?`, `value?` | |
| `Input` | `name`, `value?`, `placeholder`, `type`, `disabled`, `onChange?` | `label`, `hint` |
| `TextArea` | `name`, `value?`, `placeholder`, `rows`, `onChange?` | `label`, `hint` |
| `Select` | `name`, `value?`, `options: [{value, label, disabled?}]`, `onChange?` | `label`, `hint` |
| `Checkbox` | `name`, `checked?`, `onChange?` | `label`, `hint` |
| `Form` | `gap`, `onSubmit?` | |
| `Footer` | `buttons`, `wait` | (the panel footer, added by the runtime when `buttons` is set) |

- **Colors:** `color` props are passed as given: a semantic name, a hue
  name, or a CSS color string. Swift resolves them with `Theme`.
- **Sizes:** always sent as numbers (points); the shim converts `px`
  strings. Other CSS lengths fall back to WebKit.
- **Grid tracks:** integers, `fr`, `px`, `auto`, `min-content` and
  `max-content`. Anything else (`repeat()`, `minmax()`) falls back.
- **Table rows:** `key` is a string. `selected`, `sort` and `onClick` are
  only sent when set. **Select:** an option label that isn't text becomes
  the option's value.
- **Key chips:** `keys` as in `KeyChips` in `web/canvas.d.ts`: a string is
  split on whitespace with `Caps Lock`, `Page Up`, `Page Down` and
  `Num Lock` kept together, an array is the tokens. `Hyper` (any case) is an
  accent ✦ chip; `tap`, `hold`, `twice`, `double`, `then`, `or`, `again`
  are quiet words; `+` and a `→` between two non-arrow tokens are quiet
  separators; other tokens are `Kbd` chips (arrows a size up).
- **Events:** `onClick` gets no args. `onChange` gets `[{value}]` or
  `[{checked}]`. The shim always gives a value Button outside a Form an
  `onClick`, and every `Form` an `onSubmit`, so Swift only invokes handlers.
  Form submit: Swift collects the named fields in the form's subtree
  (checkboxes as booleans, number inputs as numbers, plus the submitting
  button's `name` and `value`) and calls `onSubmit` with `[values]`. Author
  handlers get a synthetic event with `target.value`, `target.checked` and
  `preventDefault()`.
- **Unknown types:** a capitalized host type that isn't in this table falls
  back to WebKit. Suspense hide and unhide do nothing natively.

### Allowed `style` keys

`margin`, `marginTop`, `marginRight`, `marginBottom`, `marginLeft`,
`padding` (and the four sides), `width`, `minWidth`, `maxWidth`, `height`,
`flex`, `opacity`, `textAlign`. Values are numbers or `px` strings
(`textAlign` takes `left`, `center`, `right`; `flex` takes a number). The
shim forwards allowed keys as the `style` prop.

### Fallback to WebKit

The render returns `{error, needsWeb: true}` and posts no ops when the
component tree uses any of:

- a lowercase host tag (`div`, `span`, `style`, `svg`, ...),
- a `className` prop,
- a `style` key outside the allowed set, or a value it can't express.

The check runs during reconciliation, before anything is committed. The
server then renders the same request with the WebKit renderer.

## Markdown

`Markdown.blocks` is an array of blocks, built by markdown-it in the
runtime:

```
{t:"h", level:1..6, inl:[Inline]}
{t:"p", inl:[Inline]}
{t:"quote", blocks:[Block]}
{t:"list", ordered:bool, start?:n, items:[{task?:bool|null, checked?:bool, blocks:[Block]}]}
{t:"code", lang, lines:[[Token]]}
{t:"table", align:["left"|"center"|"right"|null], head:[[Inline]], rows:[[[Inline]]]}
{t:"hr"}
{t:"footnotes", items:[{id, blocks:[Block]}]}
```

Inline runs:

```
{t:"text", s, b?:true, i?:true, del?:true}
{t:"code", s}
{t:"link", href, inl:[Inline]}
{t:"br"}
{t:"fnref", id, n}
```

Raw HTML is text. Images become their alt text. A fence with no language
has `lang: ""`. Footnote ids look like `fn1`. Links open through `open`
(http, https and mailto only, as on the web).

## Highlighting

`CodeBlock.lines` and Markdown `code.lines` are arrays of lines, each an
array of tokens `{s, c?}`. `c` is a highlight.js scope reduced to one of:
`keyword`, `string`, `number`, `comment`, `title`, `type`, `attr`,
`variable`, `literal`, `built_in`, `meta`, `symbol`, `regexp`, `addition`,
`deletion`, `punctuation`, `property`, `tag`, `section`. Swift colors them
with the GitHub light and dark palettes. Unknown languages come back as one
token per line with no `c`, so an empty line is `[{s: ""}]`; a highlighted
empty line is `[]`.

## Layout and reveal

Swift applies the ops to a `ViewTree` (`CanvasCore`), which SwiftUI
observes. The panel's height is the hosting view's fitting height at the
panel width, plus the header and footer. A native panel is revealed as soon
as the first commit is laid out; there is no `painted` round trip.
