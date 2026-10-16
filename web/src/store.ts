import { useSyncExternalStore } from 'react'
import { post } from './bridge'

export type Payload = {
  kind: 'markdown' | 'tsx'
  source: string
  title?: string
  data?: unknown
  buttons?: string[]
  wait: boolean
  theme?: 'auto' | 'dark' | 'light'
  accent?: string
}

export type CanvasError = { message: string; stack?: string }

export type Content =
  | { kind: 'none' }
  | { kind: 'markdown'; html: string }
  | { kind: 'tsx'; component: unknown }

export type State = {
  id: number
  payload: Payload | null
  content: Content
  error: CanvasError | null
}

let state: State = { id: 0, payload: null, content: { kind: 'none' }, error: null }
const listeners = new Set<() => void>()

export function getState() {
  return state
}

export function setState(next: State) {
  state = next

  for (const listener of listeners) listener()
}

function subscribe(listener: () => void) {
  listeners.add(listener)

  return () => listeners.delete(listener)
}

export function useStore() {
  return useSyncExternalStore(subscribe, getState)
}

const COMPONENT_FILE = 'canvas-component.tsx'
export const SOURCE_URL = COMPONENT_FILE

/** An error about the author's file raised by the renderer itself (bad import, no default export). */
export class AuthorError extends Error {}

/** A JavaScriptCore frame from eval'd code: `name@` with no location (JSC ignores sourceURL in stacks). */
const JSC_EVAL_FRAME = /^([^\s@]*)@$/

type Located = { stack?: unknown; line?: unknown; column?: unknown; sourceURL?: unknown }

/** Keeps stack frames from the user's component; the minified bundle's frames are noise to the author. */
function cleanStack(err: Located, message: string): string | undefined {
  if (typeof err.stack !== 'string') return undefined
  const lines = err.stack.split('\n').map((line) => line.trim()).filter((line) => line && !line.includes(message))

  const own = lines
    .map((line, index) => ({ line, index }))
    .filter(({ line }) => line.includes(COMPONENT_FILE) || JSC_EVAL_FRAME.test(line))

  if (!own.length) return undefined

  return own
    .map(({ line, index }) => {
      const match = JSC_EVAL_FRAME.exec(line)

      if (!match) return line
      // JSC reports the throwing frame's position on the error itself; it is ours when there's no sourceURL.
      const top = index === 0 && typeof err.line === 'number' && err.sourceURL === undefined
      const location = top ? `:${err.line}:${err.column}` : ''

      return `at ${match[1] || '<anonymous>'} (${COMPONENT_FILE}${location})`
    })
    .join('\n')
}

type ErrorLike = Located & { message: unknown; frame?: unknown; name?: unknown }

function isErrorLike(error: unknown): error is ErrorLike {
  return typeof error === 'object' && error !== null && 'message' in error
}

export function describeError(error: unknown): CanvasError {
  if (!isErrorLike(error)) return { message: typeof error === 'string' ? error : `Thrown value: ${safeString(error)}` }
  const message = String(error.message) || String(error.name ?? 'Error')

  if (typeof error.frame === 'string') return { message, stack: error.frame }

  if (error instanceof AuthorError) return { message }

  return { message, stack: cleanStack(error, message) }
}

function safeString(value: unknown) {
  try {
    return JSON.stringify(value) ?? String(value)
  } catch {
    return String(value)
  }
}

/** Posts the error to Swift and shows it in the panel. `id` scopes it to one render() call so late errors from replaced content are dropped. */
export function reportError(error: unknown, id = state.id) {
  if (id !== state.id) return
  const described = describeError(error)

  if (state.error && state.error.message === described.message && state.error.stack === described.stack) return
  post({ type: 'error', message: described.message, ...(described.stack ? { stack: described.stack } : {}) })
  setState({ ...state, error: described })
}
