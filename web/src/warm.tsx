import type { ComponentType } from 'react'
import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'
import { COMMON_GRAMMARS, type GrammarName } from './grammars'
import { getHighlighter, highlight, isGrammarLoaded, onGrammarReady, requestGrammar, warmGrammar } from './highlight'
import { idle } from './idle'
import { CanvasProvider } from './kit'
import { renderMarkdown } from './markdown'
import { evaluateTsx } from './tsx'

const WARM_TSX = `import { Card, Row, Stat, Badge, Text } from 'canvas'
export default function Warm({ data }: { data: number }) {
  return <Card title="warm"><Row><Stat label="n" value={data} delta="+1" /><Badge color="success" dot>ok</Badge></Row><Text muted>t</Text></Card>
}`

const WARM_MD = '# Warm\n\nSome *text*, a [link](https://example.com) and `code`.\n\n- [x] task\n\n| a | b |\n|---|---|\n| 1 | 2 |\n'

const SAMPLE = 'const value = { key: "text", n: 1 } // note\n'

function renderDetached(component: unknown) {
  const App = component as ComponentType<{ data: number }>
  const root = createRoot(document.createElement('div'))
  flushSync(() =>
    root.render(
      <CanvasProvider data={1} wait={false}>
        <App data={1} />
      </CanvasProvider>,
    ),
  )
  root.unmount()
}

/** Compiles the grammar's regexes, then highlights a sample so the highlighter has a cost estimate for render budgets. */
function* grammarTask(name: GrammarName) {
  yield* warmGrammar(name)
  highlight(SAMPLE, name)
}

/** Grammar scripts arrive asynchronously; each one queues its own task when it's ready. */
function warmGrammars() {
  const pending = new Set<GrammarName>(COMMON_GRAMMARS)

  const queue = (name: GrammarName) => {
    if (pending.delete(name)) idle.add(grammarTask(name))

    if (pending.size === 0) stop()
  }

  const stop = onGrammarReady(queue)

  for (const name of COMMON_GRAMMARS) {
    requestGrammar(name)

    if (isGrammarLoaded(name)) queue(name)
  }
}

function* steps() {
  yield getHighlighter()
  warmGrammars()
  yield
  yield renderMarkdown(WARM_MD)
  const component = evaluateTsx(WARM_TSX)
  yield
  renderDetached(component)
}

let started = false

/** Every step is small and runs in idle slices, so a render() that arrives meanwhile waits at most one step. */
export function warm() {
  if (started) return
  started = true
  idle.add(steps())
}
