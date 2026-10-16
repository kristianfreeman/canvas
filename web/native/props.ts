import { functionId, pruneFunctions } from './functions'

export type Props = Record<string, unknown>

/** Props React passes that never go to Swift. `kitMark` marks shim-made slots. */
const SKIPPED = new Set(['children', 'ref', 'kitMark'])

/** React keeps `key` to itself, so the shim passes a host element's `key` prop as `hostKey`. */
const RENAMED: Record<string, string> = { hostKey: 'key' }

function jsonValue(value: unknown): unknown {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null

  if (value === null || typeof value !== 'object') return value

  return JSON.parse(JSON.stringify(value))
}

/** The full prop set as JSON, with function props as `{"$fn": N}`. */
export function wireProps(node: number, props: Props): Props {
  const wire: Props = {}
  const functions = new Set<string>()

  for (const [key, value] of Object.entries(props)) {
    if (SKIPPED.has(key) || value === undefined) continue

    if (typeof value === 'function') {
      functions.add(key)
      wire[RENAMED[key] ?? key] = { $fn: functionId(node, key, value as (...args: unknown[]) => unknown) }
    } else {
      wire[RENAMED[key] ?? key] = jsonValue(value)
    }
  }

  pruneFunctions(node, functions)

  return wire
}

function sameValue(a: unknown, b: unknown) {
  return a === b || (typeof a === 'function' && typeof b === 'function')
}

/** True when no prop that reaches Swift changed. A function swapped for a function keeps its id, so it counts as same. */
export function sameProps(prev: Props, next: Props) {
  const keys = new Set([...Object.keys(prev), ...Object.keys(next)])

  for (const key of keys) {
    if (!SKIPPED.has(key) && !sameValue(prev[key], next[key])) return false
  }

  return true
}

/** Points function ids at the latest functions without re-sending props. */
export function refreshFunctions(node: number, props: Props) {
  for (const [key, value] of Object.entries(props)) {
    if (typeof value === 'function') functionId(node, key, value as (...args: unknown[]) => unknown)
  }
}
