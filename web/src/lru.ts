/** A bounded map that evicts the least recently used entry. `get` counts as a use. */
export class Lru<K, V> {
  private readonly entries = new Map<K, V>()

  constructor(readonly capacity: number) {}

  get(key: K): V | undefined {
    const value = this.entries.get(key)

    if (value === undefined) return undefined
    this.entries.delete(key)
    this.entries.set(key, value)

    return value
  }

  set(key: K, value: V) {
    this.entries.delete(key)
    this.entries.set(key, value)

    if (this.entries.size > this.capacity) this.entries.delete(this.entries.keys().next().value as K)
  }

  keys(): K[] {
    return [...this.entries.keys()]
  }

  get size() {
    return this.entries.size
  }
}
