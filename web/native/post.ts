import type { Op } from './ops'

/** Everything the runtime sends Swift, through the one `__post` global (docs/native.md, Messages). */
export type Message =
  | { type: 'ops'; ops: Op[] }
  | { type: 'result'; value: unknown }
  | { type: 'close'; reason?: 'escape' }
  | { type: 'subscribe'; channel: string; every?: number }
  | { type: 'unsubscribe'; channel: string }
  | { type: 'publish'; channel: string; value: unknown; persist?: true }
  | { type: 'task'; line: number; checked: boolean }
  | { type: 'error'; message: string; stack?: string; needsWeb?: true }
  | { type: 'open'; url: string }

/** The global Swift defines before the bundle runs. */
const SINK = '__post'

export function post(message: Message) {
  const sink = (globalThis as Record<string, unknown>)[SINK] as ((message: Message) => void) | undefined

  if (sink) sink(message)
  else console.log('[canvas]', JSON.stringify(message))
}

export function toJSONValue(value: unknown): unknown {
  if (value === undefined) return null

  return JSON.parse(JSON.stringify(value))
}

export function submit(value: unknown) {
  post({ type: 'result', value: toJSONValue(value) })
}

export function close() {
  post({ type: 'close' })
}
