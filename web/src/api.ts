import { flushSync } from 'react-dom'
import { nextTask, post } from './bridge'
import type { PushMessage } from './channels'
import { scheduleUpgrades } from './grammar-loader'
import { withHighlightBudget } from './highlight'
import { idle } from './idle'
import { channelStore } from './kit'
import { renderMarkdown } from './markdown'
import { measureSurface } from './measure'
import { getState, reportError, setState, type Content, type Payload, type State } from './store'
import { setAccent, setTheme } from './theme'
import { evaluateTsx } from './tsx'

export type RenderResult = { height: number; error?: string; jsStart: number; jsEnd: number }

/** Uncached code blocks beyond this much highlighting time render plain and are highlighted after the paint. */
const HIGHLIGHT_BUDGET_MS = 4
const BACKGROUND_PAUSE_MS = 250

const NONE: Content = { kind: 'none' }
const now = () => performance.timeOrigin + performance.now()

const optionalString = (value: unknown) => (typeof value === 'string' ? value : undefined)

function normalize(input: Payload | string): Payload {
  const raw = (typeof input === 'string' ? JSON.parse(input) : input) as Partial<Payload> | null

  if (!raw || typeof raw !== 'object') throw new Error('render() expects a payload object')

  return {
    kind: raw.kind === 'tsx' ? 'tsx' : 'markdown',
    source: optionalString(raw.source) ?? '',
    title: optionalString(raw.title),
    data: raw.data,
    buttons: Array.isArray(raw.buttons) ? raw.buttons.map(String) : undefined,
    wait: Boolean(raw.wait),
    theme: raw.theme,
    accent: optionalString(raw.accent),
  }
}

type Prepared = { payload: Payload | null; content: Content; failure?: unknown }

function prepare(input: Payload | string): Prepared {
  let payload: Payload

  try {
    payload = normalize(input)
  } catch (failure) {
    return { payload: null, content: NONE, failure }
  }

  try {
    const content: Content =
      payload.kind === 'tsx'
        ? { kind: 'tsx', component: evaluateTsx(payload.source) }
        : { kind: 'markdown', html: renderMarkdown(payload.source, { interactive: true }) }

    return { payload, content }
  } catch (failure) {
    return { payload, content: NONE, failure }
  }
}

/** Commits synchronously. Errors caught by the boundary during the commit land in the store before this returns. */
function commit(next: State, failure?: unknown) {
  flushSync(() => {
    setState(next)

    if (failure !== undefined) reportError(failure, next.id)
  })
}

/** Background work waits until the frame is painted, or a short while if the page isn't drawing frames. */
function signalRendered(id: number, release: () => void) {
  requestAnimationFrame(() => {
    post({ type: 'painted' })
    release()
  })
  setTimeout(release, BACKGROUND_PAUSE_MS)
  nextTask(() => {
    const state = getState()

    if (state.id === id && !state.error) post({ type: 'rendered' })
  })
}

export function render(input: Payload | string): RenderResult {
  const jsStart = now()
  const id = getState().id + 1

  withHighlightBudget(HIGHLIGHT_BUDGET_MS, () => {
    const { payload, content, failure } = prepare(input)

    if (payload) {
      setTheme(payload.theme)
      setAccent(payload.accent)
    }

    commit({ id, payload, content, error: null }, failure)
  })
  const { height } = measureSurface()
  scheduleUpgrades()
  signalRendered(id, idle.hold())
  const error = getState().error?.message

  return { height, ...(error === undefined ? {} : { error }), jsStart, jsEnd: now() }
}

/** New props for the current component without remounting it. After a render error it remounts, since the boundary is spent. */
export function setData(data: unknown): { height: number } {
  const state = getState()

  if (state.payload?.kind === 'tsx') {
    const payload = { ...state.payload, data }
    const next = state.error ? { ...state, id: state.id + 1, payload, error: null } : { ...state, payload }
    withHighlightBudget(HIGHLIGHT_BUDGET_MS, () => commit(next))
    scheduleUpgrades()
  }

  return { height: measureSurface().height }
}

export function push(batch: unknown) {
  if (Array.isArray(batch)) channelStore.push(batch as PushMessage[])
}

export function reset() {
  ;(document.activeElement as HTMLElement | null)?.blur?.()
  commit({ id: getState().id + 1, payload: null, content: NONE, error: null })
  channelStore.clear()
  setAccent(undefined)
  document.querySelector('.cv-scroll')?.scrollTo({ top: 0 })
}
