import { useMemo, type ReactNode } from 'react'
import { highlightLines } from '../highlight'
import { markdownBlocks } from '../markdown'
import { h, styleOf } from './host'
import type { PropsOf } from './props'

export function Heading({ level = 2, children, ...rest }: PropsOf<'Heading'>) {
  return h('Heading', { level: Math.min(4, Math.max(1, Math.round(level))), style: styleOf(rest) }, children)
}

const WEIGHTS = { normal: 400, medium: 500, semibold: 600, bold: 700 }

export function Text({ size = 'md', muted, weight, color, mono, children, ...rest }: PropsOf<'Text'>) {
  const numeric = typeof weight === 'string' ? WEIGHTS[weight] : weight

  return h(
    'Text',
    { size, muted: Boolean(muted), weight: numeric, color, mono: Boolean(mono), style: styleOf(rest) },
    children,
  )
}

export function Code({ children, ...rest }: PropsOf<'Code'>) {
  return h('Code', { style: styleOf(rest) }, children)
}

function childText(children: ReactNode) {
  if (typeof children === 'string') return children

  return Array.isArray(children) ? children.join('') : ''
}

export function CodeBlock({ code, lang, children, ...rest }: PropsOf<'CodeBlock'>) {
  const source = code ?? childText(children)
  const lines = useMemo(() => highlightLines(source, lang), [source, lang])

  return h('CodeBlock', { lang, lines, style: styleOf(rest) })
}

export function Markdown({ source, children, ...rest }: PropsOf<'Markdown'>) {
  const text = source ?? childText(children)
  const blocks = useMemo(() => markdownBlocks(text), [text])

  return h('Markdown', { blocks, style: styleOf(rest) })
}

export function Kbd({ tone, children, ...rest }: PropsOf<'Kbd'>) {
  return h('Kbd', { tone: tone === 'accent' ? tone : undefined, style: styleOf(rest) }, children)
}

/** A row of key chips for a shortcut like `"Hyper W → 1–7"`; Swift splits and draws it. */
export function KeyChips({ keys, ...rest }: PropsOf<'KeyChips'>) {
  const valid = typeof keys === 'string' || (Array.isArray(keys) && keys.every((key) => typeof key === 'string'))

  if (!valid) throw new TypeError(`KeyChips keys must be a string or a string array, got ${JSON.stringify(keys)}`)

  return h('KeyChips', { keys, style: styleOf(rest) })
}
