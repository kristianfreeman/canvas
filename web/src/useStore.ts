import { useCallback, useRef, useState } from 'react'

export type StoreSetter<T> = (next: T | ((previous: T) => T)) => void

type Hooks = {
  useChannel: <T>(name: string) => T | undefined
  publish: (name: string, value: unknown, options: { persist: true }) => void
}

/** A value set here, and the channel value it was set over. */
type Pending<T> = { value: T; over: T | undefined }

/**
 * `useStore(name, initial)`: like `useState`, but the value is the persisted channel `name`, so it survives
 * closing the panel and restarting the server, and `canvas get`/`pub` see it. A set shows at once; the next value
 * the channel delivers, the server's echo or anyone else's, replaces it.
 */
export function createUseStore({ useChannel, publish }: Hooks) {
  return function useStore<T>(name: string, initial: T): [T, StoreSetter<T>] {
    const remote = useChannel<T>(name)
    const [pending, setPending] = useState<Pending<T> | null>(null)
    const stored = remote === undefined ? initial : remote
    const value = pending && pending.over === remote ? pending.value : stored
    const latest = useRef({ value, remote })
    latest.current = { value, remote }

    const set = useCallback<StoreSetter<T>>(
      (next) => {
        const { value: previous, remote: over } = latest.current
        const resolved = typeof next === 'function' ? (next as (previous: T) => T)(previous) : next
        latest.current = { value: resolved, remote: over }
        setPending({ value: resolved, over })
        publish(name, resolved, { persist: true })
      },
      [name],
    )

    return [value, set]
  }
}
