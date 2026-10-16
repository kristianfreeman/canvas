import { expect, test } from 'bun:test'
import { Lru } from './lru'

test('evicts the least recently set entry once over capacity', () => {
  const lru = new Lru<string, number>(2)
  lru.set('a', 1)
  lru.set('b', 2)
  lru.set('c', 3)

  expect(lru.keys()).toEqual(['b', 'c'])
  expect(lru.get('a')).toBeUndefined()
})

test('a get refreshes an entry so the other one is evicted', () => {
  const lru = new Lru<string, number>(2)
  lru.set('a', 1)
  lru.set('b', 2)
  lru.get('a')
  lru.set('c', 3)

  expect(lru.keys()).toEqual(['a', 'c'])
})

test('re-setting an existing key updates it in place without evicting', () => {
  const lru = new Lru<string, number>(2)
  lru.set('a', 1)
  lru.set('b', 2)
  lru.set('a', 10)

  expect(lru.size).toBe(2)
  expect(lru.keys()).toEqual(['b', 'a'])
  expect(lru.get('a')).toBe(10)
})