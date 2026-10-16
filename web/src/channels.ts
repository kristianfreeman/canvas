export type PushMessage = { channel: string; value: unknown; history?: unknown[] }

export type ChannelRequest = { type: 'subscribe'; channel: string; every?: number } | { type: 'unsubscribe'; channel: string }

export type ChannelEntry = { value: unknown; history: readonly unknown[] }

export type SubscribeOptions = { every?: number; size?: number }

export const MIN_HISTORY = 120
const DEFAULT_EVERY = 1000

/** `full` replaces the history (the server's first push after a subscribe); otherwise the new values are appended. */
export function applyPush(
  prev: ChannelEntry | undefined,
  message: PushMessage,
  options: { full: boolean; capacity: number },
): ChannelEntry {
  const incoming = Array.isArray(message.history) ? message.history : [message.value]
  const merged = options.full || !prev ? incoming : [...prev.history, ...incoming]
  const history = merged.length > options.capacity ? merged.slice(merged.length - options.capacity) : merged

  return { value: message.value, history }
}

export function isReservedChannel(name: string) {
  return name === 'canvas' || name.startsWith('canvas.')
}

type Subscriber = { listener: () => void } & SubscribeOptions

type Channel = { subscribers: Set<Subscriber>; entry?: ChannelEntry; awaitingFull: boolean; sentEvery?: number }

function capacityOf(channel: Channel) {
  let capacity = MIN_HISTORY

  for (const subscriber of channel.subscribers) capacity = Math.max(capacity, subscriber.size ?? 0)

  return capacity
}

export type ChannelStore = ReturnType<typeof createChannelStore>

/** Latest value and history per channel, with ref-counted subscriptions announced through `send`. */
export function createChannelStore(send: (request: ChannelRequest) => void) {
  const channels = new Map<string, Channel>()

  function channelFor(name: string) {
    let channel = channels.get(name)

    if (!channel) {
      channel = { subscribers: new Set(), awaitingFull: true }
      channels.set(name, channel)
    }

    return channel
  }

  function announce(name: string, channel: Channel, every: number | undefined) {
    const first = channel.subscribers.size === 1

    if (!first && (every === undefined || every >= (channel.sentEvery ?? DEFAULT_EVERY))) return

    if (first) channel.awaitingFull = true
    if (every !== undefined) channel.sentEvery = every
    send(every === undefined ? { type: 'subscribe', channel: name } : { type: 'subscribe', channel: name, every })
  }

  function subscribe(name: string, listener: () => void, options: SubscribeOptions = {}) {
    const channel = channelFor(name)
    const subscriber: Subscriber = { listener, ...options }
    channel.subscribers.add(subscriber)
    announce(name, channel, options.every)

    return () => {
      if (!channel.subscribers.delete(subscriber) || channel.subscribers.size > 0) return
      if (channels.get(name) === channel) channels.delete(name)
      send({ type: 'unsubscribe', channel: name })
    }
  }

  function push(batch: readonly PushMessage[]) {
    const touched = new Set<Channel>()

    for (const message of batch) {
      if (!message || typeof message.channel !== 'string') continue
      const channel = channelFor(message.channel)
      channel.entry = applyPush(channel.entry, message, { full: channel.awaitingFull, capacity: capacityOf(channel) })
      channel.awaitingFull = false
      touched.add(channel)
    }

    for (const channel of touched) {
      for (const subscriber of channel.subscribers) subscriber.listener()
    }
  }

  return {
    subscribe,
    push,
    get: (name: string) => channels.get(name)?.entry,
    clear: () => channels.clear(),
  }
}
