import { useCallback, useMemo, useSyncExternalStore } from 'react'
import { post, toJSONValue } from '../bridge'
import { createChannelStore, isReservedChannel, type SubscribeOptions } from '../channels'
import { createUseStore } from '../useStore'

export const channelStore = createChannelStore(post)

const EMPTY: readonly unknown[] = []

function useEntry(name: string, { every, size }: SubscribeOptions) {
  const subscribe = useCallback(
    (listener: () => void) => channelStore.subscribe(name, listener, { every, size }),
    [name, every, size],
  )

  const get = () => channelStore.get(name)

  return useSyncExternalStore(subscribe, get, get)
}

export function useChannel<T = unknown>(name: string, options?: { every?: number }): T | undefined {
  return useEntry(name, { every: options?.every })?.value as T | undefined
}

export function useSeries<T = unknown>(name: string, size = 120): T[] {
  const count = Math.max(1, Math.floor(size))
  const entry = useEntry(name, { size: count })

  return useMemo(() => (entry ? entry.history.slice(-count) : EMPTY) as T[], [entry, count])
}

export function publish(name: string, value: unknown, options?: { persist?: boolean }) {
  if (typeof name !== 'string' || !name || isReservedChannel(name)) {
    console.error(`[canvas] publish: '${String(name)}' is not a channel the page can publish to (canvas.* is reserved)`)

    return
  }

  const message = { type: 'publish', channel: name, value: toJSONValue(value) } as const

  post(options?.persist ? { ...message, persist: true } : message)
}

export const useStore = createUseStore({ useChannel, publish })
