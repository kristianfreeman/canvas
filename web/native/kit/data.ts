import { size } from '../fallback'
import { h, slot, styleOf } from './host'
import type { PropsOf } from './props'

export function Card({ title, subtitle, actions, padding = 16, children, ...rest }: PropsOf<'Card'>) {
  return h(
    'Card',
    { padding: size(padding, 'Card padding'), style: styleOf(rest) },
    slot('title', title),
    slot('subtitle', subtitle),
    slot('actions', actions),
    children,
  )
}

type Tone = 'up' | 'down' | 'flat'

const UP_PREFIXES = ['+', '▲', '↑']
const DOWN_PREFIXES = ['-', '−', '▼', '↓']

function numberTone(delta: number): Tone {
  if (delta > 0) return 'up'

  return delta < 0 ? 'down' : 'flat'
}

function deltaTone(delta: number | string): Tone {
  if (typeof delta === 'number') return numberTone(delta)
  const s = delta.trim()

  if (UP_PREFIXES.some((prefix) => s.startsWith(prefix))) return 'up'

  return DOWN_PREFIXES.some((prefix) => s.startsWith(prefix)) ? 'down' : 'flat'
}

/** The delta as the web shows it after the arrow: no sign, numbers with grouping. */
function deltaText(delta: number | string) {
  const text = typeof delta === 'number' ? Math.abs(delta).toLocaleString() : delta

  return text.replace(/^\s*[+\-−▲▼↑↓]\s*/, '')
}

/** `tone` is the delta's direction and `good` whether it's an improvement after `invertDelta`; flat is never good. */
export function deltaProps(delta: number | string | undefined, invert: boolean | undefined) {
  if (delta === undefined) return { tone: 'flat' as Tone, good: false }
  const tone = deltaTone(delta)

  return { delta: deltaText(delta), tone, good: tone !== 'flat' && (tone === 'up') !== Boolean(invert) }
}

export function Stat({ label, value, delta, invertDelta, hint, color, children, ...rest }: PropsOf<'Stat'>) {
  return h(
    'Stat',
    { ...deltaProps(delta, invertDelta), color, style: styleOf(rest) },
    slot('label', label),
    slot('value', value),
    slot('hint', hint),
    children,
  )
}

export function Badge({ color, dot, children, ...rest }: PropsOf<'Badge'>) {
  return h('Badge', { color, dot: Boolean(dot), style: styleOf(rest) }, children)
}

export function Progress({ value, max, color, label, showValue, ...rest }: PropsOf<'Progress'>) {
  const ratio = Math.max(0, Math.min(1, max ? value / max : value)) || 0

  return h(
    'Progress',
    { value: ratio, color, showValue: Boolean(showValue), style: styleOf(rest) },
    slot('label', label),
  )
}

export function BarChart({ data, height = 160, color, max, format, ...rest }: PropsOf<'BarChart'>) {
  const top = max ?? Math.max(0, ...data.map((d) => d.value))

  return h(
    'BarChart',
    { data: data.map((d) => ({ value: d.value, color: d.color })), max: top, height, color, style: styleOf(rest) },
    data.map((d, i) => slot(`label${i}`, d.label)),
    format ? data.map((d, i) => slot(`value${i}`, format(d.value))) : null,
  )
}

/** Points, or `'100%'`: Swift draws the line at the container's width. */
function sparklineWidth(width: number | string) {
  return typeof width === 'string' && width.trim() === '100%' ? '100%' : size(width, 'Sparkline width')
}

export function Sparkline({ data, width = 120, height = 32, color, fill = true, ...rest }: PropsOf<'Sparkline'>) {
  return h('Sparkline', {
    data: data.filter((v) => Number.isFinite(v)),
    width: sparklineWidth(width),
    height,
    color,
    fill,
    style: styleOf(rest),
  })
}
