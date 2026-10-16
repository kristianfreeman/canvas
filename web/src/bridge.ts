import type { ChannelRequest } from './channels'

export type Outgoing =
  | { type: 'rendered' }
  | { type: 'painted' }
  | { type: 'error'; message: string; stack?: string }
  | { type: 'size'; width: number; height: number }
  | { type: 'result'; value: unknown }
  | { type: 'close'; reason?: 'escape' }
  | { type: 'open'; url: string }
  | { type: 'publish'; channel: string; value: unknown }
  | ChannelRequest

type Handler = { postMessage(message: unknown): void }

declare global {
  interface Window {
    webkit?: { messageHandlers?: { canvas?: Handler } }
    canvasHarnessPost?: (message: Outgoing) => void
  }
}

export function post(message: Outgoing) {
  try {
    const handler = window.webkit?.messageHandlers?.canvas

    // oxlint-disable-next-line unicorn/require-post-message-target-origin -- a WKScriptMessageHandler, not window.postMessage; it takes no origin
    if (handler) return handler.postMessage(message)

    if (window.canvasHarnessPost) return window.canvasHarnessPost(message)
  } catch (error) {
    console.error('[canvas] postMessage failed', error)
  }

  console.log('[canvas]', message)
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

/** A pinned panel ignores this one, so the page keeps Esc for itself. */
export function escapeClose() {
  post({ type: 'close', reason: 'escape' })
}

/** Runs `fn` as a new task. Unlike rAF or setTimeout, MessageChannel is not paused or throttled while the panel is still hidden. */
export function nextTask(fn: () => void) {
  const channel = new MessageChannel()
  channel.port1.addEventListener('message', () => {
    channel.port1.close()
    fn()
  })

  channel.port1.start()
  channel.port2.postMessage(null)
}
