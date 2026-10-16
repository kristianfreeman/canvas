# Hello, Canvas

Canvas renders Markdown and TSX in a floating panel. Agents call `canvas show plan.md`, and the panel updates live as the file changes.[^live]

> Keep it calm. Generous whitespace, one accent color, and nothing that shouts.

## What renders

| Feature        | Markdown | TSX | Notes                              |
| -------------- | :------: | :-: | ---------------------------------- |
| Live reload    |    ✓     |  ✓  | Watches the file, even atomic saves |
| Highlighting   |    ✓     |  ✓  | Shiki, GitHub light and dark        |
| Results        |          |  ✓  | `--wait` returns JSON on stdout     |
| Buttons footer |    ✓     |  ✓  | `--buttons "Approve,Reject"`        |

## Today

- [x] Build the panel server
- [x] Render Markdown with tables, footnotes and task lists
- [ ] Ship the shortcut cheat sheet
- [ ] Mermaid diagrams, later

## Code

```ts
import { Card, Stat } from 'canvas'

export default function Uptime({ data }: { data: { uptime: number } }) {
  return (
    <Card title="API">
      <Stat label="Uptime" value={`${data.uptime}%`} delta="+0.02%" />
    </Card>
  )
}
```

```bash
# Ask a question and wait for the answer
canvas show approve.tsx --wait --data '{"plan":"deploy"}' | jq -r .decision
```

```swift
let panel = CanvasPanel(contentRect: frame)
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

```json
{ "event": "result", "value": { "decision": "approve" } }
```

---

Links open in your default browser: [shiki.style](https://shiki.style). Press Esc to close.

[^live]: Editors that save by replacing the file are handled too.
