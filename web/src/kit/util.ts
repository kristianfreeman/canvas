import type { CSSProperties } from 'react'

export { resolveColor } from '../colors'

export function px(value: number | string | undefined) {
  return typeof value === 'number' ? `${value}px` : value
}

export function cx(...names: (string | false | null | undefined)[]) {
  return names.filter(Boolean).join(' ')
}

/** Pairs each item with a key built from its content; repeats get a counter so keys stay unique. */
export function keyed<T>(items: T[], text: (item: T) => string) {
  const seen = new Map<string, number>()

  return items.map((item) => {
    const base = text(item)
    const count = (seen.get(base) ?? 0) + 1
    seen.set(base, count)

    return { key: count === 1 ? base : `${base}#${count}`, item }
  })
}

export type Styled = { className?: string; style?: CSSProperties }

export function cssVars(vars: Record<string, string | undefined>, style?: CSSProperties) {
  return { ...vars, ...style } as CSSProperties
}
