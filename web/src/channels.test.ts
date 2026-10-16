import { expect, test } from 'bun:test'
import { applyPush, createChannelStore, isReservedChannel, MIN_HISTORY, type ChannelRequest } from './channels'

const range = (from: number, to: number) => Array.from({ length: to - from }, (_, i) => from + i)

test('applyPush appends history and keeps the latest value', () => {
  const first = applyPush(undefined, { channel: 'c', value: 2, history: [1, 2] }, { full: true, capacity: 5 })
  const next = applyPush(first, { channel: 'c', value: 4, history: [3, 4] }, { full: false, capacity: 5 })

  expect(next).toEqual({ value: 4, history: [1, 2, 3, 4] })
})

test('applyPush trims to capacity, dropping the oldest values', () => {
  const prev = { value: 4, history: [1, 2, 3, 4] }

  expect(applyPush(prev, { channel: 'c', value: 7, history: [5, 6, 7] }, { full: false, capacity: 5 }).history).toEqual([3, 4, 5, 6, 7])
  expect(applyPush(undefined, { channel: 'c', value: 9, history: range(0, 10) }, { full: true, capacity: 3 }).history).toEqual([7, 8, 9])
})

test('applyPush with full replaces the history, and a push without history appends the value', () => {
  const prev = { value: 3, history: [1, 2, 3] }

  expect(applyPush(prev, { channel: 'c', value: 9, history: [8, 9] }, { full: true, capacity: 5 })).toEqual({ value: 9, history: [8, 9] })
  expect(applyPush(prev, { channel: 'c', value: 4 }, { full: false, capacity: 5 })).toEqual({ value: 4, history: [1, 2, 3, 4] })
})

function storeWithLog() {
  const sent: ChannelRequest[] = []

  return { sent, store: createChannelStore((request) => sent.push(request)) }
}

test('subscriptions are ref-counted: one subscribe for the first hook, one unsubscribe after the last', () => {
  const { sent, store } = storeWithLog()
  const offA = store.subscribe('cpu', () => {})
  const offB = store.subscribe('cpu', () => {})
  offA()

  expect(sent).toEqual([{ type: 'subscribe', channel: 'cpu' }])
  offB()
  expect(sent).toEqual([{ type: 'subscribe', channel: 'cpu' }, { type: 'unsubscribe', channel: 'cpu' }])
})

test('a hook asking for a smaller interval re-announces the subscription; a larger one does not', () => {
  const { sent, store } = storeWithLog()
  store.subscribe('canvas.sys.cpu', () => {}, { every: 500 })
  store.subscribe('canvas.sys.cpu', () => {}, { every: 2000 })
  store.subscribe('canvas.sys.cpu', () => {}, { every: 250 })

  expect(sent.map((request) => ('every' in request ? request.every : undefined))).toEqual([500, 250])
})

test('the first push after subscribing replaces history; later pushes append', () => {
  const { store } = storeWithLog()
  store.push([{ channel: 'n', value: 0, history: [0] }])
  store.subscribe('n', () => {})
  store.push([{ channel: 'n', value: 3, history: [1, 2, 3] }])
  store.push([{ channel: 'n', value: 4, history: [4] }])

  expect(store.get('n')).toEqual({ value: 4, history: [1, 2, 3, 4] })
})

test('pushes notify only the touched channels, once per batch', () => {
  const { store } = storeWithLog()
  const calls = { a: 0, b: 0 }
  store.subscribe('a', () => calls.a++)
  store.subscribe('b', () => calls.b++)
  store.push([{ channel: 'a', value: 1 }, { channel: 'a', value: 2 }])

  expect(calls).toEqual({ a: 1, b: 0 })
  expect(store.get('a')?.value).toBe(2)
})

test('history capacity is the largest requested size, at least the minimum', () => {
  const { store } = storeWithLog()
  store.subscribe('big', () => {}, { size: 10 })
  store.push([{ channel: 'big', value: 499, history: range(0, 500) }])

  expect(store.get('big')?.history).toHaveLength(MIN_HISTORY)
  store.subscribe('big', () => {}, { size: 200 })
  store.push([{ channel: 'big', value: 999, history: range(500, 1000) }])
  expect(store.get('big')?.history).toHaveLength(200)
})

test('unsubscribing the last hook forgets the channel', () => {
  const { store } = storeWithLog()
  const off = store.subscribe('gone', () => {})
  store.push([{ channel: 'gone', value: 1 }])
  off()

  expect(store.get('gone')).toBeUndefined()
})

test('canvas.* channel names are reserved', () => {
  expect(isReservedChannel('canvas.sys.cpu')).toBe(true)
  expect(isReservedChannel('canvas')).toBe(true)
  expect(isReservedChannel('canvasx.cpu')).toBe(false)
  expect(isReservedChannel('top.select')).toBe(false)
})
