import { createElement, isValidElement, type ComponentType } from 'react'
import Reconciler from 'react-reconciler'
import { ConcurrentRoot, DiscreteEventPriority, NoEventPriority } from 'react-reconciler/constants'
import { describeError } from '../src/store'
import { fallbackPending, NeedsWeb, takeFallback } from './fallback'
import { callFunction, clearFunctions } from './functions'
import { hostConfig, setPriority, type Container } from './host'
import { CanvasProvider, channelStore, footer } from './kit'
import { Markdown } from './kit/text'
import { discard, flush, forgetTree, ROOT, silently } from './ops'
import { post } from './post'
import { evaluateTsx } from './tsx'

export type Payload = {
  kind: 'markdown' | 'tsx'
  source: string
  title?: string
  data?: unknown
  buttons?: unknown[]
  wait?: boolean
}

export type Outcome = { ok: true } | { error: string; stack?: string; needsWeb?: true }

type Shown = { payload: Payload; content: unknown; generation: number }

type Failure = { error: unknown }

type Settled = { fallback: NeedsWeb | null; failure: Failure | null }

/** Calls from Swift in progress. Errors and fallbacks inside one are settled by that call, not reported late. */
let depth = 0
let failure: Failure | null = null
let shown: Shown | null = null
let generation = 0

const noop = () => {}

function onCommit() {
  if (!fallbackPending()) return flush()
  discard()

  if (depth === 0) queueMicrotask(lateFallback)
}

function onUncaught(error: unknown) {
  if (error instanceof NeedsWeb) return

  if (depth > 0) failure ??= { error }
  else reportError(error)
}

function onCaught(error: unknown) {
  if (!(error instanceof NeedsWeb)) console.error(describeError(error).message)
}

const reconciler = Reconciler(hostConfig(onCommit) as never)
const container: Container = { id: ROOT }
const root = reconciler.createContainer(container, ConcurrentRoot, null, false, null, '', onUncaught, onCaught, noop, noop, null)

function commit(node: unknown) {
  reconciler.updateContainerSync(node as never, root, null, null)
}

/** Runs one call from Swift: updates are discrete and flushed before it returns. */
function run(work: () => void): Settled {
  depth++
  takeFallback()
  failure = null
  setPriority(DiscreteEventPriority)

  try {
    work()
    reconciler.flushSyncWork()
  } catch (error) {
    failure ??= { error }
  } finally {
    setPriority(NoEventPriority)
    depth--
  }

  return { fallback: takeFallback(), failure }
}

/** Unmounts without posting ops. `swiftKeeps` says whether Swift's tree still holds the old nodes. */
function forget(swiftKeeps: boolean) {
  shown = null
  depth++

  try {
    silently(() => {
      commit(null)
      reconciler.flushSyncWork()
    })
  } finally {
    depth--
  }

  forgetTree(swiftKeeps)
  clearFunctions()
}

function described(error: unknown) {
  const { message, stack } = describeError(error)

  return stack ? { error: message, stack } : { error: message }
}

export function reportError(error: unknown) {
  const { message, stack } = describeError(error)
  post(stack ? { type: 'error', message, stack } : { type: 'error', message })
}

function lateFallback() {
  const fallback = takeFallback()

  if (!fallback) return
  forget(true)
  post({ type: 'error', message: fallback.message, needsWeb: true })
}

/** A task checkbox of a Markdown panel: Swift writes the change to the source (docs/native.md, Messages). */
function postTask({ line, checked }: { line: number; checked: boolean }) {
  post({ type: 'task', line, checked })
}

function content({ payload, content: exported }: Shown) {
  if (payload.kind === 'markdown') return createElement(Markdown, { source: payload.source, onToggle: postTask })

  return isValidElement(exported) ? exported : createElement(exported as ComponentType<{ data: unknown }>, { data: payload.data })
}

function tree(current: Shown) {
  const { data, wait = false, buttons } = current.payload

  return createElement(CanvasProvider, { key: current.generation, data, wait }, content(current), footer(buttons, wait))
}

/** A render: a fresh mount, like the web page's `canvas.render`. Ops are posted before it returns. */
export function render(payload: Payload): Outcome {
  const { fallback, failure: failed } = run(() => {
    const exported = payload.kind === 'markdown' ? null : evaluateTsx(payload.source)
    shown = { payload, content: exported, generation: ++generation }
    commit(tree(shown))
  })

  if (fallback) {
    forget(true)

    return { error: fallback.message, needsWeb: true }
  }

  if (!failed) return { ok: true }
  shown = null
  run(() => commit(null))

  return described(failed.error)
}

/** Settles a call after the first render: errors and fallbacks are also posted, as the page posts them. */
function settle({ fallback, failure: failed }: Settled): Outcome {
  if (fallback) {
    forget(true)
    post({ type: 'error', message: fallback.message, needsWeb: true })

    return { error: fallback.message, needsWeb: true }
  }

  if (!failed) return { ok: true }
  reportError(failed.error)

  return described(failed.error)
}

export function setData(data: unknown): Outcome {
  const current = shown

  if (!current) return { ok: true }
  current.payload = { ...current.payload, data }

  return settle(run(() => commit(tree(current))))
}

export function invoke(id: number, args: unknown): Outcome {
  return settle(run(() => callFunction(id, Array.isArray(args) ? args : [])))
}

export function push(batch: unknown): Outcome {
  return settle(run(() => channelStore.push(Array.isArray(batch) ? batch : [])))
}

/** Unmounts and clears state for reuse. Posts no ops: the next panel starts from an empty tree. */
export function reset() {
  forget(false)
  channelStore.clear()
}

const WARM_TSX = `import { Card, Stack, Stat, Text, Button } from 'canvas'
import { useState } from 'react'
export default function Warm() {
  const [n, setN] = useState(0)
  return <Stack><Card title="t"><Stat label="l" value={n} delta="+1" /><Text muted>x</Text></Card><Button onClick={() => setN(n + 1)}>b</Button></Stack>
}`

const WARM_MD = '# Warm\n\n- [x] **b** _i_ `c` [l](https://example.com)\n\n| a | b |\n|:-|-:|\n| 1 | 2 |\n\n```ts\nconst a: number = 1\n```\n'

/**
 * Compiles, renders and highlights once without posting anything, so the first real render runs warm code. Does
 * nothing while a panel's content is shown.
 */
export function warm() {
  if (shown) return
  silently(() => {
    render({ kind: 'tsx', source: WARM_TSX })
    render({ kind: 'markdown', source: WARM_MD })
  })
  forget(true)
}
