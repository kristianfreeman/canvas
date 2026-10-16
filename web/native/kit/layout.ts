import { gridColumns, size } from '../fallback'
import { h, styleOf } from './host'
import type { PropsOf } from './props'

export function Stack({ gap = 12, align, children, ...rest }: PropsOf<'Stack'>) {
  return h('Stack', { gap: size(gap, 'Stack gap'), align, style: styleOf(rest) }, children)
}

export function Row({ gap = 12, align = 'center', justify, wrap, children, ...rest }: PropsOf<'Row'>) {
  return h('Row', { gap: size(gap, 'Row gap'), align, justify, wrap: Boolean(wrap), style: styleOf(rest) }, children)
}

export function Grid({ columns = 2, gap = 12, children, ...rest }: PropsOf<'Grid'>) {
  return h('Grid', { columns: gridColumns(columns), gap: size(gap, 'Grid gap'), style: styleOf(rest) }, children)
}

export function Divider(props: PropsOf<'Divider'>) {
  return h('Divider', { style: styleOf(props) })
}

export function Spacer({ size: length, ...rest }: PropsOf<'Spacer'>) {
  return h('Spacer', { size: size(length, 'Spacer size'), style: styleOf(rest) })
}
