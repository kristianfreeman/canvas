import { describe, expect, test } from 'bun:test'
import { checkClassName, fallbackPending, gridColumns, nativeStyle, NeedsWeb, size, takeFallback } from './fallback'

function reason(fn: () => unknown) {
  takeFallback()

  try {
    fn()
  } catch (error) {
    if (error instanceof NeedsWeb) return error.message
    throw error
  }

  return null
}

describe('fallback checks', () => {
  test('sizes are numbers or px strings', () => {
    expect(size(12, 'gap')).toBe(12)
    expect(size(' 7.5px ', 'gap')).toBe(7.5)
    expect(size(undefined, 'gap')).toBeUndefined()

    for (const bad of ['1rem', '50%', '12', 'auto', Number.NaN]) expect(reason(() => size(bad, 'gap'))).toContain('gap')
  })

  test('only the allowed style keys survive, sizes as points', () => {
    expect(nativeStyle({ margin: '4px', paddingLeft: 2, flex: 1, opacity: 0.5, textAlign: 'right', width: undefined }))
      .toEqual({ margin: 4, paddingLeft: 2, flex: 1, opacity: 0.5, textAlign: 'right' })
    expect(nativeStyle({})).toBeUndefined()
    expect(nativeStyle(undefined)).toBeUndefined()
  })

  test('other style keys and values need the web', () => {
    const cases = [
      { lineHeight: '22px' },
      { color: 'red' },
      { width: '50%' },
      { textAlign: 'justify' },
      { flex: '1 1 auto' },
      { opacity: '0.5' },
    ]

    for (const style of cases) expect([style, reason(() => nativeStyle(style))]).not.toEqual([style, null])
  })

  test('a reason stays flagged until taken, even when the throw is caught', () => {
    takeFallback()

    try {
      size('1em', 'first')
    } catch {
      // an error boundary in the author's code swallowing it
    }

    try {
      size('2em', 'second')
    } catch {
      // a second one keeps the first reason
    }

    expect(fallbackPending()).toBe(true)
    expect(takeFallback()?.message).toContain('first')
    expect(fallbackPending()).toBe(false)
  })

  test('grid columns are counts or simple tracks', () => {
    expect(gridColumns(3)).toBe(3)
    expect(gridColumns(' max-content  1fr 120px auto ')).toBe('max-content 1fr 120px auto')

    for (const bad of [0, 1.5, 'repeat(3, 1fr)', 'minmax(0, 1fr)', '1fr / 2', '']) {
      expect([bad, reason(() => gridColumns(bad))]).not.toEqual([bad, null])
    }
  })

  test('a className needs the web, an empty one does not', () => {
    expect(reason(() => checkClassName({ className: 'big' }))).toContain('big')
    expect(reason(() => checkClassName({ className: '' }))).toBeNull()
    expect(reason(() => checkClassName({}))).toBeNull()
  })
})
